import 'package:aupp/accounts/money-accounts.dart';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:aupp/components/info-tip.dart';
import 'package:aupp/helpers/records-utility-functions.dart';
import 'package:aupp/services/crypto-quote-service.dart';
import 'package:aupp/services/service-config.dart';
import 'package:aupp/services/total-wallets.dart';
import 'package:url_launcher/url_launcher.dart';

import 'asset-lots-view.dart';
import 'asset-lots.dart';
import 'asset-sheet-page.dart';
import 'asset-sheet.dart';
import 'benchmark.dart';
import 'crypto-analytics.dart';
import 'crypto-history.dart';
import 'diagram.dart';
import 'freedom.dart';
import 'module-cards.dart';
import 'portfolio-tab.dart';
import 'investments-analytics.dart';
import 'investments-cache.dart';
import 'investments-page.dart';
import 'stock-catalog.dart';
import 'ticker-search.dart';
import 'us-catalog.dart';
import 'package:aupp/dinzo/daily-money.dart';

const _classColors = {
  DiagramClass.intlStock: Color(0xFF8CC8F8),
  DiagramClass.nationalStock: Color(0xFF9BEBC7),
  DiagramClass.fii: Color(0xFFF6EE85),
  DiagramClass.reit: Color(0xFFEDA9EE),
  DiagramClass.crypto: Color(0xFF7D9CF6),
  DiagramClass.fixedIncome: Color(0xFFF5A24B),
};

String _money(double value) => getCurrencyValueString(value);

String _pct(double value) => '${NumberFormat('0.0', 'pt_BR').format(value)}%';

String _units(double value) =>
    NumberFormat('#,##0.####', 'pt_BR').format(value);

double? _parse(String text) => double.tryParse(
  text
      .trim()
      .replaceAll('R\$', '')
      .replaceAll('.', '')
      .replaceAll(',', '.')
      .trim(),
);

/// [classes] in [assets], each on its own with its target, for a
/// [DivisionCard]: one part per asset, the fixed income as one.
List<DivisionGroup> divisionOf(
  List<DiagramAsset> assets,
  List<DiagramClass> classes,
  Map<DiagramClass, double> targets,
) => [
  for (final cls in classes)
    DivisionGroup(
      cls.label,
      cls == DiagramClass.fixedIncome
          ? [
              DivisionSlice(
                '_fixedIncome',
                'Renda fixa',
                assets
                    .where((a) => a.cls == cls && a.value > 0)
                    .fold(0.0, (sum, a) => sum + a.value),
              ),
            ]
          : [
              for (final a in assets)
                if (a.cls == cls && a.value > 0)
                  DivisionSlice(a.key, a.label, a.value),
            ],
      targets[cls] ?? 0,
    ),
];

const _rowStyle = TextStyle(fontSize: 13);
const _headStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.w700);

/// The portfolio method on its tabs: the tree, what you have and its grades,
/// the targets of each class and where the next contribution goes, with the
/// asset search over it. Given [portfolio] it is the Investimentos page: the
/// money by where it is first, then the method.
class DiagramPage extends StatefulWidget {
  const DiagramPage({super.key, this.portfolio});

  /// The Carteira tab, given what the method knows of every asset.
  final Widget Function(PortfolioContext context)? portfolio;

  @override
  State<DiagramPage> createState() => _DiagramPageState();
}

class _DiagramPageState extends State<DiagramPage> {
  DiagramState _state = DiagramState.load();
  List<DiagramAsset> _base = const [];
  final _prices = <String, double>{};

  /// Today's quote of what is here (for its change of the day), and the
  /// result of each stock held, from what the Dinzo says it cost.
  final _quotes = <String, AssetQuote>{};
  final _results = <String, double>{};

  /// The quote of what is quoted in dollars, and the dollar used.
  final _usdQuotes = <String, AssetQuote>{};
  final _usdHistory = <String, List<MapEntry<DateTime, double>>>{};
  List<MapEntry<DateTime, double>> _usdBrl = const [];
  double? _dollar;
  double _outside = 0;
  double _available = 0;
  double _goals = 0;
  double _spending = 0;
  double _reserve = 0;
  double _opportunity = 0;
  double _fixedIncomeHeld = 0;
  bool _loaded = false;
  bool _coinQuotesAsked = false;

  /// Grades come straight from the state: a changed question takes one away.
  List<DiagramAsset> get assets {
    final valued = [for (final a in _base) a.withData(value: _valueOf(a))];
    final topFull = topOfTriangle(valued, _state.tiers, wealth: _wealth).full;
    return [
      for (final asset in _base)
        DiagramAsset(
          key: asset.key,
          label: asset.label,
          cls: asset.cls,
          ticker: asset.ticker,
          value: _valueOf(asset),
          quantity: _state.abroad[asset.key] ?? asset.quantity,
          price: _prices[asset.key] ?? asset.price,
          grade: _state.gradeOf(asset),
          isManual: asset.isManual,
          isEtf: asset.isEtf,
          status: _state.statusOf(asset.key),
          blockedReason: topFull && _state.tiers[asset.key] == PortfolioTier.top
              ? 'topo no limite de 10%'
              : null,
        ),
    ];
  }

  @override
  void initState() {
    super.initState();
    DiagramState.revision.addListener(_saved);
    _load();
  }

  @override
  void dispose() {
    DiagramState.revision.removeListener(_saved);
    super.dispose();
  }

  /// A save here or in a Ficha that is also open.
  void _saved() {
    final fresh = DiagramState.load();
    final watchedChanged = !mapEquals(fresh.watched, _state.watched);
    setState(() => _state = fresh);
    if (watchedChanged) _load();
  }

  Future<void> _load() async {
    await _syncAbroad();
    final snapshot = await InvestmentsCache.load();
    final now = DateTime.now();
    final overview = snapshot == null
        ? null
        : InvestmentsOverview.from(snapshot.investments, now);
    final wallets = await ServiceConfig.database.getWalletsBalanceAsOf(now);
    final defaultWallet = await ServiceConfig.database.getDefaultWallet();
    // A coin without a quote yet (first start, the demo) is worth nothing
    // until CoinGecko answers: then the page loads again, once.
    if (!_coinQuotesAsked &&
        AssetLots.coins.keys.any((c) => CryptoQuoteService.priceInMain(c) == null)) {
      _coinQuotesAsked = true;
      CryptoQuoteService.refresh().then((fetched) {
        if (fetched && mounted) _load();
      });
    }
    final coins = [
      for (final coin in AssetLots.coins.entries)
        DiagramCoin(
          coin.key,
          cryptoNames[coin.key] ?? coin.key,
          coin.value,
          coin.value * (CryptoQuoteService.priceInMain(coin.key) ?? 0),
        ),
    ];
    var available = 0.0;
    var goals = 0.0;
    var reserve = 0.0;
    var opportunity = 0.0;
    var spending = 0.0;
    for (final wallet in wallets) {
      if (wallet.isArchived) continue;
      final balance = wallet.balance ?? wallet.initialAmount;
      if (wallet.id == defaultWallet?.id) {
        spending = balance;
      } else if (wallet.isInvestmentReserve) {
        available += balance;
      } else if (TotalWallets.isGoal(wallet, defaultWallet?.id)) {
        goals += balance;
        if (wallet.isEmergencyReserve) reserve += balance;
        if (wallet.isOpportunityReserve) opportunity += balance;
      }
    }
    if (!mounted) return;
    final costs = <String, (double, double)>{};
    for (final p in overview?.positions ?? const <Position>[]) {
      final ticker = StockCompany.tickerOf(p.inv);
      final cost = p.tax.cost, profit = p.tax.profit;
      if (ticker == null || cost == null || profit == null) continue;
      final (c, r) = costs[ticker] ?? (0.0, 0.0);
      costs[ticker] = (c + cost, r + profit);
    }
    _results
      ..clear()
      ..addAll({
        for (final e in costs.entries)
          if (e.value.$1 > 0) e.key: e.value.$2 / e.value.$1 * 100,
      });
    final result = diagramAssetsFrom(
      positions: [
        for (final p in overview?.positions ?? const <Position>[])
          if (!DailyMoney.isMoney(p.inv)) p,
      ],
      coins: coins,
      state: _state,
    );
    setState(() {
      _base = result.assets;
      _outside = result.outside;
      _available = available;
      _goals = goals;
      _spending = spending;
      _reserve = reserve;
      _opportunity = opportunity;
      _fixedIncomeHeld = result.fixedIncomeHeld;
      _loaded = true;
    });
    _loadPrices();
    _loadSectors();
  }

  /// Sectors of the stocks held, once each: brapi.dev counts every request.
  Future<void> _loadSectors() async {
    var found = false;
    for (final asset in _base) {
      final ticker = asset.ticker;
      if (ticker == null ||
          asset.value <= 0 ||
          asset.isEtf ||
          asset.cls != DiagramClass.nationalStock ||
          _state.sectors.containsKey(ticker)) {
        continue;
      }
      final profile = await AssetProfile.fetch(ticker);
      if (!mounted) return;
      if (profile?.sector == null) continue;
      _state.sectors[ticker] = profile!.sector!;
      found = true;
    }
    if (found) _changed();
  }

  /// Caixinhas, investments and what stays out of the method.
  double get _wealth =>
      _base.fold<double>(0, (sum, a) => sum + _valueOf(a)) +
      _goals +
      _available +
      _spending +
      _outside;

  /// The position's price can be a day old; a purchase wants today's.
  /// Prices in reais: what is abroad comes in dollars and is converted.
  Future<void> _loadPrices() async {
    await Future.wait([
      for (final asset in _base)
        if (asset.ticker != null)
          AssetQuote.fetch(asset.ticker!, withHistory: false).then((
            quote,
          ) async {
            if (quote == null) return;
            if (mounted) _quotes[asset.key] = quote;
            var price = quote.price;
            if (quote.currency == 'USD') {
              final dollar = await BenchmarkRates.dollar();
              if (dollar == null) return;
              if (mounted) {
                _usdQuotes[asset.key] = quote;
                _dollar = dollar;
              }
              price *= dollar;
            }
            if (mounted) setState(() => _prices[asset.key] = price);
          }),
    ]);
    await _loadAbroadHistory();
  }

