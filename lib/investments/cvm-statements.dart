import 'dart:math' as math;

/// What is read from the statements of a period. Flows (revenue, cash flow)
/// cover the period; the balance is at its end.
enum Figure {
  revenue,
  costs,
  grossProfit,
  operatingExpenses,
  ebit,
  incomeTax,
  netIncome,
  assets,
  currentAssets,
  nonCurrentAssets,
  cash,
  inventory,
  currentLiabilities,
  nonCurrentLiabilities,
  grossDebt,
  equity,
  cfo,
  capex,
  depreciation,
  dividendsPaid,

  /// Investing and financing activities, and exchange rates on cash.
  cfi,
  cff,
  fxEffect,

  /// Cash at the end of the period, as in the cash flow statement.
  cashEnd;

  bool get isFlow => switch (this) {
    revenue ||
    costs ||
    grossProfit ||
    operatingExpenses ||
    cfi ||
    cff ||
    fxEffect ||
    ebit ||
    incomeTax ||
    netIncome ||
    cfo ||
    capex ||
    depreciation ||
    dividendsPaid => true,
    _ => false,
  };
}

/// The figures of a company in a period, in reais. A missing one was not in
/// the statements (a bank has no EBIT).
class Figures {
  final Map<Figure, double> values;

  const Figures(this.values);

  double? operator [](Figure figure) => values[figure];

  double? get ebitda {
    final ebit = values[Figure.ebit];
    final depreciation = values[Figure.depreciation];
    return ebit == null ? null : ebit + (depreciation ?? 0);
  }

  double? get netDebt {
    final debt = values[Figure.grossDebt];
    return debt == null ? null : debt - (values[Figure.cash] ?? 0);
  }

  /// What the activities added to cash in the period.
  double? get cashChange {
    final cfo = values[Figure.cfo];
    return cfo == null
        ? null
        : cfo +
              (values[Figure.cfi] ?? 0) +
              (values[Figure.cff] ?? 0) +
              (values[Figure.fxEffect] ?? 0);
  }

  /// Current and non-current liabilities, without the equity.
  double? get liabilities {
    final current = values[Figure.currentLiabilities];
    final nonCurrent = values[Figure.nonCurrentLiabilities];
    return current == null || nonCurrent == null ? null : current + nonCurrent;
  }

  /// Operating cash flow minus capex (capex is negative).
  double? get freeCashFlow {
    final cfo = values[Figure.cfo];
    return cfo == null ? null : cfo + (values[Figure.capex] ?? 0);
  }

  Map<String, double> toJson() => {
    for (final entry in values.entries) entry.key.name: entry.value,
  };

  factory Figures.fromJson(Map<String, dynamic> json) => Figures({
    for (final figure in Figure.values)
      if (json[figure.name] is num)
        figure: (json[figure.name] as num).toDouble(),
  });
}

/// A class of shares listed on the B3.
enum ShareClass {
  on,
  pn,
  unit;

  /// By the ticker's number: 3 is ON, 4 to 8 PN, 11 a unit.
  static ShareClass? ofTicker(String ticker) =>
      switch (RegExp(r'(\d+)$').firstMatch(ticker)?.group(1)) {
        '3' => on,
        '4' || '5' || '6' || '7' || '8' => pn,
        '11' => unit,
        _ => null,
      };
}

/// A listed company: register (FCA) and statements (DFP and ITR).
class CvmCompany {
  final String code;
  final String name;
  final String? cnpj;
  final DateTime? founded;
  final DateTime? listed;

  /// "Estatal Holding", "Privado", ...
  final String? control;

  /// Listing segment: "Novo Mercado", "Nível 2 de Governança Corporativa", ...
  final String? segment;
  final String? sector;
  final Map<String, ShareClass> tickers;

  /// How many ON and PN make a unit, by its ticker.
  final Map<String, (int, int)> units;

  /// A bank or insurer: no EBIT, margins or debt in the usual sense.
  final bool financial;

  /// By the year the period ends.
  final Map<int, Figures> years;

  /// The last twelve months, ending at [ttmEnd].
  final Figures? ttm;
  final DateTime? ttmEnd;

