import 'package:aupp/services/automatic-writes.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:aupp/demo/demo-mode.dart';
import 'package:aupp/services/logger.dart';
import 'package:aupp/services/database/sqlite-database.dart';

import 'dinzo-api.dart';
import 'dinzo-sync-engine.dart';
import 'dinzo-sync-log.dart';
import 'dinzo-sync-service.dart';
import 'package:aupp/dinzo/daily-money.dart';

enum DinzoAutoSyncState { running, applied, needsReview, failed }

class DinzoAutoSyncStatus {
  final DinzoAutoSyncState state;
  final String message;

  /// The fetched plan, kept so the review opens without fetching again.
  final DinzoPreparedSync? prepared;

  /// What came in, one line per record (sync history lines), for the
  /// notification.
  final List<String> details;

  /// Progress of a running sync, when it is countable (investment positions).
  final int? done;
  final int? total;

  const DinzoAutoSyncStatus(
    this.state,
    this.message, {
    this.prepared,
    this.details = const [],
    this.done,
    this.total,
  });
}

/// Quick sync on app open: applied on its own
/// when there is nothing to decide, otherwise left for review on the
/// Extrato. Never runs before the first (full, manual) sync, nor while the
/// sync screen is open.
class DinzoAutoSync {
  static final _logger = Logger.withClass(DinzoAutoSync);

  /// What the Extrato shows; null = nothing to show.
  static final ValueNotifier<DinzoAutoSyncStatus?> status = ValueNotifier(
    null,
  );

  /// Opening the app again within this time does not sync again.
  static const Duration minInterval = Duration(minutes: 10);

  /// Banks are asked to refresh only when the last sync is older than this
  /// (the refresh is slow and rate limited).
  static const Duration bankRefreshInterval = Duration(hours: 1);

  static DateTime? _lastAttempt;
  static Completer<void>? _running;
  static int _paused = 0;

  /// The sync screen holds this while open, so the two never apply the same
  /// plan twice.
  static void pause() => _paused++;
  static void resume() => _paused = _paused > 0 ? _paused - 1 : 0;

  /// Completes when no automatic sync is running.
  static Future<void> whenIdle() => _running?.future ?? Future.value();

  /// What keeps a plan from being applied without the user: conflicts with
  /// local edits, removals and records without a category.
  static List<String> reviewReasons(DinzoSyncPlan plan) {
    final conflicts = plan.ofKind(DinzoPlanKind.conflict).length;
    final removals = plan.ofKind(DinzoPlanKind.remove).length;
    final noCategory = plan.items
        .where((i) => i.selected && i.needsCategory)
        .length;
    return [
      if (conflicts > 0)
        '$conflicts ${conflicts == 1 ? 'conflito' : 'conflitos'}',
      if (removals > 0)
        '$removals ${removals == 1 ? 'removido' : 'removidos'} na Dinzo',
      if (noCategory > 0) '$noCategory sem categoria',
    ];
  }

  static Future<void> run({bool force = false}) =>
      AutomaticWrites.run(() => _run(force: force));

  static Future<void> _run({required bool force}) async {
    if (_running != null ||
        _paused > 0 ||
        DemoMode.active ||
        SqliteDatabase.readOnly) {
      return;
    }
    if (DinzoSyncService.apiKey == null || DinzoSyncService.lastSync == null) {
      return;
    }
    // After a restore the first sync must be the full one, on the screen.
    if (!await DailyMoney.started()) return;
    final now = DateTime.now();
    if (!force &&
        _lastAttempt != null &&
        now.difference(_lastAttempt!) < minInterval) {
      return;
    }
    _lastAttempt = now;
    final running = _running = Completer<void>();
    final previous = status.value;
    status.value = const DinzoAutoSyncStatus(
      DinzoAutoSyncState.running,
      'Sincronizando com a Dinzo…',
    );
    try {
      final last = DinzoSyncService.lastSync;
      final prepared = await DinzoSyncService.prepare(
        full: false,
        refreshBanks:
            force ||
            last == null ||
            now.difference(last) > bankRefreshInterval,
      );
      if (_paused > 0) {
        // The sync screen opened meanwhile: it fetches and applies itself.
        status.value = null;
        return;
      }
      final reasons = reviewReasons(prepared.plan);
      if (reasons.isNotEmpty) {
        final pending = prepared.plan.items
            .where((i) => i.selected && i.kind != DinzoPlanKind.unchanged)
            .length;
        final message =
            'Sync da Dinzo precisa de revisão: ${reasons.join(', ')}'
            '${pending > 0 ? ' · $pending alterações aguardando' : ''}.';
        await DinzoSyncLog.add(
          DinzoSyncLogEntry(
            at: DateTime.now(),
            trigger: 'auto',
            mode: 'rápido',
            outcome: 'revisar',
            summary: message,
            items: [
              for (final i in prepared.plan.items)
                if (i.kind == DinzoPlanKind.conflict ||
                    i.kind == DinzoPlanKind.remove ||
                    (i.selected && i.needsCategory))
                  '? ${i.kind.name} ${i.existing?.title ?? i.desired?.title} '
                      '(dinzo ${i.transaction?.id ?? i.existing?.dinzoId})',
            ],
          ),
        );
        status.value = DinzoAutoSyncStatus(
          DinzoAutoSyncState.needsReview,
          message,
          prepared: prepared,
        );
        return;
      }
      final result = await DinzoSyncService.apply(prepared, trigger: 'auto');
      final changed = result.created + result.updated + result.removed;
      status.value = changed == 0
          ? null
          : DinzoAutoSyncStatus(
              DinzoAutoSyncState.applied,
              'Dinzo: ${result.created} novos, ${result.updated} '
              'atualizados, ${result.removed} removidos.',
              details: result.items,
            );
    } on DinzoApiException catch (e, st) {
      _logger.handle(e, st, 'Automatic sync failed');
      await _logError('${e.status ?? ''} ${e.code}: ${e.message}');
      status.value = DinzoAutoSyncStatus(
        DinzoAutoSyncState.failed,
        e.code == 'missing_key'
            ? 'Configure a chave da Dinzo para sincronizar.'
            : 'Sync automático da Dinzo falhou (${e.code}).',
      );
    } catch (e, st) {
      // Mostly no network: stay quiet and keep whatever was shown before.
      _logger.handle(e, st, 'Automatic sync failed');
      await _logError('$e');
      status.value =
          previous?.state == DinzoAutoSyncState.running ? null : previous;
    } finally {
      _running = null;
      running.complete();
    }
  }

  static Future<void> _logError(String error) => DinzoSyncLog.add(
    DinzoSyncLogEntry(
      at: DateTime.now(),
      trigger: 'auto',
      mode: 'rápido',
      outcome: 'erro',
      summary: error,
    ),
  );

  /// The user dealt with it (closed the banner or applied on the screen).
  static void clear() => status.value = null;
}
