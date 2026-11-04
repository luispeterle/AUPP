import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:aupp/services/logger.dart';
import 'package:aupp/services/service-config.dart';
import 'package:aupp/settings/constants/preferences-keys.dart';

/// Client for https://brapi.dev. The user's key stays on this device, out of the
/// backups and the sync, like the Dinzo's. Without it only the sandbox tickers
/// answer.
class BrapiApi {
  static final _logger = Logger.withClass(BrapiApi);

  /// Until when the API asked to wait (429).
  static DateTime? _blockedUntil;

  /// A wait this short is waited out and the request goes again: a page asks
  /// for several quotes at once and the limit lasts a second.
  static const _shortWait = Duration(seconds: 5);

  static String? get key =>
      ServiceConfig.sharedPreferences?.getString(PreferencesKeys.brapiApiKey);

  static Future<void> setKey(String? key) async {
    final prefs = ServiceConfig.sharedPreferences!;
    if (key == null || key.trim().isEmpty) {
      await prefs.remove(PreferencesKeys.brapiApiKey);
    } else {
      await prefs.setString(PreferencesKeys.brapiApiKey, key.trim());
    }
  }

  /// A GET on /api/v2. The body is null when it is not JSON or nothing was sent.
  static Future<({int status, Map<String, dynamic>? body})> get(
    http.Client client,
    String path,
    Map<String, String> query, {
    int retries = 2,
  }) async {
    final blocked = _blockedUntil;
    if (blocked != null) {
      final left = blocked.difference(DateTime.now());
      if (left > _shortWait) return (status: 429, body: null);
      if (left > Duration.zero) await Future<void>.delayed(left);
    }
    final token = key;
    final response = await client
        .get(
          Uri.https('brapi.dev', '/api/v2/$path', query),
          headers: {if (token != null) 'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 401) {
      _logger.warning('Key missing or invalid');
    } else if (response.statusCode == 429) {
      final wait = int.tryParse(response.headers['retry-after'] ?? '') ?? 60;
      _blockedUntil = DateTime.now().add(Duration(seconds: wait));
      _logger.warning('Limit reached, waiting ${wait}s');
      if (retries > 0 && Duration(seconds: wait) <= _shortWait) {
        return get(client, path, query, retries: retries - 1);
      }
    }
    Map<String, dynamic>? body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {}
    return (status: response.statusCode, body: body);
  }

  /// Forgets a wait, for the tests.
  static void resetForTests() => _blockedUntil = null;
}
