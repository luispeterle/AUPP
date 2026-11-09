import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:aupp/investments/b3-instruments.dart';
import 'package:aupp/services/logger.dart';

/// A day of a fund in its daily report to the CVM.
class FundDay {
  final DateTime date;
  final double quota;
  final double equity;
  final int holders;

  /// Money in minus money out that day.
  final double flow;

  const FundDay(this.date, this.quota, this.equity, this.holders, this.flow);

  List<Object> toJson() => [
    date.toIso8601String().substring(0, 10),
    quota,
    equity,
    holders,
    flow,
  ];

  static FundDay fromJson(List json) => FundDay(
    DateTime.parse(json[0] as String),
    (json[1] as num).toDouble(),
    (json[2] as num).toDouble(),
    json[3] as int,
    (json[4] as num).toDouble(),
  );
}

/// A month of a Fiagro in its monthly report to the CVM. Only amounts in
/// reais are read: the percentages each fund reports come in different units
/// (one writes 0.01 for 1%, another 0.99 for 0.99%), and some put all the
/// fee under management and none under administration.
class FundMonth {
  final DateTime date;
  final double? equity;
  final int? holders;
  final double? bookPerShare;

  /// Income declared to be paid, per quota: "Rendimentos a distribuir" over
  /// the quotas issued. Null when none was declared that month.
  final double? dividendPerShare;

  const FundMonth(
    this.date, {
    this.equity,
    this.holders,
    this.bookPerShare,
    this.dividendPerShare,
  });

  /// [dividendPerShare] over the book value of the quota.
  double? get dividendYield {
    final paid = dividendPerShare;
    final book = bookPerShare;
    return paid == null || book == null || book <= 0 ? null : paid / book;
  }

  List<Object?> toJson() => [
    date.toIso8601String().substring(0, 10),
    equity,
    holders,
    bookPerShare,
    dividendPerShare,
  ];

  static FundMonth fromJson(List json) {
    double? d(Object? v) => (v as num?)?.toDouble();
    return FundMonth(
      DateTime.parse(json[0] as String),
      equity: d(json[1]),
      holders: json[2] as int?,
      bookPerShare: d(json[3]),
      dividendPerShare: d(json[4]),
    );
  }
}

/// A listed fund as the CVM has it: its register and, depending on the kind,
/// its daily or monthly reports.
class CvmFund {
  final String cnpj;
  final String? name;
  final String? manager;
  final String? administrator;
  final DateTime? since;

  /// From the register: the last net assets it has, and their date.
  final double? equity;
  final DateTime? equityDate;
  final List<FundDay> days;
  final List<FundMonth> months;

  const CvmFund(
    this.cnpj, {
    this.name,
    this.manager,
    this.administrator,
    this.since,
    this.equity,
    this.equityDate,
    this.days = const [],
    this.months = const [],
  });

  FundDay? get lastDay => days.isEmpty ? null : days.last;

  /// The quota's change over the last [span] calendar days; null without
  /// that much history. Not a return when the fund pays income: each payment
  /// takes it out of the quota.
  double? quotaChange(int span) {
    final last = lastDay;
    if (last == null) return null;
    final start = last.date.subtract(Duration(days: span));
    final first = days.where((d) => !d.date.isBefore(start)).firstOrNull;
    if (first == null ||
        first.date.difference(start).inDays > 7 ||
        first.quota <= 0) {
      return null;
    }
    return last.quota / first.quota - 1;
  }

  /// Money in minus out over the last [span] days.
  double? flowOver(int span) {
    final last = lastDay;
    if (last == null) return null;
    final start = last.date.subtract(Duration(days: span));
    return days
        .where((d) => d.date.isAfter(start))
        .fold<double>(0, (sum, d) => sum + d.flow);
  }

  /// Dividend yield of the last 12 months reported (a Fiagro); null when a
  /// month has none.
  double? get yearYield {
    final last = months.length < 12 ? null : months.sublist(months.length - 12);
    if (last == null || last.any((m) => m.dividendYield == null)) return null;
    return last.fold<double>(0, (sum, m) => sum + m.dividendYield!);
  }

