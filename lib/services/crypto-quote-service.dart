import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:aupp/services/database/sqlite-database.dart';
import 'package:aupp/services/logger.dart';
import 'package:aupp/services/service-config.dart';
import 'package:aupp/settings/constants/preferences-keys.dart';
import 'package:aupp/investments/asset-lots.dart';

/// The coin's logo, for the codes the app quotes; null for anything else.
String? cryptoLogoOf(String? code) {
  final upper = code?.toUpperCase();
  return CryptoQuoteService.coinIds.containsKey(upper)
      ? 'assets/images/crypto/${upper!.toLowerCase()}.png'
      : null;
}

/// Market quotes for the coins held (fork). Prices come from CoinGecko's public
/// API (free, no key).
class CryptoQuoteService {
  static final _logger = Logger.withClass(CryptoQuoteService);

  /// ISO code → CoinGecko coin id.
  static const coinIds = {
    'BTC': 'bitcoin',
    'ETH': 'ethereum',
    'XMR': 'monero',
    'SOL': 'solana',
    'USDT': 'tether',
    'LTC': 'litecoin',
  };

  /// Opening the app again within this time keeps the last quotes.
  static const Duration minInterval = Duration(minutes: 15);

  static Future<bool>? _running;

  static bool isQuoted(String? code) =>
      code != null && coinIds.containsKey(code.toUpperCase());

  static DateTime? get lastUpdate {
    final ms = ServiceConfig.sharedPreferences?.getInt(
      PreferencesKeys.cryptoQuotesUpdatedAt,
    );
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Fetches the quotes when the last ones are older than [minInterval]
  /// (always with [force]). Returns whether any were fetched; failures are
  /// logged and keep the previous quotes.
  static Future<bool> refresh({bool force = false}) {
    return _running ??= _refresh(force).whenComplete(() => _running = null);
  }

  static Future<bool> _refresh(bool force) async {
    final codes = AssetLots.coins.keys.toList();
    if (codes.isEmpty) return false;
    final last = lastUpdate;
    // A coin without a price in reais (bought just now, or quotes left by an
    // older app, which kept them elsewhere) is worth nothing until fetched.
    final missing = codes.any((code) => priceInMain(code) == null);
    if (!force &&
        !missing &&
        last != null &&
        DateTime.now().difference(last) < minInterval) {
      return false;
    }
    try {
      final body = await _get(
        Uri.https('api.coingecko.com', '/api/v3/simple/price', {
          'ids': codes.map((c) => coinIds[c.toUpperCase()]).join(','),
          'vs_currencies': 'brl,usd',
        }),
      );
      final prices = parsePrices(body, codes, 'BRL');
      final usd = parsePrices(body, codes, 'USD');
      final prefs = ServiceConfig.sharedPreferences!;
      if (usd.isNotEmpty) {
        await prefs.setString(PreferencesKeys.cryptoQuotesUsd, jsonEncode(usd));
      }
      if (prices.isEmpty) return false;
      await prefs.setString(
        PreferencesKeys.cryptoQuotesMain,
        jsonEncode(prices),
      );
      await prefs.setInt(
        PreferencesKeys.cryptoQuotesUpdatedAt,
        DateTime.now().millisecondsSinceEpoch,
      );
      // Screens that show balances reload on database changes.
      SqliteDatabase.dataChangeNotifier.value++;
      _logger.info('Crypto quotes in BRL: $prices');
      return true;
    } catch (e, st) {
      _logger.handle(e, st, 'Failed to fetch crypto quotes');
      return false;
    }
  }

  /// Price of one unit of each of [codes] in [main], from CoinGecko's
  /// `simple/price` response. Missing or invalid entries are left out.
  @visibleForTesting
  static Map<String, double> parsePrices(
    String body,
    List<String> codes,
    String main,
  ) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final result = <String, double>{};
    for (final code in codes) {
      final coin = json[coinIds[code.toUpperCase()]];
      final price = coin is Map ? coin[main.toLowerCase()] : null;
      if (price is num && price > 0) result[code] = price.toDouble();
    }
    return result;
  }

  static Future<String> _get(Uri uri) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throw HttpException('CoinGecko ${response.statusCode}', uri: uri);
      }
      return body;
    } finally {
      client.close();
    }
  }

  /// Last dollar price of one [code] (null before the first fetch).
  static double? usdPrice(String code) {
    final raw = ServiceConfig.sharedPreferences?.getString(
      PreferencesKeys.cryptoQuotesUsd,
    );
    if (raw == null) return null;
    try {
      return ((jsonDecode(raw) as Map)[code.toUpperCase()] as num?)?.toDouble();
    } catch (_) {
      return null;
    }
  }

  /// Last price of one [code] in reais (null before the first fetch).
  static double? priceInMain(String code) {
    final raw = ServiceConfig.sharedPreferences?.getString(
      PreferencesKeys.cryptoQuotesMain,
    );
    if (raw == null) return null;
    try {
      return ((jsonDecode(raw) as Map)[code.toUpperCase()] as num?)?.toDouble();
    } catch (_) {
      return null;
    }
  }
}
