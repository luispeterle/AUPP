import 'fiscal-tables.dart';

enum RegimeKind { mei, simples }

/// A period of the company in one regime. [end] null = still in it.
class Regime {
  RegimeKind kind;
  DateTime start;
  DateTime? end;

  Regime(this.kind, this.start, [this.end]);

  YearMonth get startMonth => YearMonth.of(start);
  YearMonth? get endMonth => end == null ? null : YearMonth.of(end!);

  bool covers(YearMonth m) =>
      !m.isBefore(startMonth) && (endMonth == null || !m.isAfter(endMonth!));

  String get label => switch (kind) {
    RegimeKind.mei => 'MEI',
    RegimeKind.simples => 'Simples Nacional (ME/EPP)',
  };

  Map<String, dynamic> toJson() => {
    'tipo': kind.name,
    'inicio': _day(start),
    if (end != null) 'fim': _day(end!),
  };

  static Regime? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = RegimeKind.values.where((k) => k.name == json['tipo']);
    final start = DateTime.tryParse('${json['inicio']}');
    if (kind.isEmpty || start == null) return null;
    return Regime(kind.first, start, DateTime.tryParse('${json['fim']}'));
  }
}

/// A part of a revenue counted in [month] (a payment whose invoice is
/// split across months, e.g. an advance).
class RevenuePart {
  YearMonth month;
  double value;

  /// Activity of this part when one payment covers invoices of different
  /// activities.
  String? activity;

  RevenuePart(this.month, this.value, {this.activity});

  Map<String, dynamic> toJson() => {
    'mes': month.key,
    'valor': value,
    if (activity != null) 'atividade': activity,
  };

  static RevenuePart? fromJson(Object? json) {
    if (json is! Map) return null;
    final month = YearMonth.tryParse(json['mes']);
    final value = (json['valor'] as num?)?.toDouble();
    if (month == null || value == null) return null;
    return RevenuePart(month, value, activity: json['atividade'] as String?);
  }
}

/// What a payment that reached a company account was, as the user said.
enum PaymentStatus {
  /// Had an invoice: revenue (in [RevenueAdjustment.parts], else in the
  /// month it arrived).
  invoice('nota'),

  /// Came in without an invoice: not in the declared revenue.
  noInvoice('semNota'),

  /// Not revenue at all (aporte, yield, refund, a loan).
  notRevenue('naoReceita');

  final String key;
  const PaymentStatus(this.key);

  static PaymentStatus? of(Object? key) {
    for (final s in values) {
      if (s.key == key) return s;
    }
    return null;
  }
}

/// What the user said about a payment that reached a company account.
/// Without a [status] it is still to be checked (and counts as an invoice
/// of its month meanwhile).
class RevenueAdjustment {
  PaymentStatus? status;

  /// Activity other than the main one.
  String? activity;

  /// The months it counts in, instead of all in the month it arrived (an
  /// invoice of another month, or only part of it invoiced).
  List<RevenuePart>? parts;

  RevenueAdjustment({this.status, this.activity, this.parts});

  bool get isEmpty => status == null && activity == null && parts == null;
  bool get counts =>
      status != PaymentStatus.noInvoice && status != PaymentStatus.notRevenue;

  Map<String, dynamic> toJson() => {
    if (status != null) 'status': status!.key,
    if (activity != null) 'atividade': activity,
    if (parts != null) 'partes': [for (final p in parts!) p.toJson()],
  };

  static RevenueAdjustment? fromJson(Object? json) {
    if (json is! Map) return null;
    final parts = json['partes'];
    return RevenueAdjustment(
      status: PaymentStatus.of(json['status']),
      activity: json['atividade'] as String?,
      parts: parts is List ? [for (final p in parts) ?RevenuePart.fromJson(p)] : null,
    );
  }
}

/// An invoice that did not go through a company account.
class ManualRevenue {
  String id;
  YearMonth month;
  double value;
  String? activity;
  String? description;