  /// Shares issued, treasury shares already taken out.
  final double? sharesOn;
  final double? sharesPn;

  /// Share of the stock in the market's hands (0–1), from the FRE.
  final double? freeFloat;

  /// The currency of the statements: BRL for the CVM, the reporting one for
  /// the SEC.
  final String currency;

  /// Files with the SEC as a foreign company (20-F or 40-F): its US ticker is
  /// an ADR, which may stand for several shares.
  final bool foreignIssuer;

  bool get fromSec => code.startsWith('SEC');

  const CvmCompany({
    required this.code,
    required this.name,
    this.cnpj,
    this.founded,
    this.listed,
    this.control,
    this.segment,
    this.sector,
    this.tickers = const {},
    this.units = const {},
    this.financial = false,
    this.years = const {},
    this.ttm,
    this.ttmEnd,
    this.sharesOn,
    this.sharesPn,
    this.freeFloat,
    this.currency = 'BRL',
    this.foreignIssuer = false,
  });

  /// The same company with one more ticker, found outside the register.
  CvmCompany withTicker(String ticker, ShareClass kind) => CvmCompany(
    code: code,
    name: name,
    cnpj: cnpj,
    founded: founded,
    listed: listed,
    control: control,
    segment: segment,
    sector: sector,
    tickers: {...tickers, ticker: kind},
    units: units,
    financial: financial,
    years: years,
    ttm: ttm,
    ttmEnd: ttmEnd,
    sharesOn: sharesOn,
    sharesPn: sharesPn,
    freeFloat: freeFloat,
    currency: currency,
    foreignIssuer: foreignIssuer,
  );

  double? get shares => sharesOn == null && sharesPn == null
      ? null
      : (sharesOn ?? 0) + (sharesPn ?? 0);

  bool get stateControlled => control?.toLowerCase().contains('estatal') ?? false;

  /// Years with figures, oldest first.
  List<int> get sortedYears => years.keys.toList()..sort();

  Map<String, dynamic> toJson() => {
    'code': code,
    'name': name,
    'cnpj': ?cnpj,
    'founded': ?founded?.toIso8601String().substring(0, 10),
    'listed': ?listed?.toIso8601String().substring(0, 10),
    'control': ?control,
    'segment': ?segment,
    'sector': ?sector,
    'tickers': {for (final e in tickers.entries) e.key: e.value.name},
    if (units.isNotEmpty)
      'units': {
        for (final e in units.entries) e.key: [e.value.$1, e.value.$2],
      },
    if (financial) 'financial': true,
    'years': {
      for (final e in years.entries) '${e.key}': e.value.toJson(),
    },
    if (ttm != null) 'ttm': ttm!.toJson(),
    'ttmEnd': ?ttmEnd?.toIso8601String().substring(0, 10),
    'sharesOn': ?sharesOn,
    'sharesPn': ?sharesPn,
    'freeFloat': ?freeFloat,
    if (currency != 'BRL') 'currency': currency,
    if (foreignIssuer) 'foreignIssuer': true,
  };

  factory CvmCompany.fromJson(Map<String, dynamic> json) {
    DateTime? date(String key) => DateTime.tryParse(json[key] as String? ?? '');
    return CvmCompany(
      code: json['code'] as String,
      name: json['name'] as String,
      cnpj: json['cnpj'] as String?,
      founded: date('founded'),
      listed: date('listed'),
      control: json['control'] as String?,
      segment: json['segment'] as String?,
      sector: json['sector'] as String?,
      tickers: {
        for (final e in (json['tickers'] as Map? ?? {}).entries)
          e.key as String: ShareClass.values.byName(e.value as String),
      },
      units: {
        for (final e in (json['units'] as Map? ?? {}).entries)
          e.key as String: (
            ((e.value as List)[0] as num).toInt(),
            ((e.value as List)[1] as num).toInt(),
          ),
      },
      financial: json['financial'] as bool? ?? false,
      years: {
        for (final e in (json['years'] as Map? ?? {}).entries)
          int.parse(e.key as String): Figures.fromJson(
            (e.value as Map).cast<String, dynamic>(),
          ),
      },
      ttm: json['ttm'] == null
          ? null
          : Figures.fromJson((json['ttm'] as Map).cast<String, dynamic>()),
      ttmEnd: date('ttmEnd'),
      sharesOn: (json['sharesOn'] as num?)?.toDouble(),
      sharesPn: (json['sharesPn'] as num?)?.toDouble(),
      freeFloat: (json['freeFloat'] as num?)?.toDouble(),
      currency: json['currency'] as String? ?? 'BRL',
      foreignIssuer: json['foreignIssuer'] as bool? ?? false,
    );
  }
}