  /// What the purchases abroad need for the chart: the closes of what is held,
  /// the dollar and the Selic since the first purchase.
  Future<void> _loadAbroadHistory() async {
    final held = {
      for (final asset in _base)
        if (asset.ticker != null && AssetLots.of(asset.key).isNotEmpty)
          asset.key: asset.ticker!,
    };
    if (held.isEmpty) return;
    await Future.wait([
      for (final e in held.entries)
        AssetQuote.fetch(e.value).then((quote) {
          if (quote == null) return;
          _usdHistory[e.key] = [
            for (final (day, close) in quote.history)
              MapEntry(DateTime(day.year, day.month, day.day), close),
          ];
        }),
    ]);
    try {
      final usdBrl = (await CryptoHistory.load(const ['BTC'])).usdBrl;
      if (mounted) setState(() => _usdBrl = usdBrl);
    } catch (e) {
      // Offline: without the chart, everything else still works.
    }
  }

  /// A price abroad in reais on a day: today's quote, or close × dollar.
  double? _abroadPriceOn(String key, DateTime day) {
    final now = DateTime.now();
    if (day.year == now.year && day.month == now.month && day.day == now.day) {
      if (_prices[key] != null) return _prices[key];
    }
    final close = CryptoAnalytics.priceOn(_usdHistory[key] ?? const [], day);
    final dollar = CryptoAnalytics.priceOn(_usdBrl, day);
    return close == null || dollar == null ? null : close * dollar;
  }

  /// The total held abroad follows the purchases. A total from before them
  /// becomes one purchase today, for the user to correct.
  Future<void> _syncAbroad() async {
    for (final e in _state.abroad.entries.toList()) {
      if (AssetLots.of(e.key).isEmpty) {
        await AssetLots.save(e.key, [
          AssetLot(
            day: DateTime.now(),
            quantity: e.value,
            note: 'Total de antes das compras: ajuste a data',
          ),
        ]);
      }
    }
    final held = AssetLots.all;
    var changed = false;
    for (final key in _state.abroad.keys.toList()) {
      final total = AssetLots.quantityOf(held[key] ?? const []);
      if (total != _state.abroad[key]) {
        _state.abroad[key] = total;
        changed = true;
      }
    }
    if (changed) _state.save();
  }

  /// Quantity held abroad times its price in reais.
  double _valueOf(DiagramAsset asset) {
    final quantity = _state.abroad[asset.key];
    final price = _prices[asset.key];
    if (quantity == null || quantity <= 0) return asset.value;
    return price == null ? 0 : quantity * price;
  }

  /// The purchases of something held abroad, each with its date.
  Future<void> _openLots(DiagramAsset asset) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AssetLotsPage(
          asset: asset.key,
          title: asset.label,
          priceOn: (day) => _abroadPriceOn(asset.key, day),
          afterChange: () async {
            final total = AssetLots.quantityOf(AssetLots.of(asset.key));
            if (total <= 0) {
              _state.abroad.remove(asset.key);
            } else {
              _state.abroad[asset.key] = total;
            }
            _changed();
          },
        ),
      ),
    );
    await _loadAbroadHistory();
  }

  void _changed() {
    _state.save();
    setState(() {});
  }

  Future<void> _addAsset({bool abroadOnly = false}) async {
    final added = await showDialog<(String, DiagramClass, bool, double)>(
      context: context,
      builder: (_) => _AddAssetDialog(abroadOnly: abroadOnly),
    );
    if (added == null || !mounted) return;
    final (ticker, cls, isEtf, quantity) = added;
    _state.watched[ticker] = cls;
    if (isEtf) _state.watchedEtfs.add(ticker);
    if (quantity > 0) {
      _state.abroad[ticker] = quantity;
      await AssetLots.save(ticker, [
        ...AssetLots.of(ticker),
        AssetLot(day: DateTime.now(), quantity: quantity),
      ]);
    }
    _state.save();
    await _load();
  }

  /// Only for what the user added: the answers go with it, unless undone.
  Future<void> _removeAsset(DiagramAsset asset) async {
    if (!_state.watched.containsKey(asset.key)) return;
    final before = _state.encode();
    _state.forget(asset.key);
    _state.save();
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${asset.label} removido'),
        action: SnackBarAction(
          label: 'Desfazer',
          onPressed: () {
            _state = DiagramState.decode(before);
            _state.save();
            _load();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hub = widget.portfolio != null;
    final assets = this.assets;
    return DefaultTabController(
      length: hub ? 5 : 4,
      initialIndex: hub ? 0 : 1,
      child: Scaffold(
        appBar: AppBar(
          // In Investimentos the tabs are the whole bar.
          toolbarHeight: hub ? 0 : null,
          title: hub ? null : const Text('Carteira e aporte'),
          bottom: _GroupedTabBar([
            if (hub) const [_TabItem(Icons.pie_chart_outline, 'Carteira')],
            [
              const _TabItem(Icons.park_outlined, 'Árvore'),
              const _TabItem(Icons.pie_chart_outline, 'Meus ativos'),
              const _TabItem(Icons.track_changes, 'Metas'),
              const _TabItem(Icons.add_card, 'Aportar e buscar'),
            ],
          ]),
        ),
        body: TabBarView(
          // Only the tabs change the page: a swipe belongs to the charts.
          physics: const NeverScrollableScrollPhysics(),
          children: [
            if (hub) ...[
              _KeepAlive(
                widget.portfolio!(
                  PortfolioContext(
                    loaded: _loaded,
                    assets: _loaded ? assets : const [],
                    targets: _state.targets,
                    quotes: _quotes,
                    stockResults: _results,
                    dollar: _dollar,
                    abroadPriceOn: _abroadPriceOn,
                    pill: (cls) => _Pill(cls),
                    onAddAbroad: () => _addAsset(abroadOnly: true),
                    onOpenLots: _openLots,
                    onRemove: _removeAsset,
                  ),
                ),
              ),
            ],
            _loading(
              () => _TreeTab(
                assets: assets,
                wealth: _wealth,
                state: _state,
                reserve: _reserve,
                fixedIncomeHeld: _fixedIncomeHeld,
                onChanged: _changed,
              ),
            ),
            _loading(
              () => _AssetsTab(
                assets: assets,
                wealth: _wealth,
                state: _state,
                outside: _outside,
                goals: _goals,
                onAdd: _addAsset,
                onQuantity: _openLots,
                onRemove: _removeAsset,
                onChanged: _changed,
              ),
            ),
            _loading(
              () => _TargetsTab(
                assets: assets,
                state: _state,
                onChanged: _changed,
                opportunityShare: _wealth <= 0
                    ? 0
                    : _opportunity / _wealth * 100,
              ),
            ),
            _KeepAlive(
              AssetSearchPage(
                embedded: true,
                idle: _loading(
                  () => _ContributionTab(
                    assets: assets,
                    state: _state,
                    available: _available,
                    reserve: _reserve,
                    opportunity: _opportunity,
                    onChanged: _changed,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A tab of the portfolio: waits for the data and follows the privacy mode.
  Widget _loading(Widget Function() tab) => !_loaded
      ? const Center(child: CircularProgressIndicator())
      : tab();
}

class _TabItem {
  final IconData icon;
  final String label;

  const _TabItem(this.icon, this.label);
}

/// Tabs as pills in two groups, one at each end of the bar. It scrolls sideways
/// when the screen is too narrow for both.
class _GroupedTabBar extends StatelessWidget implements PreferredSizeWidget {
  const _GroupedTabBar(this.groups);

  final List<List<_TabItem>> groups;

  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context) {
    final controller = DefaultTabController.of(context);
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        var index = 0;
        Widget pill(_TabItem item) {
          final i = index++;
          final selected = controller.index == i;
          final color = selected
              ? scheme.onSecondaryContainer
              : scheme.onSurfaceVariant;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Material(
              color: selected ? scheme.secondaryContainer : Colors.transparent,
              shape: const StadiumBorder(),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () => controller.animateTo(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(item.icon, size: 18, color: color),
                      const SizedBox(width: 6),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 13,
                          color: color,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        final rows = [
          for (final group in groups)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: group.map(pill).toList(),
            ),
        ];
        return LayoutBuilder(
          builder: (context, constraints) => SizedBox(
            height: preferredSize.height,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (final (i, row) in rows.indexed) ...[
                        if (i > 0) const SizedBox(width: 24),
                        row,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Keeps a tab alive while another is on screen: its data loads once.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive(this.child);

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// What is held abroad: typed by hand, since no foreign broker is read. Valued
/// by the quote in dollars times the dollar of the day.
class _Pill extends StatelessWidget {
  const _Pill(this.cls, {this.selected = true, this.onTap});

  final DiagramClass? cls;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = cls == null ? Colors.white : _classColors[cls]!;
    return Material(
      color: selected ? color : color.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          child: Text(
            cls?.label ?? 'Todos',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.black87 : color,
            ),
          ),
        ),
      ),
    );
  }
}

/// A ring of what the portfolio holds by class, or what it should hold.
class _Donut extends StatelessWidget {
  const _Donut(this.values, {required this.center, this.size = 120});

  final Map<DiagramClass, double> values;
  final String center;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _DonutPainter(
          values,
          Theme.of(context).colorScheme.surfaceContainerHigh,
        ),
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(size * 0.16),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final Map<DiagramClass, double> values;
  final Color empty;

  _DonutPainter(this.values, this.empty);

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 12.0;
    final rect = Offset.zero & size;
    final arc = rect.deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    final total = values.values.fold<double>(0, (a, b) => a + b);
    if (total <= 0) {
      canvas.drawArc(arc, 0, 2 * math.pi, false, paint..color = empty);
      return;
    }
    var start = -math.pi / 2;
    for (final cls in DiagramClass.values) {
      final value = values[cls] ?? 0;
      if (value <= 0) continue;
      final sweep = value / total * 2 * math.pi;
      canvas.drawArc(
        arc,
        start,
        sweep,
        false,
        paint..color = _classColors[cls]!,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.values != values;
}

class _Legend extends StatelessWidget {
  const _Legend(this.values);

  /// Class → text beside its name.
  final Map<DiagramClass, String> values;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final cls in DiagramClass.values)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: _classColors[cls],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    cls.label,
                    style: _rowStyle,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (values[cls] != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    values[cls]!,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// Each class in one line: its color and name, how much it has, its share
/// today and its target.
class _ClassSummary extends StatelessWidget {
  const _ClassSummary(this.values, this.targets);

  final Map<DiagramClass, double> values;
  final Map<DiagramClass, double> targets;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = values.values.fold<double>(0, (a, b) => a + b);
    final head = theme.textTheme.bodySmall;
    Widget cell(String text, double width, {TextStyle? style}) => SizedBox(
      width: width,
      child: Text(
        text,
        textAlign: TextAlign.right,
        maxLines: 1,
        style: style ?? _rowStyle,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Spacer(),
            cell('Tem', 78, style: head),
            cell('Hoje', 48, style: head),
            cell('Meta', 40, style: head),
          ],
        ),
        for (final cls in DiagramClass.values)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: _classColors[cls],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    cls.label,
                    style: _rowStyle,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                cell(_money(values[cls] ?? 0), 78),
                cell(
                  _pct(total <= 0 ? 0 : (values[cls] ?? 0) / total * 100),
                  48,
                  style: _rowStyle.copyWith(fontWeight: FontWeight.w700),
                ),
                cell('${(targets[cls] ?? 0).round()}%', 40),
              ],
            ),
          ),
      ],
    );
  }
}

/// A dense table. Columns with [wideOnly] go away on a phone.
class _Column {
  final String title;
  final int flex;
  final bool right;
  final bool wideOnly;

  const _Column(
    this.title,
    this.flex, {
    this.right = false,
    this.wideOnly = false,
  });
}

class _Table extends StatelessWidget {
  const _Table({
    required this.columns,
    required this.rows,
    this.below = const {},
  });

  final List<_Column> columns;
  final List<List<Widget>> rows;

  /// What opens under a row, by its index.
  final Map<int, Widget> below;

  static const _breakpoint = 620.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _breakpoint;
        Widget row(List<Widget> cells) => Row(
          children: [
            for (final (i, column) in columns.indexed)
              if (wide || !column.wideOnly)
                Expanded(
                  flex: column.flex,
                  child: Align(
                    alignment: column.right
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: cells[i],
                    ),
                  ),
                ),
          ],
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              color: theme.colorScheme.surfaceContainerHigh,
              child: row([
                for (final column in columns)
                  Text(
                    column.title,
                    style: _headStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ]),
            ),
            for (final (i, cells) in rows.indexed) ...[
              Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: theme.colorScheme.outlineVariant,
                      width: 0.5,
                    ),
                  ),
                ),
                child: row(cells),
              ),
              ?below[i],
            ],
          ],
        );
      },
    );
  }
}

