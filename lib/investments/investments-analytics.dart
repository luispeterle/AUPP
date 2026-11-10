import 'package:aupp/components/known-tags.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:aupp/dinzo/dinzo-taxes.dart';

/// A bank/broker as shown in the Investments tab.
class Institution {
  final String name;

  /// Asset path of the logo, or null for a generic icon.
  final String? logo;
  final Color color;

  const Institution(this.name, this.logo, this.color);

  factory Institution.fromTag(KnownTag tag) =>
      Institution(tag.name, tag.logo, tag.color);

  static final nubank = Institution.fromTag(KnownTag.of('Nubank')!);
  static final c6 = Institution.fromTag(KnownTag.of('C6')!);
  static final btg = Institution.fromTag(KnownTag.of('BTG')!);
  static final rico = Institution.fromTag(KnownTag.of('Rico')!);
  static final auvp = Institution.fromTag(KnownTag.of('AUVP')!);
  static final mercadoPago = Institution.fromTag(KnownTag.of('Mercado Pago')!);

  /// Positions don't say which account holds them; the issuer and the name
  /// do, matched against the bank catalogue ([KnownTag.banks]). "Cofrinho"
  /// is Mercado Pago's savings product (Nubank calls its own "Caixinha").
  /// Stocks have neither; [DinzoInvestment.broker] (the bank connection
  /// Dinzo holds the position under) comes first when known.
  static Institution of(DinzoInvestment inv) {
    if (inv.name.toLowerCase().startsWith('cofrinho')) return mercadoPago;
    final bank =
        KnownTag.bankIn(inv.broker ?? '') ??
        KnownTag.bankIn(inv.issuer ?? '') ??
        KnownTag.bankIn(inv.name);
    if (bank != null) return Institution.fromTag(bank);
    final label = (inv.issuer ?? '').trim();
    return Institution(
      label.isEmpty ? 'Outros' : _titleCase(label),
      null,
      Colors.blueGrey,
    );
  }

  static String _titleCase(String s) => s
      .toLowerCase()
      .split(' ')
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
      .join(' ');

  @override
  bool operator ==(Object other) => other is Institution && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

/// Product family, ready for stocks and funds the user may buy later.
String productOf(DinzoInvestment inv) {
  final name = inv.name.toLowerCase();
  if (name.startsWith('cofrinho')) return 'Cofrinho';
  switch ((inv.subType ?? '').toUpperCase()) {
    case 'CDB':
      return 'CDB';
    case 'LCI':
    case 'LCA':
      return inv.subType!.toUpperCase();
    case 'TREASURY':
      return 'Tesouro';
    case 'REAL_ESTATE_FUND':
      return 'FII';
  }
  switch (inv.type.toUpperCase()) {
    case 'MUTUAL_FUND':
      return 'Fundo';
    case 'EQUITY':
      return 'Ações';
    case 'ETF':
      return 'ETF';
    case 'SECURITY':
      return 'Previdência';
    case 'FIXED_INCOME':
      return 'Renda fixa';
    case 'COE':
      return 'COE';
    case 'CRYPTO':
    case 'CRYPTOCURRENCY':
      return 'Cripto';
  }
  return 'Outros';
}

/// "120% CDI", "12% a.a.", "12,09% em 12 meses" or null.
String? rateLabelOf(DinzoInvestment inv) {
  String pct(double v) => '${NumberFormat('#,##0.##', 'pt_BR').format(v)}%';
  if (inv.rate != null && inv.rate! > 0) {
    return '${pct(inv.rate!)} ${inv.rateType ?? ''}'.trim();
  }
  if (inv.fixedAnnualRate != null && inv.fixedAnnualRate! > 0) {
    return '${pct(inv.fixedAnnualRate!)} a.a.';
  }
  if (inv.lastTwelveMonthsRate != null) {
    return '${pct(inv.lastTwelveMonthsRate!)} em 12 meses';
  }
  return null;
}

/// Positions held at a bank or broker and of a product; null lets all through.
List<Position> filterPositions(
  Iterable<Position> positions, {
  String? institution,
  String? product,
}) => [
  for (final position in positions)
    if ((institution == null || position.institution.name == institution) &&
        (product == null || position.product == product))
      position,
];

class Position {
  final DinzoInvestment inv;
  final Institution institution;
  final String product;
  final String? rateLabel;
  final PositionTax tax;

  /// Next bracket: days left and the rate then (null at 15% or unknown age).
  final int? daysToNextBracket;
  final double? nextRate;

  Position(
    this.inv,
    this.institution,
    this.product,
    this.rateLabel,
    this.tax,
    this.daysToNextBracket,
    this.nextRate,
  );

  double get balance => inv.balance;
  double? get profitPct =>
      tax.cost == null || tax.cost! <= 0 ? null : tax.profit! / tax.cost! * 100;

