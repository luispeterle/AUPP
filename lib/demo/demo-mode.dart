import 'package:flutter/foundation.dart' show visibleForTesting;
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:aupp/dashboard/dashboard-data.dart';
import 'package:aupp/demo/demo-data.dart';
import 'package:aupp/investments/investments-cache.dart';
import 'package:aupp/services/backup-service.dart';
import 'package:aupp/services/category-hierarchy.dart';
import 'package:aupp/services/logger.dart';
import 'package:aupp/services/preferences-backup-service.dart';
import 'package:aupp/services/service-config.dart';
import 'package:aupp/services/sync-extensions.dart';
import 'package:aupp/settings/constants/preferences-keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Demo mode (fork, 2026-10-14): typing [code] and "C" on the disguise
/// calculator restarts the app on made-up data ([DemoData]), to show the app
/// without the real balances.
///
/// The demo never shares a process with the real app: entering, leaving and
/// re-entering it restart the app. A demo start keeps everything apart:
/// preferences under their own prefix, its own database folder and its own
/// cache folder. Every entry wipes and rebuilds it, so nothing done in the
/// demo survives, and a demo start is one-shot: the next start (app killed,
/// phone restarted) is the real app again.
///
/// Nothing in the demo talks to the Dinzo or other syncs, and it writes no
/// backups, database copies or home-screen widgets. Public market data
/// (crypto quotes, Selic/CDI) still loads, it carries nothing personal.
class DemoMode {
  static final _logger = Logger.withClass(DemoMode);

  static const code = '123';

  /// Whether this process runs the demo. Set once, by [bootstrap].
  static bool active = false;

  /// Whether this start comes right after the right code was typed, so the
  /// calculator must not ask again.
  static bool startUnlocked = false;

  static const _prefsPrefix = 'auppDemo.';
  static const _folder = 'demo';
  static const _markerName = 'next_start.json';

  /// A marker older than this is ignored (the restart did not happen).
  static const _markerMaxAge = Duration(minutes: 2);

  static const _appChannel = MethodChannel('aupp/app');

  /// Looks for the marker left by the code typed before the restart. Must run
  /// before the first `SharedPreferences.getInstance()`.
  static Future<void> bootstrap() async {
    try {
      final marker = await _marker();
      if (!await marker.exists()) return;
      final json =
          jsonDecode(await marker.readAsString()) as Map<String, dynamic>;
      await marker.delete();
      final at = DateTime.fromMillisecondsSinceEpoch(json['at'] as int);
      if (DateTime.now().difference(at).abs() > _markerMaxAge) return;
      startUnlocked = true;
      if (json['mode'] == 'demo') {
        active = true;
        _carriedPrefs = (json['prefs'] as Map?)?.cast<String, dynamic>();
        SharedPreferences.setPrefix(_prefsPrefix);
        _logger.info('Starting in demo mode');
      }
    } catch (e, st) {
      _logger.handle(e, st, 'Failed to read the start marker');
    }
  }

  static Map<String, dynamic>? _carriedPrefs;

  /// Look-and-feel preferences of the real app that the demo copies, so it
  /// looks like the user's own app. Data-bearing ones stay out.
  @visibleForTesting
  static const notCarriedForTesting = _notCarried;

  static const _notCarried = {
    PreferencesKeys.dinzoConfig,
    PreferencesKeys.assetLots,
    PreferencesKeys.portfolioDiagram,
    PreferencesKeys.budgetPlan,
    PreferencesKeys.totalWallets,
    PreferencesKeys.cashWallet,
  };

  /// Not backup preferences, but the demo needs them for its quotes: the brapi
  /// key (without it only the sandbox tickers answer) and the last crypto
  /// quotes (CoinGecko often says 429). Market data, nothing personal.
  static const _marketPrefs = [
    PreferencesKeys.brapiApiKey,
    PreferencesKeys.cryptoQuotesMain,
    PreferencesKeys.cryptoQuotesUsd,
    PreferencesKeys.cryptoQuotesUpdatedAt,
  ];

