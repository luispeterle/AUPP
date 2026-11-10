import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:aupp/helpers/records-utility-functions.dart';
import 'package:aupp/services/crypto-quote-service.dart';
import 'package:aupp/components/info-tip.dart';
import 'package:aupp/components/time-chart.dart';

import 'asset-lots-view.dart';
import 'asset-lots.dart';
import 'crypto-analytics.dart';
import 'crypto-history.dart';
import 'selic-comparison.dart';

/// "Modo cripto" of the Investments tab: the crypto
/// wallets (entered by hand, buy and hold), their value at the CoinGecko
/// quote, each purchase with its date, what the portfolio really did against
/// the Selic, price charts with touch to inspect and the countdown to the
/// Bitcoin halving.
class CryptoView extends StatefulWidget {
  const CryptoView({Key? key, this.sinceStart = false, this.onChanged})
    : super(key: key);

  /// What is crypto's own in the Carteira tab (each coin's chart and the
  /// halving), over the tab's period.
  final bool sinceStart;

  /// After purchases were added or changed here.
  final VoidCallback? onChanged;

  @override
  CryptoViewState createState() => CryptoViewState();
}

class CryptoViewState extends State<CryptoView> {
  static const _coinColors = {
    'BTC': Color(0xFFF7931A),
    'XMR': Color(0xFFFF6600),
    'ETH': Color(0xFF627EEA),
    'SOL': Color(0xFF9945FF),
    'LTC': Color(0xFF345D9D),
    'USDT': Color(0xFF26A17B),
  };
  static const _portfolioColor = Color(0xFF1E88E5);

  Map<String, double> _coins = const {};
  CryptoHistory? _history;
  int? _btcTip;
  late CryptoRange _range = widget.sinceStart
      ? CryptoRange.all
      : CryptoRange.year;
  bool _usd = false;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh({bool force = false}) async {
    await CryptoQuoteService.refresh(force: force);
    await AssetLots.checkLinks();
    final coins = AssetLots.coins;
    if (mounted) setState(() => _coins = coins);
    final codes = coins.keys.toList();
    try {
      final history = await CryptoHistory.load(codes, force: force);
      if (mounted) setState(() => _history = history);
    } catch (_) {
      // Offline: the charts wait for the next refresh.
    }
    if (codes.contains('BTC')) {
      final tip = await _fetchBtcTip();
      if (mounted && tip != null) setState(() => _btcTip = tip);
    }
  }

