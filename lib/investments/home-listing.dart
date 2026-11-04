import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:aupp/investments/asset-sheet.dart';
import 'package:aupp/investments/cvm-statements.dart';
import 'package:aupp/services/logger.dart';

/// Exchange rates of the Banco Central (PTAX, Olinda API): reais per unit of a
/// currency, at the last closing of the last ten days.
class Fx {
  static const currencies = {
    'AUD', 'CAD', 'CHF', 'DKK', 'EUR', 'GBP', 'JPY', 'NOK', 'SEK', 'USD',
  };
  static final _logger = Logger.withClass(Fx);
  static final _rates = <String, (DateTime, double)>{};

  @visibleForTesting
  static http.Client Function() client = http.Client.new;

  @visibleForTesting
  static void setForTest(Map<String, double> rates) {
    _rates
      ..clear()
      ..addAll({
        for (final e in rates.entries) e.key: (DateTime.now(), e.value),
      });
  }

  static bool supports(String currency) =>
      currency == 'BRL' || currencies.contains(currency);

  /// Reais per unit; 1 for reais, null for a currency the PTAX lacks.
  static Future<double?> brlPer(String currency) async {
    if (currency == 'BRL') return 1;
    if (!currencies.contains(currency)) return null;
    final known = _rates[currency];
    if (known != null && DateTime.now().difference(known.$1).inHours < 12) {
      return known.$2;
    }
    final format = DateFormat('MM-dd-yyyy');
    final now = DateTime.now();
    final url =
        'https://olinda.bcb.gov.br/olinda/servico/PTAX/versao/v1/odata/'
        'CotacaoMoedaPeriodo(moeda=@moeda,dataInicial=@dataInicial,'
        'dataFinalCotacao=@dataFinalCotacao)?@moeda=%27$currency%27'
        '&@dataInicial=%27${format.format(now.subtract(const Duration(days: 10)))}%27'
        '&@dataFinalCotacao=%27${format.format(now)}%27&\$format=json';
    final http_ = client();
    try {
      final response = await http_
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return known?.$2;
      final values = (jsonDecode(response.body) as Map)['value'] as List;
      final closings = [
        for (final v in values)
          if ((v as Map)['tipoBoletim'] == 'Fechamento') v,
      ];
      final last = (closings.isNotEmpty ? closings : values).lastOrNull as Map?;
      final rate = (last?['cotacaoVenda'] as num?)?.toDouble();
      if (rate == null) return known?.$2;
      _rates[currency] = (now, rate);
      return rate;
    } catch (e, st) {
      _logger.handle(e, st, 'PTAX of $currency failed');
      return known?.$2;
    } finally {
      http_.close();
    }
  }

  /// How many [to] one [from] buys; null when either is missing.
  static Future<double?> rate(String from, String to) async {
    if (from == to) return 1;
    final a = await brlPer(from);
    final b = await brlPer(to);
    return a == null || b == null ? null : a / b;
  }
}

/// A listing found by OpenFIGI's search: any exchange in the world.
class FigiListing {
  final String name;
  final String ticker;
  final String exchange;

  const FigiListing(this.name, this.ticker, this.exchange);

  /// Bloomberg's exchange codes → the suffix brapi (and Yahoo) uses.
  static const suffixes = {
    'GY': '.DE', 'GR': '.DE', 'LN': '.L', 'FP': '.PA', 'NA': '.AS',
    'SM': '.MC', 'IM': '.MI', 'SW': '.SW', 'SE': '.SW', 'JT': '.T',
    'JP': '.T', 'TT': '.TW', 'HK': '.HK', 'CT': '.TO', 'CN': '.TO',
    'AT': '.AX', 'AU': '.AX', 'SS': '.ST', 'NO': '.OL', 'DC': '.CO',
    'FH': '.HE', 'BB': '.BR', 'KS': '.KS', 'ID': '.IR', 'PL': '.LS',
    'AV': '.VI',
  };

  /// Exchanges by name, to show.
  static const exchangeNames = {
    'GY': 'Xetra (Alemanha)', 'GR': 'Alemanha', 'LN': 'Londres',
    'FP': 'Paris', 'NA': 'Amsterdã', 'SM': 'Madri', 'IM': 'Milão',
    'SW': 'Suíça', 'SE': 'Suíça', 'JT': 'Tóquio', 'JP': 'Japão',
    'TT': 'Taiwan', 'HK': 'Hong Kong', 'CT': 'Toronto', 'CN': 'Canadá',
    'AT': 'Austrália', 'AU': 'Austrália', 'SS': 'Estocolmo', 'NO': 'Oslo',
    'DC': 'Copenhague', 'FH': 'Helsinque', 'BB': 'Bruxelas',
    'KS': 'Coreia', 'ID': 'Dublin', 'PL': 'Lisboa', 'AV': 'Viena',
  };

