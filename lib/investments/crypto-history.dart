import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:aupp/demo/demo-mode.dart';

/// Period shown in the crypto charts.
enum CryptoRange {
  year('12 meses', 366),
  all('Desde o início', null);

  final String label;

  /// Null: from the first purchase.
  final int? days;

  const CryptoRange(this.label, this.days);
}

/// Price history of one coin in the main currency.
class CryptoSeries {
  /// One close per day (last ~2 years).
  final List<MapEntry<DateTime, double>> daily;

  /// One close per week (many years).
  final List<MapEntry<DateTime, double>> weekly;

  CryptoSeries(this.daily, this.weekly);

  /// Points for [range] ending at [now]: daily over a year; from [since] on
  /// (everything there is, without it), weekly before the daily ones begin.
  List<MapEntry<DateTime, double>> pointsFor(
    CryptoRange range,
    DateTime now, {
    DateTime? since,
  }) {
    final days = range.days;
    if (days != null) {
      final from = now.subtract(Duration(days: days));
      return [
        for (final p in daily)
          if (!p.key.isBefore(from)) p,
      ];
    }
    final firstDaily = daily.isEmpty ? null : daily.first.key;
    return [
      for (final p in [
        for (final w in weekly)
          if (firstDaily == null || w.key.isBefore(firstDaily)) w,
        ...daily,
      ])
        if (since == null || !p.key.isBefore(since)) p,
    ];
  }

  Map<String, dynamic> toJson() => {
    'daily': _encode(daily),
    'weekly': _encode(weekly),
  };

  factory CryptoSeries.fromJson(Map<String, dynamic> json) =>
      CryptoSeries(_decode(json['daily']), _decode(json['weekly']));

  static List<List<num>> _encode(List<MapEntry<DateTime, double>> points) => [
    for (final p in points) [p.key.millisecondsSinceEpoch, p.value],
  ];

  static List<MapEntry<DateTime, double>> _decode(dynamic raw) => [
    for (final p in (raw as List? ?? const []).cast<List>())
      MapEntry(
        DateTime.fromMillisecondsSinceEpoch((p[0] as num).toInt()),
        (p[1] as num).toDouble(),
      ),
  ];
}

/// Free price history (fork, 2026-10-12): Kraken's public OHLC in USD
/// (CoinGecko's free tier stops at 365 days) and the Central Bank's daily
/// dollar rate (SGS 1) to show it in reais. Cached on disk, refreshed every
/// few hours.
class CryptoHistory {
  static const krakenPairs = {
    'BTC': 'XBTUSD',
    'ETH': 'ETHUSD',
    'XMR': 'XMRUSD',
    'SOL': 'SOLUSD',
    'LTC': 'LTCUSD',
    'USDT': 'USDTUSD',
  };

  static const Duration maxAge = Duration(hours: 6);
  static const int _dailyMinutes = 1440, _weeklyMinutes = 10080;

  /// Prices in dollars, per coin.
  final Map<String, CryptoSeries> usd;

  /// Reais per dollar, per business day.
  final List<MapEntry<DateTime, double>> usdBrl;
  final DateTime fetchedAt;

  CryptoHistory(this.usd, this.usdBrl, this.fetchedAt);

  final Map<String, CryptoSeries> _converted = {};

  /// [code]'s prices in [currency] (USD or BRL), or null without history.
  CryptoSeries? seriesIn(String code, String currency) {
    final raw = usd[code];
    if (raw == null) return null;
    if (currency == 'USD') return raw;
    if (currency != 'BRL') return null;
    return _converted[code] ??= CryptoSeries(
      convert(raw.daily, usdBrl),
      convert(raw.weekly, usdBrl),
    );
  }

  static bool supports(String code) =>
      krakenPairs.containsKey(code.toUpperCase());

  static Future<File> _file() async => File(
    join((await DemoMode.supportDirectory()).path, 'crypto_history.json'),
  );

  /// Cached history for [codes], fetched again when older than [maxAge] or
  /// when [force]. Falls back to the cache when offline.
  static Future<CryptoHistory> load(
    List<String> codes, {
    bool force = false,
  }) async {
    final wanted = codes.where(supports).toList();
    final cached = await readCache();
    final fresh =
        cached != null &&
        DateTime.now().difference(cached.fetchedAt) < maxAge &&
        wanted.every(cached.usd.containsKey);
    if (wanted.isEmpty || (fresh && !force)) {
      return cached ?? CryptoHistory({}, [], DateTime.now());
    }
    try {
      final result = await _fetch(wanted);
      final file = await _file();
      await file.writeAsString(
        jsonEncode({
          'fetchedAt': result.fetchedAt.toIso8601String(),
          'usd': {for (final e in result.usd.entries) e.key: e.value.toJson()},
          'usdBrl': CryptoSeries._encode(result.usdBrl),
        }),
      );
      return result;
    } catch (_) {
      if (cached != null) return cached;
      rethrow;
    }
  }

