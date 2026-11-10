import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:aupp/components/total-text.dart';
import 'package:aupp/dinzo/daily-money.dart';
import 'package:aupp/dinzo/dinzo-taxes.dart';
import 'package:aupp/helpers/records-utility-functions.dart';
import 'package:aupp/services/crypto-quote-service.dart';

import 'asset-lots-view.dart';
import 'asset-lots.dart';
import 'asset-sheet-page.dart';
import 'asset-sheet.dart';
import 'benchmark.dart';
import 'crypto-analytics.dart';
import 'crypto-history.dart';
import 'crypto-view.dart';
import 'diagram-page.dart' show FreedomCard, divisionOf;
import 'diagram.dart';
import 'investments-cache.dart';
import 'investments-page.dart' show InstitutionLogo;
import 'module-cards.dart';
import 'money-purpose-card.dart';
import 'performance.dart';
import 'portfolio.dart';
import 'stock-catalog.dart';

/// What Carteira e aporte knows and does, handed to the Carteira tab.
class PortfolioContext {
  final bool loaded;

  /// Every asset of the method, valued in reais.
  final List<DiagramAsset> assets;
  final Map<DiagramClass, double> targets;

  /// Today's quote of each asset with a ticker, by its key.
  final Map<String, AssetQuote> quotes;

  /// The result of each stock here, by ticker, from what the Dinzo says it
  /// cost.
  final Map<String, double> stockResults;
  final double? dollar;

  /// Caixinhas, investments and what stays out of the method, as the tree
  /// counts it.
  final double wealth;

  /// A price abroad, in reais, on a day.
  final PriceOn abroadPriceOn;

  /// The class as a small coloured label.
  final Widget Function(DiagramClass) pill;
  final VoidCallback onAddAbroad;
  final void Function(DiagramAsset) onOpenLots;
  final void Function(DiagramAsset) onRemove;

  const PortfolioContext({
    required this.loaded,
    required this.assets,
    required this.targets,
    required this.quotes,
    required this.stockResults,
    required this.dollar,
    required this.wealth,
    required this.abroadPriceOn,
    required this.pill,
    required this.onAddAbroad,
    required this.onOpenLots,
    required this.onRemove,
  });
}

/// Everything invested in one page, class by class. Every class starts
/// switched on (but the everyday banks' fixed income, which is the wallets'
/// money); switching one off takes it out of the total, the charts, the
/// Divisão, the positions and its own cards at the end. Nothing is
/// remembered: each visit starts the same.
class PortfolioTab extends StatefulWidget {
  const PortfolioTab({
    super.key,
    required this.context,
    required this.snapshot,
    required this.onRefresh,
    required this.brazilExtras,
    this.banner,
  });

  final PortfolioContext context;

  /// The Dinzo's positions; null without the Dinzo.
  final InvestmentsSnapshot? snapshot;
  final Future<void> Function() onRefresh;

  /// What is only of the positions here (the full list, FGC, IR, dividends),
  /// for the classes switched on.
  final List<Widget> Function(Set<PortfolioClass> shown) brazilExtras;

  /// An error or a hint above everything.
  final Widget? banner;

  @override
  State<PortfolioTab> createState() => _PortfolioTabState();
}

class _PortfolioTabState extends State<PortfolioTab> {
  Set<PortfolioClass> _shown = PortfolioClass.shownByDefault;
  bool _sinceStart = false;
  BenchmarkRates? _rates;
  CryptoHistory? _cryptoHistory;

  /// Daily closes of the stocks here, in reais, by ticker.
  final _closes = <String, List<MapEntry<DateTime, double>>>{};
  final _cryptoKey = GlobalKey<CryptoViewState>();

  PortfolioContext get _ctx => widget.context;
  List<DinzoInvestment> get _positions =>
      widget.snapshot?.investments.where((i) => !i.archived).toList() ??
      const [];

  @override
  void initState() {
    super.initState();
    _loadHistories();
  }

  @override
  void didUpdateWidget(PortfolioTab old) {
    super.didUpdateWidget(old);
    if (old.snapshot != widget.snapshot) _loadHistories();
  }

