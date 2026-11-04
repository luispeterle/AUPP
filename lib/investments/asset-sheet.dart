import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:aupp/investments/b3-catalog.dart';
import 'package:aupp/investments/brapi-api.dart';
import 'package:aupp/investments/investments-analytics.dart';
import 'package:aupp/investments/investments-cache.dart';
import 'package:aupp/investments/sec-data.dart';
import 'package:aupp/investments/stock-catalog.dart';
import 'package:aupp/services/crypto-quote-service.dart';
import 'package:aupp/services/logger.dart';
import 'package:aupp/services/service-config.dart';
import 'package:aupp/settings/constants/preferences-keys.dart';

enum AssetKind { stock, fii, etf, crypto }

/// Names of the cryptocurrencies the app has quotes for ("BTC" → "Bitcoin").
Map<String, String> get cryptoNames => {
  for (final entry in CryptoQuoteService.coinIds.entries)
    entry.key: entry.value.isEmpty
        ? entry.key
        : entry.value[0].toUpperCase() + entry.value.substring(1),
};

bool isCryptoTicker(String ticker) =>
    CryptoQuoteService.coinIds.containsKey(ticker);

/// A ticker of the B3 ("PETR4", "TAEE11"); anything else is abroad.
bool isB3Ticker(String ticker) =>
    RegExp(r'^[A-Z][A-Z0-9]{3}\d{1,2}$').hasMatch(ticker.toUpperCase());

AssetKind? kindOfProduct(String? product) => switch (product) {
  'FII' => AssetKind.fii,
  'ETF' => AssetKind.etf,
  'Ações' => AssetKind.stock,
  'Cripto' => AssetKind.crypto,
  _ => null,
};

/// From the names in a quote, as neither source says what an asset is.
AssetKind kindFromNames(String? shortName, String? longName) {
  final names = '${shortName ?? ''} ${longName ?? ''}'.toUpperCase();
  if (names.contains('FII') ||
      names.contains('FIAGRO') ||
      names.contains('IMOBILI')) {
    return AssetKind.fii;
  }
  if (names.contains(' ETF') ||
      names.startsWith('ETF') ||
      names.contains('ISHARES') ||
      names.contains('IT NOW') ||
      names.contains('INDICE') ||
      names.contains('ÍNDICE')) {
    return AssetKind.etf;
  }
  return AssetKind.stock;
}

/// What an asset is: known for crypto and for what is held; otherwise by the
/// names in its quote.
Future<AssetKind> resolveAssetKind(String ticker, {AssetQuote? quote}) async {
  if (isCryptoTicker(ticker)) return AssetKind.crypto;
  final snapshot = await InvestmentsCache.load();
  for (final inv in snapshot?.investments ?? const []) {
    if (!inv.archived && StockCompany.tickerOf(inv) == ticker) {
      final kind = kindOfProduct(productOf(inv));
      if (kind != null) return kind;
    }
  }
  final found = quote ?? await AssetQuote.fetch(ticker, withHistory: false);
  return found == null
      ? AssetKind.stock
      : kindFromNames(found.shortName, found.longName);
}

/// Price and recent closes of an asset: brapi.dev for the B3, CoinGecko for
/// coins. Quotes can lag, so the sheet says where they come from and works
/// without them.
class AssetQuote {
  final String ticker;
  final double price;
  final double? changePct;
  final DateTime? at;
  final String? longName;
  final String? shortName;

  /// "USD" for a ticker abroad; the price is in this currency.
  final String currency;
  final List<(DateTime, double)> history;

  const AssetQuote({
    required this.ticker,
    required this.price,
    this.changePct,
    this.at,
    this.longName,
    this.shortName,
    this.currency = 'BRL',
    this.history = const [],
  });

  /// Null when the answer has no price. [history] comes in its own request.
  static AssetQuote? fromBrapiJson(
    String ticker,
    Map<String, dynamic> json, {
    List<(DateTime, double)> history = const [],
  }) {
    final data = _brapiData(json);
    final price = (data?['regularMarketPrice'] as num?)?.toDouble();
    if (data == null || price == null) return null;
    var changePct = (data['regularMarketChangePercent'] as num?)?.toDouble();
    if (changePct == null && history.length >= 2) {
      final previous = history[history.length - 2].$2;
      if (previous > 0) changePct = (price - previous) / previous * 100;
    }
    return AssetQuote(
      ticker: ticker,
      price: price,
      changePct: changePct,
      at: DateTime.tryParse(data['regularMarketTime'] as String? ?? '')?.toLocal(),
      longName: data['longName'] as String?,
      shortName: data['shortName'] as String?,
      currency: (data['currency'] as String?) ?? 'BRL',
      history: history,
    );
  }

