import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:aupp/investments/sec-data.dart';
import 'package:aupp/services/logger.dart';

/// A position of an ETF: share of its net assets (0.05 = 5%).
class EtfHolding {
  final String name;
  final double share;

  const EtfHolding(this.name, this.share);

  Map<String, dynamic> toJson() => {'n': name, 's': share};

  static EtfHolding fromJson(Map<String, dynamic> json) =>
      EtfHolding(json['n'] as String, (json['s'] as num).toDouble());
}

/// What an ETF of the United States reports to the SEC each quarter (N-PORT):
/// net assets, the return of each month and every position.
class EtfReport {
  final String series;
  final String name;

  /// The end of the month of the positions.
  final DateTime date;

  /// In dollars.
  final double netAssets;

  /// Total return of each month (0.01 = 1%), oldest first.
  final List<(DateTime, double)> months;
  final List<EtfHolding> top;
  final int positions;

  /// Share of the net assets by kind of asset ("Ações") and by country
  /// ("Estados Unidos"), largest first.
  final List<(String, double)> byKind;
  final List<(String, double)> byCountry;

  /// Share classes of the fund: with more than one (Vanguard), the ETF is one
  /// of them and [netAssets] is the whole fund's.
  final int classes;
  final DateTime fetchedAt;

  const EtfReport({
    required this.series,
    required this.name,
    required this.date,
    required this.netAssets,
    required this.months,
    required this.top,
    required this.positions,
    required this.byKind,
    required this.byCountry,
    this.classes = 1,
    required this.fetchedAt,
  });

  /// Compounded over the last [count] months reported; null when fewer.
  double? returnOver(int count) {
    if (months.length < count) return null;
    var total = 1.0;
    for (final (_, r) in months.sublist(months.length - count)) {
      total *= 1 + r;
    }
    return total - 1;
  }

  /// Share of the ten largest positions.
  double get topTen => top.take(10).fold(0, (sum, h) => sum + h.share);

  Map<String, dynamic> toJson() => {
    'series': series,
    'name': name,
    'date': date.toIso8601String(),
    'netAssets': netAssets,
    'months': [
      for (final (d, r) in months) [d.toIso8601String(), r],
    ],
    'top': [for (final h in top) h.toJson()],
    'positions': positions,
    'byKind': [
      for (final (k, s) in byKind) [k, s],
    ],
    'byCountry': [
      for (final (c, s) in byCountry) [c, s],
    ],
    'classes': classes,
    'fetchedAt': fetchedAt.toIso8601String(),
  };

  static EtfReport fromJson(Map<String, dynamic> json) {
    List<(String, double)> shares(String key) => [
      for (final item in json[key] as List)
        ((item as List)[0] as String, (item[1] as num).toDouble()),
    ];
    return EtfReport(
      series: json['series'] as String,
      name: json['name'] as String,
      date: DateTime.parse(json['date'] as String),
      netAssets: (json['netAssets'] as num).toDouble(),
      months: [
        for (final item in json['months'] as List)
          (
            DateTime.parse((item as List)[0] as String),
            (item[1] as num).toDouble(),
          ),
      ],
      top: [
        for (final item in json['top'] as List)
          EtfHolding.fromJson((item as Map).cast<String, dynamic>()),
      ],
      positions: json['positions'] as int,
      byKind: shares('byKind'),
      byCountry: shares('byCountry'),
      classes: json['classes'] as int? ?? 1,
      fetchedAt: DateTime.parse(json['fetchedAt'] as String),
    );
  }
}

/// One N-PORT, as read.
@visibleForTesting
class NportFiling {
  final String name;
  final DateTime date;
  final double netAssets;
  final List<(DateTime, double)> months;
  final Map<String, double> holdings;
  final Map<String, double> byKind;
  final Map<String, double> byCountry;
  final int positions;
  final int classes;

  const NportFiling({
    required this.name,
    required this.date,
    required this.netAssets,
    required this.months,
    required this.holdings,
    required this.byKind,
    required this.byCountry,
    required this.positions,
    this.classes = 1,
  });
}