  /// The exchanges where a company reporting in a currency usually trades.
  static const homeExchanges = {
    'EUR': ['GY', 'NA', 'FP', 'SM', 'IM', 'BB', 'FH', 'ID', 'PL', 'AV'],
    'JPY': ['JT'], 'DKK': ['DC'], 'GBP': ['LN'], 'TWD': ['TT'],
    'HKD': ['HK'], 'CNY': ['HK'], 'CHF': ['SW', 'SE'], 'SEK': ['SS'],
    'NOK': ['NO'], 'CAD': ['CT', 'CN'], 'AUD': ['AT', 'AU'], 'KRW': ['KS'],
    'USD': ['LN', 'NA', 'SW', 'HK', 'CT'],
  };

  /// What to ask brapi: "SIE.DE", and "NOVO-B.CO" for Bloomberg's "NOVOB".
  List<String> get symbols {
    final suffix = suffixes[exchange];
    if (suffix == null) return const [];
    final base = ticker.replaceAll('/', '-').replaceAll(' ', '');
    return [
      '$base$suffix',
      if (RegExp(r'^[A-Z]{3,}[AB]$').hasMatch(base))
        '${base.substring(0, base.length - 1)}-${base[base.length - 1]}$suffix',
    ];
  }
}

/// OpenFIGI's search (api.openfigi.com), without a key: a few requests a
/// minute, so each answer is kept.
class OpenFigi {
  static final _logger = Logger.withClass(OpenFigi);
  static final _cache = <String, List<FigiListing>>{};

  @visibleForTesting
  static http.Client Function() client = http.Client.new;

  /// "TT (Taiwan Stock Exchange)", as some come, → "TT".
  static String _code(Object? exchange) =>
      (exchange as String? ?? '').split(' ').first;

  @visibleForTesting
  static List<FigiListing> parse(Map<String, dynamic> json) => [
    for (final item in json['data'] as List? ?? const [])
      if ((item as Map)['securityType2'] == 'Common Stock' &&
          FigiListing.suffixes.containsKey(_code(item['exchCode'])))
        FigiListing(
          item['name'] as String? ?? '',
          item['ticker'] as String? ?? '',
          _code(item['exchCode']),
        ),
  ];

  /// Common stocks named like [query] on the exchanges brapi quotes; null
  /// when OpenFIGI did not answer (its limit, or no network), which is not
  /// the same as finding nothing.
  static Future<List<FigiListing>?> search(
    String query, {
    String? exchange,
  }) async {
    final text = query.trim().toUpperCase();
    if (text.length < 2) return const [];
    final key = '$text|${exchange ?? ''}';
    final known = _cache[key];
    if (known != null) return known;
    final http_ = client();
    try {
      Future<http.Response> ask() => http_
          .post(
            Uri.parse('https://api.openfigi.com/v3/search'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'query': text,
              'securityType2': 'Common Stock',
              'exchCode': ?exchange,
            }),
          )
          .timeout(const Duration(seconds: 20));
      var response = await ask();
      // Over the limit: waits a short reset out, once.
      final reset = int.tryParse(response.headers['ratelimit-reset'] ?? '');
      if (response.statusCode == 429 && reset != null && reset <= 20) {
        await Future<void>.delayed(Duration(seconds: reset + 1));
        response = await ask();
      }
      if (response.statusCode != 200) {
        _logger.warning('Search "$text": HTTP ${response.statusCode}');
        return null;
      }
      final found = parse(jsonDecode(response.body) as Map<String, dynamic>);
      // One per company and exchange.
      final seen = <String>{};
      return _cache[key] = [
        for (final f in found)
          if (seen.add('${f.name}|${f.exchange}')) f,
      ];
    } catch (e, st) {
      _logger.handle(e, st, 'OpenFIGI search failed');
      return null;
    } finally {
      http_.close();
    }
  }
}

/// A price per ordinary share, in the currency of the company's statements.
class SharePrice {
  /// What was quoted: the US ticker, or the home one ("7203.T").
  final String symbol;
  final double price;
  final String currency;

  /// How many ordinary shares an ADR stands for, from both prices; null when
  /// the US ticker is the share itself.
  final double? adrShares;

  const SharePrice(this.symbol, this.price, this.currency, {this.adrShares});
}

/// The price that goes with the statements of a company filing with the SEC.
/// A US company: its own ticker. A foreign one: its ADR may stand for several
/// shares, so the price comes from its home exchange, in the currency of its
/// statements, and the ADR's ratio is shown to be checked.
class HomeListing {
  static final _logger = Logger.withClass(HomeListing);