  static Future<void> enterAndRestart() async {
    final prefs = ServiceConfig.sharedPreferences;
    final carried = prefs == null || active
        ? _carriedPrefs
        : {
            ...PreferencesBackupService.exportPreferences(prefs),
            for (final key in _marketPrefs)
              if (prefs.get(key) case final value?) key: value,
          };
    await _restartAs('demo', {
      for (final e in (carried ?? const <String, dynamic>{}).entries)
        if (!_notCarried.contains(e.key) && !SyncExtensions.isPortablePref(e.key))
          e.key: e.value,
    });
  }

  static Future<void> leaveAndRestart() => _restartAs('real', null);

  static Future<void> _restartAs(
    String mode,
    Map<String, dynamic>? prefs,
  ) async {
    try {
      final marker = await _marker();
      await marker.writeAsString(
        jsonEncode({
          'mode': mode,
          'at': DateTime.now().millisecondsSinceEpoch,
          if (prefs != null) 'prefs': prefs,
        }),
      );
    } catch (e, st) {
      _logger.handle(e, st, 'Failed to write the start marker');
    }
    _logger.info('Restarting into $mode mode');
    try {
      await _appChannel.invokeMethod<void>('restart');
    } catch (_) {
      // No native restart (desktop): start a new process and leave.
      await Process.start(
        Platform.resolvedExecutable,
        const [],
        mode: ProcessStartMode.detached,
      );
      exit(0);
    }
  }

  static Future<File> _marker() async =>
      File(join((await getApplicationSupportDirectory()).path, _markerName));

  /// Where caches live (Dinzo data, market data, sync log): the app support
  /// folder, or its demo subfolder.
  static Future<Directory> supportDirectory() async {
    final base = await getApplicationSupportDirectory();
    if (!active) return base;
    final dir = Directory(join(base.path, _folder));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// The database folder for [base] (the platform default): its demo
  /// subfolder in demo mode.
  static Future<String> databaseDirectory(String base) async {
    if (!active) return base;
    final dir = Directory(join(base, _folder));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  /// Market data with nothing personal in it, copied from the real caches so
  /// the demo's charts show up at once (and offline).
  static const _publicCaches = ['crypto_history.json', 'bcb_rates.json'];

  /// Wipes the demo and builds it again for today. Called by main() after the
  /// profiles are loaded, before anything else reads the database.
  static Future<void> prepare() async {
    if (!active) return;
    final started = DateTime.now();
    final prefs = ServiceConfig.sharedPreferences!;
    try {
      await prefs.clear(); // demo-prefixed keys only
      if (_carriedPrefs != null) {
        await PreferencesBackupService.restorePreferences(
          prefs,
          _carriedPrefs!,
        );
        // Restoring skips what is not a backup preference.
        for (final key in _marketPrefs) {
          switch (_carriedPrefs![key]) {
            case final String value:
              await prefs.setString(key, value);
            case final int value:
              await prefs.setInt(key, value);
          }
        }
      }

      final base = await getApplicationSupportDirectory();
      final dir = await supportDirectory();
      await for (final entity in dir.list()) {
        await entity.delete(recursive: true);
      }
      for (final name in _publicCaches) {
        final source = File(join(base.path, name));
        if (await source.exists()) await source.copy(join(dir.path, name));
      }

      final seed = DemoData(
        DateTime.now(),
        timezone: ServiceConfig.localTimezone,
      ).build();

      await ServiceConfig.database.deleteDatabase();
      final file = File(join(dir.path, 'demo_obackup.json'));
      await file.writeAsString(jsonEncode(seed.backup));
      final ok = await BackupService.importDataFromBackupFile(file);
      await file.delete();
      await CategoryHierarchy.refresh();

      // Looks like a configured app (the key opens nothing: no network).
      await prefs.setString(PreferencesKeys.dinzoApiKey, 'dz_live_demo');
      await prefs.setString(
        PreferencesKeys.dinzoLastSync,
        DateTime.now().toIso8601String(),
      );
      await prefs.setBool('forkDefaultsApplied', true);

      await DashboardCache.store(seed.dashboard);
      await InvestmentsCache.save(seed.investments);
      _logger.info(
        'Demo ready (import: $ok) in '
        '${DateTime.now().difference(started).inMilliseconds} ms',
      );
    } catch (e, st) {
      _logger.handle(e, st, 'Failed to prepare the demo');
    }
  }
}