  ManualRevenue(
    this.id,
    this.month,
    this.value, {
    this.activity,
    this.description,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'mes': month.key,
    'valor': value,
    if (activity != null) 'atividade': activity,
    if (description != null) 'descricao': description,
  };

  static ManualRevenue? fromJson(Object? json) {
    if (json is! Map) return null;
    final month = YearMonth.tryParse(json['mes']);
    final value = (json['valor'] as num?)?.toDouble();
    if (month == null || value == null) return null;
    return ManualRevenue(
      '${json['id'] ?? month.key}',
      month,
      value,
      activity: json['atividade'] as String?,
      description: json['descricao'] as String?,
    );
  }
}

/// A monthly amount (pró-labore, accountant's fee) from [since] on, until
/// the next change.
class MonthlyValue {
  YearMonth since;
  double value;

  MonthlyValue(this.since, this.value);

  Map<String, dynamic> toJson() => {'desde': since.key, 'valor': value};

  static MonthlyValue? fromJson(Object? json) {
    if (json is! Map) return null;
    final since = YearMonth.tryParse(json['desde']);
    final value = (json['valor'] as num?)?.toDouble();
    if (since == null || value == null) return null;
    return MonthlyValue(since, value);
  }
}

/// A one-off payment of the company in [month]: a fine, the accountant's
/// fee for a change of regime…
class OtherPayment {
  String id;
  YearMonth month;

  /// Day of the month it is paid (or due).
  int day;
  double value;
  String description;

  /// The estimate of it in the Extrato (paid by Pix), created by the
  /// company module.
  String? patternId;

  OtherPayment(
    this.id,
    this.month,
    this.value,
    this.description, {
    this.day = 1,
    this.patternId,
  });

  DateTime get date => DateTime(month.year, month.month, day);

  Map<String, dynamic> toJson() => {
    'id': id,
    'mes': month.key,
    'dia': day,
    'valor': value,
    'descricao': description,
    if (patternId != null) 'estimativa': patternId,
  };

  static OtherPayment? fromJson(Object? json) {
    if (json is! Map) return null;
    final month = YearMonth.tryParse(json['mes']);
    final value = (json['valor'] as num?)?.toDouble();
    if (month == null || value == null) return null;
    return OtherPayment(
      '${json['id'] ?? month.key}',
      month,
      value,
      '${json['descricao'] ?? 'Outro pagamento'}',
      day: (json['dia'] as num?)?.toInt() ?? 1,
      patternId: json['estimativa'] as String?,
    );
  }
}

/// An activity from [since] on, until the next change.
class ActivityFrom {
  YearMonth since;
  String code;

  ActivityFrom(this.since, this.code);

  Map<String, dynamic> toJson() => {'desde': since.key, 'codigo': code};

  static ActivityFrom? fromJson(Object? json) {
    if (json is! Map) return null;
    final since = YearMonth.tryParse(json['desde']);
    final code = json['codigo'];
    if (since == null || code is! String) return null;
    return ActivityFrom(since, code);
  }
}

/// Everything the company module knows about one company beyond its
/// accounts: regimes, activities, pró-labore, revenue corrections and the
/// estimates it drives. Kept inside the company (MoneyAccounts).
class FiscalData {
  List<Regime> regimes;

  /// CNAE codes; the first is the main activity: an invoice is in it unless
  /// the user says otherwise.
  List<String> activities;

  /// Activities outside [FiscalTables.activities].
  List<Activity> customActivities;
  List<MonthlyValue> proLabore;
  List<ManualRevenue> manualRevenues;

  /// By the payment's key ([revenueKey]).
  Map<String, RevenueAdjustment> adjustments;

  /// Income estimates that forecast the company's revenue, and the
  /// activity of each from a month on (else the main one).
  List<String> forecastPatterns;
  Map<String, List<ActivityFrom>> forecastActivities;

  /// The accountant's monthly fee, and the day it is paid.
  List<MonthlyValue> accountantFee;

  /// One-off payments (fines, the accountant's fee for a change of regime).
  List<OtherPayment> otherPayments;
  int accountantDay;

  /// The module creates and keeps the estimates of the DAS, the DCTFWeb
  /// (INSS + IRRF of the pró-labore) and the accountant, with each month's
  /// amount.
  bool autoEstimates;

  /// Estimates whose amount the module computes.
  String? dasPattern;
  String? dctfwebPattern;
  String? feePattern;

  /// The accountant keeps full books: all the profit is tax-free.
  bool fullBookkeeping;

