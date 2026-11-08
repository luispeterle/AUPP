import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:aupp/components/time-chart.dart';
import 'package:aupp/desktop/analysis-page.dart';
import 'package:aupp/desktop/analysis-widgets.dart';
import 'package:aupp/desktop/compare-page.dart';
import 'package:aupp/desktop/fii-compare-page.dart';
import 'package:aupp/desktop/desktop-layout.dart';
import 'package:aupp/desktop/asset-workspaces.dart';
import 'package:aupp/helpers/records-utility-functions.dart';
import 'package:aupp/services/crypto-quote-service.dart';
import 'package:aupp/investments/home-listing.dart';
import 'package:aupp/investments/sec-data.dart';

import 'package:url_launcher/url_launcher.dart';

import 'asset-sheet.dart';
import 'diagram-page.dart';
import 'diagram.dart';
import 'fii-view.dart';
import 'investments-analytics.dart';
import 'investments-cache.dart';
import 'investments-page.dart';
import 'stock-catalog.dart';
import 'asset-lots.dart';

String _money(double value) => getCurrencyValueString(value);

String _quantity(double value) =>
    NumberFormat('#,##0.########', 'pt_BR').format(value);

String _pct(double value) => '${NumberFormat('0.0', 'pt_BR').format(value)}%';

Widget _card(
  BuildContext context,
  String title,
  Widget child, {
  Widget? action,
}) => Card(
  margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ?action,
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  ),
);

/// A site's own icon, on white for the ones made for light backgrounds.
class SiteIcon extends StatelessWidget {
  const SiteIcon(this.label, {super.key, this.size = 18});

  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final asset = siteIcon(label);
    if (asset == null) return Icon(Icons.public, size: size);
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(1),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Image.asset(asset, filterQuality: FilterQuality.medium),
    );
  }
}

/// What is held of a ticker: positions, possibly at more than one broker, or
/// the wallets of a cryptocurrency.
class _Holding {
  final double quantity;
  final double value;

  /// Null when it is not known what was paid.
  final double? cost;
  final List<String> where;
  final double portfolioTotal;

  const _Holding({
    this.quantity = 0,
    this.value = 0,
    this.cost,
    this.where = const [],
    this.portfolioTotal = 0,
  });

  bool get isEmpty => where.isEmpty;
}

/// Everything about an asset when deciding on a purchase: the user's situation,
/// the quote, their reasons, its grade, a simulation and where to read more.
class AssetSheetPage extends StatefulWidget {
  final String ticker;

  /// Inside a workspace, whose bar takes the place of the app bar.
  final bool embedded;

  const AssetSheetPage({
    super.key,
    required this.ticker,
    this.embedded = false,
  });

  /// Set by the shell: opens the sheet in its own tab of the computer's rail.
  static bool Function(String ticker)? openInTab;

  static Future<void> open(BuildContext context, String ticker) async {
    if (openInTab?.call(ticker) ?? false) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AssetSheetPage(ticker: ticker)),
    );
  }

  @override
  State<AssetSheetPage> createState() => _AssetSheetPageState();
}

class _AssetSheetPageState extends State<AssetSheetPage> {
  final _notes = AssetNotes.load();
  late final AssetNote _note = _notes.of(widget.ticker);
  late final _thesis = TextEditingController(text: _note.thesis);

  AssetQuote? _quote;
  bool _quoteLoading = true;
  _Holding _holding = const _Holding();
  late AssetKind _kind = isCryptoTicker(widget.ticker)
      ? AssetKind.crypto
      : AssetKind.stock;
  Timer? _saveTimer;
  DiagramState _diagram = DiagramState.load();
  AssetProfile? _profile;
  late final _typedGrade = TextEditingController(
    text: _diagram.typedGrades[widget.ticker]?.toString() ?? '',
  );

