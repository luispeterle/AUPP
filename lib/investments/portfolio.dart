import 'package:aupp/dinzo/dinzo-taxes.dart';

import 'asset-lots.dart';
import 'diagram.dart';
import 'stock-catalog.dart';

/// What the Carteira tab can switch on and off, in the order it shows them:
/// the classes of Carteira e aporte, and what the everyday banks hold as
/// everyday money, which is the wallets' money and not an investment.
enum PortfolioClass {
  fixedIncome('Renda fixa', DiagramClass.fixedIncome),
  nationalStock('Ações', DiagramClass.nationalStock),
  intlStock('Ações internacionais', DiagramClass.intlStock),
  fii('FIIs', DiagramClass.fii),
  reit('REITs', DiagramClass.reit),
  dailyFixedIncome('Dia a dia', null),
  crypto('Cripto', DiagramClass.crypto);

  final String label;

  /// Its class in Carteira e aporte; null for the wallets' money.
  final DiagramClass? diagram;

  const PortfolioClass(this.label, this.diagram);

  static PortfolioClass of(DiagramClass cls) =>
      values.firstWhere((c) => c.diagram == cls);

  /// What a new visit shows: everything but the everyday money and cripto.
  static Set<PortfolioClass> get shownByDefault => {
    for (final c in values)
      if (c != dailyFixedIncome && c != crypto) c,
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
      result
          .putIfAbsent(ticker, () => [])
          .add(
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
/// up. A portfolio not started yet adds nothing; one with a day missing keeps
/// its last day (nothing moved).
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
  for (final day in days) {
    for (var i = 0; i < parts.length; i++) {
      last[i] = byDay[i][day] ?? last[i];
    }
    var value = 0.0, invested = 0.0, selic = 0.0;
    for (final p in last) {
      if (p == null) continue;
      value += p.value;
      invested += p.invested;
      selic += p.selic;
    }
    result.add(PortfolioPoint(day, value, invested, selic));
  }
  return result;
}