  /// Other company expenses of each year (beyond taxes and pró-labore), for
  /// the profit of the yearly income tax.
  Map<int, double> otherExpenses;

  FiscalData({
    List<Regime>? regimes,
    List<String>? activities,
    List<Activity>? customActivities,
    List<MonthlyValue>? proLabore,
    List<ManualRevenue>? manualRevenues,
    Map<String, RevenueAdjustment>? adjustments,
    List<String>? forecastPatterns,
    Map<String, List<ActivityFrom>>? forecastActivities,
    List<MonthlyValue>? accountantFee,
    List<OtherPayment>? otherPayments,
    this.accountantDay = 8,
    this.autoEstimates = false,
    this.dasPattern,
    this.dctfwebPattern,
    this.feePattern,
    this.fullBookkeeping = false,
    Map<int, double>? otherExpenses,
  }) : regimes = regimes ?? [],
       activities = activities ?? [],
       customActivities = customActivities ?? [],
       proLabore = proLabore ?? [],
       manualRevenues = manualRevenues ?? [],
       adjustments = adjustments ?? {},
       forecastPatterns = forecastPatterns ?? [],
       forecastActivities = forecastActivities ?? {},
       accountantFee = accountantFee ?? [],
       otherPayments = otherPayments ?? [],
       otherExpenses = otherExpenses ?? {};

  bool get isSetUp => regimes.isNotEmpty;

  /// The key of a payment for [adjustments]: its Dinzo id, the same on
  /// every device; else the record id.
  static String revenueKey({String? dinzoId, int? recordId}) =>
      dinzoId ?? 'r:$recordId';

  Activity? activityOf(String code) {
    for (final a in customActivities) {
      if (a.code == code) return a;
    }
    return FiscalTables.activity(code);
  }

  String? get mainActivity => activities.isEmpty ? null : activities.first;

  /// Every activity the invoices are in.
  Set<String> get allActivities => {
    ...activities,
    for (final a in adjustments.values) ...[
      ?a.activity,
      for (final p in a.parts ?? const <RevenuePart>[]) ?p.activity,
    ],
    for (final m in manualRevenues) ?m.activity,
    for (final list in forecastActivities.values)
      for (final a in list) a.code,
  };

  /// The activity of what the estimate [patternId] forecasts in [m]: the
  /// last change on or before it, else the main one.
  String activityOfForecast(String patternId, YearMonth m) {
    ActivityFrom? best;
    for (final a in forecastActivities[patternId] ?? const <ActivityFrom>[]) {
      if (a.since.isAfter(m)) continue;
      if (best == null || a.since.isAfter(best.since)) best = a;
    }
    return best?.code ?? mainActivity ?? '';
  }

  /// From [m] on, the estimate [patternId] forecasts invoices of [code] (the
  /// months before keep theirs).
  void setForecastActivity(String patternId, YearMonth m, String code) {
    final list = forecastActivities.putIfAbsent(patternId, () => []);
    list.removeWhere((a) => a.since == m);
    if (activityOfForecast(patternId, m) != code) {
      list.add(ActivityFrom(m, code));
    }
    if (list.isEmpty) forecastActivities.remove(patternId);
  }

  YearMonth? get firstMonth {
    YearMonth? first;
    for (final r in regimes) {
      if (first == null || r.startMonth.isBefore(first)) first = r.startMonth;
    }
    return first;
  }

  Regime? regimeAt(YearMonth m) {
    for (final r in regimes) {
      if (r.covers(m)) return r;
    }
    return null;
  }

  /// The value of [series] in [m]: the last change on or before it.
  static double valueAt(List<MonthlyValue> series, YearMonth m) {
    MonthlyValue? best;
    for (final c in series) {
      if (c.since.isAfter(m)) continue;
      if (best == null || c.since.isAfter(best.since)) best = c;
    }
    return best?.value ?? 0;
  }

  double proLaboreAt(YearMonth m) => valueAt(proLabore, m);
  double accountantFeeAt(YearMonth m) => valueAt(accountantFee, m);

  double otherPaymentsAt(YearMonth m) => otherPayments
      .where((p) => p.month == m)
      .fold(0, (t, p) => t + p.value);

