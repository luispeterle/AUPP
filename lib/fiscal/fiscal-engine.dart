import 'dart:math' as math;

import 'fiscal-data.dart';
import 'fiscal-tables.dart';

enum RevenueSource {
  /// A payment that reached a company account.
  account,

  /// An invoice typed in (did not go through a company account).
  manual,

  /// An occurrence of an income estimate: counts only in a month from the
  /// current one on that has no real revenue yet.
  forecast,
}

/// Revenue of one month in one activity, from one source.
class RevenueEntry {
  final YearMonth month;
  final double value;
  final String activity;
  final RevenueSource source;

  /// What it came from: the payment's [FiscalData.revenueKey], the manual
  /// invoice's id or the estimate's id.
  final String key;
  final String title;
  final DateTime? date;

  /// A payment not checked yet (counted as an invoice meanwhile).
  final bool pending;

  const RevenueEntry({
    required this.month,
    required this.value,
    required this.activity,
    required this.source,
    required this.key,
    this.title = '',
    this.date,
    this.pending = false,
  });
}

/// The company in one month: revenue, Fator R, taxes and warnings.
class FiscalMonth {
  final YearMonth month;
  final RegimeKind? regime;
  final double revenue;
  final Map<String, double> revenueByActivity;

  /// The revenue is the estimates' (no real revenue yet).
  final bool forecast;
  final double proLabore;

  /// RBT12 of the rate (12 months before; proportional while younger).
  final double rbt12;

  /// Fator R and its window's payroll and revenue; null when no activity of
  /// the company depends on it, or out of the Simples.
  final double? fatorR;
  final double fs12;
  final double rbt12r;
  final Map<String, Annex> annexes;
  final double das;
  final double inss;
  final double irrf;

  /// The accountant's fee paid in the month.
  final double accountantFee;

  /// One-off payments of the month (not in [total]).
  final double otherPayments;
  final List<String> warnings;

  const FiscalMonth({
    required this.month,
    required this.regime,
    required this.revenue,
    required this.revenueByActivity,
    required this.forecast,
    required this.proLabore,
    required this.rbt12,
    required this.fatorR,
    required this.fs12,
    required this.rbt12r,
    required this.annexes,
    required this.das,
    required this.inss,
    required this.irrf,
    required this.accountantFee,
    this.otherPayments = 0,
    required this.warnings,
  });

  /// INSS + IRRF of the pró-labore: one guide (DCTFWeb).
  double get dctfweb => inss + irrf;

  /// The taxes of the month, due on the 20th of the next one.
  double get taxes => das + dctfweb;

  /// Taxes and accountant: what the company costs in the month.
  double get total => taxes + accountantFee;

  /// DAS ÷ revenue, in the Simples.
  double get effectiveRate =>
      regime == RegimeKind.simples && revenue > 0 ? das / revenue : 0;

  /// Everything of the month is due on the 20th of the next one.
  DateTime get due => DateTime(month.year, month.month + 1, 20);

  bool get inAnnexV => annexes.values.contains(Annex.v);
}

/// The yearly income tax of the person (estimate).
class YearIncomeTax {
  final int year;
  final double revenue;
  final double das;
  final double proLabore;
  final double inss;
  final double irrfWithheld;
  final double otherExpenses;
  final double accountantFees;
  final double otherPayments;
  final double profit;
  final double exemptProfit;
  final double taxableProfit;
  final double taxableIncome;
  final double discount;
  final double tax;
  final double reduction;

  const YearIncomeTax({
    required this.year,
    required this.revenue,
    required this.das,
    required this.proLabore,
    required this.inss,
    required this.irrfWithheld,
    required this.otherExpenses,
    required this.accountantFees,
    required this.otherPayments,
    required this.profit,
    required this.exemptProfit,
    required this.taxableProfit,
    required this.taxableIncome,
    required this.discount,
    required this.tax,
    required this.reduction,
  });

  double get due => math.max(0, tax - reduction);

  /// Positive: to pay in the declaration; negative: refund.
  double get adjustment => due - irrfWithheld;
}

