import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:aupp/services/service-config.dart';
import 'package:aupp/settings/constants/preferences-keys.dart';

/// Client-side budget for the Dinzo API (fork, 2026-10-12). Dinzo allows 120
/// requests a minute; the app keeps to [perMinute] so a big investment
/// portfolio (one request per position) never hits the wall. Requests over
/// the budget wait in line. The recent requests are kept in preferences, so
/// closing and reopening the app doesn't reset the count.
class DinzoRateLimiter {
  static const int perMinute = 80;
  static const Duration window = Duration(minutes: 1);

  /// What Dinzo itself allows (RateLimit-Policy).
  static const int serverPerMinute = 120;
  static const int serverPerDay = 5000;

  static final List<int> _sent = [];

  /// Requests per minute (epoch minute → count) over the last 24 h: Dinzo
  /// doesn't report the daily quota left, so it is counted here (this
  /// device only).
  static final Map<int, int> _daily = {};
  static bool _loaded = false;
  static Future<void> _queue = Future.value();

  /// Bumped on every request, so the settings counter redraws.
  static final ValueNotifier<int> changes = ValueNotifier(0);

  static void _load() {
    if (_loaded) return;
    _loaded = true;
    final prefs = ServiceConfig.sharedPreferences;
    final raw = prefs?.getString(PreferencesKeys.dinzoRequestLog);
    if (raw != null) _sent.addAll((jsonDecode(raw) as List).cast<int>());
    final daily = prefs?.getString(PreferencesKeys.dinzoRequestDaily);
    if (daily != null) {
      (jsonDecode(daily) as Map<String, dynamic>).forEach(
        (k, v) => _daily[int.parse(k)] = v as int,
      );
    }
  }

  /// Requests in the last minute (this device).
  static int get lastMinute {
    _load();
    final now = DateTime.now().millisecondsSinceEpoch;
    return _sent.where((t) => now - t < window.inMilliseconds).length;
  }

  /// Requests in the last 24 h (this device).
  static int get last24h {
    _load();
    final minute = DateTime.now().millisecondsSinceEpoch ~/ 60000;
    return _daily.entries
        .where((e) => minute - e.key < 1440)
        .fold(0, (s, e) => s + e.value);
  }

  /// Requests left this minute as Dinzo last reported (any device).
  static int? get serverRemaining =>
      ServiceConfig.sharedPreferences?.getInt(
        PreferencesKeys.dinzoServerRemaining,
      );

  /// Reads `RateLimit: "default";r=119;t=60` from a response.
  static Future<void> recordServer(String? header) async {
    final r = RegExp(r'r=(\d+)').firstMatch(header ?? '')?.group(1);
    if (r == null) return;
    await ServiceConfig.sharedPreferences?.setInt(
      PreferencesKeys.dinzoServerRemaining,
      int.parse(r),
    );
    changes.value++;
  }

  /// How long to wait before one more request, given the send times
  /// (epoch ms) of the recent ones.
  @visibleForTesting
  static Duration waitFor(List<int> sent, int nowMs, {int limit = perMinute}) {
    final recent = sent.where((t) => nowMs - t < window.inMilliseconds).toList()
      ..sort();
    if (recent.length < limit) return Duration.zero;
    final freeAt = recent[recent.length - limit] + window.inMilliseconds;
    return Duration(milliseconds: freeAt - nowMs);
  }

  /// Waits for a free slot and books it. Calls are served in order.
  static Future<void> acquire() {
    final next = _queue.then((_) => _take());
    _queue = next.catchError((_) {});
    return next;
  }

  static Future<void> _take() async {
    final prefs = ServiceConfig.sharedPreferences;
    _load();
    final wait = waitFor(_sent, DateTime.now().millisecondsSinceEpoch);
    if (wait > Duration.zero) await Future.delayed(wait);
    final now = DateTime.now().millisecondsSinceEpoch;
    _sent
      ..removeWhere((t) => now - t >= window.inMilliseconds)
      ..add(now);
    final minute = now ~/ 60000;
    _daily
      ..removeWhere((k, _) => minute - k >= 1440)
      ..update(minute, (c) => c + 1, ifAbsent: () => 1);
    await prefs?.setString(PreferencesKeys.dinzoRequestLog, jsonEncode(_sent));
    await prefs?.setString(
      PreferencesKeys.dinzoRequestDaily,
      jsonEncode(_daily.map((k, v) => MapEntry('$k', v))),
    );
    changes.value++;
  }

  /// Until when Dinzo refused us (daily quota): nothing is sent before it.
  static DateTime? get blockedUntil => DateTime.tryParse(
    ServiceConfig.sharedPreferences?.getString(
          PreferencesKeys.dinzoBlockedUntil,
        ) ??
        '',
  );

  static Future<void> block(Duration retryAfter) async {
    await ServiceConfig.sharedPreferences?.setString(
      PreferencesKeys.dinzoBlockedUntil,
      DateTime.now().add(retryAfter).toIso8601String(),
    );
  }
}