  /// The closes of a brapi answer, skipping days without one.
  static List<(DateTime, double)> historyFromBrapiJson(
    Map<String, dynamic> json,
  ) => [
    for (final day
        in _brapiData(json)?['historicalDataPrice'] as List? ?? const [])
      if ((day as Map)['date'] is int && day['close'] is num)
        (
          DateTime.fromMillisecondsSinceEpoch((day['date'] as int) * 1000),
          (day['close'] as num).toDouble(),
        ),
  ];

  static Map? _brapiData(Map<String, dynamic> json) {
    final results = json['results'] as List?;
    return results == null || results.isEmpty
        ? null
        : (results.first as Map)['data'] as Map?;
  }

  /// CoinGecko's answer, for crypto.
  static AssetQuote? fromCoinGeckoJson(String ticker, Map<String, dynamic> json) {
    final prices = json['prices'] as List?;
    if (prices == null || prices.isEmpty) return null;
    final history = <(DateTime, double)>[
      for (final point in prices)
        (
          DateTime.fromMillisecondsSinceEpoch((point[0] as num).toInt()),
          (point[1] as num).toDouble(),
        ),
    ];
    final last = history.last;
    final previous = history.length >= 2 ? history[history.length - 2].$2 : null;
    return AssetQuote(
      ticker: ticker,
      price: last.$2,
      changePct: previous == null || previous <= 0
          ? null
          : (last.$2 - previous) / previous * 100,
      at: last.$1,
      history: history,
    );
  }

  /// The longest history the plan was seen to allow; the free one stops at 3
  /// months, and the answer says so.
  static String _historyRange = '1y';

  static Future<List<(DateTime, double)>> _brapiHistory(
    String ticker,
    http.Client client,
  ) async {
    Future<({int status, Map<String, dynamic>? body})> ask() => BrapiApi.get(
      client,
      'stocks/historical',
      {
        'symbols': ticker,
        'range': _historyRange,
        'interval': '1d',
        'sortOrder': 'asc',
      },
    );
    var answer = await ask();
    final notInPlan =
        answer.status == 403 || answer.body?['code'] == 'INVALID_RANGE';
    if (notInPlan && _historyRange != '3mo') {
      _historyRange = '3mo';
      answer = await ask();
    }
    return answer.status == 200 && answer.body != null
        ? historyFromBrapiJson(answer.body!)
        : const [];
  }

  /// Null without network or for an unknown ticker. Only the sheet draws the
  /// history, so everything else saves that request.
  static Future<AssetQuote?> fetch(
    String ticker, {
    http.Client? client,
    bool withHistory = true,
  }) async {
    final http.Client http_ = client ?? http.Client();
    try {
      if (isCryptoTicker(ticker)) {
        final response = await http_
            .get(
              Uri.parse(
                'https://api.coingecko.com/api/v3/coins/'
                '${CryptoQuoteService.coinIds[ticker]}/market_chart'
                '?vs_currency=brl&days=365&interval=daily',
              ),
            )
            .timeout(const Duration(seconds: 15));
        if (response.statusCode != 200) return null;
        return fromCoinGeckoJson(
          ticker,
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      }
      final answer = await BrapiApi.get(http_, 'stocks/quote', {
        'symbols': ticker,
      });
      if (answer.status != 200 || answer.body == null) return null;
      return fromBrapiJson(
        ticker,
        answer.body!,
        history: withHistory ? await _brapiHistory(ticker, http_) : const [],
      );
    } catch (e, st) {
      Logger.withClass(AssetQuote).handle(e, st, 'Quote of $ticker failed');
      return null;
    } finally {
      if (client == null) http_.close();
    }
  }
}

/// What a company does and where it is: setor first, then the company. From
/// brapi.dev; null when the plan or the ticker has none.
class AssetProfile {
  final String? sector;
  final String? industry;
  final String? summary;
  final Uri? website;