Widget _text(String text, {Color? color, bool bold = false}) => Text(
  text,
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
  style: _rowStyle.copyWith(
    color: color,
    fontWeight: bold ? FontWeight.w700 : null,
  ),
);

/// The grade, edited where it is. Clicking a typed grade turns it into a field;
/// a grade that comes from the questions opens them under the row.
class _GradeCell extends StatefulWidget {
  const _GradeCell({
    super.key,
    required this.asset,
    required this.state,
    required this.onChanged,
    required this.open,
    required this.onToggle,
  });

  final DiagramAsset asset;
  final DiagramState state;
  final VoidCallback onChanged;
  final bool open;
  final VoidCallback onToggle;

  @override
  State<_GradeCell> createState() => _GradeCellState();
}

class _GradeCellState extends State<_GradeCell> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _start() {
    _controller.text = widget.asset.grade?.toString() ?? '';
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
    setState(() => _editing = true);
  }

  void _commit() {
    if (!_editing || !mounted) return;
    setState(() => _editing = false);
    final key = widget.asset.key;
    final typed = int.tryParse(_controller.text.trim());
    if (typed == widget.state.typedGrades[key]) return;
    if (typed == null) {
      widget.state.typedGrades.remove(key);
    } else {
      widget.state.typedGrades[key] = typed.clamp(0, 10);
    }
    widget.state.touch(key);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    if (_editing) {
      return SizedBox(
        width: 44,
        height: 28,
        child: TextField(
          controller: _controller,
          focusNode: _focus,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textAlign: TextAlign.center,
          style: _rowStyle,
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 2, vertical: 6),
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _commit(),
        ),
      );
    }
    final colors = Theme.of(context).colorScheme;
    final grade = widget.asset.grade;
    final stale = widget.state.isStale(widget.asset.key, DateTime.now());
    return Tooltip(
      message: stale ? 'Nota antiga: reavaliar' : 'Dar nota',
      child: Material(
        color: widget.open
            ? colors.primaryContainer
            : colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.asset.cls.hasQuestionnaire ? widget.onToggle : _start,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            child: grade == null
                ? Text(
                    'sem nota',
                    maxLines: 1,
                    style: TextStyle(fontSize: 11, color: colors.error),
                  )
                : _text(
                    '$grade',
                    bold: true,
                    color: stale ? colors.error : null,
                  ),
          ),
        ),
      ),
    );
  }
}

/// The questions of an asset, open under its row. Each answer counts right away.
/// The questions of an asset, here and on its Ficha: the answers are the same.
class DiagramQuestionsPanel extends StatelessWidget {
  const DiagramQuestionsPanel({
    super.key,
    required this.asset,
    required this.state,
    required this.onChanged,
  });

  final DiagramAsset asset;
  final DiagramState state;
  final VoidCallback onChanged;

  QuestionSet get _set => asset.questionSet;
  List<String> get _questions => state.questionsOf(_set);

  static const _titles = {
    QuestionSet.stock: 'Perguntas de ações',
    QuestionSet.fii: 'Perguntas de FIIs e REITs',
    QuestionSet.etf: 'Perguntas de ETFs',
  };

