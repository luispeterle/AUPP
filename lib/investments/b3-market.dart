import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:aupp/investments/brapi-api.dart';
import 'package:aupp/services/logger.dart';

/// A stock of the B3 in brapi's list.
class MarketRow {
  final String ticker;
  final String name;
  final double price;
  final double? changePct;
  final double volume;
  final double? marketCap;

  /// brapi's sector ("Energy Minerals") and subsector ("Petróleo e Gás
  /// Integrado").
  final String? sector;
  final String? subsector;

  const MarketRow({
    required this.ticker,
    required this.name,
    required this.price,
    this.changePct,
    this.volume = 0,
    this.marketCap,
    this.sector,
    this.subsector,
  });

  /// Null without a price, and for the fractional market (PETR4F).
  static MarketRow? fromJson(Map<String, dynamic> json) {
    final ticker = (json['stock'] as String?)?.toUpperCase();
    final price = (json['close'] as num?)?.toDouble();
    if (ticker == null || price == null || price <= 0) return null;
    if (RegExp(r'\dF$').hasMatch(ticker)) return null;
    String? text(String key) {
      final value = (json[key] as String?)?.trim();
      return value == null || value.isEmpty ? null : value;
    }

    return MarketRow(
      ticker: ticker,
      name: text('name') ?? ticker,
      price: price,
      changePct: (json['change'] as num?)?.toDouble(),
      volume: (json['volume'] as num?)?.toDouble() ?? 0,
      marketCap: (json['market_cap'] as num?)?.toDouble(),
      sector: text('sector'),
      subsector: text('subsector'),
    );
  }
}

/// brapi's sectors in Portuguese.
String? sectorLabel(String? sector) => switch (sector) {
  null => null,
  'Finance' => 'Financeiro',
  'Utilities' => 'Utilidade pública',
  'Producer Manufacturing' => 'Bens industriais',
  'Process Industries' => 'Indústria de transformação',
  'Retail Trade' => 'Varejo',
  'Non-Energy Minerals' => 'Mineração e siderurgia',
  'Transportation' => 'Transporte',
  'Consumer Durables' => 'Bens duráveis',
  'Commercial Services' => 'Serviços comerciais',
  'Consumer Non-Durables' => 'Bens de consumo não duráveis',
  'Industrial Services' => 'Serviços industriais',
  'Distribution Services' => 'Distribuição',
  'Health Services' => 'Serviços de saúde',
  'Consumer Services' => 'Serviços ao consumidor',
  'Technology Services' => 'Serviços de tecnologia',
  'Communications' => 'Comunicações',
  'Energy Minerals' => 'Petróleo, gás e combustíveis',
  'Health Technology' => 'Tecnologia em saúde',
  'Electronic Technology' => 'Tecnologia eletrônica',
  'Miscellaneous' => 'Outros',
  _ => sector,
};

/// Every stock of the B3 with its last price, from one request to brapi's
/// list (the free plan quotes one ticker per request, the list has them all).
/// Kept on disk for when there is no network.
class B3Market extends ChangeNotifier {
  static final instance = B3Market();

  /// The real estate funds (brapi's "fund" list, subtype "fii").
  static final funds = B3Market(type: 'fund', subType: 'fii');
  static final _logger = Logger.withClass(B3Market);
  static const freshFor = Duration(minutes: 20);

  B3Market({this.type = 'stock', this.subType}) {
    final name = type == 'stock' ? 'b3-market.json' : 'b3-$type.json';
    file = () async =>
        File(p.join((await getApplicationSupportDirectory()).path, name));
  }

  final String type;
  final String? subType;
  Map<String, MarketRow> _rows = {};
  DateTime? fetchedAt;
  Future<void>? _running;

  @visibleForTesting
  late Future<File> Function() file;

  @visibleForTesting
  http.Client Function() client = http.Client.new;

  MarketRow? operator [](String ticker) => _rows[ticker.toUpperCase()];
  Iterable<MarketRow> get rows => _rows.values;
  Map<String, double> get prices => {
    for (final row in _rows.values) row.ticker: row.price,
  };

  @visibleForTesting
  void setForTest(Iterable<MarketRow> rows) {
    _rows = {for (final row in rows) row.ticker: row};
    fetchedAt = DateTime.now();
  }

  /// The tickers of the same subsector, then those of the same sector, each
  /// most traded first. brapi leaves most subsectors empty and writes some in
  /// two ways ("Exploração. Refino" and "Exploração, Refino").
  List<MarketRow> peersOf(String ticker) {
    final row = this[ticker];
    if (row == null) return const [];
    String? plain(String? text) =>
        text?.toLowerCase().replaceAll('.', ',').replaceAll(RegExp(r'\s+'), ' ');
    final subsector = plain(row.subsector);
    final same = <MarketRow>[];
    final near = <MarketRow>[];
    for (final other in _rows.values) {
      if (subsector != null && plain(other.subsector) == subsector) {
        same.add(other);
      } else if (row.sector != null && other.sector == row.sector) {
        near.add(other);
      }
    }
    int byVolume(MarketRow a, MarketRow b) => b.volume.compareTo(a.volume);
    return [...same..sort(byVolume), ...near..sort(byVolume)];
  }

  static Map<String, MarketRow> parse(
    Map<String, dynamic> json, {
    String? subType,
  }) => {
    for (final item in json['stocks'] as List? ?? const [])
      if (subType == null || (item as Map)['subType'] == subType)
        if (MarketRow.fromJson((item as Map).cast<String, dynamic>())
            case final row?)
          row.ticker: row,
  };

  Future<void> ensure({bool force = false}) async {
    if (_rows.isEmpty) await _loadSaved();
    final at = fetchedAt;
    if (!force && at != null && DateTime.now().difference(at) < freshFor) {
      return;
    }
    return _running ??= _fetch().whenComplete(() => _running = null);
  }

  Future<void> _loadSaved() async {
    try {
      final saved = await file();
      if (!await saved.exists()) return;
      final json = jsonDecode(await saved.readAsString()) as Map<String, dynamic>;
      _rows = parse(json, subType: subType);
      // Old prices are shown, but asked again right away.
      fetchedAt = null;
      notifyListeners();
    } catch (e, st) {
      _logger.handle(e, st, 'Ignoring the saved list');
    }
  }

  Future<void> _fetch() async {
    final http_ = client();
    try {
      final token = BrapiApi.key;
      final response = await http_
          .get(
            Uri.https('brapi.dev', '/api/quote/list', {
              'type': type,
              'limit': '10000',
            }),
            headers: {if (token != null) 'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        _logger.warning('List: HTTP ${response.statusCode}');
        return;
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final rows = parse(json, subType: subType);
      if (rows.isEmpty) return;
      _rows = rows;
      fetchedAt = DateTime.now();
      await (await file()).writeAsString(response.body);
      notifyListeners();
    } catch (e, st) {
      _logger.handle(e, st, 'List failed');
    } finally {
      http_.close();
    }
  }
}
