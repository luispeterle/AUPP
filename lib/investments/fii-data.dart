import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// What a real estate fund holds, by the share of its assets.
enum FiiKind {
  brick('Tijolo'),
  paper('Papel'),
  funds('Fundo de fundos'),
  hybrid('Híbrido');

  const FiiKind(this.label);
  final String label;
}

/// A month of the fund's monthly report (informe mensal) to the CVM.
class FiiMonth {
  final DateTime date;
  final double? equity;
  final double? shares;
  final double? bookPerShare;

  /// The month's dividend yield on the book value times the book value: what
  /// was paid per share.
  final double? dividendPerShare;
  final int? holders;

  /// The administration fee of the month, a fraction of the equity.
  final double? adminFee;

  const FiiMonth({
    required this.date,
    this.equity,
    this.shares,
    this.bookPerShare,
    this.dividendPerShare,
    this.holders,
    this.adminFee,
  });

  List<Object?> toJson() => [
    _month(date),
    equity,
    shares,
    bookPerShare,
    dividendPerShare,
    holders,
    adminFee,
  ];

  static FiiMonth fromJson(List json) => FiiMonth(
    date: DateTime.parse('${json[0]}-01'),
    equity: (json[1] as num?)?.toDouble(),
    shares: (json[2] as num?)?.toDouble(),
    bookPerShare: (json[3] as num?)?.toDouble(),
    dividendPerShare: (json[4] as num?)?.toDouble(),
    holders: (json[5] as num?)?.toInt(),
    adminFee: (json[6] as num?)?.toDouble(),
  );
}

/// Where the assets are, as fractions of the total: real estate (with the
/// companies that hold it), credit (CRI, LCI), shares of other funds, cash and
/// the rest.
class FiiMix {
  final double realEstate;
  final double credit;
  final double funds;
  final double cash;
  final double other;

  const FiiMix({
    this.realEstate = 0,
    this.credit = 0,
    this.funds = 0,
    this.cash = 0,
    this.other = 0,
  });

  FiiKind get kind => realEstate >= 0.6
      ? FiiKind.brick
      : credit >= 0.6
      ? FiiKind.paper
      : funds >= 0.6
      ? FiiKind.funds
      : FiiKind.hybrid;

  List<(String, double)> get parts => [
    ('Imóveis', realEstate),
    ('Crédito imobiliário (CRI, LCI)', credit),
    ('Cotas de outros FIIs', funds),
    ('Caixa', cash),
    ('Outros', other),
  ];

  List<double> toJson() => [realEstate, credit, funds, cash, other];

  static FiiMix fromJson(List json) => FiiMix(
    realEstate: (json[0] as num).toDouble(),
    credit: (json[1] as num).toDouble(),
    funds: (json[2] as num).toDouble(),
    cash: (json[3] as num).toDouble(),
    other: (json[4] as num).toDouble(),
  );
}

/// A property in the quarterly report, its shares as fractions.
class FiiProperty {
  final String name;
  final String? kind;
  final double? area;
  final double? vacancy;
  final double? defaulting;

  /// Of the fund's revenue.
  final double? revenue;

  const FiiProperty({
    required this.name,
    this.kind,
    this.area,
    this.vacancy,
    this.defaulting,
    this.revenue,
  });

  /// Built and rented: the others have no vacancy to speak of.
  bool get rented => kind == null || kind!.contains('renda acabado');

  List<Object?> toJson() => [name, kind, area, vacancy, defaulting, revenue];

  static FiiProperty fromJson(List json) => FiiProperty(
    name: json[0] as String,
    kind: json[1] as String?,
    area: (json[2] as num?)?.toDouble(),
    vacancy: (json[3] as num?)?.toDouble(),
    defaulting: (json[4] as num?)?.toDouble(),
    revenue: (json[5] as num?)?.toDouble(),
  );
}

