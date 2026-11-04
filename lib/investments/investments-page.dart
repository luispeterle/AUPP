import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:aupp/dinzo/dinzo-settings-page.dart';
import 'package:aupp/dashboard/dashboard-data.dart';
import 'package:aupp/dinzo/dinzo-api.dart';
import 'package:aupp/dinzo/dinzo-sync-service.dart';
import 'package:aupp/helpers/records-utility-functions.dart';
import 'package:aupp/investments/stock-catalog.dart';

import 'diagram-page.dart';
import 'selic-comparison.dart';
import 'investment-detail-page.dart';
import 'investments-analytics.dart';
import 'investments-cache.dart';
import 'freedom.dart';
import 'portfolio-tab.dart';
import 'portfolio.dart';
import 'package:aupp/dinzo/daily-money.dart';

/// Investments tab (fork-only, pt-BR): positions, split, flows, history and
/// income tax, from the Dinzo data cached by the last sync or refresh.
class InvestmentsPage extends StatefulWidget {
  const InvestmentsPage({Key? key}) : super(key: key);

  @override
  State<InvestmentsPage> createState() => InvestmentsPageState();
}

enum _PositionSort {
  age('Idade', false),
  due('Vencimento', true),
  tax('IR', false),
  cost('Aplicado', false);

  final String label;

  /// Direction picked when the option is chosen.
  final bool ascendingByDefault;

  const _PositionSort(this.label, this.ascendingByDefault);
}

/// What each part of the money is for: the wallets divide it, see [DailyMoney].
class InvestmentsPageState extends State<InvestmentsPage> {
  InvestmentsSnapshot? _snapshot;
  InvestmentsOverview? _overview;
  bool _loading = true;
  bool _refreshing = false;
  String? _error;


  _PositionSort? _positionSort;
  bool _positionSortAscending = false;
  String? _positionBank;
  String? _positionProduct;

  final _dateFormat = DateFormat('dd/MM/yy');

  @override
  void initState() {
    super.initState();
    _loadCached();
  }

  Future<void> _loadCached() async {
    final snapshot = await InvestmentsCache.load();
    await _apply(snapshot);
    if (mounted) setState(() => _loading = false);
    await refreshInBackground();
  }

  /// When the tab is shown: fetch once a day (each refresh reads every
  /// position, one request each, and Dinzo allows 5,000 a day), or finish a
  /// refresh left halfway. The refresh button always starts over.
  Future<void> refreshInBackground() async {
    if (_refreshing) return;
    if (DashboardCache.fetchedToday(_snapshot?.fetchedAt) &&
        !await InvestmentsCache.hasPending()) {
      return;
    }
    await _refresh(restart: false);
  }

  Future<void> _refresh({bool restart = true}) async {
    // The Dinzo is optional; without it there is nothing to fetch.
    if (DinzoSyncService.apiKey == null) {
      if (mounted) setState(() {});
      return;
    }
    setState(() {
      _refreshing = true;
      _error = null;
    });
    try {
      await _apply(await InvestmentsCache.refresh(restart: restart));
    } on DinzoApiException catch (e) {
      _error = e.code == 'missing_key'
          ? 'Configure a chave da API da Dinzo em Configurações → Integrações com API.'
          : 'A Dinzo respondeu com erro: ${e.message}';
    } catch (e) {
      _error = 'Não foi possível atualizar: $e';
    }
    if (mounted) setState(() => _refreshing = false);
  }

  Future<void> _apply(InvestmentsSnapshot? snapshot) async {
    if (snapshot == null) return;
    final overview = InvestmentsOverview.from(
      snapshot.investments,
      DateTime.now(),
    );
    if (!mounted) return;
    setState(() {
      _snapshot = snapshot;
      _overview = overview;
    });
  }