  CvmFund withReports({List<FundDay>? days, List<FundMonth>? months}) =>
      CvmFund(
        cnpj,
        name: name,
        manager: manager,
        administrator: administrator,
        since: since,
        equity: equity,
        equityDate: equityDate,
        days: days ?? this.days,
        months: months ?? this.months,
      );

  Map<String, dynamic> toJson() => {
    'cnpj': cnpj,
    'name': name,
    'manager': manager,
    'administrator': administrator,
    'since': since?.toIso8601String(),
    'equity': equity,
    'equityDate': equityDate?.toIso8601String(),
  };

  static CvmFund fromJson(Map<String, dynamic> json) => CvmFund(
    json['cnpj'] as String,
    name: json['name'] as String?,
    manager: json['manager'] as String?,
    administrator: json['administrator'] as String?,
    since: DateTime.tryParse(json['since'] as String? ?? ''),
    equity: (json['equity'] as num?)?.toDouble(),
    equityDate: DateTime.tryParse(json['equityDate'] as String? ?? ''),
  );
}

String _digits(String text) => text.replaceAll(RegExp(r'\D'), '');

/// Rows of the CSVs in a CVM zip, with the names of the first line.
Iterable<Map<String, String>> _rows(List<int> zip, {String? prefix}) sync* {
  final archive = ZipDecoder().decodeBytes(zip);
  for (final file in archive.files) {
    if (!file.isFile || !file.name.endsWith('.csv')) continue;
    if (prefix != null && !p.basename(file.name).startsWith(prefix)) continue;
    final lines = const LineSplitter().convert(
      latin1.decode(file.content, allowInvalid: true),
    );
    if (lines.isEmpty) continue;
    final names = lines.first.replaceFirst('﻿', '').split(';');
    for (final line in lines.skip(1)) {
      final cells = line.split(';');
      yield {
        for (var i = 0; i < names.length && i < cells.length; i++)
          names[i]: cells[i],
      };
    }
  }
}

double? _number(String? text) =>
    text == null || text.isEmpty ? null : double.tryParse(text);

/// The register of the funds in [cnpjs]: name, manager, administrator, start
/// and last net assets. Classes (RCVM 175) and funds both have a CNPJ.
@visibleForTesting
Map<String, CvmFund> readRegister(List<int> zip, Set<String> cnpjs) {
  // About a hundred thousand funds: only what is read of each.
  const kept = [
    'CNPJ_Fundo',
    'Denominacao_Social',
    'Gestor',
    'Administrador',
    'Data_Constituicao',
    'Patrimonio_Liquido',
    'Data_Patrimonio_Liquido',
  ];
  final funds = <String, Map<String, String>>{};
  final classes = <Map<String, String>>[];
  for (final row in _rows(zip, prefix: 'registro_fundo')) {
    funds[row['ID_Registro_Fundo'] ?? ''] = {
      for (final key in kept)
        if (row[key] case final value?) key: value,
    };
  }
  for (final row in _rows(zip, prefix: 'registro_classe')) {
    if (cnpjs.contains(_digits(row['CNPJ_Classe'] ?? ''))) classes.add(row);
  }
  final out = <String, CvmFund>{};
  CvmFund make(
    String cnpj,
    Map<String, String> row,
    Map<String, String>? fund,
  ) => CvmFund(
    cnpj,
    name: row['Denominacao_Social'],
    manager: (fund ?? row)['Gestor'],
    administrator: (fund ?? row)['Administrador'],
    // A class's date is when it was adapted to RCVM 175 (2025).
    since: DateTime.tryParse(
      fund?['Data_Constituicao'] ?? row['Data_Constituicao'] ?? '',
    ),
    equity: _number(row['Patrimonio_Liquido']),
    equityDate: DateTime.tryParse(row['Data_Patrimonio_Liquido'] ?? ''),
  );
  for (final row in classes) {
    final cnpj = _digits(row['CNPJ_Classe'] ?? '');
    if (!cnpjs.contains(cnpj)) continue;
    out[cnpj] = make(cnpj, row, funds[row['ID_Registro_Fundo']]);
  }
  for (final row in funds.values) {
    final cnpj = _digits(row['CNPJ_Fundo'] ?? '');
    if (!cnpjs.contains(cnpj) || out.containsKey(cnpj)) continue;
    out[cnpj] = make(cnpj, row, null);
  }
  return out;
}