const _kinds = {
  'EC': 'Ações',
  'EP': 'Ações preferenciais',
  'DBT': 'Títulos de dívida',
  'STIV': 'Caixa e aplicações curtas',
  'RF': 'Fundos registrados',
  'LON': 'Empréstimos',
  'RE': 'Imóveis',
  'COMM': 'Commodities',
  'RA': 'Acordos de recompra',
};

const _countries = {
  'US': 'Estados Unidos',
  'BR': 'Brasil',
  'CN': 'China',
  'JP': 'Japão',
  'GB': 'Reino Unido',
  'CA': 'Canadá',
  'FR': 'França',
  'DE': 'Alemanha',
  'CH': 'Suíça',
  'NL': 'Países Baixos',
  'IE': 'Irlanda',
  'TW': 'Taiwan',
  'KR': 'Coreia do Sul',
  'IN': 'Índia',
  'AU': 'Austrália',
  'HK': 'Hong Kong',
  'SE': 'Suécia',
  'DK': 'Dinamarca',
  'IT': 'Itália',
  'ES': 'Espanha',
  'MX': 'México',
  'SG': 'Singapura',
  'KY': 'Ilhas Cayman',
  'BM': 'Bermudas',
  'LU': 'Luxemburgo',
  'IL': 'Israel',
  'ZA': 'África do Sul',
  'AR': 'Argentina',
};

String _unescape(String text) => text
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&#39;', "'")
    .trim();

String? _tag(String xml, String tag) {
  final match = RegExp('<$tag(?:\\s[^>]*)?>([^<]*)</$tag>').firstMatch(xml);
  return match == null ? null : _unescape(match.group(1)!);
}

/// The N-PORTs of a series, newest first, from the SEC's Atom feed: links to
/// the original filings (amendments left out).
@visibleForTesting
List<Uri> nportFilings(String atom) {
  final out = <Uri>[];
  for (final entry in RegExp(
    r'<entry>(.*?)</entry>',
    dotAll: true,
  ).allMatches(atom).map((m) => m.group(1)!)) {
    if (_tag(entry, 'filing-type') != 'NPORT-P') continue;
    final href = _tag(entry, 'filing-href');
    if (href == null) continue;
    out.add(
      Uri.parse(
        '${href.substring(0, href.lastIndexOf('/') + 1)}'
        'primary_doc.xml',
      ),
    );
  }
  return out;
}

/// A fund at the SEC: "S000004310", or with the class of the ticker,
/// "S000002839:C000092055" (a series with several classes reports the return
/// of each; the ETF is one of them).
({String series, String? share}) _idOf(String fund) {
  final parts = fund.split(':');
  return (series: parts.first, share: parts.length > 1 ? parts[1] : null);
}

/// Reads an N-PORT (primary_doc.xml), with the returns of the class [share]
/// (the first one when not given). Null when it is not one.
@visibleForTesting
NportFiling? readNport(String xml, {String? share}) {
  final name = _tag(xml, 'seriesName');
  final date = DateTime.tryParse(_tag(xml, 'repPdDate') ?? '');
  final netAssets = double.tryParse(_tag(xml, 'netAssets') ?? '');
  if (name == null || date == null || netAssets == null) return null;
  // The three months of the quarter that ends at [date]: rtn1 the first.
  final months = <(DateTime, double)>[];
  final classes = RegExp(r'<monthlyTotReturn\b([^>]*)/?>').allMatches(xml);
  final returns =
      classes
          .where((m) => share != null && m.group(1)!.contains('"$share"'))
          .firstOrNull ??
      classes.firstOrNull;
  if (returns != null) {
    for (var i = 1; i <= 3; i++) {
      final value = RegExp('rtn$i="([^"]*)"').firstMatch(returns.group(1)!);
      final r = double.tryParse(value?.group(1) ?? '');
      if (r == null) continue;
      months.add((DateTime(date.year, date.month - 3 + i + 1, 0), r / 100));
    }
  }
  final holdings = <String, double>{};
  final byKind = <String, double>{};
  final byCountry = <String, double>{};
  var positions = 0;
  for (final m in RegExp(
    r'<invstOrSec>(.*?)</invstOrSec>',
    dotAll: true,
  ).allMatches(xml)) {
    final block = m.group(1)!;
    final share = (double.tryParse(_tag(block, 'pctVal') ?? '') ?? 0) / 100;
    positions++;
    final holding = _tag(block, 'name') ?? _tag(block, 'title') ?? '—';
    holdings[holding] = (holdings[holding] ?? 0) + share;
    final kindCode =
        _tag(block, 'assetCat') ??
        RegExp(r'<assetConditional\b[^>]*assetCat="([^"]*)"')
            .firstMatch(block)
            ?.group(1);
    final kind =
        _kinds[kindCode] ??
        (kindCode != null && kindCode.startsWith('D')
            ? 'Derivativos'
            : 'Outros');
    byKind[kind] = (byKind[kind] ?? 0) + share;
    final code = _tag(block, 'invCountry');
    final country = code == null ? 'Outros' : (_countries[code] ?? code);
    byCountry[country] = (byCountry[country] ?? 0) + share;
  }
  return NportFiling(
    name: name,
    date: date,
    netAssets: netAssets,
    months: months,
    holdings: holdings,
    byKind: byKind,
    byCountry: byCountry,
    positions: positions,
    classes: classes.isEmpty ? 1 : classes.length,
  );
}