  Map<String, dynamic> toJson() => {
    'regimes': [for (final r in regimes) r.toJson()],
    'atividades': activities,
    if (customActivities.isNotEmpty)
      'atividadesProprias': [
        for (final a in customActivities)
          {'codigo': a.code, 'nome': a.name, 'tipo': a.kind.name},
      ],
    'proLabore': [for (final c in proLabore) c.toJson()],
    'avulsas': [for (final m in manualRevenues) m.toJson()],
    'ajustes': {
      for (final e in adjustments.entries)
        if (!e.value.isEmpty) e.key: e.value.toJson(),
    },
    'receitaPrevista': forecastPatterns,
    if (forecastActivities.isNotEmpty)
      'atividadePrevista': {
        for (final e in forecastActivities.entries)
          e.key: [for (final a in e.value) a.toJson()],
      },
    if (accountantFee.isNotEmpty)
      'contador': [for (final c in accountantFee) c.toJson()],
    if (otherPayments.isNotEmpty)
      'outrosPagamentos': [for (final p in otherPayments) p.toJson()],
    if (accountantDay != 8) 'diaContador': accountantDay,
    if (autoEstimates) 'estimativasAutomaticas': true,
    if (dasPattern != null) 'estimativaDas': dasPattern,
    if (dctfwebPattern != null) 'estimativaDctfweb': dctfwebPattern,
    if (feePattern != null) 'estimativaContador': feePattern,
    if (fullBookkeeping) 'escrituracao': true,
    if (otherExpenses.isNotEmpty)
      'outrasDespesas': {
        for (final e in otherExpenses.entries) '${e.key}': e.value,
      },
  };

  static List<String> _strings(Object? list) => [
    if (list is List)
      for (final s in list)
        if (s is String && s.trim().isNotEmpty) s,
  ];

  static FiscalData fromJson(Object? json) {
    if (json is! Map) return FiscalData();
    final adjustments = <String, RevenueAdjustment>{};
    final rawAdjustments = json['ajustes'];
    if (rawAdjustments is Map) {
      rawAdjustments.forEach((k, v) {
        final a = RevenueAdjustment.fromJson(v);
        if (a != null) adjustments['$k'] = a;
      });
    }
    final expenses = <int, double>{};
    final rawExpenses = json['outrasDespesas'];
    if (rawExpenses is Map) {
      rawExpenses.forEach((k, v) {
        final year = int.tryParse('$k');
        if (year != null && v is num) expenses[year] = v.toDouble();
      });
    }
    List<T> list<T>(Object? raw, T? Function(Object?) read) => [
      if (raw is List)
        for (final item in raw) ?read(item),
    ];
    return FiscalData(
      regimes: list(json['regimes'], Regime.fromJson),
      activities: _strings(json['atividades']),
      customActivities: list(json['atividadesProprias'], (raw) {
        if (raw is! Map) return null;
        final code = raw['codigo'];
        final kind = ActivityKind.values.where((k) => k.name == raw['tipo']);
        if (code is! String || kind.isEmpty) return null;
        return Activity(code, '${raw['nome'] ?? code}', kind.first);
      }),
      proLabore: list(json['proLabore'], MonthlyValue.fromJson),
      manualRevenues: list(json['avulsas'], ManualRevenue.fromJson),
      adjustments: adjustments,
      forecastPatterns: _strings(json['receitaPrevista']),
      forecastActivities: {
        if (json['atividadePrevista'] case final Map m)
          for (final e in m.entries)
            '${e.key}': e.value is String
                // Before: one activity for every month.
                ? [ActivityFrom(const YearMonth(2000, 1), e.value as String)]
                : list(e.value, ActivityFrom.fromJson),
      },
      accountantFee: list(json['contador'], MonthlyValue.fromJson),
      otherPayments: list(json['outrosPagamentos'], OtherPayment.fromJson),
      accountantDay: (json['diaContador'] as num?)?.toInt() ?? 8,
      autoEstimates: json['estimativasAutomaticas'] == true,
      dasPattern: json['estimativaDas'] as String?,
      dctfwebPattern: json['estimativaDctfweb'] as String?,
      feePattern: json['estimativaContador'] as String?,
      fullBookkeeping: json['escrituracao'] == true,
      otherExpenses: expenses,
    );
  }
}

String _day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