  /// Quotes of the stocks here, coins and Selic since the first purchase.
  Future<void> _loadHistories() async {
    final lots = dinzoLots(_positions);
    final days = [
      for (final list in [...lots.values, ...AssetLots.all.values])
        for (final lot in list) lot.day,
      for (final inv in _positions)
        for (final m in inv.movements) ?DateTime.tryParse(m.date),
    ]..sort();
    await Future.wait([
      for (final ticker in lots.keys)
        if (!_closes.containsKey(ticker))
          AssetQuote.fetch(ticker).then((quote) {
            if (quote == null || !mounted) return;
            setState(
              () => _closes[ticker] = [
                for (final (day, close) in quote.history)
                  MapEntry(DateTime(day.year, day.month, day.day), close),
              ],
            );
          }),
      CryptoHistory.load(AssetLots.coins.keys.toList()).then((history) {
        if (mounted) setState(() => _cryptoHistory = history);
      }, onError: (_) {}),
      _ratesSince(days.isEmpty ? null : days.first).then((rates) {
        if (mounted && rates != null) setState(() => _rates = rates);
      }),
    ]);
  }

  /// Offline, the last ones saved.
  static Future<BenchmarkRates?> _ratesSince(DateTime? first) async {
    if (first == null) return BenchmarkRates.load();
    try {
      return await BenchmarkRates.ensure(first);
    } catch (_) {
      return BenchmarkRates.load();
    }
  }

  // ---------------------------------------------------------------- prices

  bool _isToday(DateTime day) {
    final now = DateTime.now();
    return day.year == now.year && day.month == now.month && day.day == now.day;
  }

  DiagramAsset? _assetByTicker(String ticker) =>
      _ctx.assets.where((a) => a.ticker == ticker).firstOrNull;

  /// A stock here, in reais, on a day: today's quote, or that day's close.
  double? _stockPriceOn(String ticker, DateTime day) {
    if (_isToday(day)) {
      final today = _assetByTicker(ticker)?.price;
      if (today != null) return today;
    }
    return CryptoAnalytics.priceOn(_closes[ticker] ?? const [], day);
  }

  /// A coin, in reais, on a day: today's quote, or the history.
  double? _coinPriceOn(String code, DateTime day) {
    if (_isToday(day)) {
      final today = CryptoQuoteService.priceInMain(code);
      if (today != null) return today;
    }
    final series = _cryptoHistory?.seriesIn(code, 'BRL');
    return series == null
        ? null
        : CryptoAnalytics.priceOn(CryptoAnalytics.merged(series), day);
  }

  // ----------------------------------------------------------- the classes

  List<DiagramAsset> _assetsOf(PortfolioClass cls) => [
    for (final a in _ctx.assets)
      if (a.cls == cls.diagram && a.value > 0) a,
  ];

  List<DinzoInvestment> get _dailyFixedIncome => [
    for (final inv in _positions)
      if (DailyMoney.isMoney(inv)) inv,
  ];

  double _totalOf(PortfolioClass cls) => cls == PortfolioClass.dailyFixedIncome
      ? _dailyFixedIncome.fold(0.0, (sum, i) => sum + i.balance)
      : _assetsOf(cls).fold(0.0, (sum, a) => sum + a.value);

  /// What a class did day by day, from its real purchases.
  List<PortfolioPoint> _seriesOf(PortfolioClass cls) {
    final rates = _rates;
    if (rates == null) return const [];
    final today = DateTime.now();
    switch (cls) {
      case PortfolioClass.nationalStock || PortfolioClass.fii:
        final tickers = {
          for (final a in _assetsOf(cls))
            if (a.ticker != null) a.ticker!,
        };
        final lots = dinzoLots(_positions);
        return AssetLots.history(
          lots: {
            for (final e in lots.entries)
              if (tickers.contains(e.key)) e.key: e.value,
          },
          priceOn: _stockPriceOn,
          rates: rates,
          today: today,
        );
      case PortfolioClass.fixedIncome || PortfolioClass.dailyFixedIncome:
        final daily = cls == PortfolioClass.dailyFixedIncome;
        return Performance.history(
          [
            for (final inv in _positions)
              if (inv.type == DailyMoney.fixedIncomeType &&
                  DailyMoney.isMoney(inv) == daily)
                inv,
          ],
          rates,
          today,
        );
      case PortfolioClass.intlStock ||
          PortfolioClass.reit ||
          PortfolioClass.crypto:
        final crypto = cls == PortfolioClass.crypto;
        return AssetLots.history(
          lots: {for (final a in _assetsOf(cls)) a.key: AssetLots.of(a.key)},
          priceOn: crypto ? _coinPriceOn : _ctx.abroadPriceOn,
          rates: rates,
          today: today,
        );
    }
  }

  /// Fixed income without deposits (cofrinhos, funds): no past to draw.
  double get _undrawn => [
    for (final inv in _positions)
      if (inv.type == DailyMoney.fixedIncomeType &&
          _shown.contains(
            DailyMoney.isMoney(inv)
                ? PortfolioClass.dailyFixedIncome
                : PortfolioClass.fixedIncome,
          ) &&
          !inv.movements.any((m) => m.type == 'BUY'))
        inv.balance,
  ].fold(0.0, (sum, v) => sum + v);