/// Which statement a CSV of the DFP or ITR zips holds, by its file name.
enum Statement {
  bpa,
  bpp,
  dre,
  dfc;

  /// "dfp_cia_aberta_DRE_con_2025.csv" → (dre, consolidated). Null for the
  /// files not read.
  static (Statement, bool)? ofFile(String name) {
    final match = RegExp(
      r'_(BPA|BPP|DRE|DFC_MI|DFC_MD)_(con|ind)_\d{4}\.csv$',
    ).firstMatch(name);
    if (match == null) return null;
    final statement = switch (match.group(1)!) {
      'BPA' => bpa,
      'BPP' => bpp,
      'DRE' => dre,
      _ => dfc,
    };
    return (statement, match.group(2) == 'con');
  }
}

class _Account {
  final String name;
  final double value;

  const _Account(this.name, this.value);
}

/// One company's document (a DFP or an ITR) as filed, its latest version.
class _Doc {
  final DateTime refer;
  final int version;
  final bool yearly;

  /// Statements that came consolidated: the individual ones are then ignored.
  final Set<Statement> consolidated = {};

  /// Flows by (start, end), balances by end; each by account code.
  final Map<(DateTime, DateTime), Map<String, _Account>> flows = {};
  final Map<DateTime, Map<String, _Account>> balances = {};

  _Doc(this.refer, this.version, {required this.yearly});
}

/// Reads the CSVs of the CVM into [CvmCompany]s. Add every consolidated file of
/// a zip before its individual ones, then [build].
class CvmParser {
  final _docs = <String, Map<String, _Doc>>{};
  final _names = <String, String>{};
  final _cnpjs = <String, String>{};

  /// Outstanding shares by CNPJ: (date, ON, PN), treasury taken out.
  final _shares = <String, (DateTime, double, double)>{};
  final _register = <String, Map<String, String>>{};
  final _registerAt = <String, String>{};
  final _securities = <String, Map<String, (ShareClass, (int, int)?)>>{};
  final _segments = <String, String>{};

  /// CNPJs with shares on the exchange, whatever was written as their ticker.
  final _withShares = <String>{};

  /// Free float by CNPJ, with the version it came from.
  final _freeFloat = <String, (String, double)>{};
  final _listed = <String, String>{};

  /// What each statement needs, so that a 30 MB file keeps a few thousand rows.
  static bool _wanted(Statement statement, String code) {
    final level = '.'.allMatches(code).length;
    return switch (statement) {
      Statement.bpa || Statement.bpp => level <= 2,
      Statement.dre => level <= 2 || code.startsWith('3.99.01.'),
      Statement.dfc =>
        level <= 1 ||
            (code.startsWith('6.01.01.') && level == 3) ||
            ((code.startsWith('6.02.') ||
                    code.startsWith('6.03.') ||
                    code.startsWith('6.05.')) &&
                level == 2),
    };
  }