List<(String, double)> _largest(Map<String, double> shares, int count) {
  final sorted = shares.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return [for (final e in sorted.take(count)) (e.key, e.value)];
}

/// The latest N-PORT and the returns of the three before it: a year of months.
@visibleForTesting
EtfReport reportOf(String series, List<NportFiling> filings, DateTime now) {
  final latest = filings.first;
  final months = <DateTime, double>{};
  for (final filing in filings) {
    for (final (date, r) in filing.months) {
      months.putIfAbsent(date, () => r);
    }
  }
  final sorted = months.keys.toList()..sort();
  return EtfReport(
    series: series,
    name: latest.name,
    date: latest.date,
    netAssets: latest.netAssets,
    months: [for (final d in sorted) (d, months[d]!)],
    top: [
      for (final (name, share) in _largest(latest.holdings, 15))
        EtfHolding(name, share),
    ],
    positions: latest.positions,
    byKind: _largest(latest.byKind, 8),
    byCountry: _largest(latest.byCountry, 8),
    classes: latest.classes,
    fetchedAt: now,
  );
}

/// Ticker → "series:class", from the SEC's company_tickers_mf.json.
@visibleForTesting
Map<String, String> parseFundTickers(String body) {
  final json = jsonDecode(body) as Map<String, dynamic>;
  final fields = (json['fields'] as List).cast<String>();
  final series = fields.indexOf('seriesId');
  final share = fields.indexOf('classId');
  final symbol = fields.indexOf('symbol');
  return {
    for (final row in json['data'] as List)
      if ((row as List)[symbol] is String && row[series] is String)
        (row[symbol] as String).toUpperCase(): row[share] is String
            ? '${row[series]}:${row[share]}'
            : row[series],
  };
}

/// The reports of the ETFs abroad (each BDR of an ETF knows its series), from
/// the SEC: kept on this device and fetched again after [keepFor].
class SecFundStore {
  static final instance = SecFundStore();
  static final _logger = Logger.withClass(SecFundStore);
  static const keepFor = Duration(days: 15);

  final _memory = <String, EtfReport?>{};
  final _pending = <String, Future<EtfReport?>>{};

  @visibleForTesting
  Future<Directory> Function() folder = () async => Directory(
    p.join((await getApplicationSupportDirectory()).path, 'sec-funds'),
  );

  @visibleForTesting
  http.Client Function() client = http.Client.new;

  EtfReport? cached(String fund) => _memory[fund];

  Map<String, String>? _seriesByTicker;

  Future<void>? _fundTickers;

  /// The SEC's list of fund tickers, kept for a month: fetched once, then
  /// [fundOf] answers at once. [force] fetches it again.
  Future<void> ensureFundTickers({bool force = false}) {
    if (_seriesByTicker != null && !force) return Future.value();
    return _fundTickers ??= _loadFundTickers(force).whenComplete(() {
      _fundTickers = null;
    });
  }