/// The days of the funds in [cnpjs], from a month's daily report zip.
@visibleForTesting
Map<String, List<FundDay>> readDaily(List<int> zip, Set<String> cnpjs) {
  final out = <String, Map<DateTime, FundDay>>{};
  {
    for (final row in _rows(zip)) {
      final cnpj = _digits(row['CNPJ_FUNDO_CLASSE'] ?? row['CNPJ_FUNDO'] ?? '');
      if (!cnpjs.contains(cnpj)) continue;
      // A class with subclasses reports each one too: the class is the row
      // without a subclass.
      if ((row['ID_SUBCLASSE'] ?? '').isNotEmpty) continue;
      final date = DateTime.tryParse(row['DT_COMPTC'] ?? '');
      final quota = _number(row['VL_QUOTA']);
      if (date == null || quota == null) continue;
      (out[cnpj] ??= {})[date] = FundDay(
        date,
        quota,
        _number(row['VL_PATRIM_LIQ']) ?? 0,
        int.tryParse(row['NR_COTST'] ?? '') ?? 0,
        (_number(row['CAPTC_DIA']) ?? 0) - (_number(row['RESG_DIA']) ?? 0),
      );
    }
  }
  return {
    for (final e in out.entries)
      e.key: (e.value.values.toList()
        ..sort((a, b) => a.date.compareTo(b.date))),
  };
}

/// The months of the Fiagros in [cnpjs], from a monthly report zip.
@visibleForTesting
Map<String, List<FundMonth>> readFiagro(List<int> zip, Set<String> cnpjs) {
  final out = <String, Map<DateTime, FundMonth>>{};
  {
    for (final row in _rows(zip, prefix: 'inf_mensal_fiagro_2')) {
      final cnpj = _digits(row['CNPJ_Classe'] ?? '');
      if (!cnpjs.contains(cnpj)) continue;
      final date = DateTime.tryParse(row['Data_Referencia'] ?? '');
      if (date == null) continue;
      final declared = _number(row['Rendimentos_Distribuir']);
      final quotas = _number(row['Cotas_Emitidas']);
      (out[cnpj] ??= {})[DateTime(date.year, date.month)] = FundMonth(
        DateTime(date.year, date.month),
        equity: _number(row['Patrimonio_Liquido']),
        holders: int.tryParse(row['Numero_Cotistas'] ?? ''),
        bookPerShare: _number(row['Valor_Patrimonial_Cotas']),
        dividendPerShare:
            declared == null || declared <= 0 || quotas == null || quotas <= 0
            ? null
            : declared / quotas,
      );
    }
  }
  return {
    for (final e in out.entries)
      e.key: (e.value.values.toList()
        ..sort((a, b) => a.date.compareTo(b.date))),
  };
}

/// What the CVM has of a kind of report.
enum FundReports { register, daily, fiagro }

/// The rows of [cnpjs] in a downloaded zip of [part], as JSON.
@visibleForTesting
Map<String, Object> parsePart(
  FundReports part,
  List<int> zip,
  Set<String> cnpjs,
) => switch (part) {
  FundReports.register => {
    for (final e in readRegister(zip, cnpjs).entries) e.key: e.value.toJson(),
  },
  FundReports.daily => {
    for (final e in readDaily(zip, cnpjs).entries)
      e.key: [for (final d in e.value) d.toJson()],
  },
  FundReports.fiagro => {
    for (final e in readFiagro(zip, cnpjs).entries)
      e.key: [for (final m in e.value) m.toJson()],
  },
};

/// The months of each fund in one list, by date (a later file wins).
@visibleForTesting
Map<String, Object> mergeParts(FundReports part, List<Map> parsed) {
  if (part == FundReports.register) {
    return parsed.isEmpty ? {} : parsed.first.cast<String, Object>();
  }
  final out = <String, Map<String, List>>{};
  for (final file in parsed) {
    for (final e in file.entries) {
      final byDate = out[e.key as String] ??= {};
      for (final row in e.value as List) {
        byDate[(row as List).first as String] = row;
      }
    }
  }
  return {
    for (final e in out.entries)
      e.key: (e.value.keys.toList()..sort()).map((d) => e.value[d]!).toList(),
  };
}

