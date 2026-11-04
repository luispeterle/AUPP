/// Tables of the Simples Nacional, MEI, INSS and IRRF the company module
/// computes with. A year without its own line uses the latest one before
/// it: a new year is one more line.

/// A calendar month.
class YearMonth implements Comparable<YearMonth> {
  final int year;
  final int month;

  const YearMonth(this.year, this.month);

  factory YearMonth.of(DateTime d) => YearMonth(d.year, d.month);

  /// "2026-11"; null when it is not one.
  static YearMonth? tryParse(Object? text) {
    if (text is! String) return null;
    final m = RegExp(r'^(\d{4})-(\d{1,2})').firstMatch(text.trim());
    if (m == null) return null;
    final month = int.parse(m.group(2)!);
    if (month < 1 || month > 12) return null;
    return YearMonth(int.parse(m.group(1)!), month);
  }

  int get _index => year * 12 + month - 1;

  YearMonth add(int months) {
    final i = _index + months;
    return YearMonth(i ~/ 12, i % 12 + 1);
  }

  /// Months from [other] to this one (negative when before).
  int since(YearMonth other) => _index - other._index;

  bool isBefore(YearMonth o) => _index < o._index;
  bool isAfter(YearMonth o) => _index > o._index;

  @override
  int compareTo(YearMonth o) => _index.compareTo(o._index);

  @override
  bool operator ==(Object o) => o is YearMonth && o._index == _index;

  @override
  int get hashCode => _index;

  /// "2026-11".
  String get key => '$year-${month.toString().padLeft(2, '0')}';

  static const _names = [
    'jan', 'fev', 'mar', 'abr', 'mai', 'jun',
    'jul', 'ago', 'set', 'out', 'nov', 'dez',
  ];

  /// "nov/26".
  String get label => '${_names[month - 1]}/${(year % 100).toString().padLeft(2, '0')}';

  @override
  String toString() => key;
}

/// One band of a progressive table: up to [upTo] (null = no limit), the
/// [rate] less [deduction].
class Band {
  final double? upTo;
  final double rate;
  final double deduction;

  const Band(this.upTo, this.rate, this.deduction);
}

Band bandFor(List<Band> bands, double base) =>
    bands.firstWhere((b) => b.upTo == null || base <= b.upTo!);

/// How an activity is taxed in the Simples Nacional.
enum ActivityKind {
  /// Anexo III whatever the payroll.
  annexIII,

  /// Anexo III with Fator R of 28% or more, Anexo V below.
  fatorR,

  /// Anexo V whatever the payroll.
  annexV,
}

enum Annex { iii, v }

class Activity {
  final String code;
  final String name;
  final ActivityKind kind;

  /// A word or two for the spreadsheet.
  final String? _short;

  const Activity(this.code, this.name, this.kind, [this._short]);

  String get short => _short ?? code;

  bool get usesFatorR => kind == ActivityKind.fatorR;

  String get kindLabel => switch (kind) {
    ActivityKind.annexIII => 'Anexo III direto',
    ActivityKind.fatorR => 'Fator R (Anexo III ou V)',
    ActivityKind.annexV => 'Anexo V direto',
  };
}

class FiscalTables {
  FiscalTables._();

  /// Activities a service company usually has (CNAE, or the invoice's
  /// service code), and how each is taxed
  /// (LC 123/2006, art. 18, §§ 5º-B a 5º-J; Res. CGSN 140/2018, Anexo VI).
  static const activities = [
    // Service code of the invoice (LC 116), for who goes by it.
    Activity(
      '17.03.03',
      'Planejamento, coordenação, programação ou organização administrativa',
      ActivityKind.annexIII,
      'Organização administrativa',
    ),
    Activity(
      '8219-9/99',
      'Preparação de documentos e apoio administrativo',
      ActivityKind.annexIII,
      'Apoio administrativo',
    ),
    Activity(
      '8211-3/00',
      'Serviços combinados de escritório e apoio administrativo',
      ActivityKind.annexIII,
      'Escritório',
    ),
    Activity(
      '6201-5/01',
      'Desenvolvimento de programas sob encomenda',
      ActivityKind.fatorR,
      'Desenvolvimento',
    ),
    Activity(
      '6202-3/00',
      'Desenvolvimento e licenciamento de programas customizáveis',
      ActivityKind.fatorR,
      'Software customizável',
    ),
    Activity(
      '6203-1/00',
      'Desenvolvimento e licenciamento de programas não customizáveis',
      ActivityKind.fatorR,
      'Licença de software',
    ),
    Activity(
      '6204-0/00',
      'Consultoria em TI',
      ActivityKind.fatorR,
      'Consultoria em TI',
    ),
    Activity(
      '6209-1/00',
      'Suporte técnico e manutenção em TI',
      ActivityKind.fatorR,
      'Suporte de TI',
    ),
  ];

  static Activity? activity(String code) {
    for (final a in activities) {
      if (a.code == code.trim()) return a;
    }
    return null;
  }

  /// Simples Nacional, by RBT12 (LC 123/2006, Anexos III e V).
  static const annexIII = [
    Band(180000, 0.06, 0),
    Band(360000, 0.112, 9360),
    Band(720000, 0.135, 17640),
    Band(1800000, 0.16, 35640),
    Band(3600000, 0.21, 125640),
    Band(4800000, 0.33, 648000),
  ];
  static const annexV = [
    Band(180000, 0.155, 0),
    Band(360000, 0.18, 4500),
    Band(720000, 0.195, 9900),
    Band(1800000, 0.205, 17100),
    Band(3600000, 0.23, 62100),
    Band(4800000, 0.305, 540000),
  ];