/// What the pró-labore must be to reach Fator R 28% in [target].
class FatorRPlan {
  final YearMonth target;

  /// First month the new pró-labore is paid.
  final YearMonth from;

  /// Per month, from [from] to the end of [target]'s window; null when no
  /// month left can count.
  final double? proLabore;

  const FatorRPlan(this.target, this.from, this.proLabore);
}

class FiscalEngine {
  final FiscalData data;
  final List<RevenueEntry> entries;

  /// The current month: forecasts count from it on.
  final YearMonth today;

  late final Map<YearMonth, List<RevenueEntry>> _byMonth = () {
    final real = <YearMonth, List<RevenueEntry>>{};
    final forecast = <YearMonth, List<RevenueEntry>>{};
    for (final e in entries) {
      (e.source == RevenueSource.forecast ? forecast : real)
          .putIfAbsent(e.month, () => [])
          .add(e);
    }
    // The estimate stands for the money that will come into the account:
    // once some came in that month, it is replaced; an invoice typed in adds
    // to it.
    for (final f in forecast.entries) {
      if (f.key.isBefore(today)) continue;
      final arrived = (real[f.key] ?? const []).any(
        (e) => e.source == RevenueSource.account,
      );
      if (!arrived) real.putIfAbsent(f.key, () => []).addAll(f.value);
    }
    return real;
  }();

  final Map<YearMonth, FiscalMonth> _months = {};

  FiscalEngine(this.data, this.entries, {required this.today});

  /// The revenue that counts in [m]: real, else (from [today] on) forecast.
  List<RevenueEntry> revenueEntries(YearMonth m) => _byMonth[m] ?? const [];

  double revenueOf(YearMonth m) =>
      revenueEntries(m).fold(0, (s, e) => s + e.value);

  bool _isForecast(YearMonth m) =>
      revenueEntries(m).any((e) => e.source == RevenueSource.forecast);

  /// Payroll of [m]: the pró-labore in the Simples; a MEI has none.
  double payrollOf(YearMonth m) =>
      data.regimeAt(m)?.kind == RegimeKind.simples ? data.proLaboreAt(m) : 0;

  bool get usesFatorR => data.allActivities.any(
    (c) => data.activityOf(c)?.usesFatorR ?? false,
  );

  double _sum(YearMonth from, YearMonth to, double Function(YearMonth) f) {
    var total = 0.0;
    for (var m = from; !m.isAfter(to); m = m.add(1)) {
      total += f(m);
    }
    return total;
  }

  /// RBT12 of the rate in [m] (Res. CGSN 140, art. 22): the 12 months
  /// before; while younger, the average of the months so far × 12, and in
  /// the first month its own revenue × 12.
  double rbt12(YearMonth m) {
    final start = data.firstMonth;
    if (start == null) return 0;
    final active = m.since(start);
    if (active >= 12) return _sum(m.add(-12), m.add(-1), revenueOf);
    if (active <= 0) return revenueOf(m) * 12;
    return _sum(start, m.add(-1), revenueOf) / active * 12;
  }

  /// The months whose payroll and revenue give the Fator R of [m]: until
  /// 2026, the 12 before it; from 2027 (Res. CGSN 190/2026), the 12 before
  /// the previous one.
  (YearMonth, YearMonth) fatorRWindow(YearMonth m) => m.year >= 2027
      ? (m.add(-13), m.add(-2))
      : (m.add(-12), m.add(-1));

  /// Fator R of [m], with its window's payroll and revenue.
  (double, double, double) fatorR(YearMonth m) {
    final start = data.firstMonth ?? m;
    final active = m.since(start);
    if (m.year >= 2027 && active < 2) return (0.28, 0, 0);
    if (m.year < 2027 && active <= 0) {
      final fs = payrollOf(m);
      final rev = revenueOf(m);
      if (rev <= 0) return (fs > 0 ? 0.28 : 0.01, fs, rev);
      return (fs <= 0 ? 0.01 : fs / rev, fs, rev);
    }
    var (from, to) = fatorRWindow(m);
    if (from.isBefore(start)) from = start;
    if (to.isBefore(from)) return (0.28, 0, 0);
    final fs = _sum(from, to, payrollOf);
    final rev = _sum(from, to, revenueOf);
    // A younger company's months are scaled to 12: the ratio is the same.
    if (fs <= 0) return (0.01, fs, rev);
    if (rev <= 0) return (0.28, fs, rev);
    return (fs / rev, fs, rev);
  }

