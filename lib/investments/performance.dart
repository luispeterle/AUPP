import 'package:aupp/dinzo/dinzo-taxes.dart';

import 'asset-lots.dart';
import 'benchmark.dart';

class PerformancePoint {
  final DateTime date;

  /// Cumulative return since the start of the period (0.05 = +5%).
  final double portfolio;
  final double selic;

  PerformancePoint(this.date, this.portfolio, this.selic);
}

class PerformanceResult {
  /// Month ends (and today), starting at 0 on the first day of the period.
  final List<PerformancePoint> points;

  /// Realised result over the positions' whole life, from the reported
  /// balances turned back into gross values: profit as a share of what the
  /// same deposits and withdrawals would have made at 100% of the CDI.
  final double? percentOfCdi;
  final double grossProfit;
  final double cdiProfit;

  PerformanceResult(
    this.points,
    this.percentOfCdi,
    this.grossProfit,
    this.cdiProfit,
  );

  double get portfolioReturn => points.isEmpty ? 0 : points.last.portfolio;
  double get selicReturn => points.isEmpty ? 0 : points.last.selic;
}

/// Portfolio performance against the Selic. Pure: no network, no database.
///
/// Positions without deposit history (e.g. cofrinhos) are left out: their
/// past cannot be rebuilt.
class Performance {
  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static PerformanceResult compute(
    List<DinzoInvestment> investments,
    BenchmarkRates rates,
    DateTime today, {
    DateTime? from,
  }) {
    final end = _day(today);
    // Every lot grows at its contracted % of the CDI (checked against the
    // reported balances); flows happen on their dates.
    final lots = <_Lot>[];
    for (final inv in investments) {
      final moves = inv.movements
          .where((m) => m.type == 'BUY' || m.type == 'SELL')
          .toList();
      if (!moves.any((m) => m.type == 'BUY')) continue;
      final pct =
          inv.rate != null &&
              (inv.rateType ?? '').toUpperCase().contains('CDI') &&
              inv.rate! > 0
          ? inv.rate! / 100
          : 1.0;
      lots.add(_Lot(pct, _flows(moves)));
    }
    if (lots.isEmpty) return PerformanceResult([], null, 0, 0);

    final firstFlow = lots
        .expand((l) => l.flows.keys)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final start = from == null || from.isBefore(firstFlow)
        ? firstFlow
        : _day(from);

    var portfolioIndex = 1.0, selicIndex = 1.0;
    double? portfolioBase, selicBase;
    final points = <PerformancePoint>[];
    for (
      var d = firstFlow;
      !d.isAfter(end);
      d = d.add(const Duration(days: 1))
    ) {
      for (final lot in lots) {
        final flow = lot.flows[d];
        if (flow != null)
          lot.value = (lot.value + flow).clamp(0, double.infinity);
      }
      if (d == start) {
        portfolioBase = portfolioIndex;
        selicBase = selicIndex;
        points.add(PerformancePoint(d, 0, 0));
      }
      if (d == end) break;
      final cdi = BenchmarkRates.rateOn(rates.cdi, d);
      final before = lots.fold<double>(0, (s, l) => s + l.value);
      for (final lot in lots) {
        lot.value *= 1 + cdi * lot.pctOfCdi;
      }
      final after = lots.fold<double>(0, (s, l) => s + l.value);
      if (before > 0) portfolioIndex *= after / before;
      selicIndex *= 1 + BenchmarkRates.rateOn(rates.selic, d);

      final next = d.add(const Duration(days: 1));
      if (portfolioBase != null && (next.month != d.month || next == end)) {
        points.add(
          PerformancePoint(
            next,
            portfolioIndex / portfolioBase - 1,
            selicIndex / selicBase! - 1,
          ),
        );
      }
    }
    final realised = _realised(investments, rates, today);
    return PerformanceResult(points, realised.$1, realised.$2, realised.$3);
  }