  static String _money(double v) => getCurrencyValueString(v);

  static String _pct(double v) => '${NumberFormat('0.0', 'pt_BR').format(v)}%';

  static String _units(double v) =>
      NumberFormat('#,##0.####', 'pt_BR').format(v);

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final c in PortfolioClass.values)
        if (_shown.contains(c)) c,
    ];
    final total = shown.fold(0.0, (sum, c) => sum + _totalOf(c));
    final series = combineSeries([for (final c in shown) _seriesOf(c)]);
    final cutoff = DateTime.now().subtract(const Duration(days: 366));
    final undrawn = _undrawn;
    final groups = [
      for (final c in shown)
        if (c.diagram != null)
          ...divisionOf(_ctx.assets, [c.diagram!], _ctx.targets)
        else
          // The wallets' money: no target in the method.
          DivisionGroup(c.label, [
            DivisionSlice('_daily', 'Bancos do dia a dia', _totalOf(c)),
          ], 0),
    ];
    final colors = DivisionCard.colorsOf([for (final g in groups) ...g.slices]);
    final portfolio = _ctx.assets.fold(0.0, (sum, a) => sum + a.value);

    return RefreshIndicator(
      onRefresh: () async {
        await widget.onRefresh();
        await _cryptoKey.currentState?.refresh(force: true);
        await _loadHistories();
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          ?widget.banner,
          _chips(context),
          _header(context, total),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('12 meses')),
                ButtonSegment(value: true, label: Text('Desde o início')),
              ],
              selected: {_sinceStart},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _sinceStart = s.first),
            ),
          ),
          if (_rates != null && series.length >= 2) ...[
            LotsSelicCard(
              rates: _rates!,
              sinceStart: _sinceStart,
              note: _chartNote(undrawn),
              points: series,
            ),
            EvolutionCard(
              info: _chartNote(undrawn),
              unofficial:
                  shown.any(
                    (c) =>
                        c != PortfolioClass.fixedIncome &&
                        c != PortfolioClass.dailyFixedIncome,
                  )
                  ? 'Ações, FIIs e o exterior seguem o fechamento de cada dia '
                        'do Yahoo Finance (ou da brapi.dev) e cripto o da '
                        'CoinGecko ou Kraken; nenhum é fonte oficial. A renda '
                        'fixa segue o CDI do Banco Central.'
                  : null,
              points: [
                for (final p in series)
                  if (_sinceStart || !p.date.isBefore(cutoff))
                    (p.date, p.value),
              ],
            ),
          ],
          DivisionCard(groups: groups, portfolio: portfolio),
          _positionsSection(context, shown, colors),
          if (shown.any((c) => c.isBrazil)) ...widget.brazilExtras(_shown),
          if (shown.any((c) => c.isAbroad)) ?_watching(context),
          if (_ctx.loaded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: FreedomCard(wealth: _ctx.wealth),
            ),
          if (_shown.contains(PortfolioClass.crypto))
            CryptoView(
              key: _cryptoKey,
              sinceStart: _sinceStart,
              onChanged: _loadHistories,
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: MoneyPurposeCard(),
          ),
        ],
      ),
    );
  }

  String _chartNote(double undrawn) => [
    'Cada classe pelo que ela fez de verdade: ações e FIIs pelas compras da '
        'Dinzo e a cotação de cada dia (brapi.dev, até 3 meses no plano '
        'grátis), renda fixa pelo % do CDI contratado em cada aplicação, '
        'exterior e cripto pelas compras informadas e a cotação de cada dia.',
    if (undrawn > 0)
      '${_money(undrawn)} em cofrinhos e fundos ficam fora dos gráficos: a '
          'Dinzo não informa quando foram aplicados.',
  ].join('\n\n');

  Widget _chips(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
    child: Row(
      children: [
        for (final c in PortfolioClass.values)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilterChip(
              label: Text(c.label),
              selected: _shown.contains(c),
              onSelected: (on) => setState(() {
                _shown = {..._shown};
                on ? _shown.add(c) : _shown.remove(c);
              }),
            ),
          ),
      ],
    ),
  );

  Widget _header(BuildContext context, double total) {
    final theme = Theme.of(context);
    final abroad = _shown.any((c) => c.isAbroad);
    final daily = _totalOf(PortfolioClass.dailyFixedIncome);
    final money = widget.snapshot == null
        ? null
        : widget.snapshot!.bankBalance +
              DailyMoney.parkedIn(widget.snapshot!.investments) -
              widget.snapshot!.cardDebt;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const TotalLabel(
                  'Total',
                  info:
                      'Só as classes marcadas acima. A renda fixa dos bancos '
                      'do dia a dia é o dinheiro das carteiras: fica de fora '
                      'até ser marcada.',
                ),
                const SizedBox(height: 4),
                TotalValue(_money(total)),
                if (money != null &&
                    !_shown.contains(PortfolioClass.dailyFixedIncome) &&
                    daily > 0)
                  Text(
                    'Mais ${_money(money)} de dinheiro nos bancos do dia a dia',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          if (abroad && _ctx.dollar != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'US\$ 1 = ${getCurrencyValueString(_ctx.dollar!)}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- positions

  Widget _positionsSection(
    BuildContext context,
    List<PortfolioClass> shown,
    Map<String, Color> colors,
  ) {
    final cards = <(double, Widget)>[];
    for (final c in shown) {
      switch (c) {
        case PortfolioClass.nationalStock || PortfolioClass.fii:
          final module = _ctx.assets
              .where(
                (a) => const {
                  DiagramClass.nationalStock,
                  DiagramClass.fii,
                  DiagramClass.fixedIncome,
                }.contains(a.cls),
              )
              .fold(0.0, (sum, a) => sum + a.value);
          for (final a in _assetsOf(c)) {
            cards.add((a.value, _stockCard(context, a, module, colors)));
          }
        case PortfolioClass.intlStock || PortfolioClass.reit:
          final module = _ctx.assets
              .where(
                (a) =>
                    a.cls == DiagramClass.intlStock ||
                    a.cls == DiagramClass.reit,
              )
              .fold(0.0, (sum, a) => sum + a.value);
          for (final a in _assetsOf(c)) {
            cards.add((a.value, _abroadCard(context, a, module, colors)));
          }
        case PortfolioClass.crypto:
          final module = _totalOf(c);
          for (final a in _assetsOf(c)) {
            cards.add((a.value, _coinCard(context, a, module, colors)));
          }
        case PortfolioClass.fixedIncome || PortfolioClass.dailyFixedIncome:
          // One by one in "Todas as posições".
          break;
      }
    }
    cards.sort((a, b) => b.$1.compareTo(a.$1));
    return PositionsSection(
      cards: [for (final (_, card) in cards) card],
      action: PopupMenuButton<String>(
        tooltip: 'Adicionar',
        onSelected: (what) =>
            what == 'crypto' ? _addCoin() : _ctx.onAddAbroad(),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'abroad', child: Text('Ativo lá fora')),
          PopupMenuItem(value: 'crypto', child: Text('Compra de cripto')),
        ],
        child: IgnorePointer(
          child: OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Adicionar', style: TextStyle(fontSize: 13)),
          ),
        ),
      ),
      empty: const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('Nenhuma posição nas classes marcadas.'),
      ),
    );
  }

  Future<void> _addCoin() async {
    final crypto = _cryptoKey.currentState;
    if (crypto != null) return crypto.pickCoin();
    // Cripto switched off: switch it on, then ask.
    setState(() => _shown = {..._shown, PortfolioClass.crypto});
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _cryptoKey.currentState?.pickCoin(),
    );
  }

  Widget _stockCard(
    BuildContext context,
    DiagramAsset asset,
    double module,
    Map<String, Color> colors,
  ) {
    final quote = _ctx.quotes[asset.key];
    return PositionCard(
      color: colors[asset.key] ?? DivisionCard.palette.first,
      logo: InstitutionLogo(
        institution: StockCompany.badgeOf(asset.ticker ?? asset.label),
        size: 36,
      ),
      title: asset.label,
      subtitle:
          StockCompany.of(asset.ticker)?.name ??
          quote?.longName ??
          quote?.shortName,
      badge: asset.cls == DiagramClass.nationalStock
          ? null
          : _ctx.pill(asset.cls),
      price: asset.price == null ? '—' : _money(asset.price!),
      changePct: quote?.changePct,
      onTap: asset.ticker == null
          ? null
          : () => AssetSheetPage.open(context, asset.ticker!),
      figures: [
        ('Quantidade', PositionCard.bold(_units(asset.quantity))),
        ('Valor', PositionCard.bold(_money(asset.value))),
        (
          'Resultado',
          PositionCard.result(context, _ctx.stockResults[asset.ticker]),
        ),
        (
          'No Brasil',
          PositionCard.bold(
            module <= 0 ? '—' : _pct(asset.value / module * 100),
          ),
        ),
      ],
    );
  }

  Widget _abroadCard(
    BuildContext context,
    DiagramAsset asset,
    double module,
    Map<String, Color> colors,
  ) {
    final quote = _ctx.quotes[asset.key];
    var cost = 0.0;
    double? result;
    for (final lot in AssetLots.of(asset.key)) {
      final part = AssetLots.costOf(
        lot,
        (day) => _ctx.abroadPriceOn(asset.key, day),
      );
      if (part == null) {
        cost = 0;
        break;
      }
      cost += part;
    }
    if (cost > 0 && asset.value > 0) result = (asset.value / cost - 1) * 100;
    return PositionCard(
      color: colors[asset.key] ?? DivisionCard.palette.first,
      logo: InstitutionLogo(
        institution: StockCompany.badgeOf(asset.label),
        size: 36,
      ),
      title: asset.label,
      subtitle: quote?.longName ?? quote?.shortName,
      badge: _ctx.pill(asset.cls),
      price: quote == null
          ? '—'
          : NumberFormat.currency(
              locale: 'pt_BR',
              symbol: r'US$ ',
            ).format(quote.price),
      changePct: quote?.changePct,
      onTap: asset.ticker == null
          ? null
          : () => AssetSheetPage.open(context, asset.ticker!),
      figures: [
        (
          'Quantidade',
          InkWell(
            onTap: () => _ctx.onOpenLots(asset),
            borderRadius: BorderRadius.circular(4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PositionCard.bold(_units(asset.quantity)),
                const SizedBox(width: 3),
                const Icon(Icons.edit_outlined, size: 13),
              ],
            ),
          ),
        ),
        ('Valor', PositionCard.bold(_money(asset.value))),
        ('Resultado', PositionCard.result(context, result)),
        (
          'Lá fora',
          PositionCard.bold(
            module <= 0 ? '—' : _pct(asset.value / module * 100),
          ),
        ),
      ],
      action: asset.isManual
          ? IconButton(
              tooltip: 'Remover',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () => _ctx.onRemove(asset),
            )
          : null,
      warning: quote == null
          ? 'Sem cotação: confira a chave da brapi.dev em Ajustes › Dinzo.'
          : null,
    );
  }

  Widget _coinCard(
    BuildContext context,
    DiagramAsset asset,
    double module,
    Map<String, Color> colors,
  ) {
    final code = asset.key;
    final lots = AssetLots.of(code);
    double? cost = lots.isEmpty ? null : 0;
    for (final lot in lots) {
      final part = AssetLots.costOf(lot, (day) => _coinPriceOn(code, day));
      cost = part == null || cost == null ? null : cost + part;
    }
    final logo = cryptoLogoOf(code);
    void open() => _cryptoKey.currentState?.openLots(code);
    return PositionCard(
      color: colors[code] ?? DivisionCard.palette.first,
      logo: logo == null
          ? const Icon(Icons.currency_bitcoin, size: 36)
          : Image.asset(logo, width: 36, height: 36),
      title: code,
      subtitle: cryptoNames[code],
      badge: _ctx.pill(asset.cls),
      price: _money(CryptoQuoteService.priceInMain(code) ?? asset.price ?? 0),
      onTap: open,
      figures: [
        (
          'Quantidade',
          InkWell(
            onTap: open,
            borderRadius: BorderRadius.circular(4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: PositionCard.bold(
                    NumberFormat(
                      '#,##0.########',
                      'pt_BR',
                    ).format(asset.quantity),
                  ),
                ),
                const SizedBox(width: 3),
                const Icon(Icons.edit_outlined, size: 13),
              ],
            ),
          ),
        ),
        ('Valor', PositionCard.bold(_money(asset.value))),
        (
          'Resultado',
          PositionCard.result(
            context,
            cost == null || cost <= 0 ? null : (asset.value / cost - 1) * 100,
            note: lots.any((lot) => lot.cost == null) ? ' est.' : null,
          ),
        ),
        (
          'Em cripto',
          PositionCard.bold(
            module <= 0 ? '—' : _pct(asset.value / module * 100),
          ),
        ),
      ],
    );
  }

  /// Abroad, studied but not held: a tap adds the first purchase.
  Widget? _watching(BuildContext context) {
    final watching = [
      for (final a in _ctx.assets)
        if ((a.cls == DiagramClass.intlStock || a.cls == DiagramClass.reit) &&
            a.quantity <= 0)
          a,
    ];
    if (watching.isEmpty) return null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Estudando lá fora, sem posição',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final asset in watching)
                ActionChip(
                  label: Text(asset.label),
                  avatar: const Icon(Icons.add, size: 16),
                  tooltip: 'Adicionar compra',
                  onPressed: () => _ctx.onOpenLots(asset),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
