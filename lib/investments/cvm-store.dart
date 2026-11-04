import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:aupp/investments/b3-market.dart';
import 'package:aupp/investments/cvm-statements.dart';
import 'package:aupp/services/logger.dart';

/// The statements of every company listed on the B3, from the CVM's open data
/// (dados.cvm.gov.br). The zips stay on this computer, out of the backup and the
/// sync, and are fetched again only when the CVM changes them.
///
/// Five DFPs give ten years, as each also brings the year before. The ITRs of
/// this year give the last twelve months.
class CvmStore extends ChangeNotifier {
  static final instance = CvmStore();
  static final _logger = Logger.withClass(CvmStore);
  static const _base = 'https://dados.cvm.gov.br/dados/CIA_ABERTA';

  /// How long a build is trusted before asking the CVM what changed.
  static const checkEvery = Duration(days: 7);

  /// Raised when the reading changes: the zips on disk are read again.
  static const format = 4;
  bool _outdated = false;

  Map<String, CvmCompany> _companies = {};
  Map<String, List<CvmNotice>> _notices = {};
  Map<String, String> _byTicker = {};
  Map<String, String>? _byName;

  /// Tickers already looked for in vain.
  final _missing = <String>{};
  DateTime? builtAt;

  /// What is being done, while it is: "Baixando DFP 2023 (3 de 8)".
  String? progress;
  String? error;
  Future<void>? _running;

  /// The folder, swapped in the tests.
  @visibleForTesting
  Future<Directory> Function() folder = () async =>
      Directory(p.join((await getApplicationSupportDirectory()).path, 'cvm'));

  @visibleForTesting
  http.Client Function() client = http.Client.new;

  bool get ready => _companies.isNotEmpty;
  bool get busy => _running != null;

  Iterable<CvmCompany> get companies => _companies.values;

  /// Material facts and notices of the last year, newest first.
  List<CvmNotice> noticesOf(CvmCompany company) =>
      _notices[company.code] ?? const [];

  /// The company of a ticker. One that the register lacks (some companies
  /// write their CVM code where the ticker goes) is found by the root ("PETR"
  /// of PETR4) or by the name brapi gives it, and kept.
  CvmCompany? byTicker(String ticker) {
    ticker = ticker.toUpperCase();
    final code = _byTicker[ticker];
    if (code != null) return _companies[code];
    final kind = ShareClass.ofTicker(ticker);
    if (ticker.length < 5 || kind == null || _missing.contains(ticker)) {
      return null;
    }
    final root = ticker.substring(0, 4);
    var found = _byTicker.entries
        .where((e) => e.key.startsWith(root))
        .map((e) => _companies[e.value])
        .firstOrNull;
    final name = _plainName(B3Market.instance[ticker]?.name);
    if (found == null && name != null) {
      _byName ??= {
        for (final c in _companies.values)
          if (_plainName(c.name) case final plain?) plain: c.code,
      };
      found = _companies[_byName![name]];
    }
    if (found == null) {
      // Asked again once brapi's list is in.
      if (B3Market.instance[ticker] != null) _missing.add(ticker);
      return null;
    }
    final linked = found.withTicker(ticker, kind);
    _companies[linked.code] = linked;
    _byTicker[ticker] = linked.code;
    return linked;
  }

