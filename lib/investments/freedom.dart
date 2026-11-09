import 'dart:math' as math;

import 'package:aupp/models/category-type.dart';
import 'package:aupp/models/record.dart';

import 'investments-analytics.dart';

/// Financial freedom as the course measures it: when the portfolio's income
/// pays the monthly spending. Pessimistic on purpose: 8% a year and a quarter
/// set aside (tax, inflation, bad years).
class Freedom {
  static const annualRate = 0.08;
  static const kept = 0.75;
  static const months = 6;

  static double get monthlyRate => math.pow(1 + annualRate, 1 / 12) - 1;

  /// What [wealth] would pay each month.
  static double passiveIncome(double wealth) =>
      math.max(0.0, wealth) * monthlyRate * kept;

  /// The wealth that pays [spending] each month.
  static double wealthFor(double spending) =>
      math.max(0.0, spending) / (monthlyRate * kept);

  /// What the month costs to live, average of the [months] full months
  /// before [now]: the income minus what was set aside to invest. Goals,
  /// leftovers and spending all count; only investing does not.
  ///
  /// Income leaves out transfers and what lands in [investWallets]. Set aside =
  /// transfers from any other wallet into [investWallets], minus what comes back
  /// out of them, plus what was invested straight from any other wallet (minus
  /// what came back straight into one), so nothing is counted twice.
  static double livingCost(
    Iterable<Record?> records,
    DateTime now, {
    required Set<int> investWallets,
  }) {
    final end = DateTime(now.year, now.month);
    final start = DateTime(now.year, now.month - months);
    var income = 0.0;
    var invested = 0.0;
    for (final r in records) {
      if (r == null || r.isDestinationTransferView) continue;
      final d = r.dateTime;
      if (d.isBefore(start) || !d.isBefore(end)) continue;
      final amount = (r.value ?? 0).abs();
      if (r.isInvestmentFlow) {
        if (!investWallets.contains(r.walletId)) {
          invested += r.isInvestmentBuy ? amount : -amount;
        }
        continue;
      }
      if (r.isTransfer) {
        final from = investWallets.contains(r.walletId);
        final to = investWallets.contains(r.transferWalletId);
        if (to && !from) invested += amount;
        if (from && !to) invested -= amount;
        continue;
      }
      if (r.category?.categoryType == CategoryType.income &&
          !investWallets.contains(r.walletId)) {
        income += r.value ?? 0;
      }
    }
    return math.max(0.0, income - invested) / months;
  }

  static DateTime spendingStart(DateTime now) =>
      DateTime(now.year, now.month - months);
}

/// The deposit guarantee (FGC): R$ 250 mil per institution. Only bank-issued
/// fixed income counts (CDB, LCI, LCA, the Mercado Pago "Cofrinho").
class DepositGuarantee {
  static const perInstitution = 250000.0;
  static const products = {'CDB', 'LCI', 'LCA', 'Cofrinho'};

  /// Institution name → covered balance, only where it passes the limit.
  static Map<String, double> overLimit(List<Position> positions) {
    final covered = <String, double>{};
    for (final p in positions) {
      if (!products.contains(p.product)) continue;
      covered[p.institution.name] = (covered[p.institution.name] ?? 0) + p.balance;
    }
    return {
      for (final e in covered.entries)
        if (e.value > perInstitution) e.key: e.value,
    };
  }
}