/// A fund with its reports: the register and the months from the monthly one,
/// the properties, tenants and leases from the last quarterly one.
class FiiFund {
  final String cnpj;
  final String name;
  final String? isin;

  /// The CVM's segment ("Logística", "Shoppings"; many say "Multicategoria").
  final String? segment;
  final String? administrator;
  final String? management;
  final DateTime? since;

  /// Oldest first.
  final List<FiiMonth> months;
  final FiiMix? mix;
  final DateTime? quarter;
  final List<FiiProperty> properties;

  /// The tenants' sectors, by their share of the fund's revenue.
  final Map<String, double> tenants;

  /// When the leases end, by their share of the revenue ("Até 1 ano").
  final List<(String, double)> leases;

  /// The leases' inflation indexes, by their share of the revenue.
  final Map<String, double> indexes;

  const FiiFund({
    required this.cnpj,
    required this.name,
    this.isin,
    this.segment,
    this.administrator,
    this.management,
    this.since,
    this.months = const [],
    this.mix,
    this.quarter,
    this.properties = const [],
    this.tenants = const {},
    this.leases = const [],
    this.indexes = const {},
  });

  FiiMonth? get last => months.lastOrNull;
  double? get bookPerShare => last?.bookPerShare;
  FiiKind? get kind => mix?.kind;

  /// The segment when it says something: "Multicategoria" and "Outros" don't.
  String? get plainSegment =>
      segment == null || const {'Multicategoria', 'Outros'}.contains(segment)
      ? null
      : segment;

  /// The months of the last year of reports, up to the last one.
  List<FiiMonth> get lastYear {
    final end = last?.date;
    if (end == null) return const [];
    final start = DateTime(end.year - 1, end.month + 1);
    return [
      for (final m in months)
        if (!m.date.isBefore(start)) m,
    ];
  }

  /// Paid per share in the last twelve months. A month or two left blank in
  /// the reports counts as the average of the others; null with fewer than
  /// ten.
  double? get dividends12m {
    final known = [for (final m in lastYear) ?m.dividendPerShare];
    if (known.length < 10) return null;
    return known.fold<double>(0, (sum, v) => sum + v) / known.length * 12;
  }

  /// The newest month that says what was paid.
  FiiMonth? get lastPaid {
    for (final m in months.reversed) {
      if (m.dividendPerShare != null) return m;
    }
    return null;
  }

  double? get lastDividend => lastPaid?.dividendPerShare;

  /// Months with a payment among the last [count] that say what was paid.
  (int paid, int of) paidMonths(int count) {
    final known = [
      for (final m in months.reversed.take(count)) ?m.dividendPerShare,
    ];
    return (known.where((v) => v > 0).length, known.length);
  }

  /// How much the payment moves: the standard deviation over the mean of the
  /// last [count] months. Low is steady.
  double? dividendSwing(int count) {
    final recent = [
      for (final m in months.reversed.take(count)) ?m.dividendPerShare,
    ];
    if (recent.length < 6) return null;
    final mean = recent.reduce((a, b) => a + b) / recent.length;
    if (mean <= 0) return null;
    final variance =
        recent.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
        recent.length;
    return math.sqrt(variance) / mean;
  }

  /// The administration fee of the last twelve months, on the equity.
  double? get adminFee12m {
    final year = lastYear;
    if (year.length < 12 || year.any((m) => m.adminFee == null)) return null;
    return year.fold<double>(0, (sum, m) => sum + m.adminFee!);
  }

  /// By area, among the properties built and rented.
  double? get vacancy {
    var area = 0.0;
    var empty = 0.0;
    for (final property in properties) {
      final a = property.area;
      final v = property.vacancy;
      if (!property.rented || a == null || a <= 0 || v == null) continue;
      area += a;
      empty += a * v;
    }
    return area == 0 ? null : empty / area;
  }

  int get rentedCount => properties.where((p) => p.rented).length;

  double? pvp(double price) {
    final book = bookPerShare;
    return book == null || book <= 0 ? null : price / book;
  }