  /// What was added by hand keeps its class; otherwise it follows the kind.
  DiagramAsset get _gradeAsset => DiagramAsset(
    key: widget.ticker,
    label: widget.ticker,
    ticker: widget.ticker,
    cls:
        _diagram.watched[widget.ticker] ??
        switch (_kind) {
          AssetKind.fii => DiagramClass.fii,
          AssetKind.crypto => DiagramClass.crypto,
          AssetKind.stock || AssetKind.etf => DiagramClass.nationalStock,
        },
    isEtf:
        _diagram.watchedEtfs.contains(widget.ticker) || _kind == AssetKind.etf,
    status: _diagram.statusOf(widget.ticker),
  );

  @override
  void initState() {
    super.initState();
    DiagramState.revision.addListener(_diagramSaved);
    _loadQuote();
    _loadPortfolio();
  }

  @override
  void dispose() {
    DiagramState.revision.removeListener(_diagramSaved);
    _typedGrade.dispose();
    if (_saveTimer?.isActive ?? false) _saveNow();
    _saveTimer?.cancel();
    _thesis.dispose();
    super.dispose();
  }

  Future<void> _loadQuote() async {
    setState(() => _quoteLoading = true);
    final quote = await AssetQuote.fetch(widget.ticker);
    final kind = await resolveAssetKind(widget.ticker, quote: quote);
    if (!mounted) return;
    if (kind != AssetKind.crypto) {
      AssetProfile.fetch(widget.ticker).then((profile) {
        if (!mounted) return;
        setState(() => _profile = profile);
        // Kept for "Ações por setor" in Carteira e aporte.
        final sector = profile?.sector;
        if (sector != null && _diagram.sectors[widget.ticker] != sector) {
          _diagram.sectors[widget.ticker] = sector;
          _diagram.save();
        }
      });
    }
    setState(() {
      _quote = quote;
      _kind = kind;
      _quoteLoading = false;
    });
  }

  Future<void> _loadPortfolio() async {
    final snapshot = await InvestmentsCache.load();
    if (!mounted) return;
    final overview = snapshot == null
        ? null
        : InvestmentsOverview.from(snapshot.investments, DateTime.now());
    final total = overview?.total ?? 0;
    final positions = [
      for (final p in overview?.positions ?? const <Position>[])
        if (StockCompany.tickerOf(p.inv) == widget.ticker) p,
    ];
    final coin = AssetLots.coins[widget.ticker];
    final costs = positions.map((p) => p.tax.cost).toList();
    setState(() {
      _holding = coin != null
          ? _Holding(
              quantity: coin,
              value:
                  coin * (CryptoQuoteService.priceInMain(widget.ticker) ?? 0),
              where: const ['Cripto'],
              portfolioTotal: total,
            )
          : _Holding(
              quantity: positions.fold(
                0,
                (sum, p) =>
                    sum + ((p.inv.raw['quantity'] as num?)?.toDouble() ?? 0),
              ),
              value: positions.fold(0, (sum, p) => sum + p.balance),
              cost: positions.isEmpty || costs.contains(null)
                  ? null
                  : costs.fold<double>(0, (sum, cost) => sum + cost!),
              where: {for (final p in positions) p.institution.name}.toList(),
              portfolioTotal: total,
            );
    });
  }