/// The CVM's data of the listed funds that are not FIIs: ETFs (register only:
/// they file no daily report), infrastructure funds, FIDCs and the like (daily
/// report) and Fiagros (monthly report). Each part is fetched the first time
/// a fund needs it, then each file again only when the CVM changes it, at most
/// every [checkEvery]. Of each file only the listed funds are kept (a month of
/// daily reports is about 10 MB zipped), on this device, out of the backup and
/// the sync.
class CvmFundStore extends ChangeNotifier {
  static final instance = CvmFundStore();
  static final _logger = Logger.withClass(CvmFundStore);
  static const _base = 'https://dados.cvm.gov.br/dados';
  static const checkEvery = Duration(days: 3);

  /// Months of daily reports before the current one.
  static const dailyMonths = 6;

  /// Raised when the reading changes.
  static const format = 2;

  final _register = <String, CvmFund>{};
  final _days = <String, List<FundDay>>{};
  final _months = <String, List<FundMonth>>{};
  final _builtAt = <FundReports, DateTime>{};
  final _running = <FundReports, Future<void>>{};

  String? progress;
  final _errors = <FundReports, String>{};

  /// Why the last download of [part] failed; null once it worked.
  String? errorOf(FundReports part) => _errors[part];

  @visibleForTesting
  Future<Directory> Function() folder = () async => Directory(
    p.join((await getApplicationSupportDirectory()).path, 'cvm-funds'),
  );

  @visibleForTesting
  http.Client Function() client = http.Client.new;

  bool get busy => _running.isNotEmpty;

  bool has(FundReports part) => _builtAt.containsKey(part);

  /// The fund with every report loaded so far.
  CvmFund? fund(String cnpj) {
    final registered = _register[cnpj];
    final days = _days[cnpj];
    final months = _months[cnpj];
    if (registered == null && days == null && months == null) return null;
    return (registered ?? CvmFund(cnpj)).withReports(
      days: days,
      months: months,
    );
  }

  /// The listed funds' CNPJs ([b3Instruments]).
  static Set<String> get listed => {
    for (final value in b3Instruments.values)
      if (value.$4 != null && value.$4!.length == 14) value.$4!,
  };

  Future<void> ensure(FundReports part, {bool force = false}) async {
    if (!has(part)) await _loadSaved(part);
    final built = _builtAt[part];
    if (!force &&
        built != null &&
        DateTime.now().difference(built) < checkEvery) {
      return;
    }
    return _running[part] ??= _refresh(part).whenComplete(() {
      _running.remove(part);
      progress = null;
      notifyListeners();
    });
  }

  Future<File> _builtFile(FundReports part) async =>
      File(p.join((await folder()).path, '${part.name}.json'));

  void _apply(FundReports part, Map<String, dynamic> funds) {
    switch (part) {
      case FundReports.register:
        _register
          ..clear()
          ..addAll({
            for (final e in funds.entries)
              e.key: CvmFund.fromJson((e.value as Map).cast<String, dynamic>()),
          });
      case FundReports.daily:
        _days
          ..clear()
          ..addAll({
            for (final e in funds.entries)
              e.key: [
                for (final d in e.value as List) FundDay.fromJson(d as List),
              ],
          });
      case FundReports.fiagro:
        _months
          ..clear()
          ..addAll({
            for (final e in funds.entries)
              e.key: [
                for (final m in e.value as List) FundMonth.fromJson(m as List),
              ],
          });
    }
  }

  Future<void> _loadSaved(FundReports part) async {
    try {
      final file = await _builtFile(part);
      if (!await file.exists()) return;
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (json['format'] != format) return;
      _apply(part, (json['funds'] as Map).cast<String, dynamic>());
      final at = DateTime.tryParse(json['builtAt'] as String? ?? '');
      if (at != null) _builtAt[part] = at;
      notifyListeners();
    } catch (e, st) {
      _logger.handle(e, st, 'Ignoring the saved ${part.name}');
    }
  }

  void _say(String? text) {
    progress = text;
    notifyListeners();
  }