  Future<void> _editQuestions(BuildContext context) async {
    final controller = TextEditingController(text: _questions.join('\n'));
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_titles[_set]!),
        content: SizedBox(
          width: 560,
          child: TextField(
            controller: controller,
            maxLines: 14,
            style: _rowStyle,
            decoration: const InputDecoration(
              helperText:
                  'Uma por linha. Mudar uma pergunta pede uma nova resposta dela '
                  'em todos os ativos.',
              helperMaxLines: 2,
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(
              context,
              DiagramState.defaultsOf(_set).join('\n'),
            ),
            child: const Text('Restaurar padrão'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null) return;
    final questions = [
      for (final line in text.split('\n'))
        if (line.trim().isNotEmpty) line.trim(),
    ];
    if (questions.isEmpty) return;
    state.setQuestions(_set, questions);
    onChanged();
  }

  /// Where to read the answer, from the sites of the Ficha.
  List<AssetLink> _sources(String question) {
    final ticker = asset.ticker;
    final labels = DiagramState.questionSources[question];
    if (ticker == null || labels == null) return const [];
    final links = assetLinks(
      ticker,
      StockCompany.of(ticker)?.name,
      kind: switch (_set) {
        QuestionSet.fii => AssetKind.fii,
        QuestionSet.etf => AssetKind.etf,
        QuestionSet.stock => AssetKind.stock,
      },
    );
    return [
      for (final label in labels) ...links.where((link) => link.label == label),
    ];
  }

  void _answer(String question, String? value) {
    final answers = state.answers.putIfAbsent(asset.key, () => {});
    final skipped = state.skipped.putIfAbsent(asset.key, () => {});
    answers.remove(question);
    skipped.remove(question);
    if (value == 'yes') answers[question] = true;
    if (value == 'no') answers[question] = false;
    if (value == 'na') skipped.add(question);
    state.touch(asset.key);
    onChanged();
  }

  Widget _question(BuildContext context, String question) {
    final answer = state.answers[asset.key]?[question];
    final skipped = state.skipped[asset.key]?.contains(question) ?? false;
    final selected = skipped
        ? 'na'
        : answer == null
        ? null
        : answer
        ? 'yes'
        : 'no';
    final sources = _sources(question);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(question, style: _rowStyle),
                if (sources.isNotEmpty)
                  Wrap(
                    spacing: 10,
                    children: [
                      for (final link in sources)
                        InkWell(
                          onTap: () => launchUrl(
                            link.url,
                            mode: LaunchMode.externalApplication,
                          ),
                          child: Text(
                            '${link.label} ↗',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SegmentedButton<String>(
            emptySelectionAllowed: true,
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity(horizontal: -3, vertical: -3),
              textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
            ),
            segments: const [
              ButtonSegment(value: 'yes', label: Text('Sim')),
              ButtonSegment(value: 'no', label: Text('Não')),
              ButtonSegment(
                value: 'na',
                label: Text('N/A'),
                tooltip: 'Não se aplica a este ativo: não conta',
              ),
            ],
            selected: {?selected},
            onSelectionChanged: (value) =>
                _answer(question, value.isEmpty ? null : value.single),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final answers = state.answers[asset.key] ?? const <String, bool>{};
    final skipped = state.skipped[asset.key] ?? const <String>{};
    final grade = questionnaireGrade(_questions, answers, skipped: skipped);
    final answered = _questions
        .where((q) => answers.containsKey(q) || skipped.contains(q))
        .length;
    final at = state.gradedAt[asset.key];
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const InfoTip(
                'Sim soma 1, não tira 1, N/A não conta. Só nota positiva recebe '
                'aporte.',
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  at == null
                      ? ''
                      : 'Respondida em ${DateFormat('dd/MM/yyyy').format(at)} · '
                            'próxima revisão '
                            '${DateFormat('dd/MM/yyyy').format(DiagramState.nextReview(DateTime.now()))}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                grade == null
                    ? '$answered/${_questions.length}'
                    : 'Nota $grade',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          if (at != null && state.isStale(asset.key, DateTime.now()))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Revisão de '
                      '${DateFormat('dd/MM').format(DiagramState.reviewStart(DateTime.now()))} '
                      'pendente: confira as respostas com os balanços novos.',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    onPressed: () {
                      state.touch(asset.key);
                      onChanged();
                    },
                    child: const Text('Revisei, continua igual'),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'No triângulo:',
                style: _rowStyle.copyWith(fontWeight: FontWeight.w600),
              ),
              SegmentedButton<PortfolioTier>(
                emptySelectionAllowed: true,
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity(horizontal: -3, vertical: -3),
                  textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
                ),
                segments: [
                  for (final tier in PortfolioTier.values)
                    ButtonSegment(
                      value: tier,
                      label: Text(tier.label),
                      tooltip: tier.description,
                    ),
                ],
                selected: {?state.tiers[asset.key]},
                onSelectionChanged: (value) {
                  if (value.isEmpty) {
                    state.tiers.remove(asset.key);
                  } else {
                    state.tiers[asset.key] = value.single;
                  }
                  onChanged();
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final question in _questions) _question(context, question),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.edit_note, size: 18),
              label: const Text('Editar perguntas'),
              onPressed: () => _editQuestions(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// Aportando, pausado or desmontando, beside the name. Changing it asks why:
/// only fundamentals, an emergency or living off the portfolio justify it.
class _StatusButton extends StatelessWidget {
  const _StatusButton({
    required this.asset,
    required this.state,
    required this.onChanged,
  });

  final DiagramAsset asset;
  final DiagramState state;
  final VoidCallback onChanged;

  static IconData iconOf(HoldStatus status) => switch (status) {
    HoldStatus.buying => Icons.play_circle_outline,
    HoldStatus.paused => Icons.pause_circle,
    HoldStatus.unwinding => Icons.south_east,
  };

  static Color colorOf(BuildContext context, HoldStatus status) =>
      switch (status) {
        HoldStatus.buying => Theme.of(context).colorScheme.outline,
        HoldStatus.paused => Colors.amber.shade700,
        HoldStatus.unwinding => Theme.of(context).colorScheme.error,
      };

  Future<void> _choose(BuildContext context, HoldStatus status) async {
    if (status == HoldStatus.buying) {
      state.status.remove(asset.key);
      state.statusNotes.remove(asset.key);
      onChanged();
      return;
    }
    final reason = await showDialog<String>(
      context: context,
      builder: (_) =>
          _ReasonDialog(status: status, current: state.statusNotes[asset.key]),
    );
    if (reason == null) return;
    state.status[asset.key] = status;
    state.statusNotes[asset.key] = reason;
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final status = state.statusOf(asset.key);
    final note = state.statusNotes[asset.key];
    return PopupMenuButton<HoldStatus>(
      tooltip: note == null ? status.label : '${status.label}: $note',
      padding: EdgeInsets.zero,
      onSelected: (value) => _choose(context, value),
      itemBuilder: (context) => [
        for (final option in HoldStatus.values)
          PopupMenuItem(
            value: option,
            child: Row(
              children: [
                Icon(iconOf(option), size: 18, color: colorOf(context, option)),
                const SizedBox(width: 8),
                Text(option.label),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Icon(iconOf(status), size: 16, color: colorOf(context, status)),
      ),
    );
  }
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.status, this.current});

  final HoldStatus status;
  final String? current;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  late String? _reason = holdReasons.contains(widget.current)
      ? widget.current
      : null;
  late final _other = TextEditingController(
    text: holdReasons.contains(widget.current) ? '' : widget.current ?? '',
  );

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  String? get _chosen =>
      _other.text.trim().isNotEmpty ? _other.text.trim() : _reason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unwinding = widget.status == HoldStatus.unwinding;
    return AlertDialog(
      title: Text(widget.status.label),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                unwinding
                    ? 'Vender só aos poucos (uma venda por semestre ruim) e parar se '
                          'a empresa reagir. Queda ou alta da cotação não é motivo.'
                    : 'O ativo fica na carteira e só deixa de receber aportes. '
                          'Cotação em queda não é motivo: empresa boa em queda é hora de comprar.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              RadioGroup<String>(
                groupValue: _reason,
                onChanged: (value) => setState(() {
                  _reason = value;
                  _other.clear();
                }),
                child: Column(
                  children: [
                    for (final reason in holdReasons)
                      RadioListTile<String>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: reason,
                        title: Text(reason, style: _rowStyle),
                      ),
                  ],
                ),
              ),
              TextField(
                controller: _other,
                decoration: const InputDecoration(
                  labelText: 'Outro motivo',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _chosen == null
              ? null
              : () => Navigator.pop(context, _chosen),
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}

Widget _rowIcon(String tooltip, IconData icon, VoidCallback onPressed) =>
    IconButton(
      tooltip: tooltip,
      style: IconButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: const Size(28, 28),
        fixedSize: const Size(28, 28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: Icon(icon, size: 18),
      onPressed: onPressed,
    );

/// The asset's logo and name in a row of a table. Fixed income has no logo.
Widget _assetCell(DiagramAsset asset) => Row(
  children: [
    if (asset.ticker != null && asset.cls != DiagramClass.fixedIncome) ...[
      InstitutionLogo(
        institution: StockCompany.badgeOf(asset.ticker!),
        size: 20,
      ),
      const SizedBox(width: 6),
    ],
    Flexible(child: _text(_nameOf(asset), bold: true)),
  ],
);

String _nameOf(DiagramAsset asset) {
  final ticker = asset.ticker;
  if (ticker == null) return asset.label;
  return cryptoNames[ticker] == null
      ? ticker
      : '$ticker · ${cryptoNames[ticker]}';
}

class _AssetsTab extends StatefulWidget {
  const _AssetsTab({
    required this.assets,
    required this.wealth,
    required this.state,
    required this.outside,
    required this.goals,
    required this.onAdd,
    required this.onQuantity,
    required this.onRemove,
    required this.onChanged,
  });

  final List<DiagramAsset> assets;
  final double wealth;
  final DiagramState state;
  final double outside;
  final double goals;
  final VoidCallback onAdd;
  final void Function(DiagramAsset) onQuantity;
  final void Function(DiagramAsset) onRemove;
  final VoidCallback onChanged;

  @override
  State<_AssetsTab> createState() => _AssetsTabState();
}

class _AssetsTabState extends State<_AssetsTab> {
  DiagramClass? _filter;
  String _query = '';
  String? _openQuestions;

  Map<DiagramClass, double> get _byClass {
    final values = <DiagramClass, double>{};
    for (final asset in widget.assets) {
      values[asset.cls] = (values[asset.cls] ?? 0) + asset.value;
    }
    return values;
  }

  /// How much the asset lacks to reach its ideal: the target of its class,
  /// split by grade. The same gap the contribution fills.
  Widget _missingCell(DiagramAsset asset, double total) {
    if (!asset.isEligible) return _text('—');
    final target = widget.state.targets[asset.cls] ?? 0;
    final ideal =
        target / 100 * total * idealShareInClass(asset, widget.assets) / 100;
    final missing = ideal - asset.value;
    return Tooltip(
      message: 'Ideal: ${_money(ideal)}',
      child: missing < 1
          ? _text('—')
          : _text(
              _money(missing),
              color: Theme.of(context).colorScheme.primary,
              bold: true,
            ),
    );
  }

  Widget _table() {
    final total = _byClass.values.fold<double>(0, (a, b) => a + b);
    final query = _query.trim().toLowerCase();
    final shown = widget.assets
        .where(
          (a) =>
              (_filter == null || a.cls == _filter) &&
              (query.isEmpty || _nameOf(a).toLowerCase().contains(query)),
        )
        .toList();
    if (shown.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('Nenhum ativo aqui.')),
      );
    }
    return _Table(
      columns: const [
        _Column('Tipo', 5, wideOnly: true),
        _Column('Ativo', 5),
        _Column('Valor atual', 4, right: true),
        _Column('Falta', 4, right: true),
        _Column('Nota', 3, right: true),
        _Column('Qtd.', 3, right: true, wideOnly: true),
        _Column('', 4, right: true),
      ],
      below: {
        for (final (i, asset) in shown.indexed)
          if (asset.key == _openQuestions)
            i: DiagramQuestionsPanel(
              asset: asset,
              state: widget.state,
              onChanged: widget.onChanged,
            ),
      },
      rows: [
        for (final asset in shown)
          [
            _Pill(asset.cls),
            Row(
              children: [
                if (asset.cls != DiagramClass.fixedIncome)
                  _StatusButton(
                    asset: asset,
                    state: widget.state,
                    onChanged: widget.onChanged,
                  ),
                Flexible(child: _assetCell(asset)),
              ],
            ),
            asset.cls == DiagramClass.intlStock ||
                    asset.cls == DiagramClass.reit
                ? Tooltip(
                    message: 'Suas compras lá fora',
                    child: InkWell(
                      onTap: () => widget.onQuantity(asset),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(child: _text(_money(asset.value))),
                          const SizedBox(width: 3),
                          const Icon(Icons.edit_outlined, size: 13),
                        ],
                      ),
                    ),
                  )
                : _text(_money(asset.value)),
            _missingCell(asset, total),
            _GradeCell(
              key: ValueKey(asset.key),
              asset: asset,
              state: widget.state,
              onChanged: widget.onChanged,
              open: asset.key == _openQuestions,
              onToggle: () => setState(
                () => _openQuestions = asset.key == _openQuestions
                    ? null
                    : asset.key,
              ),
            ),
            _text(asset.quantity > 0 ? _units(asset.quantity) : '—'),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (asset.ticker != null)
                  _rowIcon(
                    'Abrir a Ficha',
                    Icons.manage_search,
                    () => AssetSheetPage.open(context, asset.ticker!),
                  ),
                if (asset.isManual)
                  _rowIcon(
                    'Remover',
                    Icons.delete_outline,
                    () => widget.onRemove(asset),
                  ),
              ],
            ),
          ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final byClass = _byClass;
    final total = byClass.values.fold<double>(0, (a, b) => a + b);
    final summary = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Donut(byClass, center: _money(total), size: 132),
        const SizedBox(height: 12),
        _ClassSummary(byClass, widget.state.targets),
      ],
    );
    final filters = Wrap(
      spacing: 5,
      runSpacing: 5,
      children: [
        _Pill(
          null,
          selected: _filter == null,
          onTap: () => setState(() => _filter = null),
        ),
        for (final cls in DiagramClass.values)
          _Pill(
            cls,
            selected: _filter == cls,
            onTap: () => setState(() => _filter = _filter == cls ? null : cls),
          ),
      ],
    );
    final search = Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 36,
            child: TextField(
              style: _rowStyle,
              decoration: const InputDecoration(
                hintText: 'Pesquisar',
                prefixIcon: Icon(Icons.search, size: 18),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: widget.onAdd,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Adicionar', style: _rowStyle),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 860;
        final main = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            search,
            const SizedBox(height: 8),
            filters,
            const SizedBox(height: 8),
            _table(),
            if (widget.goals + widget.outside > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Text(
                      'Fora da conta: '
                      '${_money(widget.goals + widget.outside)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(width: 4),
                    InfoTip(
                      '${_money(widget.goals)} de metas ficam nos bancos do dia a '
                      'dia. '
                      '${_money(widget.outside)} em fundos, previdência e COE ficam '
                      'fora: você não escolhe o que eles têm.',
                    ),
                  ],
                ),
              ),
          ],
        );
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: main),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 300,
                    child: Column(
                      children: [
                        summary,
                        const SizedBox(height: 16),
                        _TriangleCard(
                          widget.assets,
                          widget.state,
                          widget.wealth,
                        ),
                        const SizedBox(height: 12),
                        ?_sectorsCard(context, widget.assets, widget.state),
                      ],
                    ),
                  ),
                ],
              )
            else ...[
              Center(child: summary),
              const SizedBox(height: 12),
              main,
              const SizedBox(height: 16),
              _TriangleCard(widget.assets, widget.state, widget.wealth),
              const SizedBox(height: 12),
              ?_sectorsCard(context, widget.assets, widget.state),
            ],
          ],
        );
      },
    );
  }
}