  const AssetProfile({this.sector, this.industry, this.summary, this.website});

  static AssetProfile? fromBrapiJson(Map<String, dynamic> json) {
    final results = json['results'] as List?;
    final data = results == null || results.isEmpty
        ? null
        : (results.first as Map)['data'] as Map?;
    if (data == null) return null;
    String? text(String key) {
      final value = (data[key] as String?)?.trim();
      return value == null || value.isEmpty ? null : value;
    }

    final site = text('website');
    final profile = AssetProfile(
      sector: text('sectorDisp') ?? text('sector'),
      industry: text('industryDisp') ?? text('industry'),
      summary: text('longBusinessSummary') ?? text('description'),
      website: site == null ? null : Uri.tryParse(site),
    );
    return profile.sector == null && profile.summary == null ? null : profile;
  }

  static Future<AssetProfile?> fetch(String ticker, {http.Client? client}) async {
    final http.Client http_ = client ?? http.Client();
    try {
      final answer = await BrapiApi.get(http_, 'stocks/profile', {
        'symbols': ticker,
      });
      return answer.status == 200 && answer.body != null
          ? fromBrapiJson(answer.body!)
          : null;
    } catch (e, st) {
      Logger.withClass(AssetProfile).handle(e, st, 'Profile of $ticker failed');
      return null;
    } finally {
      if (client == null) http_.close();
    }
  }
}

/// The day under the pointer in a chart of [count] days drawn over [width].
int chartIndexAt(double x, double width, int count) {
  if (count < 2 || width <= 0) return 0;
  return (x / width * (count - 1)).round().clamp(0, count - 1);
}

/// What the user wrote about an asset. Goes in the backup and to the other
/// devices (preference [PreferencesKeys.assetNotes]).
/// No price target: in Buy and Hold the price alone never decides.
class AssetNote {
  String thesis;
  String sellIf;

  AssetNote({this.thesis = '', this.sellIf = ''});

  bool get isEmpty => thesis.trim().isEmpty && sellIf.trim().isEmpty;

  Map<String, dynamic> toJson() => {
    if (thesis.isNotEmpty) 'thesis': thesis,
    if (sellIf.isNotEmpty) 'sellIf': sellIf,
  };

  factory AssetNote.fromJson(Map<String, dynamic> json) => AssetNote(
    thesis: json['thesis'] as String? ?? '',
    sellIf: json['sellIf'] as String? ?? '',
  );
}

/// All the notes.
class AssetNotes {
  final Map<String, AssetNote> notes;

  AssetNotes(this.notes);

  AssetNote of(String ticker) => notes.putIfAbsent(ticker, AssetNote.new);

  /// Tickers the user wrote something about.
  List<String> get tickers =>
      notes.entries.where((e) => !e.value.isEmpty).map((e) => e.key).toList()
        ..sort();

  static AssetNotes decode(String? raw) {
    if (raw == null || raw.isEmpty) return AssetNotes({});
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return AssetNotes({
        for (final e in (json['notes'] as Map? ?? const {}).entries)
          e.key as String: AssetNote.fromJson(
            (e.value as Map).cast<String, dynamic>(),
          ),
      });
    } catch (_) {
      return AssetNotes({});
    }
  }

  String encode() => jsonEncode({
    'notes': {
      for (final e in notes.entries)
        if (!e.value.isEmpty) e.key: e.value.toJson(),
    },
  });

  static AssetNotes load() => decode(
    ServiceConfig.sharedPreferences?.getString(PreferencesKeys.assetNotes),
  );

  Future<void> save() async => ServiceConfig.sharedPreferences?.setString(
    PreferencesKeys.assetNotes,
    encode(),
  );
}

/// What a purchase would do to the position, the "Investir" wallet and the
/// portfolio.
class PurchaseSimulation {
  final double cost;

  /// What is left in the wallet; negative when it does not cover the purchase.
  final double remaining;
  final double newQuantity;

  /// Null when the cost of what is already held is unknown.
  final double? newAverage;

  /// Share of the position in the portfolio after buying (0–100).
  final double sharePct;

  const PurchaseSimulation({
    required this.cost,
    required this.remaining,
    required this.newQuantity,
    required this.newAverage,
    required this.sharePct,
  });

