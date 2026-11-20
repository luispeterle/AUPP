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

/// Fixed income day by day, from its deposits and sales. Pure: no network,
/// no database.
class Performance {
  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Income tax assumed for a position bought before the Dinzo's history:
  /// what was withheld on each sale is taken as all of it IR at 20%, with no
  /// IOF, which gives back the profit, the cost and, at the contracted rate,
  /// the day it was bought.
  static const oldPositionTax = 0.20;

  /// The positions in [investments] day by day, in reais, each deposit at its
  /// contracted % of the CDI from its own date, in the shape of the other
  /// portfolios ([PortfolioPoint]).
  ///
  /// Gross by default: sales leave at their gross amount and nothing is
  /// withheld. With [net], what really moved in the account: sales leave at
  /// what reached it (after IR and IOF), each day is worth the gross minus
  /// the IR of its holding period, and an open position ends at the balance
  /// the bank reports, the gap spread over its life.
  ///
  /// Positions without any sale or deposit (cofrinhos) are left out: their
  /// past cannot be rebuilt.
  static List<PortfolioPoint> history(
    List<DinzoInvestment> investments,
    BenchmarkRates rates,
    DateTime today, {
    bool net = false,
  }) {
    final end = _day(today);
    final positions = [
      for (final inv in investments) ?_Position.of(inv, rates),
    ];
    if (positions.isEmpty) return const [];
    final first = positions
        .map((p) => p.start)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final days = [
      for (
        var d = first;
        !d.isAfter(end);
        d = DateTime(d.year, d.month, d.day + 1)
      )
        d,
    ];
    final paths = [for (final p in positions) p.path(days, rates, net)];
    final points = <PortfolioPoint>[];
    var invested = 0.0, selic = 0.0;
    for (var i = 0; i < days.length; i++) {
      final d = days[i];
      var moved = 0.0;
      for (final p in positions) {
        moved += (net ? p.cash : p.flows)[d] ?? 0;
      }
      invested += moved;
      selic += moved;
      final value = paths.fold(0.0, (sum, path) => sum + path[i]);
      points.add(PortfolioPoint(d, value, invested, selic));
      selic *= 1 + BenchmarkRates.rateOn(rates.selic, d);
    }
    return points;
  }

}

/// One fixed income position for [Performance.history]: its deposits and
/// sales, gross ([flows]) and as they moved in the account ([cash]).
class _Position {
  final double pctOfCdi;
  final Map<DateTime, double> flows;
  final Map<DateTime, double> cash;
  final DateTime start;

  /// From this day on it holds nothing: what the model left over is not money.
  final DateTime? closedOn;

  /// What the bank reports now, already net of IR; null when it is not known
  /// how it got there.
  final double? balance;

  _Position(
    this.pctOfCdi,
    this.flows,
    this.cash,
    this.start,
    this.closedOn,
    this.balance,
  );

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static _Position? of(DinzoInvestment inv, BenchmarkRates rates) {
    final pct =
        inv.rate != null &&
            (inv.rateType ?? '').toUpperCase().contains('CDI') &&
            inv.rate! > 0
        ? inv.rate! / 100
        : 1.0;
    final moves = inv.movements
        .where((m) => m.type == 'BUY' || m.type == 'SELL')
        .toList();
    final known = moves.any((m) => m.type == 'BUY');
    final flows = <DateTime, double>{}, cash = <DateTime, double>{};
    void add(DateTime day, double gross, double received) {
      flows[day] = (flows[day] ?? 0) + gross;
      cash[day] = (cash[day] ?? 0) + received;
    }

    DateTime? lastSale;
    for (final m in moves) {
      final date = DateTime.tryParse(m.date);
      if (date == null) continue;
      final day = _day(date);
      final amount = (m.amount ?? 0).abs();
      if (m.type == 'BUY') {
        add(day, amount, amount);
        continue;
      }
      final received = (m.netAmount ?? amount).abs();
      if (!known) {
        // Bought before the history: without the tax nothing tells what went
        // in, and a sale alone would count as money made.
        final profit = (amount - received) / Performance.oldPositionTax;
        final cost = amount - profit;
        if (profit <= 0 || cost <= 0) continue;
        add(_boughtOn(day, amount / cost, pct, rates), cost, cost);
      }
      add(day, -amount, -received);
      if (lastSale == null || day.isAfter(lastSale)) lastSale = day;
    }
    if (flows.isEmpty) return null;
    final start = flows.keys.reduce((a, b) => a.isBefore(b) ? a : b);
    final open = known && inv.balance > 0;
    return _Position(
      pct,
      flows,
      cash,
      start,
      open ? null : lastSale,
      open ? inv.balance : null,
    );
  }

  /// The day [growth] was reached by [sold] at [pct] of the CDI; before the
  /// rates known, at the first one known.
  static DateTime _boughtOn(
    DateTime sold,
    double growth,
    double pct,
    BenchmarkRates rates,
  ) {
    if (rates.cdi.isEmpty) return sold;
    final earliest = rates.cdi.keys.reduce((a, b) => a.isBefore(b) ? a : b);
    var day = sold;
    var factor = 1.0;
    for (var i = 0; factor < growth && i < 3650; i++) {
      day = DateTime(day.year, day.month, day.day - 1);
      final rate = day.isBefore(earliest)
          ? (day.weekday > DateTime.friday ? 0.0 : rates.cdi[earliest]!)
          : BenchmarkRates.rateOn(rates.cdi, day);
      factor *= 1 + rate * pct;
    }
    return day;
  }

  /// What it was worth on each of [days] (gross, or [net] of IR).
  List<double> path(List<DateTime> days, BenchmarkRates rates, bool net) {
    final values = List<double>.filled(days.length, 0);
    var gross = 0.0, cost = 0.0;
    var first = -1;
    for (var i = 0; i < days.length; i++) {
      final day = days[i];
      final flow = flows[day];
      if (flow != null) {
        if (first < 0) first = i;
        if (flow > 0) {
          cost += flow;
        } else if (gross > 0) {
          // A sale takes its share of the cost with it.
          cost *= (1 + flow / gross).clamp(0, 1);
        }
        gross = (gross + flow).clamp(0, double.infinity);
      }
      if (closedOn != null && !day.isBefore(closedOn!)) gross = cost = 0;
      values[i] = net
          ? gross -
                DinzoTaxes.rateFor(day.difference(start).inDays) *
                    (gross - cost).clamp(0, double.infinity)
          : gross;
      gross *= 1 + BenchmarkRates.rateOn(rates.cdi, day) * pctOfCdi;
    }
    // The model ends where the bank says, the gap spread from the start.
    final last = days.length - 1;
    if (net && balance != null && first >= 0) {
      final gap = balance! - values[last];
      final span = last - first;
      for (var i = first; i <= last; i++) {
        values[i] += span == 0 ? gap : gap * (i - first) / span;
      }
    }
    return values;
  }
}