  /// What waiting for the next bracket saves, on today's profit.
  double get savingIfWait => nextRate == null || (tax.grossProfit ?? 0) <= 0
      ? 0
      : tax.grossProfit! * (tax.rate - nextRate!);
}

class MonthFlow {
  final DateTime month;
  double deposits = 0;
  double withdrawals = 0;

  MonthFlow(this.month);
}

class InvestmentsOverview {
  final List<Position> positions;
  final double total;
  final double estimatedTax;

  /// Balance of positions with unknown deposits (their tax is a guess and
  /// they have no profit figure).
  final double withoutHistory;
  final double knownCost;
  final double knownProfit;
  final Map<Institution, double> byInstitution;
  final Map<String, double> byProduct;
  final Map<String, double> byRate;
  final List<MonthFlow> flows;

  /// Positions moving to a lower bracket within [tipWindowDays].
  final List<Position> bracketTips;

  /// The next [maturityCount] positions to mature (today or later).
  final List<Position> upcomingMaturities;

  InvestmentsOverview({
    required this.positions,
    required this.total,
    required this.estimatedTax,
    required this.withoutHistory,
    required this.knownCost,
    required this.knownProfit,
    required this.byInstitution,
    required this.byProduct,
    required this.byRate,
    required this.flows,
    required this.bracketTips,
    required this.upcomingMaturities,
  });

  static const int maturityCount = 3;

  static DateTime? dueDateOf(Position p) =>
      p.inv.dueDate == null ? null : DateTime.tryParse(p.inv.dueDate!);

  static const int tipWindowDays = 45;

  static ({int days, double rate})? _nextBracket(int? ageDays) {
    if (ageDays == null) return null;
    for (final (limit, rate) in const [
      (180, 0.20),
      (360, 0.175),
      (720, 0.15),
    ]) {
      if (ageDays <= limit) return (days: limit - ageDays + 1, rate: rate);
    }
    return null;
  }

  factory InvestmentsOverview.from(
    List<DinzoInvestment> investments,
    DateTime today,
  ) {
    final positions = <Position>[];
    for (final inv in investments) {
      if (inv.archived || inv.balance <= 0) continue;
      final tax = DinzoTaxes.positionTax(inv, today);
      final next = tax.rate > 0 ? _nextBracket(tax.ageDays) : null;
      positions.add(
        Position(
          inv,
          Institution.of(inv),
          productOf(inv),
          rateLabelOf(inv),
          tax,
          next?.days,
          next?.rate,
        ),
      );
    }
    positions.sort((a, b) => b.balance.compareTo(a.balance));

    double sum(Iterable<double> v) => v.fold(0, (a, b) => a + b);
    Map<K, double> group<K>(K Function(Position) key) {
      final m = <K, double>{};
      for (final p in positions) {
        m[key(p)] = (m[key(p)] ?? 0) + p.balance;
      }
      return Map.fromEntries(
        m.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
      );
    }

    final flowsByMonth = <DateTime, MonthFlow>{};
    for (final inv in investments) {
      for (final m in inv.movements) {
        final date = DateTime.tryParse(m.date);
        if (date == null) continue;
        final month = DateTime(date.year, date.month);
        final flow = flowsByMonth.putIfAbsent(month, () => MonthFlow(month));
        if (m.type == 'BUY') {
          flow.deposits += m.amount ?? 0;
        } else if (m.type == 'SELL') {
          flow.withdrawals += m.netAmount ?? m.amount ?? 0;
        }
      }
    }
    final withHistory = positions.where((p) => p.tax.cost != null);
    return InvestmentsOverview(
      positions: positions,
      total: sum(positions.map((p) => p.balance)),
      estimatedTax: sum(positions.map((p) => p.tax.tax)),
      withoutHistory: sum(
        positions.where((p) => p.tax.cost == null).map((p) => p.balance),
      ),
      knownCost: sum(withHistory.map((p) => p.tax.cost!)),
      knownProfit: sum(withHistory.map((p) => p.tax.profit!)),
      byInstitution: group((p) => p.institution),
      byProduct: group((p) => p.product),
      byRate: group((p) => p.rateLabel ?? 'Sem taxa informada'),
      flows: flowsByMonth.values.toList()
        ..sort((a, b) => a.month.compareTo(b.month)),
      bracketTips:
          positions
              .where(
                (p) =>
                    p.daysToNextBracket != null &&
                    p.daysToNextBracket! <= tipWindowDays &&
                    p.savingIfWait >= 1,
              )
              .toList()
            ..sort(
              (a, b) => a.daysToNextBracket!.compareTo(b.daysToNextBracket!),
            ),
      upcomingMaturities:
          (positions.where((p) {
                final due = dueDateOf(p);
                return due != null &&
                    !due.isBefore(DateTime(today.year, today.month, today.day));
              }).toList()..sort(
                (a, b) => dueDateOf(a)!.compareTo(dueDateOf(b)!),
              ))
              .take(maturityCount)
              .toList(),
    );
  }
}