  factory PurchaseSimulation.of({
    required double quantity,
    required double price,
    required double heldQuantity,
    required double? heldCost,
    required double positionValue,
    required double portfolioTotal,
    required double available,
  }) {
    final cost = quantity * price;
    final newQuantity = heldQuantity + quantity;
    final knownCost = heldQuantity <= 0 ? 0.0 : heldCost;
    final total = portfolioTotal + cost;
    return PurchaseSimulation(
      cost: cost,
      remaining: available - cost,
      newQuantity: newQuantity,
      newAverage: knownCost == null || newQuantity <= 0
          ? null
          : (knownCost + cost) / newQuantity,
      sharePct: total <= 0 ? 0 : (positionValue + cost) / total * 100,
    );
  }
}

/// A link of the shortcuts card.
class AssetLink {
  final String label;
  final Uri url;

  const AssetLink(this.label, this.url);
}

/// Icon of a site of [assetLinks] (assets/images/sites), by its label. Bundled
/// and not fetched: it shows offline, and no site learns what is being studied.
String? siteIcon(String label) => switch (label) {
  'AUVP Analítica' => 'assets/images/sites/auvp.png',
  'Fundamentus' => 'assets/images/sites/fundamentus.png',
  'RI da empresa' || 'Gestora' => 'assets/images/sites/ri.png',
  'CVM' => 'assets/images/sites/cvm.png',
  'SEC' => 'assets/images/sites/sec.png',
  'Notícias' => 'assets/images/sites/noticias.png',
  'Clube FII' => 'assets/images/sites/clubefii.png',
  'Funds Explorer' => 'assets/images/sites/fundsexplorer.png',
  'CoinGecko' => 'assets/images/sites/coingecko.png',
  'Mempool' => 'assets/images/sites/mempool.png',
  'TradingView' => 'assets/images/sites/tradingview.png',
  _ => null,
};

/// Where to read about an asset, by its kind. These sites have no API, so the
/// app takes the user to the right page instead of copying them.
List<AssetLink> assetLinks(
  String ticker,
  String? name, {
  AssetKind kind = AssetKind.stock,
}) {
  final lower = ticker.toLowerCase();
  final company = name ?? ticker;
  Uri search(String base, String query) =>
      Uri.https(base, '/search', {'q': query});
  final news = AssetLink(
    'Notícias',
    search('news.google.com', '$company $ticker'),
  );
  // Abroad: the US listings are in the AUVP's international pages and at the
  // SEC; another exchange has only news and its investor relations.
  if (kind != AssetKind.crypto && !isB3Ticker(ticker)) {
    final us = !ticker.contains('.');
    return [
      if (us)
        AssetLink(
          'AUVP Analítica',
          Uri.parse(
            'https://analitica.auvp.com.br/'
            '${kind == AssetKind.etf ? 'etfs' : 'stocks'}/$ticker',
          ),
        ),
      if (us)
        AssetLink(
          'SEC',
          // The new EDGAR page wants the company's number: given a ticker it
          // shows the last company seen. The classic one takes the ticker.
          switch (SecCatalog.instance[ticker]?.cik) {
            final cik? => Uri.parse('https://www.sec.gov/edgar/browse/?CIK=$cik'),
            null => Uri.https('www.sec.gov', '/cgi-bin/browse-edgar', {
              'action': 'getcompany',
              'CIK': ticker,
            }),
          },
        ),
      AssetLink(
        'RI da empresa',
        search('www.google.com', 'investor relations $company'),
      ),
      news,
    ];
  }
  final cvm = AssetLink(
    'CVM',
    Uri.parse('https://www.rad.cvm.gov.br/ENET/frmConsultaExternaCVM.aspx'),
  );
  switch (kind) {
    case AssetKind.stock:
      return [
        AssetLink(
          'AUVP Analítica',
          Uri.parse('https://analitica.auvp.com.br/acoes/$ticker'),
        ),
        AssetLink(
          'Fundamentus',
          Uri.parse('https://www.fundamentus.com.br/detalhes.php?papel=$ticker'),
        ),
        AssetLink(
          'RI da empresa',
          search('www.google.com', 'relações com investidores $company'),
        ),
        cvm,
        news,
      ];
    case AssetKind.fii:
      return [
        AssetLink(
          'AUVP Analítica',
          Uri.parse('https://analitica.auvp.com.br/fiis/$ticker'),
        ),
        AssetLink(
          'Funds Explorer',
          Uri.parse('https://www.fundsexplorer.com.br/funds/$lower'),
        ),
        AssetLink(
          'Clube FII',
          Uri.parse('https://www.clubefii.com.br/fiis/$ticker'),
        ),
        AssetLink(
          'Gestora',
          search('www.google.com', 'relatório gerencial $ticker $company'),
        ),
        news,
      ];
    case AssetKind.etf:
      return [
        AssetLink(
          'AUVP Analítica',
          Uri.parse('https://analitica.auvp.com.br/etfs/$ticker'),
        ),
        AssetLink(
          'TradingView',
          Uri.parse('https://br.tradingview.com/symbols/BMFBOVESPA-$ticker/'),
        ),
        AssetLink('Gestora', search('www.google.com', 'ETF $ticker $company')),
        news,
      ];
    case AssetKind.crypto:
      return [
        AssetLink(
          'CoinGecko',
          Uri.parse(
            'https://www.coingecko.com/pt/moedas/'
            '${CryptoQuoteService.coinIds[ticker] ?? lower}',
          ),
        ),
        AssetLink(
          'TradingView',
          Uri.parse('https://br.tradingview.com/symbols/${ticker}BRL/'),
        ),
        if (ticker == 'BTC')
          AssetLink('Mempool', Uri.parse('https://mempool.space/')),
        news,
      ];
  }
}

