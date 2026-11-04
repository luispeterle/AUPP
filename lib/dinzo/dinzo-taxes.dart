
/// A movement inside an investment position (Dinzo `InvestmentTransaction`).
class DinzoInvestmentMovement {
  final String id;

  /// `BUY`, `SELL`, `TAX` (e.g. come-cotas)...
  final String type;
  final String date;

  /// Gross amount.
  final double? amount;

  /// What actually reached the account (after withheld income tax).
  final double? netAmount;

  DinzoInvestmentMovement({
    required this.id,
    required this.type,
    required this.date,
    this.amount,
    this.netAmount,
  });

  factory DinzoInvestmentMovement.fromJson(Map<String, dynamic> json) =>
      DinzoInvestmentMovement(
        id: json['id'] as String,
        type: json['type'] as String? ?? '',
        date: json['date'] as String,
        amount: (json['amount'] as num?)?.toDouble(),
        netAmount: (json['net_amount'] as num?)?.toDouble(),
      );
}

/// An investment position with its movements (Dinzo `/v1/investments/{id}`).
class DinzoInvestment {
  /// Stable identity across syncs (the row `id` changes on every sync).
  final String assetKey;
  final String name;

  /// `FIXED_INCOME`, `MUTUAL_FUND`, `EQUITY`...
  final String type;

  /// Current gross balance.
  final double balance;
  final bool? taxExempt;
  final bool archived;
  final String? purchaseDate;
  final List<DinzoInvestmentMovement> movements;

  /// Contracted yield: [rate] % of [rateType] (e.g. 120 % of `CDI`), or a
  /// fixed annual rate.
  final double? rate;
  final String? rateType;
  final double? fixedAnnualRate;

  final String? subType;
  final String? issuer;
  final String? code;
  final String? dueDate;

  /// Funds: return over the last 12 months, in percent.
  final double? lastTwelveMonthsRate;

  /// Bank connection holding it ("Nubank"), from Dinzo's MCP: the REST row
  /// doesn't say. Stored in [raw] as `broker`.
  final String? broker;

  /// The API row as received, kept for the local investments cache.
  final Map<String, dynamic> raw;

  DinzoInvestment({
    required this.assetKey,
    required this.name,
    required this.type,
    required this.balance,
    this.taxExempt,
    this.archived = false,
    this.purchaseDate,
    this.movements = const [],
    this.rate,
    this.rateType,
    this.fixedAnnualRate,
    this.subType,
    this.issuer,
    this.code,
    this.dueDate,
    this.lastTwelveMonthsRate,
    this.broker,
    this.raw = const {},
  });

  factory DinzoInvestment.fromJson(
    Map<String, dynamic> json,
  ) => DinzoInvestment(
    assetKey: json['asset_key'] as String? ?? json['id'] as String,
    name: (json['name'] as String? ?? '').trim(),
    type: json['type'] as String? ?? '',
    balance: (json['balance'] as num?)?.toDouble() ?? 0,
    taxExempt: json['tax_exempt'] as bool?,
    archived: json['archived'] as bool? ?? false,
    purchaseDate: json['purchase_date'] as String?,
    rate: (json['rate'] as num?)?.toDouble(),
    rateType: json['rate_type'] as String?,
    fixedAnnualRate: (json['fixed_annual_rate'] as num?)?.toDouble(),
    subType: json['sub_type'] as String?,
    issuer: json['issuer'] as String?,
    code: json['code'] as String?,
    dueDate: json['due_date'] as String?,
    lastTwelveMonthsRate: (json['last_twelve_months_rate'] as num?)?.toDouble(),
    broker: json['broker'] as String?,
    raw: json,
    movements: ((json['transactions'] as List?) ?? const [])
        .map((m) => DinzoInvestmentMovement.fromJson(m as Map<String, dynamic>))
        .toList(),
  );
}

/// Brazilian income tax on fixed income (regressive table) from investment
/// data. Pure: no network, no database.
class DinzoTaxes {
  static const double maxRate = 0.225;

  /// Regressive rate by holding period.
  static double rateFor(int days) => days <= 180
      ? 0.225
      : days <= 360
      ? 0.20
      : days <= 720
      ? 0.175
      : 0.15;

  /// Cost, profit and income tax of one position on [today].
  ///
  /// The balance Open Finance reports is already NET of income tax (checked
  /// against the contracted rate × CDI: a R$ 10.000 CDB at 120% CDI shows
  /// exactly the after-tax value). So the tax is not something still to pay:
  /// it is already deducted, and the gross value is rebuilt from it.
  static PositionTax positionTax(DinzoInvestment inv, DateTime today) {
    if (inv.archived || inv.balance <= 0) return const PositionTax();
    final buys = inv.movements.where((m) => m.type == 'BUY').toList();
    final cost = buys.fold<double>(0, (s, m) => s + (m.amount ?? 0));
    // Exempt products pay nothing; funds already pay through come-cotas.
    final taxable = inv.taxExempt != true && inv.type != 'MUTUAL_FUND';
    // Unknown deposits (e.g. cofrinhos): no profit figure, nothing to rebuild.
    if (cost <= 0) return const PositionTax();
    // Partial redemptions took their share of the cost with them.
    final sold = inv.movements
        .where((m) => m.type == 'SELL')
        .fold<double>(0, (s, m) => s + (m.amount ?? 0));
    final remainingCost = cost * inv.balance / (inv.balance + sold);
    final netProfit = inv.balance - remainingCost;
    final firstBuy =
        inv.purchaseDate ??
        (buys.map((m) => m.date).toList()..sort()).firstOrNull;
    final purchased = firstBuy == null ? null : DateTime.tryParse(firstBuy);
    final days = purchased == null ? null : today.difference(purchased).inDays;
    // Unknown purchase date: highest bracket.
    final rate = !taxable ? 0.0 : (days == null ? maxRate : rateFor(days));
    final grossProfit = netProfit > 0 ? netProfit / (1 - rate) : netProfit;
    return PositionTax(
      cost: remainingCost,
      profit: netProfit,
      grossProfit: grossProfit,
      tax: grossProfit - netProfit,
      rate: rate,
      ageDays: days,
    );
  }
}

class PositionTax {
  /// Remaining invested amount (null when the position has no history).
  final double? cost;

  /// Profit after tax (what the reported balance already reflects).
  final double? profit;

  /// Profit before tax.
  final double? grossProfit;

  /// Income tax already deducted from the reported balance.
  final double tax;

  /// Current bracket (0 for exempt products and funds).
  final double rate;

  /// Days since the first deposit, when known.
  final int? ageDays;

  const PositionTax({
    this.cost,
    this.profit,
    this.grossProfit,
    this.tax = 0,
    this.rate = 0,
    this.ageDays,
  });
}