  /// Waits for a pause in the typing: each save goes to the other devices.
  void _noteChanged() {
    _note.thesis = _thesis.text;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), _saveNow);
    setState(() {});
  }

  void _saveNow() => _notes.save();

  void _diagramSaved() => setState(() => _diagram = DiagramState.load());

  /// A grade given to what is not held puts the asset in the portfolio to study.
  void _gradeChanged() {
    if (_holding.isEmpty) {
      _diagram.watched[widget.ticker] = _gradeAsset.cls;
      if (_gradeAsset.isEtf) _diagram.watchedEtfs.add(widget.ticker);
    }
    _diagram.save();
  }

  Widget _buildStock() {
    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              title: Text(widget.ticker),
              // On the computer Comparar is a tab of the workspace.
              actions: [
                IconButton(
                  tooltip: 'Comparar',
                  icon: const Icon(Icons.table_chart_outlined),
                  onPressed: () => _push(
                    'Comparar · ${widget.ticker}',
                    ComparePage(ticker: widget.ticker),
                  ),
                ),
              ],
            ),
      body: _quoteLoading
          ? const Center(child: CircularProgressIndicator())
          : AnalysisPage(
              ticker: widget.ticker,
              held: !_holding.isEmpty,
              top: _stockTop(),
            ),
    );
  }

  /// The price of the last months on the left, the thesis on the right.
  Widget _stockTop() {
    final quote = _quote;
    final history = quote?.history ?? const <(DateTime, double)>[];
    final currency = quote?.currency ?? 'BRL';
    String price(double v) =>
        pricePerShare(v, currency: currency == 'BRL' ? 'BRL' : currency);
    final Widget chart;
    if (history.length < 2) {
      chart = Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text('Sem histórico de preço.', style: mutedStyle(context)),
      );
    } else {
      final change = history.last.$2 / history.first.$2 - 1;
      final up = change >= 0;
      final color = up ? const Color(0xFF26A65B) : const Color(0xFFE5484D);
      final months = (history.last.$1.difference(history.first.$1).inDays / 30)
          .round();
      chart = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle(
            'Preço · $months ${months == 1 ? 'mês' : 'meses'}',
            trailing: Text(
              '${price(history.last.$2)}  '
              '${up ? '+' : ''}${percent(change)} no período',
              style: denseStyle(context)
                  .copyWith(color: color, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 8),
          TimeChart(
            area: true,
            height: 200,
            series: [
              TimeSeries('Preço', color, [
                for (final h in history) (h.$1, h.$2),
              ]),
            ],
            format: price,
            dateLabel: DateFormat('dd/MM/yyyy').format,
            axisLabel: DateFormat('dd/MM').format,
          ),
          Text(
            'Dados da ${_kind == AssetKind.crypto ? 'CoinGecko' : 'brapi.dev'}, '
            'podem ter atraso',
            style: mutedStyle(context, size: 11),
          ),
        ],
      );
    }
    final side = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Minha tese'),
        const SizedBox(height: 8),
        // As tall as the chart beside it.
        SizedBox(
          height: 216,
          child: TextField(
            controller: _thesis,
            expands: true,
            minLines: null,
            maxLines: null,
            textAlignVertical: TextAlignVertical.top,
            style: denseStyle(context, size: 13).copyWith(height: 1.4),
            decoration: const InputDecoration(
              hintText: 'Por que quero este ativo',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => _noteChanged(),
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= 900
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Panel(child: chart)),
                const SizedBox(width: 20),
                // The same width as the grade below, on a wide screen.
                SizedBox(
                  width: constraints.maxWidth >= 1250
                      ? analysisSideWidth(constraints.maxWidth)
                      : 420,
                  child: Panel(child: side),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Panel(child: chart),
                const SizedBox(height: 14),
                Panel(child: side),
              ],
            ),
    );
  }

  void _push(String title, Widget page) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: page,
      ),
    ),
  );

  /// Where there are no sites inside the app: the browser.
  Future<void> _open(AssetLink link) async {
    final messenger = ScaffoldMessenger.of(context);
    final url = link.url;
    final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(content: Text('Não consegui abrir ${url.host}')),
      );
    }
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    final quote = _quote;
    final company =
        cryptoNames[widget.ticker] ??
        StockCompany.of(widget.ticker)?.name ??
        quote?.longName;
    final change = quote?.changePct;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InstitutionLogo(
                institution: StockCompany.badgeOf(widget.ticker),
                size: 44,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.ticker, style: theme.textTheme.titleLarge),
                    if (company != null)
                      Text(company, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (quote != null) ...[
                    Text(
                      quote.currency == 'USD'
                          ? 'US\$ ${NumberFormat('#,##0.00', 'pt_BR').format(quote.price)}'
                          : getCurrencyValueString(quote.price),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (change != null)
                      Text(
                        '${change >= 0 ? '+' : ''}${_pct(change)} hoje',
                        style: TextStyle(
                          color: getAmountColor(change, theme.brightness),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ] else if (_quoteLoading)
                    const SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    TextButton.icon(
                      onPressed: _loadQuote,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Sem cotação'),
                    ),
                ],
              ),
            ],
          ),
          if (quote != null && quote.history.length >= 2) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 170,
              width: double.infinity,
              child: _PriceChart(history: quote.history),
            ),
            const SizedBox(height: 4),
            Text(
              '${(quote.history.last.$1.difference(quote.history.first.$1).inDays / 30).round()} meses · dados do '
              '${_kind == AssetKind.crypto ? 'CoinGecko' : 'brapi.dev'}, podem ter atraso'
              '${quote.at == null ? '' : ' · ${DateFormat('dd/MM HH:mm').format(quote.at!)}'}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value, {Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.w600, color: color),
        ),
      ],
    ),
  );

  Widget _buildSituation() {
    final holding = _holding;
    final theme = Theme.of(context);
    if (holding.isEmpty) {
      return _card(
        context,
        'Sua situação',
        Text(
          'Você ainda não tem ${widget.ticker}.',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }
    final cost = holding.cost;
    final quantity = holding.quantity;
    final price = _quote?.price;
    final current = price != null && quantity > 0
        ? price * quantity
        : holding.value;
    final profit = cost == null ? null : current - cost;
    return _card(
      context,
      'Sua situação',
      Column(
        children: [
          _row('Quantidade', _quantity(quantity)),
          if (cost != null && quantity > 0)
            _row('Preço médio', _money(cost / quantity)),
          _row('Valor hoje', _money(current)),
          if (profit != null)
            _row(
              'Resultado',
              '${_money(profit)}'
                  '${cost! > 0 ? ' (${_pct(profit / cost * 100)})' : ''}',
              color: getAmountColor(profit, theme.brightness),
            ),
          if (holding.portfolioTotal > 0)
            _row(
              'Na carteira',
              _pct(holding.value / holding.portfolioTotal * 100),
            ),
          _row('Onde', holding.where.join(', ')),
        ],
      ),
    );
  }

  Widget _buildLinks() {
    final links = assetLinks(
      widget.ticker,
      cryptoNames[widget.ticker] ?? StockCompany.of(widget.ticker)?.name,
      kind: _kind,
    );
    return _card(
      context,
      'Para ler',
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final link in links)
            ActionChip(
              avatar: SiteIcon(link.label),
              label: Text(link.label),
              onPressed: () => _open(link),
            ),
        ],
      ),
    );
  }

  Widget _buildThesis() {
    InputDecoration field(String label, {String? helper}) => InputDecoration(
      labelText: label,
      helperText: helper,
      helperMaxLines: 2,
      alignLabelWithHint: true,
      border: const OutlineInputBorder(),
    );
    return _card(
      context,
      'Minha tese',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _thesis,
            minLines: 3,
            maxLines: 8,
            decoration: field('Por que quero este ativo'),
            onChanged: (_) => _noteChanged(),
          ),
        ],
      ),
    );
  }

  /// The course's order: the sector before the company, the company before
  /// the numbers.
  Widget? _buildCompany() {
    final profile = _profile;
    if (profile == null) return null;
    final theme = Theme.of(context);
    return _card(
      context,
      'Setor e empresa',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (profile.sector != null)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.category_outlined, size: 16),
                  label: Text(profile.sector!),
                ),
                if (profile.industry != null &&
                    profile.industry != profile.sector)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(profile.industry!),
                  ),
              ],
            ),
          if (profile.summary != null) ...[
            const SizedBox(height: 8),
            _ExpandableText(profile.summary!),
          ],
          if (profile.website != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.language, size: 18),
                label: Text(profile.website!.host),
                onPressed: () => _open(AssetLink('Site', profile.website!)),
              ),
            ),
          Text(
            'Antes da empresa, o setor: perene, comum, pouco regulado e previsível. '
            'Depois, compare com as concorrentes do mesmo setor.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  /// The grade of this asset in "Carteira e aporte", on the same answers.
  Widget _buildGrade() {
    final Widget child;
    if (_quoteLoading) {
      child = const Center(child: CircularProgressIndicator());
    } else if (_gradeAsset.cls.hasQuestionnaire) {
      child = DiagramQuestionsPanel(
        asset: _gradeAsset,
        state: _diagram,
        onChanged: _gradeChanged,
      );
    } else {
      child = TextField(
        controller: _typedGrade,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(
          labelText: 'Nota de 0 a 10',
          border: OutlineInputBorder(),
        ),
        onChanged: (text) {
          final typed = int.tryParse(text);
          if (typed == null) {
            _diagram.typedGrades.remove(widget.ticker);
          } else {
            _diagram.typedGrades[widget.ticker] = typed.clamp(0, 10);
          }
          _diagram.touch(widget.ticker);
          _gradeChanged();
        },
      );
    }
    return _card(
      context,
      'Nota em Carteira e aporte',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          child,
          const SizedBox(height: 8),
          Text(
            _holding.isEmpty
                ? 'Dar nota aqui já adiciona o ativo em Carteira e aporte.'
                : 'É a mesma nota de Carteira e aporte.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // A stock's page is its analysis: the chart and the thesis on top.
    if (_kind == AssetKind.stock) return _buildStock();
    // In a workspace with web views, the sites are in its bar.
    final links = widget.embedded && AssetWorkspaces.instance.supported
        ? null
        : _buildLinks();
    final fii = _kind == AssetKind.fii;
    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              title: const Text('Ficha do ativo'),
              // On the computer Comparar is a tab of the workspace.
              actions: [
                if (fii)
                  IconButton(
                    tooltip: 'Comparar',
                    icon: const Icon(Icons.table_chart_outlined),
                    onPressed: () => _push(
                      'Comparar · ${widget.ticker}',
                      FiiComparePage(ticker: widget.ticker),
                    ),
                  ),
              ],
            ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _buildHeader(),
          if (fii && !_quoteLoading)
            FiiPanel(
              ticker: widget.ticker,
              price: _quote?.price,
              history: _quote?.history ?? const [],
            ),
          AdaptiveColumns(
            left: [_buildSituation(), ?_buildCompany(), _buildThesis(), ?links],
            right: [_buildGrade()],
            narrow: [
              _buildSituation(),
              ?_buildCompany(),
              _buildThesis(),
              _buildGrade(),
              ?links,
            ],
          ),
        ],
      ),
    );
  }
}