/// A search result: a full ticker, or a company whose share class is unknown.
class AssetSearchResult {
  final String? ticker;
  final String root;
  final String? name;

  const AssetSearchResult(this.root, this.name, {this.ticker});
}

final _fullTicker = RegExp(r'^[A-Z0-9]{4}\d{1,2}[A-Z]?$');

String _fold(String text) {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüç';
  const to = 'aaaaaeeeeiiiiooooouuuuc';
  final buffer = StringBuffer();
  for (final char in text.toLowerCase().split('')) {
    final index = from.indexOf(char);
    buffer.write(index < 0 ? char : to[index]);
  }
  return buffer.toString();
}

/// By ticker or company name, in the B3 catalogue. A typed ticker comes first
/// even when the catalogue does not know it.
List<AssetSearchResult> searchAssets(String query, {int limit = 30}) {
  final upper = query.trim().toUpperCase();
  if (upper.length < 2) return const [];
  final results = <AssetSearchResult>[];
  final foldedQuery = _fold(query.trim());
  for (final entry in cryptoNames.entries) {
    if (entry.key.startsWith(upper) || _fold(entry.value).contains(foldedQuery)) {
      results.add(AssetSearchResult(entry.key, entry.value, ticker: entry.key));
    }
  }
  if (_fullTicker.hasMatch(upper)) {
    final root = upper.substring(0, 4);
    results.add(
      AssetSearchResult(
        root,
        b3Catalog[root]?.$1,
        ticker: upper.replaceFirst(RegExp(r'[A-Z]$'), ''),
      ),
    );
  }
  final folded = _fold(query.trim());
  final byRoot = <AssetSearchResult>[];
  final byName = <AssetSearchResult>[];
  final taken = {for (final result in results) result.root};
  for (final entry in b3Catalog.entries) {
    if (taken.contains(entry.key)) continue;
    if (entry.key.startsWith(upper)) {
      byRoot.add(AssetSearchResult(entry.key, entry.value.$1));
    } else if (_fold(entry.value.$1 ?? '').contains(folded)) {
      byName.add(AssetSearchResult(entry.key, entry.value.$1));
    }
  }
  return [...results, ...byRoot, ...byName].take(limit).toList();
}

/// Tickers of a company that exist, as most only trade in some share classes.
Future<List<String>> tickersOfRoot(String root, {http.Client? client}) async {
  const classes = ['3', '4', '11', '5', '6'];
  final quotes = await Future.wait([
    for (final suffix in classes)
      AssetQuote.fetch('$root$suffix', client: client, withHistory: false),
  ]);
  return [
    for (final quote in quotes)
      if (quote != null) quote.ticker,
  ];
}