  double? dividendYield(double price) {
    final paid = dividends12m;
    return paid == null || price <= 0 ? null : paid / price;
  }

  double? marketCap(double price) {
    final shares = last?.shares;
    return shares == null ? null : shares * price;
  }

  Map<String, dynamic> toJson() => {
    'cnpj': cnpj,
    'name': name,
    'isin': ?isin,
    'segment': ?segment,
    'administrator': ?administrator,
    'management': ?management,
    'since': ?since?.toIso8601String().substring(0, 10),
    'months': [for (final m in months) m.toJson()],
    'mix': ?mix?.toJson(),
    'quarter': ?quarter?.toIso8601String().substring(0, 10),
    'properties': [for (final p in properties) p.toJson()],
    'tenants': tenants,
    'leases': [
      for (final (label, share) in leases) [label, share],
    ],
    'indexes': indexes,
  };

  static FiiFund fromJson(Map<String, dynamic> json) => FiiFund(
    cnpj: json['cnpj'] as String,
    name: json['name'] as String,
    isin: json['isin'] as String?,
    segment: json['segment'] as String?,
    administrator: json['administrator'] as String?,
    management: json['management'] as String?,
    since: DateTime.tryParse(json['since'] as String? ?? ''),
    months: [
      for (final m in json['months'] as List? ?? const [])
        FiiMonth.fromJson(m as List),
    ],
    mix: json['mix'] == null ? null : FiiMix.fromJson(json['mix'] as List),
    quarter: DateTime.tryParse(json['quarter'] as String? ?? ''),
    properties: [
      for (final p in json['properties'] as List? ?? const [])
        FiiProperty.fromJson(p as List),
    ],
    tenants: {
      for (final e in (json['tenants'] as Map? ?? const {}).entries)
        e.key as String: (e.value as num).toDouble(),
    },
    leases: [
      for (final l in json['leases'] as List? ?? const [])
        ((l as List)[0] as String, (l[1] as num).toDouble()),
    ],
    indexes: {
      for (final e in (json['indexes'] as Map? ?? const {}).entries)
        e.key as String: (e.value as num).toDouble(),
    },
  );
}

String _month(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}';

/// "KINEA RENDA IMOBILIÁRIA FUNDO DE INVESTIMENTO IMOBILIÁRIO RESPONSABILIDADE
/// LIMITADA" → "KINEA RENDA IMOBILIARIA", so that brapi's names meet the CVM's.
String? plainFundName(String? name) {
  if (name == null) return null;
  const accents = {
    'Á': 'A',
    'À': 'A',
    'Â': 'A',
    'Ã': 'A',
    'É': 'E',
    'Ê': 'E',
    'Í': 'I',
    'Ó': 'O',
    'Ô': 'O',
    'Õ': 'O',
    'Ú': 'U',
    'Ç': 'C',
  };
  var plain = name.toUpperCase();
  accents.forEach((from, to) => plain = plain.replaceAll(from, to));
  plain = plain.replaceAll(RegExp(r'[^A-Z0-9 ]'), ' ');
  plain = plain.replaceAll(RegExp(r'\s+'), ' ');
  for (final words in [
    r'FUNDO DE INVESTIMENTO IMOBILIARIO',
    r'FUNDO DE INVEST\w* IMOB\w*',
    r'FI IMOBILIARIO',
    r'RESPONSABILIDADE LIMITADA',
    r'RESP LIMITADA',
    r'\bFII\b',
    r'\bRL\b',
  ]) {
    plain = plain.replaceAll(RegExp(words), ' ');
  }
  plain = plain.replaceAll(RegExp(r'\s+'), ' ').trim();
  return plain.isEmpty ? null : plain;
}

/// Reads the CSVs of the monthly and quarterly reports. Each report can be
/// sent again: the highest version of a date wins.
class FiiParser {
  /// Three years: enough for the steadiness of the payments.
  static const keptMonths = 36;