  FiscalMonth month(YearMonth m) => _months.putIfAbsent(m, () => _compute(m));

  FiscalMonth _compute(YearMonth m) {
    final regime = data.regimeAt(m)?.kind;
    final tables = FiscalTables.forYear(m.year);
    final byActivity = <String, double>{};
    for (final e in revenueEntries(m)) {
      byActivity.update(e.activity, (v) => v + e.value, ifAbsent: () => e.value);
    }
    final revenue = revenueOf(m);
    final warnings = <String>[];
    var das = 0.0;
    var rbt = 0.0;
    double? r;
    var fs12 = 0.0;
    var rbt12r = 0.0;
    final annexes = <String, Annex>{};
    var proLabore = 0.0;
    var inss = 0.0;
    var irrf = 0.0;

    if (regime == RegimeKind.mei) {
      das = tables.dasMei;
      final (used, limit) = meiYearUse(m);
      if (used > limit * (1 + FiscalTables.meiTolerance)) {
        warnings.add(
          'Faturamento do MEI no ano passou 20% do limite: exclusão '
          'desde janeiro',
        );
      } else if (used > limit) {
        warnings.add('Faturamento do MEI no ano passou do limite: imposto '
            'sobre o excesso');
      }
    } else if (regime == RegimeKind.simples) {
      rbt = rbt12(m);
      if (usesFatorR) {
        final f = fatorR(m);
        r = f.$1;
        fs12 = f.$2;
        rbt12r = f.$3;
      }
      for (final e in byActivity.entries) {
        final activity = data.activityOf(e.key);
        final annex = switch (activity?.kind) {
          ActivityKind.annexV => Annex.v,
          ActivityKind.fatorR =>
            (r ?? 0) >= FiscalTables.fatorRThreshold ? Annex.iii : Annex.v,
          _ => Annex.iii,
        };
        annexes[e.key] = annex;
        das += e.value * FiscalTables.effectiveRate(annex, rbt);
      }
      if (annexes.containsValue(Annex.v) &&
          byActivity.keys.any((c) => data.activityOf(c)?.usesFatorR ?? false)) {
        warnings.add(
          'Anexo V: Fator R de ${(100 * (r ?? 0)).toStringAsFixed(1)}%, '
          'abaixo de 28%',
        );
      }
      proLabore = data.proLaboreAt(m);
      inss = tables.inss(proLabore);
      irrf = tables.irrf(proLabore);
      if (proLabore > 0 && proLabore < tables.minimumWage - 0.005) {
        warnings.add('Pró-labore abaixo do salário mínimo');
      }
      if (proLabore <= 0) warnings.add('Sem pró-labore');
      if (rbt > 3600000) {
        warnings.add('RBT12 acima de 3,6 milhões: ISS fora do DAS');
      }
    }
    return FiscalMonth(
      month: m,
      regime: regime,
      revenue: revenue,
      revenueByActivity: byActivity,
      forecast: _isForecast(m),
      proLabore: proLabore,
      rbt12: rbt,
      fatorR: r,
      fs12: fs12,
      rbt12r: rbt12r,
      annexes: annexes,
      das: _round2(das),
      inss: _round2(inss),
      irrf: _round2(irrf),
      accountantFee: regime == null ? 0 : data.accountantFeeAt(m),
      otherPayments: data.otherPaymentsAt(m),
      warnings: warnings,
    );
  }

