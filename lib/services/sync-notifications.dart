import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:aupp/dinzo/dinzo-sync-service.dart';
import 'package:aupp/dinzo/dinzo-auto-sync.dart';
import 'package:aupp/investments/investments-cache.dart';
import 'package:aupp/services/logger.dart';
import 'package:aupp/services/sync-extensions.dart';

/// Android: while Dinzo, an extension or the investments sync, a
/// foreground service (`SyncForegroundService`, native) keeps the process
/// alive with the phone locked or the app in the background, and its
/// notification shows the progress. When nothing is running it stops and the
/// notification goes away: no result notifications (fork, 2026-10-29; the
/// outcome shows in the Extrato's sync pill).
class SyncNotifications {
  static final _logger = Logger.withClass(SyncNotifications);
  static const _appChannel = MethodChannel('aupp/app');
  static bool _attached = false;
  static bool _serviceOn = false;

  static final _notifiers = <(ValueNotifier<DinzoAutoSyncStatus?>, String)>[
    (DinzoAutoSync.status, 'Dinzo'),
    for (final e in SyncExtensions.all) (e.status, e.name),
    (InvestmentsCache.status, 'Investimentos'),
  ];

  /// Starts following the sync statuses. Android only; asks for the
  /// notification permission when there is a sync to follow.
  static void attach() {
    if (_attached || kIsWeb || !Platform.isAndroid) return;
    _attached = true;
    _askPermission();
    for (final (notifier, _) in _notifiers) {
      notifier.addListener(_update);
    }
    _update();
  }

  static Future<void> _askPermission() async {
    // Only someone with a sync to follow is asked (all of them are
    // optional; connecting one asks on the next start).
    if (DinzoSyncService.apiKey == null && !SyncExtensions.anyConfigured) return;
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_sync'),
        ),
      );
      await plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } catch (e, st) {
      _logger.handle(e, st, 'Notification permission unavailable');
    }
  }

  static Future<void> _update() async {
    final running = [
      for (final (notifier, title) in _notifiers)
        if (notifier.value?.state == DinzoAutoSyncState.running)
          (title, notifier.value!),
    ];
    try {
      if (running.isEmpty) {
        if (!_serviceOn) return;
        _serviceOn = false;
        await _appChannel.invokeMethod('syncDone');
        return;
      }
      final (title, status) = running.first;
      _serviceOn =
          await _appChannel.invokeMethod<bool>('syncRunning', {
            'text': '$title: ${status.message}',
            'done': status.done,
            'total': status.total,
          }) ??
          false;
    } catch (e, st) {
      _logger.handle(e, st, 'Sync service failed');
    }
  }
}