  /// Current block height (mempool.space, free); null when offline.
  static Future<int?> _fetchBtcTip() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(
        Uri.https('mempool.space', '/api/blocks/tip/height'),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      final body = await response.transform(utf8.decoder).join();
      return response.statusCode == 200 ? int.tryParse(body.trim()) : null;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  String get _currency => _usd ? 'USD' : 'BRL';

  CryptoSeries? _seriesOf(String code) => _history?.seriesIn(code, _currency);

  double? _priceOf(String code) => _usd
      ? CryptoQuoteService.usdPrice(code)
      : CryptoQuoteService.priceInMain(code);

  /// Reais per dollar on [day] (for costs entered in reais).
  double? _usdBrlOn(DateTime day) {
    final fx = _history?.usdBrl;
    return fx == null ? null : CryptoAnalytics.priceOn(fx, day);
  }

  /// A coin's price in reais on a day: the history, or today's quote.
  double? _reaisOn(String code, DateTime day) {
    final now = DateTime.now();
    if (day.year == now.year && day.month == now.month && day.day == now.day) {
      final today = CryptoQuoteService.priceInMain(code);
      if (today != null) return today;
    }
    final series = _history?.seriesIn(code, 'BRL');
    return series == null
        ? null
        : CryptoAnalytics.priceOn(CryptoAnalytics.merged(series), day);
  }

  /// One position per coin, in the shown currency, largest first.
  List<CryptoPosition> get _positions {
    final result = <CryptoPosition>[];
    for (final e in _coins.entries) {
      final price = _priceOf(e.key);
      if (price == null) continue;
      final lots = AssetLots.of(e.key);
      double? cost = lots.isEmpty ? null : 0;
      for (final lot in lots) {
        var part = AssetLots.costOf(lot, (day) => _reaisOn(e.key, day));
        // The amounts paid are in reais.
        if (part != null && _usd) {
          final fx = _usdBrlOn(lot.day);
          part = fx == null ? null : part / fx;
        }
        cost = part == null || cost == null ? null : cost + part;
      }
      result.add(
        CryptoPosition(
          e.key,
          e.value,
          price,
          cost: cost,
          costIsEstimate: lots.any((lot) => lot.cost == null),
        ),
      );
    }
    result.sort((a, b) => b.value.compareTo(a.value));
    return result;
  }

  String _money(double v) {
    if (_usd) {
      return NumberFormat.currency(
        locale: 'pt_BR',
        symbol: 'US\$',
        decimalDigits: 2,
      ).format(v);
    }
    return getCurrencyValueString(v);
  }

  String _pct(double v) =>
      '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1).replaceAll('.', ',')}%';

  DateFormat get _dateFormat => switch (_range) {
    CryptoRange.year => DateFormat('dd/MM/yy'),
    CryptoRange.all => DateFormat('MM/yyyy'),
  };

  /// The logo, or a generic coin for a code the app has none for.
  static Widget _coinIcon(String code, double size, Color color) {
    final logo = cryptoLogoOf(code);
    return logo == null
        ? FaIcon(FontAwesomeIcons.coins, size: size, color: color)
        : Image.asset(logo, width: size, height: size);
  }

  static String _nameOf(String code) => switch (code) {
    'BTC' => 'Bitcoin',
    'XMR' => 'Monero',
    'ETH' => 'Ethereum',
    'SOL' => 'Solana',
    'LTC' => 'Litecoin',
    'USDT' => 'Tether',
    _ => code,
  };

  Color _colorOf(String code) => _coinColors[code] ?? _portfolioColor;

  /// The first purchase of a coin: where "Desde o início" begins.
  static DateTime? _firstBuy(String code) {
    final lots = AssetLots.of(code);
    return lots.isEmpty ? null : lots.first.day;
  }

  // ----------------------------------------------------------- purchases

  Future<void> openLots(String code) => _openLots(code);

  Future<void> pickCoin() => _pickCoin();

  Future<void> _openLots(String code) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AssetLotsPage(
          asset: code,
          title: _nameOf(code),
          priceOn: (day) => _reaisOn(code, day),
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _coins = AssetLots.coins);
    await CryptoQuoteService.refresh(force: true);
    if (mounted) await refresh();
    widget.onChanged?.call();
  }