  final _register = <String, (String, Map<String, String>)>{};
  final _months = <String, Map<String, (int, FiiMonth)>>{};
  final _mix = <String, (String, FiiMix)>{};
  final _properties = <String, (String, List<FiiProperty>)>{};
  final _leases =
      <String, (String, List<(String, double)>, Map<String, double>)>{};

  /// Each row of [csv] as a lookup by column name.
  static void _rows(
    String csv,
    void Function(String? Function(String) cell) f,
  ) {
    final lines = const LineSplitter().convert(csv);
    if (lines.isEmpty) return;
    final names = lines.first.replaceFirst('﻿', '').split(';');
    final header = {for (final (i, name) in names.indexed) name.trim(): i};
    for (final line in lines.skip(1)) {
      if (line.length < 20) continue;
      final cells = line.split(';');
      f((column) {
        final i = header[column];
        if (i == null || i >= cells.length) return null;
        final value = cells[i].trim();
        return value.isEmpty ? null : value;
      });
    }
  }

  static double? _number(String? text) =>
      text == null ? null : double.tryParse(text.replaceAll(',', '.'));

  /// A share: some funds write 0.67 for 0.67%.
  static double? _share(String? text, {double max = 1}) {
    final value = _number(text);
    if (value == null || value < 0) return null;
    return value > max ? value / 100 : value;
  }

  /// "2026-09-01" and version 2 → "2026-09-01#0002", which sorts.
  static String _key(String date, String? version) =>
      '$date#${(version ?? '0').padLeft(4, '0')}';

  /// The register part of the monthly report (geral): the newest row of each
  /// fund wins.
  void addRegister(String csv) => _rows(csv, (cell) {
    final cnpj = cell('CNPJ_Fundo_Classe');
    final date = cell('Data_Referencia');
    if (cnpj == null || date == null) return;
    final key = _key(date, cell('Versao'));
    final known = _register[cnpj];
    if (known != null && known.$1.compareTo(key) >= 0) return;
    _register[cnpj] = (
      key,
      {
        'name': ?cell('Nome_Fundo_Classe'),
        'isin': ?cell('Codigo_ISIN'),
        'segment': ?cell('Segmento_Atuacao'),
        'administrator': ?cell('Nome_Administrador'),
        'management': ?cell('Tipo_Gestao'),
        'since': ?cell('Data_Funcionamento'),
      },
    );
  });

  /// The numbers of each month (complemento).
  void addMonths(String csv) => _rows(csv, (cell) {
    final cnpj = cell('CNPJ_Fundo_Classe');
    final date = DateTime.tryParse(cell('Data_Referencia') ?? '');
    if (cnpj == null || date == null) return;
    final version = int.tryParse(cell('Versao') ?? '') ?? 0;
    final months = _months.putIfAbsent(cnpj, () => {});
    final month = _month(date);
    final known = months[month];
    if (known != null && known.$1 > version) return;
    final book = _number(cell('Valor_Patrimonial_Cotas'));
    // A month's dividend yield above 15% is a percentage written as such.
    final yieldOnBook = _share(
      cell('Percentual_Dividend_Yield_Mes'),
      max: 0.15,
    );
    months[month] = (
      version,
      FiiMonth(
        date: DateTime(date.year, date.month),
        equity: _number(cell('Patrimonio_Liquido')),
        shares: _number(cell('Cotas_Emitidas')),
        bookPerShare: book,
        dividendPerShare: book == null || yieldOnBook == null
            ? null
            : book * yieldOnBook,
        holders: _number(cell('Total_Numero_Cotistas'))?.round(),
        adminFee: _share(
          cell('Percentual_Despesas_Taxa_Administracao'),
          max: 0.05,
        ),
      ),
    );
  });