class _TargetsTab extends StatefulWidget {
  const _TargetsTab({
    required this.assets,
    required this.state,
    required this.onChanged,
    required this.opportunityShare,
  });

  final List<DiagramAsset> assets;
  final DiagramState state;
  final VoidCallback onChanged;

  /// The opportunity reserve, in % of wealth: it is not a class.
  final double opportunityShare;

  @override
  State<_TargetsTab> createState() => _TargetsTabState();
}

class _TargetsTabState extends State<_TargetsTab> {
  late Map<DiagramClass, double> _draft = {...widget.state.targets};

  double get _total => _draft.values.fold(0, (a, b) => a + b);
  bool get _valid => (_total - 100).abs() < 0.01;
  bool get _unsaved => DiagramClass.values.any(
    (c) => (_draft[c] ?? 0) != (widget.state.targets[c] ?? 0),
  );

  void _save() {
    widget.state.targets
      ..clear()
      ..addAll({
        for (final e in _draft.entries)
          if (e.value > 0) e.key: e.value,
      });
    widget.onChanged();
    setState(() {});
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Metas salvas')));
  }

  Map<DiagramClass, double> get _held {
    final values = <DiagramClass, double>{};
    for (final asset in widget.assets) {
      values[asset.cls] = (values[asset.cls] ?? 0) + asset.value;
    }
    return values;
  }

  double get _heldTotal => _held.values.fold(0, (a, b) => a + b);

  /// In reais, per class: what it has, what the target means and what is
  /// missing or left over. Shown behind the (i) by the total.
  String _figures() {
    final total = _heldTotal;
    if (total <= 0) return '';
    return [
      for (final cls in DiagramClass.values)
        () {
          final have = _held[cls] ?? 0;
          final goal = (_draft[cls] ?? 0) / 100 * total;
          final missing = goal - have;
          final gap = missing.abs() < total * 0.005
              ? 'na meta'
              : missing > 0
              ? 'faltam ${_money(missing)}'
              : 'sobram ${_money(-missing)}';
          return '${cls.label}: tem ${_money(have)} (${_pct(have / total * 100)}) · '
              'meta ${_money(goal)} · $gap';
        }(),
    ].join('\n');
  }