  @visibleForTesting
  static Future<File> Function() file = () async => File(
    p.join((await getApplicationSupportDirectory()).path, 'home-listings.json'),
  );

  @visibleForTesting
  static Future<AssetQuote?> Function(String symbol) quote = (symbol) =>
      AssetQuote.fetch(symbol, withHistory: false);

  static Map<String, dynamic>? _saved;

  static Future<Map<String, dynamic>> _load() async {
    if (_saved != null) return _saved!;
    try {
      final saved = await file();
      _saved = await saved.exists()
          ? (jsonDecode(await saved.readAsString()) as Map).cast<String, dynamic>()
          : {};
    } catch (_) {
      _saved = {};
    }
    return _saved!;
  }

  static Future<void> _remember(String key, String? symbol) async {
    final saved = await _load();
    saved[key] = {'symbol': symbol, 'at': DateTime.now().toIso8601String()};
    try {
      await (await file()).writeAsString(jsonEncode(saved));
    } catch (_) {}
  }

  /// "TOYOTA MOTOR CORP/" → "TOYOTA MOTOR"; "SAP SE" → "SAP".
  @visibleForTesting
  static String searchName(String name) {
    var plain = name.toUpperCase().replaceAll(RegExp(r'/[A-Z]{2}/?$'), '');
    plain = plain.replaceAll(RegExp(r'[^A-Z0-9 ]'), ' ');
    const tails = {
      'INC', 'CORP', 'CORPORATION', 'CO', 'LTD', 'LIMITED', 'PLC', 'SE',
      'AG', 'NV', 'N', 'V', 'SA', 'S', 'A', 'AS', 'AB', 'ASA', 'OYJ', 'SPA',
      'HOLDING', 'HOLDINGS', 'GROUP', 'THE', 'ADR', 'ADS',
    };
    final words = plain.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    while (words.length > 1 && tails.contains(words.last)) {
      words.removeLast();
    }
    return words.take(3).join(' ');
  }

  /// [quote]'s price in [currency], or null when no PTAX rate converts it.
  static Future<double?> _inCurrency(AssetQuote quote, String currency) async {
    var price = quote.price;
    var from = quote.currency;
    // London quotes in pence.
    if (from == 'GBp' || from == 'GBX') {
      price /= 100;
      from = 'GBP';
    }
    final rate = await Fx.rate(from, currency);
    return rate == null ? null : price * rate;
  }

  static Future<SharePrice?> priceFor(
    CvmCompany company,
    String usTicker,
  ) async {
    final us = await quote(usTicker);
    if (!company.foreignIssuer) {
      if (us == null) return null;
      final price = await _inCurrency(us, company.currency);
      return price == null
          ? null
          : SharePrice(usTicker, price, company.currency);
    }
    final key = company.code;
    final saved = (await _load())[key] as Map?;
    String? symbol = saved?['symbol'] as String?;
    final at = DateTime.tryParse(saved?['at'] as String? ?? '');
    final stale = at == null || DateTime.now().difference(at).inDays > 30;
    AssetQuote? home;
    if (symbol != null && !stale) {
      home = await quote(symbol);
    } else if (saved == null || stale) {
      final (found, quoted, answered) = await _find(company);
      (symbol, home) = (found, quoted);
      // Only a real answer is kept: a refused search is asked again later.
      if (answered) await _remember(key, symbol);
    }
    if (home == null || symbol == null) return null;
    final price = await _inCurrency(home, company.currency);
    if (price == null) return null;
    double? ratio;
    if (us != null) {
      final adr = await _inCurrency(us, company.currency);
      if (adr != null && price > 0) ratio = adr / price;
    }
    return SharePrice(symbol, price, company.currency, adrShares: ratio);
  }

  /// The home listing: OpenFIGI's results on the exchanges of the currency of
  /// the statements, the first one brapi quotes in a convertible currency.
  static Future<(String?, AssetQuote?, bool)> _find(CvmCompany company) async {
    final name = searchName(company.name);
    final first = name.split(' ').first;
    // Asked exchange by exchange: a search across all of them returns one
    // page, which may not reach Tokyo or Taipei.
    for (final exchange in (FigiListing.homeExchanges[company.currency] ??
            const <String>[])
        .take(3)) {
      final found = await OpenFigi.search(name, exchange: exchange);
      if (found == null) return (null, null, false);
      for (final candidate in found) {
        if (!candidate.name.toUpperCase().startsWith(first)) continue;
        for (final symbol in candidate.symbols) {
          final q = await quote(symbol);
          if (q == null || q.price <= 0) continue;
          if (await _inCurrency(q, company.currency) == null) continue;
          return (symbol, q, true);
        }
      }
    }
    _logger.info('No home listing for ${company.name}');
    return (null, null, true);
  }
}