  /// Effective rate of [annex] for [rbt12]: (RBT12 × nominal − dedução) ÷
  /// RBT12; the first band's nominal rate when there is no revenue yet.
  static double effectiveRate(Annex annex, double rbt12) {
    final bands = annex == Annex.iii ? annexIII : annexV;
    if (rbt12 <= 0) return bands.first.rate;
    final b = bandFor(bands, rbt12);
    return (rbt12 * b.rate - b.deduction) / rbt12;
  }

  /// Fator R from which a [ActivityKind.fatorR] activity is in Anexo III.
  static const fatorRThreshold = 0.28;

  /// MEI revenue limit per year; the opening year's is this ÷ 12 per month
  /// open. Up to 20% over, only the excess is taxed; beyond, the MEI is
  /// excluded back to January.
  static const meiYearLimit = 81000.0;
  static const meiTolerance = 0.2;

  /// Rate of the pró-labore INSS (contribuinte individual, retained).
  static const inssRate = 0.11;

  /// Share of the revenue a service company may distribute tax-free
  /// without full bookkeeping (lucro presumido of services).
  static const presumedProfit = 0.32;

  static YearTables forYear(int year) {
    YearTables? best;
    for (final t in _years) {
      if (t.year <= year && (best == null || t.year > best.year)) best = t;
    }
    return best ?? _years.first;
  }

  static final _years = [
    YearTables(
      year: 2025,
      minimumWage: 1518,
      inssCeiling: 8157.41,
      dasMei: 80.90,
      monthlyIrrf: _irrf2025,
      monthlyReducer: null,
      yearIrrf: _yearIrrf2026,
      yearReducer: null,
      simplifiedDiscount: 607.20,
      yearSimplifiedLimit: 16754.34,
    ),
    YearTables(
      year: 2026,
      minimumWage: 1621,
      inssCeiling: 8475.55,
      dasMei: 86.05,
      monthlyIrrf: _irrf2025,
      monthlyReducer: const Reducer(5000, 7350, 978.62, 0.133145),
      yearIrrf: _yearIrrf2026,
      yearReducer: const Reducer(60000, 88200, 8429.73, 0.095575),
      simplifiedDiscount: 607.20,
      yearSimplifiedLimit: 16754.34,
    ),
  ];

  /// Monthly IRRF since May 2025 (still in 2026).
  static const _irrf2025 = [
    Band(2428.80, 0, 0),
    Band(2826.65, 0.075, 182.16),
    Band(3751.05, 0.15, 394.16),
    Band(4664.68, 0.225, 675.49),
    Band(null, 0.275, 908.73),
  ];

  /// Yearly table: the monthly one × 12 (not checked against the official
  /// yearly table).
  static const _yearIrrf2026 = [
    Band(29145.60, 0, 0),
    Band(33919.80, 0.075, 2185.92),
    Band(45012.60, 0.15, 4729.92),
    Band(55976.16, 0.225, 8105.88),
    Band(null, 0.275, 10904.76),
  ];
}

/// Reduction of the income tax (Lei 15.270/2025): income up to [free] pays
/// nothing; up to [partial], the tax is reduced by [fixed] − [factor] ×
/// income.
class Reducer {
  final double free;
  final double partial;
  final double fixed;
  final double factor;

  const Reducer(this.free, this.partial, this.fixed, this.factor);

  /// The reduction for [income], limited to [tax].
  double of(double income, double tax) {
    if (income <= free) return tax;
    if (income > partial) return 0;
    final r = fixed - factor * income;
    return r.clamp(0, tax).toDouble();
  }
}

class YearTables {
  final int year;
  final double minimumWage;
  final double inssCeiling;

  /// DAS of a service MEI: 5% of the minimum wage + R$ 5 of ISS.
  final double dasMei;
  final List<Band> monthlyIrrf;
  final Reducer? monthlyReducer;
  final List<Band> yearIrrf;
  final Reducer? yearReducer;

  /// Monthly simplified discount (instead of the INSS, when larger).
  final double simplifiedDiscount;

  /// Yearly simplified discount: 20% of the taxable income, up to this.
  final double yearSimplifiedLimit;

  const YearTables({
    required this.year,
    required this.minimumWage,
    required this.inssCeiling,
    required this.dasMei,
    required this.monthlyIrrf,
    required this.monthlyReducer,
    required this.yearIrrf,
    required this.yearReducer,
    required this.simplifiedDiscount,
    required this.yearSimplifiedLimit,
  });

  double inss(double proLabore) =>
      FiscalTables.inssRate *
      (proLabore < inssCeiling ? proLabore : inssCeiling);

  /// IRRF withheld on [proLabore] (no dependants).
  double irrf(double proLabore) {
    if (proLabore <= 0) return 0;
    final inssPaid = inss(proLabore);
    final discount =
        inssPaid > simplifiedDiscount ? inssPaid : simplifiedDiscount;
    final base = proLabore - discount;
    if (base <= 0) return 0;
    final b = bandFor(monthlyIrrf, base);
    final tax = base * b.rate - b.deduction;
    if (tax <= 0) return 0;
    final reduction = monthlyReducer?.of(proLabore, tax) ?? 0;
    return _round2(tax - reduction);
  }
}

double _round2(double v) => (v * 100).roundToDouble() / 100;