  /// Purchases of any coin the app quotes, held or not.
  Future<void> _pickCoin() async {
    final code = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Moeda'),
        children: [
          for (final code in CryptoQuoteService.coinIds.keys)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, code),
              child: Text('${_nameOf(code)} ($code)'),
            ),
        ],
      ),
    );
    if (code != null) await _openLots(code);
  }

  // --------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return _buildBody(context);
  }

  @override
  void didUpdateWidget(CryptoView old) {
    super.didUpdateWidget(old);
    if (old.sinceStart != widget.sinceStart) {
      _range = widget.sinceStart ? CryptoRange.all : CryptoRange.year;
    }
  }

  /// Each coin's chart, the halving and the sources.
  Widget _buildExtras(BuildContext context) {
    final now = DateTime.now();
    final positions = _positions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final p in positions)
          if (_seriesOf(p.code) != null)
            _TouchChartCard(
              key: ValueKey('${p.code}-$_range'),
              title: _nameOf(p.code),
              icon: _coinIcon(p.code, 18, _colorOf(p.code)),
              color: _colorOf(p.code),
              points: _seriesOf(
                p.code,
              )!.pointsFor(_range, now, since: _firstBuy(p.code)),
              marks: p.code == 'BTC' ? BtcHalving.past : const [],
              dateFormat: _dateFormat,
              money: _money,
              pct: _pct,
            ),
        if (positions.any((p) => p.code == 'BTC')) _buildHalving(now),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                'Fontes da cripto',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 4),
              const InfoTip(
                'Cotação atual: CoinGecko. Histórico: Kraken (em dólar) × dólar '
                'do Banco Central. Altura dos blocos: mempool.space.',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context) =>
      _coins.isEmpty ? const SizedBox.shrink() : _buildExtras(context);

  Widget _buildHalving(DateTime now) {
    final theme = Theme.of(context);
    final tip = _btcTip ?? BtcHalving.guessTip(now);
    final next = BtcHalving.nextHeight(tip);
    final date = BtcHalving.estimate(next, tip, now);
    final days = date.difference(now).inDays;
    final progress = (tip % BtcHalving.interval) / BtcHalving.interval;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                FaIcon(
                  FontAwesomeIcons.hourglassHalf,
                  size: 16,
                  color: _colorOf('BTC'),
                ),
                const SizedBox(width: 8),
                Text('Próximo halving', style: theme.textTheme.titleMedium),
                const SizedBox(width: 6),
                const InfoTip(
                  'No halving a recompensa por bloco cai pela metade '
                  '(3,125 → 1,5625 BTC).',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Faltam ~$days dias',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: _colorOf('BTC'),
              ),
            ),
            Text(
              '≈ ${DateFormat('dd/MM/yyyy').format(date)} · bloco '
              '${NumberFormat.decimalPattern('pt_BR').format(next)}'
              '${_btcTip == null ? ' (estimativa sem conexão)' : ''}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                color: _colorOf('BTC'),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${(progress * 100).toStringAsFixed(0)}% do ciclo',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One line in a card; moving over it shows the value and date of a point.
class _TouchChartCard extends StatelessWidget {
  final String title;
  final Widget icon;
  final Color color;
  final List<MapEntry<DateTime, double>> points;

  /// Dates marked with a vertical line (when inside the chart).
  final List<DateTime> marks;
  final DateFormat dateFormat;
  final String Function(double) money;
  final String Function(double) pct;

  const _TouchChartCard({
    Key? key,
    required this.title,
    required this.icon,
    required this.color,
    required this.points,
    this.marks = const [],
    required this.dateFormat,
    required this.money,
    required this.pct,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = points.isEmpty ? null : points.last;
    final change = points.length < 2 || shown == null || points.first.value == 0
        ? null
        : (shown.value / points.first.value - 1) * 100;
    final inRange = points.isEmpty
        ? const <DateTime>[]
        : [
            for (final d in marks)
              if (!d.isBefore(points.first.key) && !d.isAfter(points.last.key))
                d,
          ];
    return InvestmentCard(
      title: title,
      leading: icon,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (shown != null)
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: money(shown.value),
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextSpan(
                    text: '  ${dateFormat.format(shown.key)}',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (change != null)
                    TextSpan(
                      text: '  ${pct(change)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: change >= 0
                            ? Colors.green.shade600
                            : Colors.red.shade400,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          points.length < 2
              ? const SizedBox(
                  height: 220,
                  child: Center(child: Text('Sem histórico no período')),
                )
              : TimeChart(
                  marks: inRange,
                  series: [
                    TimeSeries(title, color, [
                      for (final p in points) (p.key, p.value),
                    ]),
                  ],
                  format: money,
                  dateLabel: DateFormat('dd/MM/yyyy').format,
                  axisLabel: DateFormat(
                    points.last.key.difference(points.first.key).inDays <= 92
                        ? 'dd/MM'
                        : 'MM/yy',
                  ).format,
                ),
        ],
      ),
    );
  }
}