  /// The assets of the newest month (ativo_passivo).
  void addAssets(String csv) => _rows(csv, (cell) {
    final cnpj = cell('CNPJ_Fundo_Classe');
    final date = cell('Data_Referencia');
    if (cnpj == null || date == null) return;
    final key = _key(date, cell('Versao'));
    final known = _mix[cnpj];
    if (known != null && known.$1.compareTo(key) >= 0) return;
    double sum(List<String> columns) =>
        columns.fold(0, (total, c) => total + (_number(cell(c)) ?? 0));
    final cash = sum(['Total_Necessidades_Liquidez']);
    final invested = sum(['Total_Investido']);
    final total = cash + invested;
    if (total <= 0) return;
    final realEstate = sum([
      'Direitos_Bens_Imoveis',
      'Acoes_Sociedades_Atividades_FII',
      'Cotas_Sociedades_Atividades_FII',
    ]);
    final credit = sum([
      'CRI',
      'CRI_CRA',
      'LCI',
      'LCI_LCA',
      'LIG',
      'Letras_Hipotecarias',
      'Debentures',
      'Cedulas_Debentures',
      'Notas_Promissorias',
    ]);
    final funds = sum(['FII']);
    final other = math.max(0.0, invested - realEstate - credit - funds);
    _mix[cnpj] = (
      key,
      FiiMix(
        realEstate: realEstate / total,
        credit: credit / total,
        funds: funds / total,
        cash: cash / total,
        other: other / total,
      ),
    );
  });

  /// Rows of the newest quarter of each fund, in [into].
  static void _newest<T>(
    Map<String, (String, List<T>)> into,
    String cnpj,
    String key,
    T item,
  ) {
    final known = into[cnpj];
    if (known == null || known.$1.compareTo(key) < 0) {
      into[cnpj] = (key, [item]);
    } else if (known.$1 == key) {
      known.$2.add(item);
    }
  }

  /// The properties of the quarterly report (imovel).
  void addProperties(String csv) => _rows(csv, (cell) {
    final cnpj = cell('CNPJ_Fundo_Classe');
    final date = cell('Data_Referencia');
    final name = cell('Nome_Imovel');
    if (cnpj == null || date == null || name == null) return;
    _newest(
      _properties,
      cnpj,
      _key(date, cell('Versao')),
      FiiProperty(
        name: name,
        kind: cell('Classe'),
        area: _number(cell('Area')),
        vacancy: _share(cell('Percentual_Vacancia')),
        defaulting: _share(cell('Percentual_Inadimplencia')),
        revenue: _share(cell('Percentual_Receitas_FII')),
      ),
    );
  });

  final _tenantRows = <String, (String, List<(String, double)>)>{};

  /// The tenants' sectors of the quarterly report (inquilino).
  void addTenants(String csv) => _rows(csv, (cell) {
    final cnpj = cell('CNPJ_Fundo_Classe');
    final date = cell('Data_Referencia');
    final sector = cell('Setor_Atuacao');
    final share = _share(cell('Percentual_Receitas_FII'));
    if (cnpj == null || date == null || sector == null || share == null) {
      return;
    }
    _newest(_tenantRows, cnpj, _key(date, cell('Versao')), (sector, share));
  });

  static const _leaseBands = {
    'Até 1 ano': ['Ate_3Meses', '3a6Meses', '6a9Meses', '9a12Meses'],
    '1 a 2 anos': ['12a15Meses', '15a18Meses', '18a21Meses', '21a24Meses'],
    '2 a 3 anos': ['24a27Meses', '27a30Meses', '30a33Meses', '33a36Meses'],
    'Mais de 3 anos': ['Acima_36Meses'],
    'Sem prazo': ['Indeterminado'],
  };