  /// A class: its target on a slider marked where it is today.
  Widget _classRow(BuildContext context, DiagramClass cls) {
    final theme = Theme.of(context);
    final total = _heldTotal;
    final have = _held[cls] ?? 0;
    final haveShare = total <= 0 ? 0.0 : have / total * 100;
    final target = _draft[cls] ?? 0;
    final slider = SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTrackColor: _classColors[cls],
        thumbColor: _classColors[cls],
        trackHeight: 4,
        overlayShape: SliderComponentShape.noOverlay,
      ),
      child: Slider(
        value: target.clamp(0, 100),
        max: 100,
        divisions: 100,
        onChanged: (value) =>
            setState(() => _draft[cls] = value.roundToDouble()),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 28,
            child: Row(
              children: [
                SizedBox(
                  width: 142,
                  child: Text(
                    cls.label,
                    style: _rowStyle.copyWith(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // The track runs between the thumb's radius on each side.
                      const inset = 10.0;
                      final x =
                          inset +
                          (constraints.maxWidth - 2 * inset) *
                              haveShare.clamp(0, 100) /
                              100;
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          slider,
                          if (total > 0)
                            Positioned(
                              left: x - 1,
                              top: 0,
                              bottom: 0,
                              child: IgnorePointer(
                                child: Center(
                                  child: Container(
                                    width: 2,
                                    height: 14,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 42,
                  child: Text(
                    '${target.round()}%',
                    textAlign: TextAlign.right,
                    style: _rowStyle.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = _total;
    final overview = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Donut(_draft, center: '${total.round()}%', size: 104),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _valid
                  ? 'Total: 100%'
                  : total < 100
                  ? 'Faltam ${_pct(100 - total)}'
                  : 'Passou ${_pct(total - 100)}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: _valid ? null : theme.colorScheme.error,
              ),
            ),
            const SizedBox(width: 4),
            InfoTip(
              'Quanto de cada tipo você quer ter. A soma precisa dar 100%. '
              'O traço em cada barra é onde você está hoje.'
              '${_heldTotal > 0 ? '\n\n${_figures()}' : ''}',
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text('Você tem', style: theme.textTheme.bodySmall),
        Text(
          _money(_heldTotal),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    );
    final sliders = Column(
      children: [
        for (final cls in DiagramClass.values) _classRow(context, cls),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _unsaved
                  ? () => setState(() => _draft = {...widget.state.targets})
                  : null,
              child: const Text('Desfazer'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _valid && _unsaved ? _save : null,
              child: const Text('Salvar'),
            ),
          ],
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (constraints.maxWidth >= 620)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                overview,
                const SizedBox(width: 24),
                Expanded(child: sliders),
              ],
            )
          else ...[
            Center(child: overview),
            const SizedBox(height: 8),
            sliders,
          ],
          const SizedBox(height: 16),
          _piarCard(context),
        ],
      ),
    );
  }

  /// The investor profiles: their ranges as a check of the targets being
  /// drafted, and their suggested targets a tap away.
  Widget _piarCard(BuildContext context) {
    final theme = Theme.of(context);
    final profile = widget.state.piarProfile;
    final suggested = profile?.suggestedTargets;
    final applied =
        suggested != null &&
        DiagramClass.values.every(
          (c) => (suggested[c] ?? 0) == (_draft[c] ?? 0),
        );
    double mine(PiarGroup group) => group == PiarGroup.opportunity
        ? widget.opportunityShare
        : group.classes.fold(0.0, (sum, cls) => sum + (_draft[cls] ?? 0));
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    'Referência do seu perfil (PIAR)',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                const SizedBox(width: 6),
                const InfoTip(
                  'Escolha um perfil para ver as faixas dele e, se quiser, usar as '
                  'metas que ele sugere. As faixas já vêm sem a reserva de '
                  'oportunidade, que fica fora das metas. Exterior soma ações, ETFs '
                  'e renda fixa fora do Brasil.',
                ),
              ],
            ),
            DropdownButton<PiarProfile>(
              value: profile,
              isExpanded: true,
              hint: const Text('Escolher o perfil'),
              underline: const SizedBox.shrink(),
              items: [
                for (final p in PiarProfile.values)
                  DropdownMenuItem(value: p, child: Text(p.label)),
              ],
              onChanged: (value) {
                widget.state.piarProfile = value;
                widget.onChanged();
                setState(() {});
              },
            ),
            if (profile != null) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: applied
                      ? null
                      : () {
                          setState(() => _draft = {...suggested!});
                          _save();
                        },
                  icon: Icon(applied ? Icons.check : Icons.auto_fix_high),
                  label: Text(
                    applied
                        ? 'Suas metas são as do perfil'
                        : 'Usar como minhas metas',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              for (final e in profile.ranges.entries)
                Builder(
                  builder: (context) {
                    final (low, high) = e.key == PiarGroup.opportunity
                        ? e.value
                        : profile.portfolioRange(e.key);
                    final value = mine(e.key);
                    final inside = value >= low - 0.01 && value <= high + 0.01;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Tooltip(
                            message: inside
                                ? 'Dentro da faixa do perfil: '
                                      '${low.round()}–${high.round()}%'
                                : value < low
                                ? 'Abaixo da faixa do perfil: o perfil pede '
                                      'pelo menos ${low.round()}%'
                                : 'Acima da faixa do perfil: o perfil pede '
                                      'no máximo ${high.round()}%',
                            waitDuration: const Duration(milliseconds: 200),
                            triggerMode: TooltipTriggerMode.tap,
                            child: Icon(
                              inside
                                  ? Icons.check_circle
                                  : value < low
                                  ? Icons.arrow_circle_up
                                  : Icons.arrow_circle_down,
                              size: 18,
                              color: inside
                                  ? const Color(0xFF43A047)
                                  : Colors.amber.shade700,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(e.key.label, style: _rowStyle)),
                          Text(
                            '${low.round()}–${high.round()}%',
                            style: theme.textTheme.bodySmall,
                          ),
                          SizedBox(
                            width: 64,
                            child: Text(
                              _pct(value),
                              textAlign: TextAlign.right,
                              style: _rowStyle.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }
}

const _tierColors = {
  PortfolioTier.base: Color(0xFFF2B33D),
  PortfolioTier.middle: Color(0xFFC0CA33),
  PortfolioTier.top: Color(0xFF7CB342),
};

/// The inverted triangle of the course: how the stocks and funds split
/// between base, middle and top, and the top against its limit.
class _TriangleCard extends StatelessWidget {
  const _TriangleCard(this.assets, this.state, this.wealth);

  final List<DiagramAsset> assets;
  final DiagramState state;
  final double wealth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final byTier = <PortfolioTier, double>{};
    for (final asset in assets) {
      final tier = state.tiers[asset.key];
      if (tier != null) byTier[tier] = (byTier[tier] ?? 0) + asset.value;
    }
    final total = byTier.values.fold<double>(0, (a, b) => a + b);
    final top = topOfTriangle(assets, state.tiers, wealth: wealth);
    String share(PortfolioTier tier) =>
        total <= 0 ? '—' : _pct((byTier[tier] ?? 0) / total * 100);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('Base, meio e topo', style: theme.textTheme.titleSmall),
                const SizedBox(width: 6),
                InfoTip(
                  'Cerca de ${PortfolioTier.baseShare.round()}% fica na base, em '
                  'empresas antigas e lucrativas. O topo fica limitado a '
                  '${PortfolioTier.topLimit.round()}% do patrimônio.',
                ),
              ],
            ),
            const SizedBox(height: 10),
            Center(
              child: SizedBox(
                width: 220,
                height: 130,
                child: CustomPaint(
                  painter: _TrianglePainter({
                    for (final tier in PortfolioTier.values)
                      tier: '${tier.label} ${share(tier)}',
                  }, font: theme.textTheme.labelSmall!),
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (total <= 0)
              Text(
                'Escolha base, meio ou topo nas perguntas de cada ação ou fundo.',
                style: theme.textTheme.bodySmall,
              )
            else ...[
              const SizedBox(height: 4),
              Text(
                'Topo: ${_money(top.top)}, ${_pct(top.share)} do patrimônio '
                '(limite ${PortfolioTier.topLimit.round()}%).'
                '${top.full ? ' Chegou ao limite: o topo não recebe mais aportes.' : ''}',
                style: _rowStyle.copyWith(
                  color: top.full ? theme.colorScheme.error : null,
                  fontWeight: top.full ? FontWeight.w700 : null,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  final Map<PortfolioTier, String> labels;

  /// The theme's text, so the labels use the app's font.
  final TextStyle font;

  _TrianglePainter(this.labels, {required this.font});

  @override
  void paint(Canvas canvas, Size size) {
    final band = size.height / 3;
    for (final (i, tier) in PortfolioTier.values.indexed) {
      double halfWidth(double y) => size.width / 2 * (1 - y / size.height);
      final y0 = band * i;
      final y1 = band * (i + 1) - 2;
      final path = Path()
        ..moveTo(size.width / 2 - halfWidth(y0), y0)
        ..lineTo(size.width / 2 + halfWidth(y0), y0)
        ..lineTo(size.width / 2 + halfWidth(y1), y1)
        ..lineTo(size.width / 2 - halfWidth(y1), y1)
        ..close();
      canvas.drawPath(path, Paint()..color = _tierColors[tier]!);
      final text = TextPainter(
        text: TextSpan(
          text: labels[tier],
          style: font.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);
      text.paint(
        canvas,
        Offset(
          size.width / 2 - text.width / 2,
          (y0 + y1) / 2 - text.height / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(_TrianglePainter old) => !mapEquals(old.labels, labels);
}

/// How the stocks held split by sector (brapi.dev). Null with no sector known.
Widget? _sectorsCard(
  BuildContext context,
  List<DiagramAsset> assets,
  DiagramState state,
) {
  final bySector = <String, double>{};
  for (final asset in assets) {
    final sector = state.sectors[asset.ticker];
    if (sector == null || asset.value <= 0) continue;
    bySector[sector] = (bySector[sector] ?? 0) + asset.value;
  }
  if (bySector.isEmpty) return null;
  final total = bySector.values.fold<double>(0, (a, b) => a + b);
  final rows = bySector.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final theme = Theme.of(context);
  return Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Ações por setor', style: theme.textTheme.titleSmall),
              const SizedBox(width: 6),
              const InfoTip(
                'Ações de setores diferentes deixam a carteira mais resistente. '
                'Escolha o setor antes da empresa.',
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final e in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(e.key, style: _rowStyle)),
                      Text(
                        _pct(e.value / total * 100),
                        style: _rowStyle.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: e.value / total,
                      minHeight: 6,
                      color: _classColors[DiagramClass.nationalStock],
                      backgroundColor: theme.colorScheme.surfaceContainerHigh,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

const _rootColors = {
  true: Color(0xFF43A047), // in Brazil
  false: Color(0xFF1E88E5), // abroad or outside the market
};
const _reserveColor = Color(0xFFE0A526);

Color _rootColor(CerradoRoot root) =>
    root == CerradoRoot.emergency ? _reserveColor : _rootColors[root.home]!;

/// Where you are: the Cerrado tree painted with what you have, and the
/// emergency reserve, which comes before everything else.
class _TreeTab extends StatelessWidget {
  const _TreeTab({
    required this.assets,
    required this.wealth,
    required this.state,
    required this.reserve,
    required this.fixedIncomeHeld,
    required this.onChanged,
  });

  final List<DiagramAsset> assets;

  /// Everything the portfolio holds, for the passive income.
  final double wealth;
  final DiagramState state;
  final double reserve;
  final double fixedIncomeHeld;
  final VoidCallback onChanged;

  Map<CerradoRoot, bool> get _auto => cerradoRoots(
    assets: assets,
    emergencyReserve: reserve,
    fixedIncomeHeld: fixedIncomeHeld,
  );

  Future<void> _editTarget(BuildContext context) async {
    final controller = TextEditingController(
      text: state.emergencyTarget.toStringAsFixed(0),
    );
    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Meta da reserva de emergência'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            prefixText: 'R\$ ',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, double.tryParse(controller.text)),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value < 0) return;
    state.emergencyTarget = value;
    onChanged();
  }

  Widget _reserveCard(BuildContext context) {
    final theme = Theme.of(context);
    final target = state.emergencyTarget;
    final done = target <= 0 ? 1.0 : (reserve / target).clamp(0.0, 1.0);
    final complete = reserve >= target;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.shield_outlined, color: _reserveColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          'Reserva de emergência',
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(width: 6),
                      InfoTip(
                        'O próximo aporte completa a reserva antes de ir para a '
                        'carteira. Ela fica nos bancos do dia a dia: não conta '
                        'na renda fixa da carteira.',
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Mudar a meta da reserva',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: () => _editTarget(context),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: done,
                minHeight: 10,
                color: _reserveColor,
                backgroundColor: theme.colorScheme.surfaceContainerHigh,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              complete
                  ? '${_money(reserve)}: completa.'
                  : '${_money(reserve)} de ${_money(target)}. Faltam '
                        '${_money(target - reserve)}.',
              style: _rowStyle,
            ),
          ],
        ),
      ),
    );
  }

  Widget _rootList(BuildContext context, Map<CerradoRoot, bool> auto) {
    final theme = Theme.of(context);
    return Column(
      children: [
        for (final root in CerradoRoot.values)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(
              children: [
                _RootNumber(root, painted: auto[root]!),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        root.label,
                        style: _rowStyle.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        auto[root]! ? 'Na sua carteira' : 'Ainda não tem',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                // Painted by what the portfolio holds: the Dinzo and what is
                // typed abroad. Nothing to switch by hand.
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Icon(
                    auto[root]! ? Icons.check_circle : Icons.circle_outlined,
                    color: auto[root]!
                        ? const Color(0xFF43A047)
                        : theme.colorScheme.outlineVariant,
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auto = _auto;
    final painted = {for (final root in CerradoRoot.values) root: auto[root]!};
    final count = painted.values.where((p) => p).length;
    final diversified = count >= CerradoRoot.diversified;
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$count',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: diversified ? const Color(0xFF43A047) : _reserveColor,
                ),
              ),
              TextSpan(
                text: ' de ${CerradoRoot.values.length} raízes',
                style: theme.textTheme.titleMedium,
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          diversified
              ? 'Carteira diversificada: raízes largas seguram a árvore em qualquer clima.'
              : 'O mínimo é ${CerradoRoot.diversified} raízes. Direcione os próximos '
                    'aportes para as que faltam.',
          style: _rowStyle,
        ),
      ],
    );
    final tree = AspectRatio(
      aspectRatio: 1.25,
      child: CustomPaint(
        painter: _TreePainter(
          painted,
          empty: theme.colorScheme.outlineVariant,
          surface: theme.colorScheme.surface,
          ground: theme.colorScheme.onSurfaceVariant,
          font: theme.textTheme.labelSmall!,
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 860;
        final left = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: 8),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: tree,
              ),
            ),
          ],
        );
        final right = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _reserveCard(context),
            const SizedBox(height: 12),
            _rootList(context, auto),
            const SizedBox(height: 12),
            _FreedomCard(wealth: wealth),
          ],
        );
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: left),
                  const SizedBox(width: 20),
                  SizedBox(width: 380, child: right),
                ],
              )
            else ...[
              left,
              const SizedBox(height: 12),
              right,
            ],
          ],
        );
      },
    );
  }
}

/// When the portfolio's income pays the monthly spending: the top of the
/// tree. Spending is the average of the last closed months.
class _FreedomCard extends StatefulWidget {
  const _FreedomCard({required this.wealth});

  final double wealth;

  @override
  State<_FreedomCard> createState() => _FreedomCardState();
}

class _FreedomCardState extends State<_FreedomCard> {
  double? _spending;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final now = DateTime.now();
    final wallets = await ServiceConfig.database.getWalletsBalanceAsOf(now);
    final spending = Freedom.livingCost(
      MoneyAccounts.withoutTransfers(
        await ServiceConfig.database.getAllRecordsInInterval(
          Freedom.spendingStart(now),
          now,
        ),
      ),
      now,
      investWallets: {
        for (final w in wallets)
          if (w.id != null && w.isInvestmentReserve) w.id!,
      },
    );
    if (mounted) setState(() => _spending = spending);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spending = _spending ?? 0;
    final wealth = widget.wealth;
    final income = Freedom.passiveIncome(wealth);
    final needed = Freedom.wealthFor(spending);
    final done = needed <= 0 ? 0.0 : (wealth / needed).clamp(0.0, 1.0);
    Widget figure(String label, double value, Color color) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          Text(
            '${_money(value)}/mês',
            style: theme.textTheme.titleMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '🕊️ Liberdade financeira',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                InfoTip(
                  'Quanto a carteira pagaria por mês × quanto você gasta.'
                  '${spending > 0 && done < 1 ? '\n\nPara viver de renda: patrimônio de ${_money(needed)} '
                            '(faltam ${_money(needed - wealth)}).' : ''}'
                  '\n\nConta pessimista: 8% ao ano, guardando 25% de margem. Custo de '
                  'vida = renda menos o separado para investir (Investir e Investido '
                  'Bruto), média dos últimos ${Freedom.months} meses fechados.',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                figure('Renda passiva estimada', income, Colors.green),
                figure('Custo de vida', spending, theme.colorScheme.onSurface),
              ],
            ),
            if (spending > 0) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: done,
                        minHeight: 8,
                        color: Colors.green,
                        backgroundColor: theme.colorScheme.surfaceContainerHigh,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    done >= 1 ? 'Livre!' : _pct(done * 100),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RootNumber extends StatelessWidget {
  const _RootNumber(this.root, {required this.painted});

  final CerradoRoot root;
  final bool painted;

  @override
  Widget build(BuildContext context) {
    final color = _rootColor(root);
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: painted ? color : null,
        border: Border.all(
          color: painted ? color : Theme.of(context).colorScheme.outline,
          width: 1.5,
        ),
      ),
      child: Text(
        '${root.index + 1}',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: painted ? Colors.white : Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }
}

/// A tree of the Cerrado: a small crown and wide roots. Brazil to the left,
/// abroad and outside the market to the right, the reserve straight down.
class _TreePainter extends CustomPainter {
  final Map<CerradoRoot, bool> painted;
  final Color empty;
  final Color surface;
  final Color ground;

  /// The theme's text, so the numbers use the app's font.
  final TextStyle font;

  _TreePainter(
    this.painted, {
    required this.empty,
    required this.surface,
    required this.ground,
    required this.font,
  });

  static const _left = [
    CerradoRoot.fixedIncome,
    CerradoRoot.stocks,
    CerradoRoot.fiis,
    CerradoRoot.etfs,
  ];
  static const _right = [
    CerradoRoot.etfsAbroad,
    CerradoRoot.stocksAbroad,
    CerradoRoot.reits,
    CerradoRoot.digital,
    CerradoRoot.physical,
    CerradoRoot.company,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final groundY = h * 0.27;
    final origin = Offset(w / 2, groundY);
    final count = painted.values.where((p) => p).length;

    final trunk = Paint()
      ..color = const Color(0xFF6D4C41)
      ..strokeWidth = h * 0.075 * 0.45
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(w / 2, h * 0.12), origin, trunk);

    // Crown: fuller as more roots are painted.
    final crown = Paint()
      ..color = const Color(0xFF558B2F)
          .withValues(alpha: 0.25 + 0.6 * count / CerradoRoot.values.length);
    final r = h * 0.075;
    for (final (dx, dy, k) in const [
      (0.0, 0.0, 1.25),
      (-1.3, 0.35, 1.0),
      (1.3, 0.35, 1.0),
      (-0.7, -0.45, 0.95),
      (0.75, -0.4, 0.95),
      (-2.2, 0.75, 0.7),
      (2.2, 0.75, 0.7),
    ]) {
      canvas.drawCircle(Offset(w / 2 + dx * r, h * 0.1 + dy * r), r * k, crown);
    }
    canvas.drawLine(
      Offset(w * 0.04, groundY),
      Offset(w * 0.96, groundY),
      Paint()
        ..color = ground.withValues(alpha: 0.35)
        ..strokeWidth = 1,
    );

    void root(CerradoRoot root, Offset end, double width) {
      final on = painted[root] ?? false;
      final path = Path()
        ..moveTo(origin.dx, origin.dy)
        ..cubicTo(
          origin.dx,
          origin.dy + (end.dy - origin.dy) * 0.55,
          origin.dx + (end.dx - origin.dx) * 0.45,
          end.dy,
          end.dx,
          end.dy,
        );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = on ? width : 2
          ..color = on ? _rootColor(root) : empty,
      );
      final dot = h * 0.032;
      canvas.drawCircle(
        end,
        dot,
        Paint()..color = on ? _rootColor(root) : surface,
      );
      canvas.drawCircle(
        end,
        dot,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = on ? _rootColor(root) : empty,
      );
      final text = TextPainter(
        text: TextSpan(
          text: '${root.index + 1}',
          style: font.copyWith(
            fontSize: dot * (root.index >= 9 ? 0.85 : 1.05),
            fontWeight: FontWeight.w700,
            color: on ? Colors.white : ground,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, end - Offset(text.width / 2, text.height / 2));
    }

    final width = h * 0.022;
    for (final (i, r) in _left.indexed) {
      final t = i / (_left.length - 1);
      root(r, Offset(w * (0.1 + 0.08 * (i % 2)), h * (0.36 + 0.5 * t)), width);
    }
    for (final (i, r) in _right.indexed) {
      final t = i / (_right.length - 1);
      root(r, Offset(w * (0.9 - 0.08 * (i % 2)), h * (0.34 + 0.54 * t)), width);
    }
    root(CerradoRoot.emergency, Offset(w / 2, h * 0.93), width * 1.5);
  }

  @override
  bool shouldRepaint(_TreePainter old) =>
      !mapEquals(old.painted, painted) || old.empty != empty;
}

class _ContributionTab extends StatefulWidget {
  const _ContributionTab({
    required this.assets,
    required this.state,
    required this.available,
    required this.reserve,
    required this.opportunity,
    required this.onChanged,
  });

  final List<DiagramAsset> assets;
  final DiagramState state;
  final double available;

  /// What the emergency reserve holds now.
  final double reserve;

  /// The opportunity reserve: kept apart, for crises.
  final double opportunity;
  final VoidCallback onChanged;

  @override
  State<_ContributionTab> createState() => _ContributionTabState();
}

class _ContributionTabState extends State<_ContributionTab> {
  late final _amount = TextEditingController(
    text: _initial <= 0 ? '' : _initial.toStringAsFixed(2).replaceAll('.', ','),
  );
  late final _monthly = TextEditingController(
    text: widget.state.monthlyContribution <= 0
        ? ''
        : widget.state.monthlyContribution.toStringAsFixed(0),
  );
  DiagramPlan? _plan;
  double _toReserve = 0;
  String? _openQuestions;

  double get _initial => widget.state.lastContribution > 0
      ? widget.state.lastContribution
      : widget.available;

  @override
  void dispose() {
    _amount.dispose();
    _monthly.dispose();
    super.dispose();
  }

  /// A sum well above the usual contribution goes in 10 months: buying all at
  /// once risks buying an anomaly of the market.
  Widget? _spreadCard() {
    final amount = _parse(_amount.text);
    final monthly = widget.state.monthlyContribution;
    if (amount == null || monthly <= 0 || amount <= 10 * monthly) return null;
    final theme = Theme.of(context);
    final part = (amount / 10 * 100).floorToDouble() / 100;
    return Card(
      margin: const EdgeInsets.only(top: 12),
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              Icons.calendar_month,
              color: theme.colorScheme.onSecondaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Mais de 10 vezes o seu aporte mensal: melhor dividir em 10 aportes '
                'de ${_money(part)}, um por mês.',
                style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
              ),
            ),
            TextButton(
              onPressed: () {
                _amount.text = part.toStringAsFixed(2).replaceAll('.', ',');
                _calculate();
              },
              child: const Text('Usar 1/10'),
            ),
          ],
        ),
      ),
    );
  }

  /// A grade or a price that changed makes the suggestions on screen old.
  @override
  void didUpdateWidget(_ContributionTab old) {
    super.didUpdateWidget(old);
    final amount = _parse(_amount.text);
    if (_plan == null || amount == null || amount <= 0) return;
    _replan(amount);
  }

  /// The reserve first, the portfolio with the rest.
  void _replan(double amount) {
    final split = splitForReserve(
      amount: amount,
      reserve: widget.reserve,
      target: widget.state.emergencyTarget,
    );
    _toReserve = split.toReserve;
    _plan = planContribution(
      assets: widget.assets,
      targetPercent: widget.state.targets,
      amount: split.toPortfolio,
    );
  }

  Widget _reserveFirst() {
    final theme = Theme.of(context);
    final target = widget.state.emergencyTarget;
    final missing = target - widget.reserve - _toReserve;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              Icons.shield_outlined,
              color: theme.colorScheme.onTertiaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Primeiro a reserva de emergência: ${_money(_toReserve)} vão para ela, '
                'numa renda fixa com liquidez. '
                '${missing > 0.005 ? 'Ainda faltarão ${_money(missing)} para ${_money(target)}.' : 'Com isso ela fica completa.'}'
                '${_plan!.total - widget.assets.fold<double>(0, (s, a) => s + a.value) <= 0.005 ? ' Nada sobra para a carteira neste aporte.' : ''}',
                style: TextStyle(color: theme.colorScheme.onTertiaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// What could receive money but has no grade: without it there is no way to
  /// tell where the money goes, so nothing is suggested until it is graded.
  /// Without a grade, or not reviewed since the quarter's review began: the
  /// contribution waits for them.
  List<DiagramAsset> get _ungraded {
    final now = DateTime.now();
    return [
      for (final asset in widget.assets)
        if (asset.status == HoldStatus.buying &&
            (widget.state.targets[asset.cls] ?? 0) > 0 &&
            (asset.grade == null ||
                widget.state.pendingReview([asset], now).isNotEmpty))
          asset,
    ];
  }

  Widget _gradesFirst() {
    final theme = Theme.of(context);
    final ungraded = _ungraded;
    final onCard = theme.colorScheme.onSecondaryContainer;
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.star_half, color: onCard),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    ungraded.every((a) => a.grade != null)
                        ? 'Revisão de ${DateFormat('dd/MM').format(DiagramState.reviewStart(DateTime.now()))}: '
                              'reavalie ${ungraded.length == 1 ? '1 ativo' : '${ungraded.length} ativos'} '
                              'antes do aporte.'
                        : ungraded.length == 1
                        ? 'Primeiro a nota: falta dar nota a 1 ativo.'
                        : 'Primeiro as notas: faltam ${ungraded.length} ativos.',
                    style: TextStyle(
                      color: onCard,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                InfoTip(
                  'O aporte é dividido pelas notas. Com um ativo sem nota, não dá '
                  'para dizer onde colocar o dinheiro: dê a nota aqui ou em Meus '
                  'ativos, ou pause os aportes dele.',
                ),
              ],
            ),
            const SizedBox(height: 10),
            Material(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              clipBehavior: Clip.antiAlias,
              child: _Table(
                columns: const [
                  _Column('Tipo', 5, wideOnly: true),
                  _Column('Ativo', 6),
                  _Column('Nota', 3, right: true),
                ],
                below: {
                  for (final (i, asset) in ungraded.indexed)
                    if (asset.key == _openQuestions)
                      i: DiagramQuestionsPanel(
                        asset: asset,
                        state: widget.state,
                        onChanged: widget.onChanged,
                      ),
                },
                rows: [
                  for (final asset in ungraded)
                    [
                      _Pill(asset.cls),
                      _assetCell(asset),
                      _GradeCell(
                        key: ValueKey(asset.key),
                        asset: asset,
                        state: widget.state,
                        onChanged: widget.onChanged,
                        open: asset.key == _openQuestions,
                        onToggle: () => setState(
                          () => _openQuestions = asset.key == _openQuestions
                              ? null
                              : asset.key,
                        ),
                      ),
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _calculate() {
    final amount = _parse(_amount.text);
    if (amount == null || amount <= 0) return;
    widget.state.lastContribution = amount;
    widget.onChanged();
    setState(() => _replan(amount));
  }

  Widget _distribution() {
    final byClass = <DiagramClass, double>{};
    for (final asset in widget.assets) {
      byClass[asset.cls] = (byClass[asset.cls] ?? 0) + asset.value;
    }
    final total = byClass.values.fold<double>(0, (a, b) => a + b);
    return Wrap(
      spacing: 20,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _Donut(byClass, center: _money(total), size: 96),
        _Legend({
          for (final cls in DiagramClass.values)
            cls: total <= 0
                ? '0%'
                : '${_pct((byClass[cls] ?? 0) / total * 100)}'
                      ' / ${(widget.state.targets[cls] ?? 0).round()}%',
        }),
      ],
    );
  }

  Widget _results(DiagramPlan plan) {
    final theme = Theme.of(context);
    final excluded = [
      for (final asset in widget.assets)
        if (asset.ineligibleReason != null &&
            (widget.state.targets[asset.cls] ?? 0) > 0)
          asset,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Sugestões', style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        if (plan.suggestions.isEmpty)
          Text(
            'Nada a sugerir: nenhum ativo apto está abaixo do ideal.',
            style: theme.textTheme.bodySmall,
          )
        else
          _Table(
            columns: const [
              _Column('Tipo', 5, wideOnly: true),
              _Column('Ativo', 5),
              _Column('Atual', 4, right: true, wideOnly: true),
              _Column('Preço', 4, right: true, wideOnly: true),
              _Column('Nota', 2, right: true, wideOnly: true),
              _Column('Após (%)', 3, right: true, wideOnly: true),
              _Column('Aportar', 4, right: true),
              _Column('Qtd.', 3, right: true),
              _Column('', 2, right: true),
            ],
            rows: [
              for (final s in plan.suggestions)
                [
                  _Pill(s.asset.cls),
                  _assetCell(s.asset),
                  _text(_money(s.asset.value)),
                  _text(s.asset.price == null ? '—' : _money(s.asset.price!)),
                  _text('${s.asset.grade}'),
                  _text(_pct(s.sharePctAfter)),
                  _text(_money(s.amount), bold: true),
                  _text(s.units == null ? '—' : _units(s.units!)),
                  s.asset.ticker == null
                      ? const SizedBox.shrink()
                      : IconButton(
                          tooltip: 'Abrir a Ficha',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 28,
                            height: 28,
                          ),
                          icon: const Icon(Icons.manage_search, size: 18),
                          onPressed: () =>
                              AssetSheetPage.open(context, s.asset.ticker!),
                        ),
                ],
            ],
          ),
        if (plan.unassigned > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Sem destino: ${_money(plan.unassigned)}. Fica para o próximo aporte, '
              'em vez de passar da meta ou comprar fração de cota.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (excluded.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('Não entraram', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          _Table(
            columns: const [
              _Column('Ativo', 6),
              _Column('Motivo', 4),
              _Column('Nota', 3, right: true),
            ],
            below: {
              for (final (i, asset) in excluded.indexed)
                if (asset.key == _openQuestions)
                  i: DiagramQuestionsPanel(
                    asset: asset,
                    state: widget.state,
                    onChanged: widget.onChanged,
                  ),
            },
            rows: [
              for (final asset in excluded)
                [
                  _assetCell(asset),
                  _text(asset.ineligibleReason!),
                  _GradeCell(
                    key: ValueKey(asset.key),
                    asset: asset,
                    state: widget.state,
                    onChanged: widget.onChanged,
                    open: asset.key == _openQuestions,
                    onToggle: () => setState(
                      () => _openQuestions = asset.key == _openQuestions
                          ? null
                          : asset.key,
                    ),
                  ),
                ],
            ],
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = _plan;
    final hasTargets = (widget.state.targetTotal - 100).abs() < 0.01;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            // Narrower on a phone, so the button and the note still fit.
            Flexible(
              child: SizedBox(
                width: 170,
                height: 40,
                child: TextField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: _rowStyle,
                  decoration: const InputDecoration(
                    labelText: 'Valor do aporte',
                    prefixText: 'R\$ ',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => hasTargets ? _calculate() : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: hasTargets ? _calculate : null,
              child: const Text('Calcular'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                children: [
                  const InfoTip(
                    'Primeiro o valor completa a reserva de emergência; depois vai '
                    'para os tipos mais abaixo da meta; dentro de cada um, para os '
                    'ativos mais abaixo do peso que a nota dá a eles. Não envia '
                    'ordem, não sugere venda e não considera custos nem imposto.',
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Na carteira Investir: ${_money(widget.available)}',
                      style: theme.textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            SizedBox(
              width: 170,
              height: 40,
              child: TextField(
                controller: _monthly,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: _rowStyle,
                decoration: const InputDecoration(
                  labelText: 'Aporte mensal típico',
                  prefixText: 'R\$ ',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (text) {
                  widget.state.monthlyContribution = double.tryParse(text) ?? 0;
                  widget.onChanged();
                },
              ),
            ),
            const SizedBox(width: 12),
            const InfoTip(
              'Valores acima de 10 vezes ele são divididos em 10 meses.',
            ),
          ],
        ),
        ?_spreadCard(),
        if (widget.opportunity > 0)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                Text(
                  'Reserva de oportunidade: ${_money(widget.opportunity)}, fora '
                  'deste aporte',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(width: 4),
                const InfoTip(
                  'Numa crise, use aos poucos em empresas boas que caíram sem '
                  'perder fundamentos.',
                ),
              ],
            ),
          ),
        if (!hasTargets)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Defina na aba Metas quanto quer de cada tipo, somando 100%.',
              style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
            ),
          ),
        const SizedBox(height: 12),
        _distribution(),
        const SizedBox(height: 12),
        if (plan != null && _toReserve > 0) _reserveFirst(),
        if (_ungraded.isNotEmpty)
          _gradesFirst()
        else if (plan != null)
          _results(plan),
      ],
    );
  }
}

/// How many shares are held abroad: typed, since the Dinzo does not see foreign
/// brokers. Zero removes the holding but keeps the asset to study.
class _AddAssetDialog extends StatefulWidget {
  const _AddAssetDialog({this.abroadOnly = false});

  /// From Internacional: only stocks, ETFs and REITs abroad. What is here
  /// comes from the Dinzo, and coins have their own purchases.
  final bool abroadOnly;

  @override
  State<_AddAssetDialog> createState() => _AddAssetDialogState();
}

class _AddAssetDialogState extends State<_AddAssetDialog> {
  final _ticker = TextEditingController();
  final _tickerFocus = FocusNode();
  final _quantity = TextEditingController();
  late DiagramClass _cls = widget.abroadOnly
      ? DiagramClass.intlStock
      : DiagramClass.nationalStock;
  bool _checking = false;
  String? _error;

  bool get _foreign =>
      _cls == DiagramClass.intlStock || _cls == DiagramClass.reit;

  @override
  void dispose() {
    _ticker.dispose();
    _tickerFocus.dispose();
    _quantity.dispose();
    super.dispose();
  }

  /// The ticker field; abroad it suggests while typing.
  Widget _tickerField() {
    InputDecoration decoration() => InputDecoration(
      labelText: _foreign ? 'Ticker ou nome' : 'Ticker',
      hintText: _foreign ? 'NVDA, Apple, VOO…' : 'VALE3, MXRF11, BTC, VOO…',
      errorText: _error,
      border: const OutlineInputBorder(),
    );
    if (!_foreign) {
      return TextField(
        controller: _ticker,
        focusNode: _tickerFocus,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        decoration: decoration(),
        onSubmitted: (_) => _submit(),
      );
    }
    return RawAutocomplete<String>(
      textEditingController: _ticker,
      focusNode: _tickerFocus,
      optionsBuilder: (value) => searchAbroad(value.text),
      onSelected: (ticker) {
        _ticker.text = ticker;
        setState(() => _error = null);
      },
      fieldViewBuilder: (context, controller, focus, onSubmit) => TextField(
        controller: controller,
        focusNode: focus,
        autofocus: true,
        decoration: decoration(),
        onSubmitted: (_) => _submit(),
      ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280, maxWidth: 360),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                for (final ticker in options)
                  ListTile(
                    dense: true,
                    leading: InstitutionLogo(
                      institution: StockCompany.badgeOf(ticker),
                      size: 28,
                    ),
                    title: Text(ticker),
                    subtitle: Text(usCatalog[ticker]?.$1 ?? ''),
                    onTap: () => onSelected(ticker),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// A typed ticker usually says what it is.
  Future<void> _submit() async {
    final ticker = _ticker.text.trim().toUpperCase();
    if (ticker.length < 2) {
      setState(() => _error = 'Digite o ticker.');
      return;
    }
    final foreign = _cls == DiagramClass.intlStock || _cls == DiagramClass.reit;
    setState(() {
      _checking = true;
      _error = null;
    });
    final quote = await AssetQuote.fetch(ticker, withHistory: false);
    if (!mounted) return;
    if (quote == null) {
      setState(() {
        _checking = false;
        _error = 'Não encontrei cotação de $ticker.';
      });
      return;
    }
    if (foreign || quote.currency == 'USD') {
      Navigator.pop(context, (
        ticker,
        foreign ? _cls : DiagramClass.intlStock,
        _cls != DiagramClass.reit &&
            kindFromNames(quote.shortName, quote.longName) == AssetKind.etf,
        _parse(_quantity.text) ?? 0,
      ));
      return;
    }
    final kind = await resolveAssetKind(ticker, quote: quote);
    if (!mounted) return;
    final cls = switch (kind) {
      AssetKind.fii => DiagramClass.fii,
      AssetKind.crypto => DiagramClass.crypto,
      _ => _cls == DiagramClass.fixedIncome ? DiagramClass.nationalStock : _cls,
    };
    Navigator.pop(context, (ticker, cls, kind == AssetKind.etf, 0.0));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.abroadOnly ? 'Adicionar ativo lá fora' : 'Adicionar ativo'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _tickerField(),
            const SizedBox(height: 12),
            DropdownButtonFormField<DiagramClass>(
              initialValue: _cls,
              decoration: const InputDecoration(
                labelText: 'Tipo',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final cls in DiagramClass.values)
                  if (cls != DiagramClass.fixedIncome &&
                      (!widget.abroadOnly ||
                          cls == DiagramClass.intlStock ||
                          cls == DiagramClass.reit))
                    DropdownMenuItem(value: cls, child: Text(cls.label)),
              ],
              onChanged: (value) => setState(() => _cls = value ?? _cls),
            ),
            if (_cls == DiagramClass.intlStock ||
                _cls == DiagramClass.reit) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _quantity,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Quantidade que você tem',
                  helperText:
                      'Ticker de lá (VOO, AAPL, O). Cotação em dólar pela '
                      'brapi.dev, convertida pelo dólar do Banco Central.',
                  helperMaxLines: 3,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _checking ? null : _submit,
          child: _checking
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Adicionar'),
        ),
      ],
    );
  }
}
