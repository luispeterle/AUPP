import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:aupp/investments/b3-market.dart';
import 'package:aupp/investments/fii-data.dart';
import 'package:aupp/services/logger.dart';

/// The monthly and quarterly reports of every real estate fund, from the CVM's
/// open data (dados.cvm.gov.br), about 10 MB. Like the statements of the
/// companies, the zips stay on this device, out of the backup and the sync,
/// and are fetched again only when the CVM changes them.
class FiiStore extends ChangeNotifier {
  static final instance = FiiStore();
  static final _logger = Logger.withClass(FiiStore);
  static const _base = 'https://dados.cvm.gov.br/dados/FII/DOC';

  /// The monthly reports come by the middle of the next month.
  static const checkEvery = Duration(days: 3);

  /// Raised when the reading changes: the zips on disk are read again.
  static const format = 1;
  bool _outdated = false;

  Map<String, FiiFund> _funds = {};
  Map<String, String> _byRoot = {};
  Map<String, String>? _byName;
  DateTime? builtAt;

  String? progress;
  String? error;
  Future<void>? _running;

  @visibleForTesting
  Future<Directory> Function() folder = () async => Directory(
    p.join((await getApplicationSupportDirectory()).path, 'cvm-fii'),
  );

  @visibleForTesting
  http.Client Function() client = http.Client.new;

  bool get ready => _funds.isNotEmpty;
  bool get busy => _running != null;
  Iterable<FiiFund> get funds => _funds.values;

  /// The fund of a ticker, by the root of its ISIN ("KNRI" of BRKNRICTF007) or,
  /// when the ISIN is the CVM's code, by the name brapi gives it.
  FiiFund? byTicker(String ticker) {
    ticker = ticker.toUpperCase();
    if (ticker.length < 5) return null;
    final cnpj = _byRoot[ticker.substring(0, 4)];
    if (cnpj != null) return _funds[cnpj];
    final name = plainFundName(B3Market.funds[ticker]?.name);
    if (name == null) return null;
    _byName ??= {
      for (final f in _funds.values)
        if (plainFundName(f.name) case final plain?) plain: f.cnpj,
    };
    return _funds[_byName![name]];
  }

  @visibleForTesting
  void setForTest(Iterable<FiiFund> funds) {
    _set({for (final f in funds) f.cnpj: f});
    builtAt = DateTime.now();
  }

  void _set(Map<String, FiiFund> funds) {
    _funds = funds;
    // A root shared by two funds goes to the one with the newest report.
    final byRoot = <String, FiiFund>{};
    for (final fund in funds.values) {
      final isin = fund.isin;
      if (isin == null || isin.length < 6) continue;
      final root = isin.substring(2, 6);
      final known = byRoot[root];
      if (known == null || _newer(fund, known)) byRoot[root] = fund;
    }
    _byRoot = {for (final e in byRoot.entries) e.key: e.value.cnpj};
    _byName = null;
  }

  static bool _newer(FiiFund a, FiiFund b) {
    final ad = a.last?.date;
    final bd = b.last?.date;
    if (ad == null || bd == null) return bd == null && ad != null;
    if (ad != bd) return ad.isAfter(bd);
    return (a.last?.equity ?? 0) > (b.last?.equity ?? 0);
  }

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
      File(p.join((await folder()).path, 'funds.json'));

  Future<void> _loadSaved() async {
    try {
      final file = await _builtFile();
      if (!await file.exists()) return;
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      _set({
        for (final item in json['funds'] as List)
          (item as Map)['cnpj'] as String: FiiFund.fromJson(
            item.cast<String, dynamic>(),
          ),
      });
      builtAt = DateTime.tryParse(json['builtAt'] as String? ?? '');
      if (json['format'] != format) {
        _outdated = true;
        builtAt = null;
      }
      notifyListeners();
    } catch (e, st) {
      _logger.handle(e, st, 'Ignoring the saved funds');
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
      _say('Procurando os informes dos FIIs na CVM');
      final year = DateTime.now().year;
      final files = [
        for (final y in [year, year - 1, year - 2])
          (
            name: 'inf_mensal_fii_$y.zip',
            url: '$_base/INF_MENSAL/DADOS/inf_mensal_fii_$y.zip',
            label: 'informes mensais de $y',
          ),
        for (final y in [year, year - 1])
          (
            name: 'inf_trimestral_fii_$y.zip',
            url: '$_base/INF_TRIMESTRAL/DADOS/inf_trimestral_fii_$y.zip',
            label: 'informes trimestrais de $y',
          ),
      ];
      var changed = !ready || _outdated;
      final kept = <String>{};
      for (final (i, file) in files.indexed) {
        _say('Baixando ${file.label} (${i + 1} de ${files.length})');
        final path = File(p.join(dir.path, file.name));
        final head = await http_
            .head(Uri.parse(file.url))
            .timeout(const Duration(seconds: 30));
        // This year's zips only exist once the first reports come.
        if (head.statusCode == 404) continue;
        kept.add(file.name);
        final modified = head.headers['last-modified'];
        if (modified != null &&
            meta[file.name] == modified &&
            await path.exists()) {
          continue;
        }
        final response = await http_
            .get(Uri.parse(file.url))
            .timeout(const Duration(minutes: 3));
        if (response.statusCode != 200) {
          throw HttpException('${file.name}: HTTP ${response.statusCode}');
        }
        await path.writeAsBytes(response.bodyBytes);
        meta[file.name] = modified;
        changed = true;
      }
      await for (final entry in dir.list()) {
        final name = p.basename(entry.path);
        if (name.endsWith('.zip') && !kept.contains(name)) {
          await entry.delete();
          meta.remove(name);
        }
      }
      await metaFile.writeAsString(jsonEncode(meta));
      if (changed) {
        _say('Lendo os informes');
        final paths = [for (final name in kept) p.join(dir.path, name)];
        final built = await Isolate.run(
          () => buildFiiFunds(paths, format: format),
        );
        await (await _builtFile()).writeAsString(built);
        _outdated = false;
        final json = jsonDecode(built) as Map<String, dynamic>;
        _set({
          for (final item in json['funds'] as List)
            (item as Map)['cnpj'] as String: FiiFund.fromJson(
              item.cast<String, dynamic>(),
            ),
        });
      }
      builtAt = DateTime.now();
      final saved = await _builtFile();
      if (await saved.exists()) {
        final json = jsonDecode(await saved.readAsString()) as Map;
        json['builtAt'] = builtAt!.toIso8601String();
        await saved.writeAsString(jsonEncode(json));
      }
    } catch (e, st) {
      _logger.handle(e, st, 'Funds refresh failed');
      error = 'Não consegui atualizar os informes dos FIIs na CVM';
    } finally {
      http_.close();
    }
  }
}