  /// A statement CSV of the DFP ([yearly]) or ITR, already decoded from
  /// Latin-1.
  void addStatement(
    String csv,
    Statement statement, {
    required bool consolidated,
    required bool yearly,
  }) {
    final lines = csv.split('\n');
    if (lines.isEmpty) return;
    final header = _header(lines.first);
    final cnpjAt = header['CNPJ_CIA']!;
    final referAt = header['DT_REFER']!;
    final versionAt = header['VERSAO']!;
    final nameAt = header['DENOM_CIA']!;
    final codeAt = header['CD_CVM']!;
    final scaleAt = header['ESCALA_MOEDA']!;
    final startAt = header['DT_INI_EXERC'];
    final endAt = header['DT_FIM_EXERC']!;
    final accountAt = header['CD_CONTA']!;
    final accountNameAt = header['DS_CONTA']!;
    final valueAt = header['VL_CONTA']!;
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.length < 20) continue;
      final cells = line.trimRight().split(';');
      if (cells.length <= valueAt) continue;
      final account = cells[accountAt];
      if (!_wanted(statement, account)) continue;
      final company = cells[codeAt];
      final refer = DateTime.tryParse(cells[referAt]);
      final version = int.tryParse(cells[versionAt]) ?? 0;
      final end = DateTime.tryParse(cells[endAt]);
      final raw = double.tryParse(cells[valueAt]);
      if (refer == null || end == null || raw == null) continue;
      final docs = _docs.putIfAbsent(company, () => {});
      final key = '${yearly ? 'DFP' : 'ITR'} ${cells[referAt]}';
      var doc = docs[key];
      if (doc == null || doc.version < version) {
        doc = docs[key] = _Doc(refer, version, yearly: yearly);
      } else if (doc.version > version) {
        continue;
      }
      if (consolidated) {
        doc.consolidated.add(statement);
      } else if (doc.consolidated.contains(statement)) {
        continue;
      }
      _names[company] = cells[nameAt];
      _cnpjs[cells[cnpjAt]] = company;
      // Earnings per share are in reais whatever the scale of the statement.
      final value = cells[scaleAt] == 'MIL' && !account.startsWith('3.99')
          ? raw * 1000
          : raw;
      final accounts = switch (statement) {
        Statement.bpa || Statement.bpp => doc.balances.putIfAbsent(
          end,
          () => {},
        ),
        Statement.dre || Statement.dfc => doc.flows.putIfAbsent((
          DateTime.tryParse(startAt == null ? '' : cells[startAt]) ?? end,
          end,
        ), () => {}),
      };
      accounts[account] = _Account(cells[accountNameAt], value);
    }
  }

  /// The "composicao_capital" CSV of a DFP or ITR.
  void addCapital(String csv) {
    final lines = csv.split('\n');
    if (lines.isEmpty) return;
    final header = _header(lines.first);
    double cell(List<String> cells, String name) =>
        double.tryParse(cells[header[name]!]) ?? 0;
    for (final line in lines.skip(1)) {
      final cells = line.trimRight().split(';');
      if (cells.length < header.length) continue;
      final refer = DateTime.tryParse(cells[header['DT_REFER']!]);
      if (refer == null) continue;
      final cnpj = cells[header['CNPJ_CIA']!];
      final known = _shares[cnpj];
      if (known != null && !known.$1.isBefore(refer)) continue;
      final on =
          cell(cells, 'QT_ACAO_ORDIN_CAP_INTEGR') -
          cell(cells, 'QT_ACAO_ORDIN_TESOURO');
      final pn =
          cell(cells, 'QT_ACAO_PREF_CAP_INTEGR') -
          cell(cells, 'QT_ACAO_PREF_TESOURO');
      _shares[cnpj] = (refer, on, pn);
    }
  }

  /// "fca_cia_aberta_geral" CSV: founding date, sector and control. A newer
  /// year's file wins, so add the older ones first.
  void addRegister(String csv) {
    final lines = csv.split('\n');
    if (lines.isEmpty) return;
    final header = _header(lines.first);
    for (final line in lines.skip(1)) {
      final cells = line.trimRight().split(';');
      if (cells.length < header.length) continue;
      final row = {
        for (final e in header.entries) e.key: cells[e.value].trim(),
      };
      final cnpj = row['CNPJ_Companhia']!;
      final at = '${row['Data_Referencia']}|${row['Versao']!.padLeft(4, '0')}';
      if ((_registerAt[cnpj] ?? '').compareTo(at) > 0) continue;
      _registerAt[cnpj] = at;
      _register[cnpj] = row;
    }
  }

  /// "fca_cia_aberta_valor_mobiliario" CSV: the tickers of each company.
  void addSecurities(String csv) {
    final lines = csv.split('\n');
    if (lines.isEmpty) return;
    final header = _header(lines.first);
    for (final line in lines.skip(1)) {
      final cells = line.trimRight().split(';');
      if (cells.length < header.length) continue;
      String cell(String name) => cells[header[name]!].trim();
      final kind = switch (cell('Valor_Mobiliario')) {
        'Ações Ordinárias' => ShareClass.on,
        'Ações Preferenciais' => ShareClass.pn,
        'Units' => ShareClass.unit,
        _ => null,
      };
      // The end of trading is sometimes filled with its start; the end of the
      // listing is not.
      if (kind == null || cell('Data_Fim_Listagem').isNotEmpty) continue;
      final cnpj = cell('CNPJ_Companhia');
      _withShares.add(cnpj);
      // Some companies write their CVM code or zeros here: they are found by
      // name later (CvmStore.byTicker).
      final ticker = cell('Codigo_Negociacao').toUpperCase();
      if (!RegExp(r'^[A-Z][A-Z0-9]{3}\d{1,2}$').hasMatch(ticker)) continue;
      _securities.putIfAbsent(cnpj, () => {})[ticker] = (
        kind,
        kind == ShareClass.unit ? unitComposition(cell('Composicao_BDR_Unit')) : null,
      );
      final segment = cell('Segmento');
      if (segment.isNotEmpty) _segments[cnpj] = segment;
      final listed = cell('Data_Inicio_Listagem');
      if (listed.isNotEmpty) {
        final known = _listed[cnpj];
        if (known == null || listed.compareTo(known) < 0) _listed[cnpj] = listed;
      }
    }
  }

  /// "fre_cia_aberta_distribuicao_capital" CSV: the shares in circulation.
  void addFreeFloat(String csv) {
    final lines = csv.split('\n');
    if (lines.isEmpty) return;
    final header = _header(lines.first);
    for (final line in lines.skip(1)) {
      final cells = line.trimRight().split(';');
      if (cells.length < header.length) continue;
      String cell(String name) => cells[header[name]!].trim();
      final pct = double.tryParse(cell('Percentual_Total_Acoes_Circulacao'));
      if (pct == null || pct <= 0) continue;
      final cnpj = cell('CNPJ_Companhia');
      final at = '${cell('Data_Referencia')}|${cell('Versao').padLeft(4, '0')}';
      if ((_freeFloat[cnpj]?.$1 ?? '').compareTo(at) > 0) continue;
      _freeFloat[cnpj] = (at, pct / 100);
    }
  }

  /// Whether the register says the company has shares on the exchange.
  bool listsShares(CvmCompany company) =>
      company.tickers.isNotEmpty || _withShares.contains(company.cnpj);

  /// "1 ON e 2 PN", "2 ações preferenciais e 1 ação ordinária" → (1, 2).
  static (int, int)? unitComposition(String text) {
    var on = 0;
    var pn = 0;
    for (final match in RegExp(
      r'(\d+)\s*(ações|ação)?\s*(ON|PN[AB]?|ordin\w*|prefer\w*)',
      caseSensitive: false,
    ).allMatches(text)) {
      final count = int.parse(match.group(1)!);
      final kind = match.group(3)!.toLowerCase();
      if (kind.startsWith('on') || kind.startsWith('ordin')) {
        on += count;
      } else {
        pn += count;
      }
    }
    return on + pn == 0 ? null : (on, pn);
  }

  static Map<String, int> _header(String line) {
    final names = line.trimRight().replaceFirst('﻿', '').split(';');
    return {for (final (i, name) in names.indexed) name: i};
  }

  Map<String, CvmCompany> build() {
    final byCode = {
      for (final e in _cnpjs.entries) e.value: e.key,
    };
    final out = <String, CvmCompany>{};
    for (final entry in _docs.entries) {
      final code = entry.key;
      final docs = entry.value.values.toList()
        ..sort((a, b) => b.refer.compareTo(a.refer));
      final cnpj = byCode[code];
      final financial = !docs.any(
        (doc) => doc.flows.values.any((accounts) => _ebitOf(accounts) != null),
      );
      final years = <int, Figures>{};
      final yearEnds = <int, DateTime>{};
      for (final doc in docs.where((d) => d.yearly)) {
        for (final period in doc.flows.keys) {
          final (start, end) = period;
          if (end.difference(start).inDays < 340) continue;
          if (years.containsKey(end.year)) continue;
          years[end.year] = _figures(doc, period);
          yearEnds[end.year] = end;
        }
      }
      Figures? ttm;
      DateTime? ttmEnd;
      final lastYear = years.isEmpty ? null : years.keys.reduce(math.max);
      final quarter = docs.where((d) => !d.yearly).firstOrNull;
      if (lastYear != null &&
          quarter != null &&
          quarter.refer.isAfter(yearEnds[lastYear]!)) {
        ttm = _trailing(quarter, years[lastYear]!, yearEnds[lastYear]!);
        if (ttm != null) ttmEnd = quarter.refer;
      }
      if (ttm == null && lastYear != null) {
        ttm = years[lastYear];
        ttmEnd = yearEnds[lastYear];
      }
      final register = cnpj == null ? null : _register[cnpj];
      var shares = cnpj == null ? null : _shares[cnpj];
      if (shares != null) {
        final scale = _shareScale(docs, shares.$2 + shares.$3);
        shares = (shares.$1, shares.$2 * scale, shares.$3 * scale);
      }
      final securities = cnpj == null ? null : _securities[cnpj];
      DateTime? date(String? text) => DateTime.tryParse(text ?? '');
      String? text(String? value) =>
          value == null || value.isEmpty ? null : value;
      out[code] = CvmCompany(
        code: code,
        name: _names[code] ?? code,
        cnpj: cnpj,
        founded: date(register?['Data_Constituicao']),
        listed: date(cnpj == null ? null : _listed[cnpj]),
        control: text(register?['Especie_Controle_Acionario']),
        segment: cnpj == null ? null : _segments[cnpj],
        sector: text(register?['Setor_Atividade']),
        tickers: {
          for (final e in (securities ?? const {}).entries) e.key: e.value.$1,
        },
        units: {
          for (final e in (securities ?? const {}).entries)
            if (e.value.$2 != null) e.key: e.value.$2!,
        },
        financial: financial,
        years: years,
        ttm: ttm,
        ttmEnd: ttmEnd,
        sharesOn: shares?.$2,
        sharesPn: shares?.$3,
        freeFloat: cnpj == null ? null : _freeFloat[cnpj]?.$2,
      );
    }
    return out;
  }

  /// Last year plus this year so far minus the same months of last year. The
  /// balance is the quarter's.
  static Figures? _trailing(_Doc quarter, Figures year, DateTime yearEnd) {
    final ytdPeriods = quarter.flows.keys
        .where((p) => p.$2 == quarter.refer)
        .toList();
    if (ytdPeriods.isEmpty) return null;
    // The longest one is the year so far; the other is the quarter alone.
    final ytd = ytdPeriods.reduce((a, b) => a.$1.isBefore(b.$1) ? a : b);
    final months = (ytd.$2.year - ytd.$1.year) * 12 + ytd.$2.month - ytd.$1.month;
    final previous = quarter.flows.keys.where(
      (p) =>
          p.$2.year == ytd.$2.year - 1 &&
          p.$2.month == ytd.$2.month &&
          (p.$2.year - p.$1.year) * 12 + p.$2.month - p.$1.month == months,
    );
    if (previous.isEmpty) return null;
    // The year so far must start right after the last closed year.
    if (ytd.$1.difference(yearEnd).inDays > 5) return null;
    final now = _figures(quarter, ytd);
    final before = _figures(quarter, previous.first);
    final values = <Figure, double>{};
    for (final figure in Figure.values) {
      final total = year[figure];
      final current = now[figure];
      if (!figure.isFlow) {
        if (current != null) values[figure] = current;
      } else if (total != null && current != null) {
        values[figure] = total + current - (before[figure] ?? 0);
      }
    }
    return Figures(values);
  }

  /// Some companies file their share count in thousands, and the file does not
  /// say which. The net income over the earnings per share they report tells.
  static double _shareScale(List<_Doc> docs, double filed) {
    if (filed <= 0) return 1;
    for (final doc in docs.where((d) => d.yearly)) {
      for (final MapEntry(key: period, value: accounts) in doc.flows.entries) {
        double? eps;
        double? income;
        for (final e in accounts.entries) {
          if (e.key.startsWith('3.99.01.') && e.value.value > 0) {
            eps = math.max(eps ?? 0, e.value.value);
          }
          if (e.key.startsWith('3.') &&
              e.value.name.toLowerCase().contains('controladora')) {
            income = e.value.value;
          }
        }
        if (eps == null) continue;
        income ??= _figures(doc, period)[Figure.netIncome];
        if (income == null || income <= 0) continue;
        final ratio = income / eps / filed;
        return ratio > 300 && ratio < 3000 ? 1000 : 1;
      }
    }
    return 1;
  }

  static _Account? _ebitOf(Map<String, _Account> accounts) {
    for (final e in accounts.entries) {
      if (e.key.startsWith('3.') &&
          e.value.name.startsWith('Resultado Antes do Resultado Financeiro')) {
        return e.value;
      }
    }
    return null;
  }

  /// The figures of a period: its flows, and the balance at its end. A
  /// statement is found by the names of its accounts, as banks and insurers
  /// number them differently.
  static Figures _figures(_Doc doc, (DateTime, DateTime) period) {
    final flows = doc.flows[period] ?? const {};
    final balance = doc.balances[period.$2] ?? const {};
    final values = <Figure, double>{};
    double? at(Map<String, _Account> accounts, String code) =>
        accounts[code]?.value;
    Iterable<MapEntry<String, _Account>> under(
      Map<String, _Account> accounts,
      String prefix,
    ) => accounts.entries.where((e) => e.key.startsWith(prefix));
    String lower(MapEntry<String, _Account> e) => e.value.name.toLowerCase();
    int level(String code) => '.'.allMatches(code).length;

    // Income statement.
    final revenue = at(flows, '3.01');
    if (revenue != null) values[Figure.revenue] = revenue;
    final ebit = _ebitOf(flows);
    if (ebit != null) {
      values[Figure.ebit] = ebit.value;
      final costs = flows['3.02'];
      if (costs != null && costs.name.startsWith('Custo')) {
        values[Figure.costs] = costs.value;
      }
      final expenses = flows['3.04'];
      if (expenses != null && expenses.name.startsWith('Despesas')) {
        values[Figure.operatingExpenses] = expenses.value;
      }
      final gross = flows['3.03'];
      if (gross != null && gross.name.startsWith('Resultado Bruto')) {
        values[Figure.grossProfit] = gross.value;
      }
    }
    for (final e in under(flows, '3.')) {
      if (level(e.key) != 1) continue;
      final name = lower(e);
      if (name.startsWith('imposto de renda e contribuição social')) {
        values[Figure.incomeTax] = e.value.value;
      }
      // The last "Lucro ... Período" is the net income, consolidated when
      // there is a consolidated statement.
      if (name.startsWith('lucro') && name.contains('período')) {
        values[Figure.netIncome] = e.value.value;
      }
    }

    // Cash flow.
    final cfo = at(flows, '6.01');
    if (cfo != null) values[Figure.cfo] = cfo;
    for (final (code, figure) in [
      ('6.02', Figure.cfi),
      ('6.03', Figure.cff),
      ('6.04', Figure.fxEffect),
      ('6.05.02', Figure.cashEnd),
    ]) {
      final value = at(flows, code);
      if (value != null && cfo != null) values[figure] = value;
    }
    var depreciation = 0.0;
    var foundDepreciation = false;
    for (final e in under(flows, '6.01.01.')) {
      final name = lower(e);
      if (RegExp(r'deprecia|amortiza|exaust|deple').hasMatch(name) &&
          !name.contains('juros') &&
          !name.contains('custo')) {
        depreciation += e.value.value;
        foundDepreciation = true;
      }
    }
    if (foundDepreciation) values[Figure.depreciation] = depreciation;
    var capex = 0.0;
    var foundCapex = false;
    for (final e in under(flows, '6.02.')) {
      final name = lower(e);
      if (RegExp(r'imobilizad|intang').hasMatch(name) &&
          !RegExp(r'venda|alienaç|recebimento|baixa').hasMatch(name) &&
          e.value.value < 0) {
        capex += e.value.value;
        foundCapex = true;
      }
    }
    if (foundCapex || cfo != null) values[Figure.capex] = capex;
    var dividends = 0.0;
    for (final e in under(flows, '6.03.')) {
      final name = lower(e);
      if (RegExp(r'dividend|juros sobre (o )?capital|jcp').hasMatch(name) &&
          !RegExp(r'não controlador|nao controlador|recebid').hasMatch(name) &&
          e.value.value < 0) {
        dividends -= e.value.value;
      }
    }
    if (cfo != null) values[Figure.dividendsPaid] = dividends;

    // Balance.
    final assets = at(balance, '1');
    if (assets != null) values[Figure.assets] = assets;
    if (!doc.flows.values.any((a) => _ebitOf(a) != null)) {
      // A bank: only what means the same for it.
    } else {
      final current = at(balance, '1.01');
      if (current != null) values[Figure.currentAssets] = current;
      final nonCurrent = balance['1.02'];
      if (nonCurrent != null && nonCurrent.name.startsWith('Ativo Não')) {
        values[Figure.nonCurrentAssets] = nonCurrent.value;
      }
      final longTerm = balance['2.02'];
      if (longTerm != null && longTerm.name.startsWith('Passivo Não')) {
        values[Figure.nonCurrentLiabilities] = longTerm.value;
      }
      final cash = (at(balance, '1.01.01') ?? 0) + (at(balance, '1.01.02') ?? 0);
      values[Figure.cash] = cash;
      final inventory = balance['1.01.04'];
      if (inventory != null && inventory.name.startsWith('Estoques')) {
        values[Figure.inventory] = inventory.value;
      }
      final currentLiabilities = at(balance, '2.01');
      if (currentLiabilities != null) {
        values[Figure.currentLiabilities] = currentLiabilities;
      }
      double debt = 0;
      for (final code in ['2.01.04', '2.02.01']) {
        final account = balance[code];
        if (account != null && account.name.startsWith('Empréstimos')) {
          debt += account.value;
        }
      }
      values[Figure.grossDebt] = debt;
    }
    for (final e in under(balance, '2.')) {
      if (level(e.key) == 1 && lower(e).startsWith('patrimônio líquido')) {
        values[Figure.equity] = e.value.value;
      }
    }
    return Figures(values);
  }
}