  /// When the leases end and their indexes (complemento of the quarter).
  void addLeases(String csv) => _rows(csv, (cell) {
    final cnpj = cell('CNPJ_Fundo_Classe');
    final date = cell('Data_Referencia');
    if (cnpj == null || date == null) return;
    final key = _key(date, cell('Versao'));
    final known = _leases[cnpj];
    if (known != null && known.$1.compareTo(key) >= 0) return;
    final bands = <(String, double)>[];
    for (final e in _leaseBands.entries) {
      var share = 0.0;
      for (final band in e.value) {
        share +=
            _share(cell('Percentual_Vencimento_Receita_FII_Faixa_$band')) ?? 0;
      }
      if (share > 0) bands.add((e.key, share));
    }
    final indexes = <String, double>{
      for (final (label, column) in const [
        ('IPCA', 'IPCA'),
        ('IGP-M', 'IGPM'),
        ('INPC', 'INPC'),
        ('INCC', 'INCC'),
      ])
        if (_share(cell('Percentual_Indexador_Receita_FII_$column'))
            case final share? when share > 0)
          label: share,
    };
    _leases[cnpj] = (key, bands, indexes);
  });

  Map<String, FiiFund> build() {
    final out = <String, FiiFund>{};
    for (final MapEntry(key: cnpj, value: (_, info)) in _register.entries) {
      final months = [
        for (final (_, m) in _months[cnpj]?.values ?? const <(int, FiiMonth)>[])
          m,
      ]..sort((a, b) => a.date.compareTo(b.date));
      if (months.length > keptMonths) {
        months.removeRange(0, months.length - keptMonths);
      }
      final tenants = <String, double>{};
      for (final (sector, share)
          in _tenantRows[cnpj]?.$2 ?? const <(String, double)>[]) {
        if (share <= 0 || sector == '-') continue;
        tenants[sector] = (tenants[sector] ?? 0) + share;
      }
      final quarter = _properties[cnpj]?.$1 ?? _leases[cnpj]?.$1;
      out[cnpj] = FiiFund(
        cnpj: cnpj,
        name: info['name'] ?? cnpj,
        isin: info['isin'],
        segment: info['segment'],
        administrator: info['administrator'],
        management: info['management'],
        since: DateTime.tryParse(info['since'] ?? ''),
        months: months,
        mix: _mix[cnpj]?.$2,
        quarter: quarter == null
            ? null
            : DateTime.tryParse(quarter.split('#').first),
        properties: [...?_properties[cnpj]?.$2]
          ..sort((a, b) => (b.revenue ?? 0).compareTo(a.revenue ?? 0)),
        tenants: tenants,
        leases: _leases[cnpj]?.$2 ?? const [],
        indexes: _leases[cnpj]?.$3 ?? const {},
      );
    }
    return out;
  }
}

/// Reads the zips into the JSON of the funds. Runs in an isolate.
String buildFiiFunds(List<String> paths, {required int format}) {
  final parser = FiiParser();
  // Older first, so that the register of the newer wins on equal versions.
  final sorted = [...paths]
    ..sort((a, b) => p.basename(a).compareTo(p.basename(b)));
  for (final path in sorted) {
    final archive = ZipDecoder().decodeBytes(File(path).readAsBytesSync());
    for (final file in archive.files) {
      final name = file.name;
      final read = switch (name) {
        _ when name.contains('inf_mensal_fii_geral_') => parser.addRegister,
        _ when name.contains('inf_mensal_fii_complemento_') => parser.addMonths,
        _ when name.contains('inf_mensal_fii_ativo_passivo_') =>
          parser.addAssets,
        _ when name.contains('inf_trimestral_fii_imovel_2') =>
          parser.addProperties,
        _
            when name.contains(
              'inf_trimestral_fii_imovel_renda_acabado_inquilino_',
            ) =>
          parser.addTenants,
        _ when name.contains('inf_trimestral_fii_complemento_') =>
          parser.addLeases,
        _ => null,
      };
      read?.call(latin1.decode(file.content, allowInvalid: true));
    }
  }
  final funds = parser.build().values.where((f) => f.months.isNotEmpty);
  return jsonEncode({
    'format': format,
    'builtAt': DateTime.now().toIso8601String(),
    'funds': [for (final f in funds) f.toJson()],
  });
}