/// A long text that opens on a tap.
class _ExpandableText extends StatefulWidget {
  const _ExpandableText(this.text);

  final String text;

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _open = false;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => setState(() => _open = !_open),
    child: Text(
      widget.text,
      maxLines: _open ? null : 4,
      overflow: _open ? null : TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodyMedium,
    ),
  );
}

/// A year of closes. The mouse (or a finger) shows the value of any day.
class _PriceChart extends StatefulWidget {
  const _PriceChart({required this.history});

  final List<(DateTime, double)> history;

  @override
  State<_PriceChart> createState() => _PriceChartState();
}

class _PriceChartState extends State<_PriceChart> {
  static const _labelWidth = 56.0;
  int? _index;

  void _pointAt(Offset position, double width) {
    final index = chartIndexAt(
      position.dx,
      width - _labelWidth,
      widget.history.length,
    );
    if (index != _index) setState(() => _index = index);
  }

  void _clear() {
    if (_index != null) setState(() => _index = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return MouseRegion(
          cursor: SystemMouseCursors.precise,
          onHover: (event) => _pointAt(event.localPosition, width),
          onExit: (_) => _clear(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanDown: (details) => _pointAt(details.localPosition, width),
            onPanUpdate: (details) => _pointAt(details.localPosition, width),
            onPanEnd: (_) => _clear(),
            onPanCancel: _clear,
            child: CustomPaint(
              size: Size.infinite,
              painter: _PriceChartPainter(
                widget.history,
                labelWidth: _labelWidth,
                selected: _index,
                line: theme.colorScheme.primary,
                guide: theme.colorScheme.outline,
                text: theme.textTheme.bodySmall!,
                tipBackground: theme.colorScheme.inverseSurface,
                tipText: theme.textTheme.bodySmall!.copyWith(
                  color: theme.colorScheme.onInverseSurface,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PriceChartPainter extends CustomPainter {
  final List<(DateTime, double)> history;
  final double labelWidth;
  final int? selected;
  final Color line;
  final Color guide;
  final TextStyle text;
  final Color tipBackground;
  final TextStyle tipText;

  _PriceChartPainter(
    this.history, {
    required this.labelWidth,
    required this.selected,
    required this.line,
    required this.guide,
    required this.text,
    required this.tipBackground,
    required this.tipText,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final prices = history.map((e) => e.$2);
    final low = prices.reduce((a, b) => a < b ? a : b);
    final high = prices.reduce((a, b) => a > b ? a : b);
    final range = high == low ? 1.0 : high - low;
    final chartWidth = size.width - labelWidth;
    double y(double price) => 6 + (high - price) / range * (size.height - 12);
    double x(int index) => index / (history.length - 1) * chartWidth;

    void label(String value, double top) {
      final painter = TextPainter(
        text: TextSpan(text: value, style: text),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, Offset(chartWidth + 6, top - painter.height / 2));
    }

    final guidePaint = Paint()
      ..color = guide.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (final price in [high, low]) {
      canvas.drawLine(
        Offset(0, y(price)),
        Offset(chartWidth, y(price)),
        guidePaint,
      );
      label(price.toStringAsFixed(2).replaceAll('.', ','), y(price));
    }
    final path = Path();
    for (var i = 0; i < history.length; i++) {
      if (i == 0) {
        path.moveTo(x(i), y(history[i].$2));
      } else {
        path.lineTo(x(i), y(history[i].$2));
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
    final index = selected;
    if (index != null && index < history.length) {
      _paintSelection(canvas, size, x(index), y(history[index].$2), index);
    }
  }

  void _paintSelection(
    Canvas canvas,
    Size size,
    double x,
    double y,
    int index,
  ) {
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = guide
        ..strokeWidth = 1,
    );
    canvas.drawCircle(Offset(x, y), 5, Paint()..color = tipBackground);
    canvas.drawCircle(Offset(x, y), 3.5, Paint()..color = line);

    final (date, price) = history[index];
    final first = history.first.$2;
    final change = first > 0 ? (price - first) / first * 100 : null;
    final tip = TextPainter(
      text: TextSpan(
        style: tipText,
        children: [
          TextSpan(
            text: getCurrencyValueString(price),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(
            text:
                '\n${DateFormat('dd/MM/yyyy').format(date)}'
                '${change == null ? '' : ' · ${change >= 0 ? '+' : ''}${_pct(change)}'}',
          ),
        ],
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    const padding = 8.0;
    final boxWidth = tip.width + padding * 2;
    final boxHeight = tip.height + padding * 2;
    // Beside the point, on the side that fits, and never over it.
    final left = x + 12 + boxWidth <= size.width ? x + 12 : x - 12 - boxWidth;
    final top = (y - boxHeight / 2).clamp(0.0, size.height - boxHeight);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, boxWidth, boxHeight),
        const Radius.circular(6),
      ),
      Paint()..color = tipBackground,
    );
    tip.paint(canvas, Offset(left + padding, top + padding));
  }

  @override
  bool shouldRepaint(_PriceChartPainter old) =>
      old.history != history || old.selected != selected || old.line != line;
}

/// Finds an asset to open its sheet: the user's positions and the assets they
/// wrote about come first, then any B3 ticker or company.
class AssetSearchPage extends StatefulWidget {
  const AssetSearchPage({super.key, this.embedded = false, this.idle});

  /// A tab of Investimentos, whose bar takes the place of the app bar.
  final bool embedded;

  /// Shown under the field while nothing is typed, in place of the positions
  /// and notes (the Aportar e buscar tab).
  final Widget? idle;

  @override
  State<AssetSearchPage> createState() => _AssetSearchPageState();
}

class _AssetSearchPageState extends State<AssetSearchPage> {
  final _query = TextEditingController();
  final _queryFocus = FocusNode();
  List<String> _held = const [];
  List<String> _noted = const [];
  bool _checking = false;

  /// Other exchanges, asked only on request (OpenFIGI allows a few a minute).
  String? _otherQuery;
  List<FigiListing>? _other;
  bool _searchingOther = false;

  @override
  void initState() {
    super.initState();
    _load();
    AssetWorkspaces.instance.addListener(_onWorkspacesChanged);
    SecCatalog.instance.addListener(_secChanged);
    SecCatalog.instance.ensure();
  }

  void _secChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _searchOther() async {
    final query = _query.text.trim();
    setState(() {
      _searchingOther = true;
      _otherQuery = query;
      _other = null;
    });
    final found = await OpenFigi.search(query);
    if (!mounted || _otherQuery != query) return;
    setState(() {
      _searchingOther = false;
      _other = found;
      // Refused (its limit): the button comes back to try again.
      if (found == null) _otherQuery = null;
    });
    if (found == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'A OpenFIGI não respondeu (limite de buscas por minuto). Tente de novo '
            'daqui a pouco.',
          ),
        ),
      );
    }
  }

  Future<void> _openOther(FigiListing listing) async {
    final symbol = listing.symbols.firstOrNull;
    if (symbol == null) return;
    await SecCatalog.instance.remember(
      symbol,
      SecCatalog.displayName(listing.name),
    );
    await _openSheet(symbol);
  }

  @override
  void dispose() {
    SecCatalog.instance.removeListener(_secChanged);
    AssetWorkspaces.instance.removeListener(_onWorkspacesChanged);
    _query.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  AssetWorkspace? _lastWorkspace;

  /// Back from an asset on the computer: ready for the next search.
  void _onWorkspacesChanged() {
    final current = AssetWorkspaces.instance.current;
    final cameBack = _lastWorkspace != null && current == null;
    _lastWorkspace = current;
    if (cameBack) _readyForNextSearch();
  }

  void _readyForNextSearch() {
    if (!mounted) return;
    _query.clear();
    _queryFocus.requestFocus();
    _load();
  }

  Future<void> _load() async {
    final snapshot = await InvestmentsCache.load();
    final held = <String>{
      for (final inv in snapshot?.investments ?? const [])
        if (!inv.archived && inv.balance > 0) ?StockCompany.tickerOf(inv),
    };
    held.addAll(AssetLots.coins.keys);
    if (!mounted) return;
    setState(() {
      _held = held.toList()..sort();
      _noted = AssetNotes.load().tickers
          .where((ticker) => !held.contains(ticker))
          .toList();
    });
  }

  Future<void> _openSheet(String ticker) async {
    final inWorkspace = AssetSheetPage.openInTab?.call(ticker) ?? false;
    if (inWorkspace) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AssetSheetPage(ticker: ticker)),
    );
    _readyForNextSearch();
  }

  /// A company was chosen: which of its tickers exist?
  Future<void> _openRoot(AssetSearchResult result) async {
    setState(() => _checking = true);
    final tickers = await tickersOfRoot(result.root);
    if (!mounted) return;
    setState(() => _checking = false);
    if (tickers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Não encontrei cotação de ${result.root}. Digite o ticker completo.',
          ),
        ),
      );
    } else if (tickers.length == 1) {
      await _openSheet(tickers.single);
    } else {
      final chosen = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(result.name ?? result.root),
          children: [
            for (final ticker in tickers)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, ticker),
                child: Text(ticker),
              ),
          ],
        ),
      );
      if (chosen != null && mounted) await _openSheet(chosen);
    }
  }

  Widget _tickerTile(String ticker) => ListTile(
    leading: InstitutionLogo(institution: StockCompany.badgeOf(ticker)),
    title: Text(
      cryptoNames[ticker] == null
          ? StockCompany.titleOf(ticker)
          : '${cryptoNames[ticker]} · $ticker',
    ),
    onTap: () => _openSheet(ticker),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final results = searchAssets(_query.text);
    final query = _query.text.trim();
    final abroad = query.length >= 2
        ? SecCatalog.instance.search(query, limit: 15)
        : const <SecListing>[];
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(text, style: theme.textTheme.titleSmall),
    );
    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(title: const Text('Buscar ativo')),
      body: Column(
        children: [
          Padding(
            padding: widget.idle == null
                ? const EdgeInsets.all(12)
                : const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: TextField(
              controller: _query,
              focusNode: _queryFocus,
              // In a tab, the phone's keyboard waits for a tap; over the
              // contribution, the value field comes first.
              autofocus:
                  widget.idle == null &&
                  (!widget.embedded || isWideLayout(context)),
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Ticker, empresa ou moeda: PETR4, Itaú, AAPL, Toyota, Bitcoin…',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (results.isEmpty && abroad.isNotEmpty) {
                  _openSheet(abroad.first.ticker);
                  return;
                }
                if (results.isEmpty) return;
                final first = results.first;
                first.ticker != null
                    ? _openSheet(first.ticker!)
                    : _openRoot(first);
              },
            ),
          ),
          if (_checking) const LinearProgressIndicator(),
          Expanded(
            child: widget.idle != null && _query.text.trim().length < 2
                ? widget.idle!
                : ListView(
                    children: _query.text.trim().length >= 2
                        ? [
                            if (results.isEmpty && abroad.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(24),
                                child: Center(
                                  child: Text(
                                    'Nada encontrado na B3 nem nos EUA.',
                                  ),
                                ),
                              ),
                            for (final result in results)
                              ListTile(
                                leading: InstitutionLogo(
                                  institution: StockCompany.badgeOf(
                                    result.ticker ?? '${result.root}3',
                                  ),
                                ),
                                title: Text(result.name ?? result.root),
                                subtitle: Text(result.ticker ?? result.root),
                                onTap: () => result.ticker != null
                                    ? _openSheet(result.ticker!)
                                    : _openRoot(result),
                              ),
                            if (abroad.isNotEmpty) heading('Nos EUA (SEC)'),
                            for (final listing in abroad)
                              ListTile(
                                leading: InstitutionLogo(
                                  institution: StockCompany.badgeOf(
                                    listing.ticker,
                                  ),
                                ),
                                title: Text(
                                  SecCatalog.displayName(listing.name),
                                ),
                                subtitle: Text(
                                  [
                                    listing.ticker,
                                    ?listing.exchange,
                                  ].join(' · '),
                                ),
                                onTap: () => _openSheet(listing.ticker),
                              ),
                            heading('Outras bolsas'),
                            if (_otherQuery != query)
                              ListTile(
                                leading: const Icon(Icons.public),
                                title: Text('Buscar "$query" em outras bolsas'),
                                subtitle: const Text(
                                  'Alemanha, Japão, Reino Unido, França… pela OpenFIGI',
                                ),
                                onTap: _searchOther,
                              )
                            else if (_searchingOther)
                              const Padding(
                                padding: EdgeInsets.all(16),
                                child: LinearProgressIndicator(),
                              )
                            else if (_other?.isEmpty ?? true)
                              const ListTile(
                                title: Text('Nada nas outras bolsas.'),
                                subtitle: Text(
                                  'A OpenFIGI aceita poucas buscas por minuto sem chave; '
                                  'tente de novo daqui a pouco.',
                                ),
                              )
                            else
                              for (final listing in _other!)
                                ListTile(
                                  leading: const Icon(Icons.public),
                                  title: Text(
                                    SecCatalog.displayName(listing.name),
                                  ),
                                  subtitle: Text(
                                    '${listing.symbols.first} · '
                                    '${FigiListing.exchangeNames[listing.exchange] ?? listing.exchange}',
                                  ),
                                  onTap: () => _openOther(listing),
                                ),
                          ]
                        : [
                            if (_held.isNotEmpty) heading('Na sua carteira'),
                            for (final ticker in _held) _tickerTile(ticker),
                            if (_noted.isNotEmpty)
                              heading('Com anotações suas'),
                            for (final ticker in _noted) _tickerTile(ticker),
                          ],
                  ),
          ),
        ],
      ),
    );
  }
}