/// A document a company sent the CVM (IPE): a material fact, a notice to the
/// market or to shareholders.
class CvmNotice {
  final DateTime date;
  final String category;
  final String subject;
  final String url;

  const CvmNotice(this.date, this.category, this.subject, this.url);

  /// The categories kept: what moves a shareholder's view of the company.
  static const categories = {
    'Fato Relevante',
    'Comunicado ao Mercado',
    'Aviso aos Acionistas',
    'Relatório Proventos',
  };

  List<Object> toJson() => [
    date.toIso8601String().substring(0, 10),
    category,
    subject,
    url,
  ];

  factory CvmNotice.fromJson(List<dynamic> json) => CvmNotice(
    DateTime.parse(json[0] as String),
    json[1] as String,
    json[2] as String,
    json[3] as String,
  );

  /// The "ipe_cia_aberta" CSV, by CVM code (zero-padded as in the
  /// statements), from [since] on.
  static Map<String, List<CvmNotice>> parse(String csv, DateTime since) {
    final lines = csv.split('\n');
    if (lines.isEmpty) return {};
    final header = CvmParser._header(lines.first);
    final out = <String, List<CvmNotice>>{};
    for (final line in lines.skip(1)) {
      final cells = line.trimRight().split(';');
      if (cells.length < header.length) continue;
      String cell(String name) => cells[header[name]!].trim();
      final category = cell('Categoria');
      if (!categories.contains(category)) continue;
      final date = DateTime.tryParse(cell('Data_Entrega'));
      if (date == null || date.isBefore(since)) continue;
      final kind = cell('Tipo');
      final subject = [cell('Assunto'), kind]
          .firstWhere((t) => t.isNotEmpty, orElse: () => category);
      out
          .putIfAbsent(cell('Codigo_CVM').padLeft(6, '0'), () => [])
          .add(CvmNotice(date, category, subject, cell('Link_Download')));
    }
    return out;
  }
}