  /// Bank-issued fixed income above what the FGC covers in one institution.
  Widget? _buildGuarantee(InvestmentsOverview o) {
    final over = DepositGuarantee.overLimit(o.positions);
    if (over.isEmpty) return null;
    return _card(
      title: '🛡️ Acima da garantia do FGC',
      info: 'O FGC cobre até ${_money(DepositGuarantee.perInstitution)} por '
          'instituição em CDB, LCI e LCA. Os próximos aportes podem ir para outra '
          'instituição sólida (Basileia acima de 12) ou para o Tesouro.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final e in over.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                '${e.key}: ${_money(e.value)}, ${_money(e.value - DepositGuarantee.perInstitution)} '
                'sem garantia.',
              ),
            ),
        ],
      ),
    );
  }

  String _money(double v) => getCurrencyValueString(v);

  String _pct(double v) => '${v.toStringAsFixed(1).replaceAll('.', ',')}%';

  @override
  Widget build(BuildContext context) {
    return DiagramPage(
      portfolio: (portfolio) => PortfolioTab(
        context: portfolio,
        snapshot: _snapshot,
        onRefresh: _refresh,
        banner: _banner(),
        brazilExtras: _brazilExtras,
      ),
    );
  }

  /// An error, the Dinzo to connect, or a refresh going on.
  Widget? _banner() {
    if (_loading || _refreshing) {
      return const LinearProgressIndicator(minHeight: 2);
    }
    if (_error != null) {
      return MaterialBanner(
        content: Text(_error!),
        actions: [
          TextButton(
            onPressed: () => setState(() => _error = null),
            child: const Text('OK'),
          ),
        ],
      );
    }
    if (_overview != null) return null;
    return MaterialBanner(
      content: Text(
        DinzoSyncService.apiKey == null
            ? 'Ações, FIIs e renda fixa vêm da Dinzo (opcional). Conecte a sua '
                  'conta para vê-los aqui.'
            : 'Sincronize com a Dinzo ou atualize para ver as posições daqui.',
      ),
      actions: [
        DinzoSyncService.apiKey == null
            ? TextButton(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const DinzoSettingsPage()),
                  );
                  if (mounted) _refresh();
                },
                child: const Text('Conectar a Dinzo'),
              )
            : TextButton(
                onPressed: _refreshing ? null : _refresh,
                child: const Text('Atualizar agora'),
              ),
      ],
    );
  }

  /// Fork: what is only of the positions here, for the classes shown in the
  /// Carteira tab.
  List<Widget> _brazilExtras(Set<PortfolioClass> shown) {
    final o = _overview;
    if (o == null) return const [];
    bool include(Position p) {
      if (DailyMoney.isMoney(p.inv)) {
        return shown.contains(PortfolioClass.dailyFixedIncome);
      }
      if (p.inv.type == DailyMoney.fixedIncomeType) {
        return shown.contains(PortfolioClass.fixedIncome);
      }
      return shown.contains(PortfolioClass.nationalStock) ||
          shown.contains(PortfolioClass.fii);
    }

    return [
      _buildPositions(o, include),
      ?_buildGuarantee(o),
      if (o.bracketTips.isNotEmpty) _buildTips(o),
      if (_snapshot!.income.isNotEmpty) _buildIncome(),
    ];
  }

  // ---------------------------------------------------------------- header

  /// [info] is the explanation: behind an icon by the title, out of the way.
  Widget _card({
    required String title,
    String? subtitle,
    String? info,
    required Widget child,
  }) => InvestmentCard(title: title, subtitle: subtitle, info: info, child: child);

  // ----------------------------------------------------------- performance

  // ------------------------------------------------------------------ tips

  Widget _buildTips(InvestmentsOverview o) {
    return _card(
      title: '💡 Espere para resgatar',
      info: 'Posições que mudam para uma alíquota menor de IR em breve',
      child: Column(
        children: [
          for (final p in o.bracketTips)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: _logo(p.institution, 32),
              title: Text(
                '${p.product} ${p.rateLabel ?? ''} · ${_money(p.balance)}',
              ),
              subtitle: Text(
                'IR cai de ${_pct(p.tax.rate * 100)} para '
                '${_pct(p.nextRate! * 100)} em ${p.daysToNextBracket} dias',
              ),
              trailing: Text(
                '−${_money(p.savingIfWait)}',
                style: const TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () => _openPosition(p),
            ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------- tax

  // ---------------------------------------------------------------- income

  Widget _buildIncome() {
    final income = _snapshot!.income;
    double amountOf(Map<String, dynamic> m) =>
        ((m['amount'] ?? m['value'] ?? m['total']) as num?)?.toDouble() ?? 0;
    return _card(
      title: 'Proventos (12 meses)',
      info: 'Dividendos e JCP dos seus ativos na B3',
      child: Column(
        children: [
          for (final m in income)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                '${m['ticker'] ?? m['code'] ?? m['name'] ?? ''} '
                '${m['type'] ?? ''}',
              ),
              subtitle: Text('${m['payment_date'] ?? m['date'] ?? ''}'),
              trailing: Text(_money(amountOf(m))),
            ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- positions

  /// All together, the largest first, with the bank and the product as filters.
  Widget _buildPositions(InvestmentsOverview o, bool Function(Position) include) {
    final shownPositions = o.positions.where(include).toList();
    final theme = Theme.of(context);
    double total(Iterable<Position> positions) =>
        positions.fold(0, (sum, p) => sum + p.balance);

    // By how much is in each, like the rest of the page.
    List<T> ranked<T>(T Function(Position) keyOf) {
      final sums = <T, double>{};
      for (final p in shownPositions) {
        sums[keyOf(p)] = (sums[keyOf(p)] ?? 0) + p.balance;
      }
      return sums.keys.toList()
        ..sort((a, b) => sums[b]!.compareTo(sums[a]!));
    }

    final banks = <String, Institution>{
      for (final p in shownPositions) p.institution.name: p.institution,
    };
    final bankNames = ranked((p) => p.institution.name);
    final products = ranked((p) => p.product);
    // What was filtered may be gone after a refresh.
    final bank = bankNames.contains(_positionBank) ? _positionBank : null;
    final product = products.contains(_positionProduct)
        ? _positionProduct
        : null;
    final shown = filterPositions(
      shownPositions,
      institution: bank,
      product: product,
    );

    Widget filters(List<Widget> chips) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Row(
        children: [
          for (final chip in chips)
            Padding(padding: const EdgeInsets.only(right: 6), child: chip),
        ],
      ),
    );

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Todas as posições',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Text(
                  '${shown.length} · ${_money(total(shown))}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (bankNames.length > 1)
            filters([
              for (final name in bankNames)
                FilterChip(
                  avatar: _logo(banks[name]!, 20),
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  label: Text(name),
                  selected: bank == name,
                  onSelected: (selected) =>
                      setState(() => _positionBank = selected ? name : null),
                ),
            ]),
          if (products.length > 1)
            filters([
              for (final name in products)
                FilterChip(
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  label: Text(name),
                  selected: product == name,
                  onSelected: (selected) =>
                      setState(() => _positionProduct = selected ? name : null),
                ),
            ]),
          _positionSortBar(),
          for (final p in _sortedPositions(shown)) _positionTile(p),
        ],
      ),
    );
  }

  /// Positions in [_positionSort] order; unknown values always go last.
  List<Position> _sortedPositions(List<Position> positions) {
    final sort = _positionSort;
    if (sort == null) {
      return List.of(positions)
        ..sort((a, b) => b.balance.compareTo(a.balance));
    }
    Comparable? key(Position p) => switch (sort) {
      _PositionSort.age => p.tax.ageDays,
      _PositionSort.due =>
        p.inv.dueDate == null ? null : DateTime.tryParse(p.inv.dueDate!),
      _PositionSort.tax => p.tax.rate,
      _PositionSort.cost => p.tax.cost,
    };
    int compare(Position a, Position b) {
      final ka = key(a), kb = key(b);
      if (ka == null || kb == null) {
        return ka == null && kb == null ? 0 : (ka == null ? 1 : -1);
      }
      var c = ka.compareTo(kb);
      // Same bracket: the larger tax amount decides.
      if (c == 0 && sort == _PositionSort.tax) {
        c = a.tax.tax.compareTo(b.tax.tax);
      }
      return _positionSortAscending ? c : -c;
    }

    return List.of(positions)..sort(compare);
  }

  Widget _positionSortBar() {
    final ascending = _positionSortAscending;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final option in _PositionSort.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(option.label),
                        selected: _positionSort == option,
                        visualDensity: VisualDensity.compact,
                        onSelected: (selected) => setState(() {
                          _positionSort = selected ? option : null;
                          _positionSortAscending = option.ascendingByDefault;
                        }),
                      ),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: ascending ? 'Menor primeiro' : 'Maior primeiro',
            icon: Icon(ascending ? Icons.arrow_upward : Icons.arrow_downward),
            onPressed: _positionSort == null
                ? null
                : () => setState(() => _positionSortAscending = !ascending),
          ),
        ],
      ),
    );
  }

  Widget _positionTile(Position p) {
    final theme = Theme.of(context);
    final ticker = StockCompany.tickerOf(p.inv);
    final quantity = (p.inv.raw['quantity'] as num?)?.toDouble();
    final price = (p.inv.raw['value'] as num?)?.toDouble();
    final parts = <String>[
      p.institution.name,
      if (ticker != null && quantity != null && price != null)
        '${NumberFormat('#,##0.########', 'pt_BR').format(quantity)} × '
            '${_money(price)}',
      if (_positionSort == _PositionSort.age && p.tax.ageDays != null)
        'há ${p.tax.ageDays} dias',
      if (p.tax.cost != null) 'aplicado ${_money(p.tax.cost!)}',
      if (p.tax.profit != null)
        'lucro ${_money(p.tax.profit!)}'
            '${p.profitPct == null ? '' : ' (${_pct(p.profitPct!)})'}',
      if (p.tax.rate > 0)
        'IR ${_pct(p.tax.rate * 100)}'
            '${p.daysToNextBracket == null ? '' : ' → ${_pct(p.nextRate! * 100)} em ${p.daysToNextBracket}d'}',
      if (p.inv.dueDate != null)
        'vence ${_dateFormat.format(DateTime.parse(p.inv.dueDate!))}',
    ];
    return ListTile(
      leading: InstitutionLogo(
        institution: ticker == null
            ? p.institution
            : StockCompany.badgeOf(ticker),
      ),
      title: Text(
        ticker != null
            ? StockCompany.titleOf(ticker)
            : '${p.product}${p.rateLabel == null ? '' : ' · ${p.rateLabel}'}',
      ),
      subtitle: Text(
        parts.join(' · '),
        style: theme.textTheme.bodySmall,
      ),
      trailing: Text(
        _money(p.balance),
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      onTap: () => _openPosition(p),
    );
  }

  void _openPosition(Position p) => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => InvestmentDetailPage(position: p)),
  );

  Widget _logo(Institution institution, double size) =>
      InstitutionLogo(institution: institution, size: size);
}

/// Bank logo in a rounded square, or the bank's initial when there is none.
class InstitutionLogo extends StatelessWidget {
  final Institution institution;
  final double size;

  const InstitutionLogo({Key? key, required this.institution, this.size = 32})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.25),
      child: SizedBox(
        width: size,
        height: size,
        child: institution.logo != null
            ? Container(
                // The coins' logos are round: no square around them.
                color: institution.logo!.contains('/crypto/')
                    ? null
                    : Colors.white,
                child: Image.asset(institution.logo!, fit: BoxFit.contain),
              )
            : Container(
                color: institution.color,
                alignment: Alignment.center,
                child: Text(
                  institution.name.isEmpty ? '?' : institution.name[0],
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: size * 0.45,
                  ),
                ),
              ),
      ),
    );
  }
}
