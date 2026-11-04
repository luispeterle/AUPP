import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart';
import 'package:aupp/demo/demo-mode.dart';
import 'package:aupp/services/logger.dart';

/// Daily Selic and CDI rates from the Brazilian Central Bank's public SGS
/// API (no key). Cached on the device and topped up at most once a day.
class BenchmarkRates {
  /// Day → daily rate as a fraction (0.00050788 = 0,050788% a.d.).
  final Map<DateTime, double> selic;
  final Map<DateTime, double> cdi;

  /// First day of the month → IPCA of the month as a fraction (SGS 433).
  final Map<DateTime, double> ipca;
  final DateTime fetchedAt;

  BenchmarkRates(this.selic, this.cdi, this.fetchedAt, {this.ipca = const {}});

  /// Inflation from the month after [from] to [to], as a fraction: what money
  /// must earn just to keep its purchasing power. Months not published yet
  /// count nothing.
  static double inflationBetween(
    Map<DateTime, double> ipca,
    DateTime from,
    DateTime to,
  ) {
    var factor = 1.0;
    for (final e in ipca.entries) {
      final month = e.key;
      if (month.isAfter(DateTime(from.year, from.month)) &&
          !month.isAfter(DateTime(to.year, to.month))) {
        factor *= 1 + e.value;
      }
    }
    return factor - 1;
  }

  static final _logger = Logger.withClass(BenchmarkRates);
  static const _fileName = 'bcb_rates.json';
  static const _selicSeries = 11;
  static const _cdiSeries = 12;
  static const _ipcaSeries = 433;
  static const _dollarSeries = 1;
  static double? _dollar;

  /// Today's dollar in reais (PTAX, SGS 1), once per run. Null offline.
  static Future<double?> dollar() async {
    if (_dollar != null) return _dollar;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final now = DateTime.now();
      final rates = await _series(
        client,
        _dollarSeries,
        now.subtract(const Duration(days: 10)),
        now,
      );
      if (rates.isEmpty) return null;
      final last = rates.keys.reduce((a, b) => a.isAfter(b) ? a : b);
      // _series reads percentages; the dollar is a price.
      return _dollar = rates[last]! * 100;
    } catch (e, st) {
      _logger.handle(e, st, 'Dollar rate failed');
      return null;
    } finally {
      client.close();
    }
  }

  /// Rate of [day], or the last published one for a business day the bank
  /// has not published yet (it lags a day or two); 0 on weekends.
  static double rateOn(Map<DateTime, double> rates, DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    final known = rates[d];
    if (known != null) return known;
    if (d.weekday > DateTime.friday || rates.isEmpty) return 0;
    final last = rates.keys.reduce((a, b) => a.isAfter(b) ? a : b);
    return d.isAfter(last) ? rates[last]! : 0;
  }

  static Future<File> _file() async {
    final dir = await DemoMode.supportDirectory();
    return File(join(dir.path, _fileName));
  }

  static Map<DateTime, double> _decode(Map<String, dynamic> json) => {
    for (final e in json.entries)
      DateTime.parse(e.key): (e.value as num).toDouble(),
  };

  static Map<String, double> _encode(Map<DateTime, double> m) => {
    for (final e in m.entries)
      e.key.toIso8601String().substring(0, 10): e.value,
  };

  static Future<BenchmarkRates?> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return BenchmarkRates(
        _decode(json['selic'] as Map<String, dynamic>),
        _decode(json['cdi'] as Map<String, dynamic>),
        DateTime.parse(json['fetchedAt'] as String),
        ipca: _decode(json['ipca'] as Map<String, dynamic>? ?? const {}),
      );
    } catch (e, st) {
      _logger.handle(e, st, 'Failed to read the benchmark cache');
      return null;
    }
  }

  /// Rates from [from] to today, reusing the cache when it is from today.
  static Future<BenchmarkRates> ensure(DateTime from) async {
    final cached = await load();
    final now = DateTime.now();
    final start = DateTime(from.year, from.month, from.day);
    if (cached != null &&
        now.difference(cached.fetchedAt) < const Duration(hours: 20) &&
        cached.ipca.isNotEmpty &&
        cached.cdi.keys.any(
          (d) => !d.isAfter(start.add(const Duration(days: 5))),
        )) {
      return cached;
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final rates = BenchmarkRates(
        await _series(client, _selicSeries, start, now),
        await _series(client, _cdiSeries, start, now),
        now,
        ipca: await _series(client, _ipcaSeries, start, now),
      );
      final file = await _file();
      await file.writeAsString(
        jsonEncode({
          'selic': _encode(rates.selic),
          'cdi': _encode(rates.cdi),
          'ipca': _encode(rates.ipca),
          'fetchedAt': now.toIso8601String(),
        }),
      );
      return rates;
    } finally {
      client.close();
    }
  }

  static String _br(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  static Future<Map<DateTime, double>> _series(
    HttpClient client,
    int series,
    DateTime from,
    DateTime to,
  ) async {
    final uri = Uri.parse(
      'https://api.bcb.gov.br/dados/serie/bcdata.sgs.$series/dados'
      '?formato=json&dataInicial=${_br(from)}&dataFinal=${_br(to)}',
    );
    final request = await client.getUrl(uri);
    final response = await request.close().timeout(const Duration(seconds: 60));
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw HttpException('BCB ${response.statusCode}', uri: uri);
    }
    final result = <DateTime, double>{};
    for (final row in (jsonDecode(body) as List).cast<Map<String, dynamic>>()) {
      final parts = (row['data'] as String).split('/');
      result[DateTime(
            int.parse(parts[2]),
            int.parse(parts[1]),
            int.parse(parts[0]),
          )] =
          double.parse(row['valor'] as String) / 100;
    }
    return result;
  }
}