  /// The history on disk, without fetching (null when there is none).
  static Future<CryptoHistory?> readCache() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (json['usd'] == null) return null; // older format
      return CryptoHistory(
        {
          for (final e in (json['usd'] as Map<String, dynamic>).entries)
            e.key: CryptoSeries.fromJson(e.value as Map<String, dynamic>),
        },
        CryptoSeries._decode(json['usdBrl']),
        DateTime.parse(json['fetchedAt'] as String),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<CryptoHistory> _fetch(List<String> codes) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final now = DateTime.now();
      final usdBrl = parseBcbSeries(
        await _get(
          client,
          Uri.parse(
            'https://api.bcb.gov.br/dados/serie/bcdata.sgs.1/dados'
            '?formato=json&dataInicial=${_br(DateTime(now.year - 9, 1, 1))}'
            '&dataFinal=${_br(now)}',
          ),
        ),
      );
      final usd = <String, CryptoSeries>{};
      for (final code in codes) {
        Future<List<MapEntry<DateTime, double>>> candles(int minutes) async =>
            parseKrakenOhlc(
              await _get(
                client,
                Uri.https('api.kraken.com', '/0/public/OHLC', {
                  'pair': krakenPairs[code.toUpperCase()]!,
                  'interval': '$minutes',
                }),
              ),
            );
        usd[code] = CryptoSeries(
          await candles(_dailyMinutes),
          await candles(_weeklyMinutes),
        );
      }
      return CryptoHistory(usd, usdBrl, now);
    } finally {
      client.close();
    }
  }

  static Future<String> _get(HttpClient client, Uri uri) async {
    final request = await client.getUrl(uri);
    final response = await request.close().timeout(const Duration(seconds: 30));
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
    return body;
  }

  static String _br(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// Closes from Kraken's `OHLC` response (`[time, open, high, low, close,
  /// …]` rows under the pair's own key).
  @visibleForTesting
  static List<MapEntry<DateTime, double>> parseKrakenOhlc(String body) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final errors = (json['error'] as List?) ?? const [];
    if (errors.isNotEmpty) throw HttpException('Kraken: ${errors.join(', ')}');
    final result = json['result'] as Map<String, dynamic>;
    final rows =
        result.entries.firstWhere((e) => e.key != 'last').value as List;
    // Candles open at 00:00 UTC: keep that calendar day (in Brazil the
    // local time would fall on the evening before).
    DateTime day(num seconds) {
      final t = DateTime.fromMillisecondsSinceEpoch(
        seconds.toInt() * 1000,
        isUtc: true,
      );
      return DateTime(t.year, t.month, t.day);
    }

    return [
      for (final row in rows.cast<List>())
        MapEntry(day(row[0] as num), double.parse(row[4].toString())),
    ];
  }

  /// Daily rates from the Central Bank's SGS (`[{data: dd/MM/yyyy, valor}]`).
  @visibleForTesting
  static List<MapEntry<DateTime, double>> parseBcbSeries(String body) {
    final result = <MapEntry<DateTime, double>>[];
    for (final row in (jsonDecode(body) as List).cast<Map<String, dynamic>>()) {
      final parts = (row['data'] as String).split('/');
      result.add(
        MapEntry(
          DateTime(
            int.parse(parts[2]),
            int.parse(parts[1]),
            int.parse(parts[0]),
          ),
          double.parse(row['valor'].toString()),
        ),
      );
    }
    result.sort((a, b) => a.key.compareTo(b.key));
    return result;
  }

  /// [usd] prices times the latest [rate] on or before each date (weekends
  /// and holidays use the previous business day). Points before the first
  /// rate are dropped.
  @visibleForTesting
  static List<MapEntry<DateTime, double>> convert(
    List<MapEntry<DateTime, double>> usd,
    List<MapEntry<DateTime, double>> rate,
  ) {
    final result = <MapEntry<DateTime, double>>[];
    var i = -1;
    for (final p in usd) {
      final day = DateTime(p.key.year, p.key.month, p.key.day);
      while (i + 1 < rate.length && !rate[i + 1].key.isAfter(day)) {
        i++;
      }
      if (i >= 0) result.add(MapEntry(p.key, p.value * rate[i].value));
    }
    return result;
  }
}
