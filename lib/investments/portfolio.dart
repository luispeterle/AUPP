import 'package:aupp/dinzo/dinzo-taxes.dart';

import 'asset-lots.dart';
import 'diagram.dart';
import 'stock-catalog.dart';

/// What the Carteira tab can switch on and off: the classes of Carteira e
/// aporte, and what the everyday banks hold as everyday money, which is the
/// wallets' money and not an investment.
enum PortfolioClass {
  nationalStock('Ações', DiagramClass.nationalStock),
  fii('FIIs', DiagramClass.fii),
  fixedIncome('Renda fixa', DiagramClass.fixedIncome),
  dailyFixedIncome('Dia a dia', null),
  intlStock('Ações internacionais', DiagramClass.intlStock),
  reit('REITs', DiagramClass.reit),
  crypto('Cripto', DiagramClass.crypto);

  final String label;

  /// Its class in Carteira e aporte; null for the wallets' money.
  final DiagramClass? diagram;

  const PortfolioClass(this.label, this.diagram);

  static PortfolioClass of(DiagramClass cls) =>
      values.firstWhere((c) => c.diagram == cls);

  /// What a new visit shows: everything invested.
  static Set<PortfolioClass> get shownByDefault => {
    for (final c in values)
      if (c != dailyFixedIncome) c,
  };

  /// Held in Brazil: the Dinzo's positions.
  bool get isBrazil =>
      this == nationalStock ||
      this == fii ||
      this == fixedIncome ||
      this == dailyFixedIncome;

  bool get isAbroad => this == intlStock || this == reit;
}

/// The purchases and sales of each stock in [investments], by ticker, as the
/// Dinzo reports them (date, quantity, amount): the same lots a purchase
/// abroad has, so its past follows the real quotes.
Map<String, List<AssetLot>> dinzoLots(Iterable<DinzoInvestment> investments) {
  final result = <String, List<AssetLot>>{};
  for (final inv in investments) {
    if (inv.archived) continue;
    final ticker = StockCompany.tickerOf(inv);
    final moves = inv.raw['transactions'];
    if (ticker == null || moves is! List) continue;
    for (final move in moves.whereType<Map>()) {
      final type = move['type'];
      final day = DateTime.tryParse('${move['date']}');
      final quantity = (move['quantity'] as num?)?.toDouble();
      if (day == null || quantity == null || quantity == 0) continue;
      if (type != 'BUY' && type != 'SELL') continue;
      final sign = type == 'BUY' ? 1 : -1;
      final amount = (move['amount'] as num?)?.toDouble();
      result.putIfAbsent(ticker, () => []).add(
        AssetLot(
          id: 'dinzo:${inv.assetKey}:${move['id'] ?? result[ticker]!.length}',
          day: DateTime(day.year, day.month, day.day),
          quantity: sign * quantity.abs(),
          cost: amount == null ? null : sign * amount.abs(),
        ),
      );
    }
  }
  return result;
}

/// Several portfolios as one, day by day: values, money in and its Selic add
/// up; the return of each day is that of the whole, weighted by what each
/// held. A portfolio not started yet adds nothing; one with a day missing
/// keeps its last day (nothing moved).
List<PortfolioPoint> combineSeries(List<List<PortfolioPoint>> series) {
  final parts = [
    for (final s in series)
      if (s.isNotEmpty) s,
  ];
  if (parts.isEmpty) return const [];
  if (parts.length == 1) return parts.first;
  DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);
  final days = {
    for (final s in parts)
      for (final p in s) dayOf(p.date),
  }.toList()..sort();
  final byDay = [
    for (final s in parts) {for (final p in s) dayOf(p.date): p},
  ];
  final last = List<PortfolioPoint?>.filled(parts.length, null);
  final result = <PortfolioPoint>[];
  var index = 1.0;
  for (final day in days) {
    var before = 0.0, moved = 0.0;
    for (var i = 0; i < parts.length; i++) {
      final previous = last[i];
      final today = byDay[i][day];
      if (previous != null && today != null && previous.value > 0) {
        before += previous.value;
        moved += previous.value * (today.index / previous.index);
      } else if (previous != null) {
        before += previous.value;
        moved += previous.value;
      }
      if (today != null) last[i] = today;
    }
    if (before > 0) index *= moved / before;
    var value = 0.0, invested = 0.0, selic = 0.0;
    for (final p in last) {
      if (p == null) continue;
      value += p.value;
      invested += p.invested;
      selic += p.selic;
    }
    result.add(PortfolioPoint(day, value, invested, selic, index));
  }
  return result;
}