  /// "Cia. Siderúrgica Nacional S/A" → "CIA SIDERURGICA NACIONAL".
  static String? _plainName(String? name) {
    if (name == null) return null;
    const accents = {'Á': 'A', 'À': 'A', 'Â': 'A', 'Ã': 'A', 'É': 'E', 'Ê': 'E',
      'Í': 'I', 'Ó': 'O', 'Ô': 'O', 'Õ': 'O', 'Ú': 'U', 'Ç': 'C'};
    var plain = name.toUpperCase();
    accents.forEach((from, to) => plain = plain.replaceAll(from, to));
    plain = plain
        .replaceAll(RegExp(r'\bS\.?\s?/?A\.?$|\bS\.A\.?'), ' ')
        .replaceAll(RegExp(r'[^A-Z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return plain.isEmpty ? null : plain;
  }

  @visibleForTesting
  void setForTest(
    Iterable<CvmCompany> companies, {
    Map<String, List<CvmNotice>> notices = const {},
  }) {
    _set({for (final c in companies) c.code: c});
    _notices = notices;
    builtAt = DateTime.now();
  }

  void _setJson(Map<String, dynamic> json) {
    _set({
      for (final item in json['companies'] as List)
        (item as Map)['code'] as String: CvmCompany.fromJson(
          item.cast<String, dynamic>(),
        ),
    });
    _notices = {
      for (final e in (json['notices'] as Map? ?? const {}).entries)
        e.key as String: [
          for (final item in e.value as List)
            CvmNotice.fromJson(item as List),
        ],
    };
  }

  void _set(Map<String, CvmCompany> companies) {
    _companies = companies;
    _byTicker = {
      for (final c in companies.values)
        for (final ticker in c.tickers.keys) ticker: c.code,
    };
    _byName = null;
    _missing.clear();
  }

  /// Loads what was built before and, when it is old or missing, refreshes in
  /// the background. Listeners hear the progress.
  Future<void> ensure({bool force = false}) async {
    if (!ready) await _loadSaved();
    final built = builtAt;
    if (!force &&
        built != null &&
        DateTime.now().difference(built) < checkEvery) {
      return;
    }
    return _running ??= _refresh().whenComplete(() {
      _running = null;
      progress = null;
      notifyListeners();
    });
  }

  Future<File> _builtFile() async =>
      File(p.join((await folder()).path, 'companies.json'));

  Future<void> _loadSaved() async {
    try {
      final file = await _builtFile();
      if (!await file.exists()) return;
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      _setJson(json);
      builtAt = DateTime.tryParse(json['builtAt'] as String? ?? '');
      if (json['format'] != format) {
        _outdated = true;
        builtAt = null;
      }
      notifyListeners();
    } catch (e, st) {
      _logger.handle(e, st, 'Ignoring the saved statements');
    }
  }

  void _say(String? text) {
    progress = text;
    notifyListeners();
  }

  Future<void> _refresh() async {
    error = null;
    final http_ = client();
    try {
      final dir = await folder();
      await dir.create(recursive: true);
      final metaFile = File(p.join(dir.path, 'meta.json'));
      final meta = await metaFile.exists()
          ? (jsonDecode(await metaFile.readAsString()) as Map)
                .cast<String, dynamic>()
          : <String, dynamic>{};
      _say('Procurando os balanços na CVM');
      final files = await _files(http_, DateTime.now());
      var changed = !ready || _outdated;
      for (final (i, file) in files.indexed) {
        _say('Baixando ${file.label} (${i + 1} de ${files.length})');
        final path = File(p.join(dir.path, file.name));
        final head = await http_
            .head(Uri.parse(file.url))
            .timeout(const Duration(seconds: 30));
        final modified = head.headers['last-modified'];
        if (modified != null &&
            meta[file.name] == modified &&
            await path.exists()) {
          continue;
        }
        final response = await http_
            .get(Uri.parse(file.url))
            .timeout(const Duration(minutes: 5));
        if (response.statusCode != 200) {
          throw HttpException('${file.name}: HTTP ${response.statusCode}');
        }
        await path.writeAsBytes(response.bodyBytes);
        meta[file.name] = modified;
        changed = true;
      }
      // A zip no longer in the list (a year too old now) goes away.
      final names = {for (final f in files) f.name};
      await for (final entry in dir.list()) {
        final name = p.basename(entry.path);
        if (name.endsWith('.zip') && !names.contains(name)) {
          await entry.delete();
          meta.remove(name);
        }
      }
      await metaFile.writeAsString(jsonEncode(meta));
      if (changed) {
        _say('Lendo os balanços');
        final paths = [for (final f in files) p.join(dir.path, f.name)];
        final built = await Isolate.run(() => buildCompanies(paths));
        await (await _builtFile()).writeAsString(built);
        _outdated = false;
        _setJson(jsonDecode(built) as Map<String, dynamic>);
      }
      builtAt = DateTime.now();
      final saved = await _builtFile();
      if (await saved.exists()) {
        final json = jsonDecode(await saved.readAsString()) as Map;
        json['builtAt'] = builtAt!.toIso8601String();
        await saved.writeAsString(jsonEncode(json));
      }
    } catch (e, st) {
      _logger.handle(e, st, 'Statements refresh failed');
      error = 'Não consegui atualizar os balanços da CVM';
    } finally {
      http_.close();
    }
  }

  /// The zips to have: the five DFPs, this year's ITRs (and last year's while
  /// the yearly ones are coming), and, for this year and the last, the
  /// register (FCA), the reference form (FRE, for the free float) and the
  /// notices (IPE).
  static Future<List<({String name, String url, String label})>> _files(
    http.Client client,
    DateTime now,
  ) async {
    Future<bool> exists(String url) async =>
        (await client
                .head(Uri.parse(url))
                .timeout(const Duration(seconds: 30)))
            .statusCode ==
        200;
    String dfp(int year) => '$_base/DOC/DFP/DADOS/dfp_cia_aberta_$year.zip';
    String itr(int year) => '$_base/DOC/ITR/DADOS/itr_cia_aberta_$year.zip';
    String fca(int year) => '$_base/DOC/FCA/DADOS/fca_cia_aberta_$year.zip';
    String fre(int year) => '$_base/DOC/FRE/DADOS/fre_cia_aberta_$year.zip';
    String ipe(int year) => '$_base/DOC/IPE/DADOS/ipe_cia_aberta_$year.zip';
    final last = await exists(dfp(now.year - 1)) ? now.year - 1 : now.year - 2;
    final itrs = [
      if (await exists(itr(now.year))) now.year,
      if (now.month <= 5 || !await exists(itr(now.year))) now.year - 1,
    ];
    final fcas = [now.year - 1, if (await exists(fca(now.year))) now.year];
    final fres = [now.year - 1, if (await exists(fre(now.year))) now.year];
    final ipes = [now.year - 1, if (await exists(ipe(now.year))) now.year];
    return [
      for (final year in [last, last - 1, last - 3, last - 5, last - 7])
        (name: 'dfp_cia_aberta_$year.zip', url: dfp(year), label: 'DFP $year'),
      for (final year in itrs)
        (name: 'itr_cia_aberta_$year.zip', url: itr(year), label: 'ITR $year'),
      for (final year in fcas)
        (name: 'fca_cia_aberta_$year.zip', url: fca(year), label: 'cadastro $year'),
      for (final year in fres)
        (name: 'fre_cia_aberta_$year.zip', url: fre(year), label: 'formulário de referência $year'),
      for (final year in ipes)
        (name: 'ipe_cia_aberta_$year.zip', url: ipe(year), label: 'comunicados $year'),
    ];
  }
}

/// Reads the zips into the JSON of the companies with a ticker. Runs in an
/// isolate: it reads a few hundred megabytes of CSV.
@visibleForTesting
String buildCompanies(List<String> paths) {
  final parser = CvmParser();
  int yearOf(String path) =>
      int.tryParse(RegExp(r'(\d{4})\.zip$').firstMatch(path)?.group(1) ?? '') ??
      0;
  // Register and reference form: older first, so that the newer wins.
  final registers = paths
      .where((path) => RegExp(r'^(fca|fre)_').hasMatch(p.basename(path)))
      .toList()
    ..sort((a, b) => yearOf(a).compareTo(yearOf(b)));
  for (final path in registers) {
    final archive = ZipDecoder().decodeBytes(File(path).readAsBytesSync());
    for (final file in archive.files) {
      final name = file.name;
      if (!RegExp(r'_(geral|valor_mobiliario|distribuicao_capital)_\d{4}')
          .hasMatch(name)) {
        continue;
      }
      final text = latin1.decode(file.content, allowInvalid: true);
      if (name.contains('_geral_')) parser.addRegister(text);
      if (name.contains('_valor_mobiliario_')) parser.addSecurities(text);
      if (name.contains('_distribuicao_capital_')) parser.addFreeFloat(text);
    }
  }
  final notices = <String, List<CvmNotice>>{};
  final since = DateTime.now().subtract(const Duration(days: 366));
  for (final path in paths.where((p_) => p.basename(p_).startsWith('ipe'))) {
    final archive = ZipDecoder().decodeBytes(File(path).readAsBytesSync());
    for (final file in archive.files) {
      final found = CvmNotice.parse(
        latin1.decode(file.content, allowInvalid: true),
        since,
      );
      for (final e in found.entries) {
        notices.putIfAbsent(e.key, () => []).addAll(e.value);
      }
    }
  }
  for (final path in paths) {
    final name = p.basename(path);
    final yearly = name.startsWith('dfp');
    if (!yearly && !name.startsWith('itr')) continue;
    final archive = ZipDecoder().decodeBytes(File(path).readAsBytesSync());
    // Consolidated first: an individual statement only fills what is missing.
    final files = [
      for (final file in archive.files)
        if (Statement.ofFile(file.name) case (final statement, final con))
          (file, statement, con),
    ]..sort((a, b) => (a.$3 ? 0 : 1).compareTo(b.$3 ? 0 : 1));
    for (final (file, statement, consolidated) in files) {
      parser.addStatement(
        latin1.decode(file.content, allowInvalid: true),
        statement,
        consolidated: consolidated,
        yearly: yearly,
      );
    }
    for (final file in archive.files) {
      if (file.name.contains('composicao_capital')) {
        parser.addCapital(latin1.decode(file.content, allowInvalid: true));
      }
    }
  }
  final companies = parser.build().values.where(parser.listsShares).toList();
  final codes = {for (final c in companies) c.code};
  return jsonEncode({
    'format': CvmStore.format,
    'builtAt': DateTime.now().toIso8601String(),
    'companies': [for (final c in companies) c.toJson()],
    'notices': {
      for (final e in notices.entries)
        if (codes.contains(e.key))
          e.key: [
            for (final n in e.value..sort((a, b) => b.date.compareTo(a.date)))
              n.toJson(),
          ],
    },
  });
}