  /// The zips of a part: the register is one file; the reports are a file a
  /// month (the current one may not exist yet), a year of Fiagro's.
  List<({String name, String url})> _files(FundReports part) {
    final now = DateTime.now();
    String month(int back) {
      final d = DateTime(now.year, now.month - back);
      return '${d.year}${d.month.toString().padLeft(2, '0')}';
    }

    return switch (part) {
      FundReports.register => [
        (
          name: 'registro_fundo_classe',
          url: '$_base/FI/CAD/DADOS/registro_fundo_classe.zip',
        ),
      ],
      FundReports.daily => [
        for (var i = 0; i <= dailyMonths; i++)
          (
            name: 'inf_diario_fi_${month(i)}',
            url: '$_base/FI/DOC/INF_DIARIO/DADOS/inf_diario_fi_${month(i)}.zip',
          ),
      ],
      FundReports.fiagro => [
        for (var i = 0; i <= 13; i++)
          (
            name: 'inf_mensal_fiagro_${month(i)}',
            url:
                '$_base/FIAGRO/DOC/INF_MENSAL/DADOS/'
                'inf_mensal_fiagro_${month(i)}.zip',
          ),
      ],
    };
  }

  static const _labels = {
    FundReports.register: 'o cadastro dos fundos',
    FundReports.daily: 'os informes diários',
    FundReports.fiagro: 'os informes dos Fiagros',
  };

  Future<void> _refresh(FundReports part) async {
    _errors.remove(part);
    final http_ = client();
    try {
      final dir = await folder();
      await dir.create(recursive: true);
      final metaFile = File(p.join(dir.path, 'meta.json'));
      final meta = await metaFile.exists()
          ? (jsonDecode(await metaFile.readAsString()) as Map)
                .cast<String, dynamic>()
          : <String, dynamic>{};
      final files = _files(part);
      var changed = !has(part);
      final kept = <File>[];
      final cnpjs = listed;
      for (final (i, file) in files.indexed) {
        _say('Baixando ${_labels[part]} da CVM (${i + 1} de ${files.length})');
        final parsed = File(p.join(dir.path, '${file.name}.json'));
        final head = await http_
            .head(Uri.parse(file.url))
            .timeout(const Duration(seconds: 30));
        if (head.statusCode == 404) continue;
        kept.add(parsed);
        final modified = head.headers['last-modified'];
        if (modified != null &&
            meta[file.name] == '$format $modified' &&
            await parsed.exists()) {
          continue;
        }
        final response = await http_
            .get(Uri.parse(file.url))
            .timeout(const Duration(minutes: 3));
        if (response.statusCode != 200) {
          throw HttpException('${file.name}: HTTP ${response.statusCode}');
        }
        final zip = response.bodyBytes;
        await parsed.writeAsString(
          await Isolate.run(() => jsonEncode(parsePart(part, zip, cnpjs))),
        );
        meta[file.name] = '$format $modified';
        changed = true;
      }
      // Months that left the window, and zips of the first version.
      final prefix = files.first.name.substring(0, 10);
      final names = {for (final f in files) f.name};
      await for (final entry in dir.list()) {
        final name = p.basenameWithoutExtension(entry.path);
        if (entry.path.endsWith('.zip') ||
            (name.startsWith(prefix) && !names.contains(name))) {
          await entry.delete();
          meta.remove(name);
        }
      }
      await metaFile.writeAsString(jsonEncode(meta));
      if (changed && kept.isNotEmpty) {
        _say('Lendo ${_labels[part]}');
        final parsed = [
          for (final file in kept) jsonDecode(await file.readAsString()) as Map,
        ];
        final funds = mergeParts(part, parsed);
        _apply(part, funds.cast<String, dynamic>());
        await (await _builtFile(part))
            .writeAsString(jsonEncode({'format': format, 'funds': funds}));
      }
      _builtAt[part] = DateTime.now();
      final saved = await _builtFile(part);
      if (await saved.exists()) {
        final json = jsonDecode(await saved.readAsString()) as Map;
        json['builtAt'] = _builtAt[part]!.toIso8601String();
        await saved.writeAsString(jsonEncode(json));
      }
    } catch (e, st) {
      _logger.handle(e, st, '${part.name} refresh failed');
      _errors[part] = 'Não consegui baixar ${_labels[part]} da CVM';
    } finally {
      http_.close();
    }
  }
}