  /// MEI revenue of [m]'s year up to [m], and that year's limit (6.750 per
  /// month open in the opening year).
  (double, double) meiYearUse(YearMonth m) {
    var used = 0.0;
    for (var i = YearMonth(m.year, 1); !i.isAfter(m); i = i.add(1)) {
      if (data.regimeAt(i)?.kind == RegimeKind.mei) used += revenueOf(i);
    }
    final opening = data.firstMonth?.year == m.year;
    final limit = opening
        ? FiscalTables.meiYearLimit / 12 * _monthsOpenIn(m.year)
        : FiscalTables.meiYearLimit;
    return (used, limit);
  }

  int _monthsOpenIn(int year) {
    final start = data.firstMonth;
    if (start == null || start.year != year) return 12;
    return 13 - start.month;
  }

  /// Every month from the first regime to [to].
  List<FiscalMonth> months(YearMonth to) {
    final start = data.firstMonth;
    if (start == null) return [];
    return [for (var m = start; !m.isAfter(to); m = m.add(1)) month(m)];
  }

  /// The pró-labore, paid from [from] on, that makes the Fator R of
  /// [target] reach 28%.
  FatorRPlan planFatorR(YearMonth target, YearMonth from) {
    final start = data.firstMonth ?? target;
    var (wFrom, wTo) = fatorRWindow(target);
    if (wFrom.isBefore(start)) wFrom = start;
    final revenue = _sum(wFrom, wTo, revenueOf);
    var have = 0.0;
    var left = 0;
    for (var m = wFrom; !m.isAfter(wTo); m = m.add(1)) {
      if (m.isBefore(from)) {
        have += payrollOf(m);
      } else if (data.regimeAt(m)?.kind == RegimeKind.simples) {
        left++;
      }
    }
    if (left == 0) return FatorRPlan(target, from, null);
    final need = FiscalTables.fatorRThreshold * revenue - have;
    final minimum = FiscalTables.forYear(from.year).minimumWage;
    return FatorRPlan(target, from, math.max(need / left, minimum));
  }

  /// The person's yearly income tax (estimate): the pró-labore, plus the
  /// distributed profit above the tax-free share (32% of the revenue
  /// without full books).
  YearIncomeTax incomeTax(int year) {
    var revenue = 0.0, das = 0.0, pl = 0.0, inss = 0.0, irrf = 0.0;
    var fees = 0.0, others = 0.0;
    for (var m = YearMonth(year, 1); m.year == year; m = m.add(1)) {
      if (data.regimeAt(m) == null) continue;
      final fm = month(m);
      revenue += fm.revenue;
      das += fm.das;
      pl += fm.proLabore;
      inss += fm.inss;
      irrf += fm.irrf;
      fees += fm.accountantFee;
      others += fm.otherPayments;
    }
    final other = data.otherExpenses[year] ?? 0;
    final profit = math.max(
      0.0,
      revenue - das - pl - fees - others - other,
    );
    final exempt = data.fullBookkeeping
        ? profit
        : math.min(profit, FiscalTables.presumedProfit * revenue);
    final taxableProfit = profit - exempt;
    final income = pl + taxableProfit;
    final tables = FiscalTables.forYear(year);
    final simplified = math.min(0.2 * income, tables.yearSimplifiedLimit);
    final discount = math.max(inss, simplified);
    final base = math.max(0.0, income - discount);
    final b = bandFor(tables.yearIrrf, base);
    final tax = math.max(0.0, base * b.rate - b.deduction);
    final reduction = tables.yearReducer?.of(income, tax) ?? 0;
    return YearIncomeTax(
      year: year,
      revenue: revenue,
      das: das,
      proLabore: pl,
      inss: inss,
      irrfWithheld: irrf,
      otherExpenses: other,
      accountantFees: fees,
      otherPayments: others,
      profit: profit,
      exemptProfit: exempt,
      taxableProfit: taxableProfit,
      taxableIncome: income,
      discount: discount,
      tax: _round2(tax),
      reduction: _round2(reduction),
    );
  }
}

double _round2(double v) => (v * 100).roundToDouble() / 100;