  /// The positions in [investments] day by day, in reais, each deposit at its
  /// contracted % of the CDI from its own date: what [compute] measures, in
  /// the shape of the other portfolios ([PortfolioPoint]). Positions without
  /// deposits (cofrinhos) are left out: their past cannot be rebuilt.
  static List<PortfolioPoint> history(
    List<DinzoInvestment> investments,
    BenchmarkRates rates,
    DateTime today,
  ) {
    final end = _day(today);
    final lots = <_Lot>[];
    for (final inv in investments) {
      final moves = inv.movements
          .where((m) => m.type == 'BUY' || m.type == 'SELL')
          .toList();
      if (!moves.any((m) => m.type == 'BUY')) continue;
      final pct =
          inv.rate != null &&
              (inv.rateType ?? '').toUpperCase().contains('CDI') &&
              inv.rate! > 0
          ? inv.rate! / 100
          : 1.0;
      lots.add(_Lot(pct, _flows(moves)));
    }
    if (lots.isEmpty) return const [];
    final first = lots
        .expand((l) => l.flows.keys)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final points = <PortfolioPoint>[];
    var invested = 0.0, selic = 0.0, index = 1.0;
    for (
      var d = first;
      !d.isAfter(end);
      d = DateTime(d.year, d.month, d.day + 1)
    ) {
      for (final lot in lots) {
        final flow = lot.flows[d];
        if (flow == null) continue;
        lot.value = (lot.value + flow).clamp(0, double.infinity);
        invested += flow;
        selic += flow;
      }
      final value = lots.fold<double>(0, (s, l) => s + l.value);
      points.add(PortfolioPoint(d, value, invested, selic, index));
      if (d == end) break;
      final cdi = BenchmarkRates.rateOn(rates.cdi, d);
      for (final lot in lots) {
        lot.value *= 1 + cdi * lot.pctOfCdi;
      }
      final after = lots.fold<double>(0, (s, l) => s + l.value);
      if (value > 0) index *= after / value;
      selic *= 1 + BenchmarkRates.rateOn(rates.selic, d);
    }
    return points;
  }

  static Map<DateTime, double> _flows(List<DinzoInvestmentMovement> moves) {
    final flows = <DateTime, double>{};
    for (final m in moves) {
      final date = DateTime.tryParse(m.date);
      if (date == null) continue;
      final amount = (m.amount ?? 0) * (m.type == 'BUY' ? 1 : -1);
      flows[_day(date)] = (flows[_day(date)] ?? 0) + amount;
    }
    return flows;
  }

  /// (percent of CDI, gross profit, CDI profit) from the real balances.
  static (double?, double, double) _realised(
    List<DinzoInvestment> investments,
    BenchmarkRates rates,
    DateTime today,
  ) {
    final end = _day(today);
    final flows = <DateTime, double>{};
    double grossEnd = 0;
    for (final inv in investments) {
      final moves = inv.movements
          .where((m) => m.type == 'BUY' || m.type == 'SELL')
          .toList();
      if (!moves.any((m) => m.type == 'BUY')) continue;
      _flows(moves).forEach((d, v) => flows[d] = (flows[d] ?? 0) + v);
      final t = DinzoTaxes.positionTax(inv, today);
      if (t.cost != null) grossEnd += t.cost! + (t.grossProfit ?? 0);
    }
    if (flows.isEmpty) return (null, 0, 0);
    final days = flows.keys.toList()..sort();
    double shadow = 0, deposited = 0;
    for (
      var d = days.first;
      !d.isAfter(end);
      d = d.add(const Duration(days: 1))
    ) {
      final flow = flows[d];
      if (flow != null) {
        shadow += flow;
        deposited += flow;
      }
      if (d == end) break;
      shadow *= 1 + BenchmarkRates.rateOn(rates.cdi, d);
    }
    final grossProfit = grossEnd - deposited;
    final cdiProfit = shadow - deposited;
    return (
      cdiProfit > 0 ? grossProfit / cdiProfit * 100 : null,
      grossProfit,
      cdiProfit,
    );
  }
}

class _Lot {
  final double pctOfCdi;
  final Map<DateTime, double> flows;
  double value = 0;

  _Lot(this.pctOfCdi, this.flows);
}