  Future<void> _loadFundTickers(bool force) async {
    final file = File(p.join((await folder()).path, 'fund-tickers.json'));
    String? body;
    try {
      if (!force &&
          await file.exists() &&
          DateTime.now().difference(await file.lastModified()) <
              const Duration(days: 30)) {
        body = await file.readAsString();
      } else {
        final http_ = client();
        try {
          final response = await http_
              .get(
                Uri.parse('https://www.sec.gov/files/company_tickers_mf.json'),
                headers: secHeaders,
              )
              .timeout(const Duration(seconds: 60));
          if (response.statusCode == 200) {
            body = response.body;
            await file.parent.create(recursive: true);
            await file.writeAsString(body);
          }
        } finally {
          http_.close();
        }
      }
    } catch (e, st) {
      _logger.handle(e, st, 'SEC fund tickers failed');
    }
    try {
      // Offline: last month's list.
      if (body == null && await file.exists()) {
        body = await file.readAsString();
      }
      if (body != null) _seriesByTicker = parseFundTickers(body);
    } catch (e, st) {
      _logger.handle(e, st, 'SEC fund tickers unreadable');
    }
  }

  /// The series and class of a fund listed in the United States ("VOO" →
  /// S000002839:C000092055), once [ensureFundTickers] is done; null when not
  /// a fund (or not loaded).
  String? fundOf(String ticker) => _seriesByTicker?[ticker.toUpperCase()];

  Future<String?> seriesOf(String ticker) async {
    await ensureFundTickers();
    return fundOf(ticker);
  }

  /// The series with a report on this device.
  Future<Set<String>> saved() async {
    final dir = await folder();
    if (!await dir.exists()) return {};
    return {
      await for (final entry in dir.list())
        if (entry.path.endsWith('.json'))
          p.basenameWithoutExtension(entry.path).replaceAll('_', ':'),
    };
  }

  /// [fund] is a series, or "series:class" (see [readNport]). Null when the
  /// SEC has no N-PORT of it (an ETF of crypto or of another country does not
  /// file one).
  Future<EtfReport?> load(String fund) {
    if (_memory.containsKey(fund)) return Future.value(_memory[fund]);
    return _pending[fund] ??= _load(fund).whenComplete(() {
      _pending.remove(fund);
    });
  }

  Future<EtfReport?> _load(String fund) async {
    final file = File(
      p.join((await folder()).path, '${fund.replaceAll(':', '_')}.json'),
    );
    EtfReport? saved;
    try {
      if (await file.exists()) {
        saved = EtfReport.fromJson(
          jsonDecode(await file.readAsString()) as Map<String, dynamic>,
        );
        if (DateTime.now().difference(saved.fetchedAt) < keepFor) {
          return _memory[fund] = saved;
        }
      }
    } catch (e, st) {
      _logger.handle(e, st, 'Ignoring the saved report of $fund');
    }
    final fetched = await _fetch(fund);
    if (fetched != null) {
      try {
        await file.parent.create(recursive: true);
        await file.writeAsString(jsonEncode(fetched.toJson()));
      } catch (e, st) {
        _logger.handle(e, st, 'Report of $fund not saved');
      }
    }
    // Offline: the old report is better than none. Nothing at all (the SEC
    // did not answer) is not kept: the next opening asks again.
    final report = fetched ?? saved;
    if (report != null) _memory[fund] = report;
    return report;
  }

  Future<EtfReport?> _fetch(String fund) async {
    final (:series, :share) = _idOf(fund);
    final http_ = client();
    try {
      final feed = await http_
          .get(
            Uri.https('www.sec.gov', '/cgi-bin/browse-edgar', {
              'action': 'getcompany',
              'CIK': series,
              'type': 'NPORT-P',
              'owner': 'include',
              'count': '8',
              'output': 'atom',
            }),
            headers: secHeaders,
          )
          .timeout(const Duration(seconds: 30));
      if (feed.statusCode != 200) return null;
      final filings = <NportFiling>[];
      for (final url in nportFilings(feed.body).take(4)) {
        final response = await http_
            .get(url, headers: secHeaders)
            .timeout(const Duration(minutes: 2));
        if (response.statusCode != 200) continue;
        final filing = readNport(utf8.decode(response.bodyBytes), share: share);
        if (filing != null) filings.add(filing);
      }
      if (filings.isEmpty) return null;
      return reportOf(fund, filings, DateTime.now());
    } catch (e, st) {
      _logger.handle(e, st, 'N-PORT of $series failed');
      return null;
    } finally {
      http_.close();
    }
  }
}
