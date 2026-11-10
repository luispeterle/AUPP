import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' show basename, join;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:aupp/demo/demo-mode.dart';
import 'package:aupp/dinzo/dinzo-auto-sync.dart';
import 'package:aupp/services/sync-extensions.dart';
import 'package:aupp/hybrid_sync/hybrid-sync-core.dart';
import 'package:aupp/hybrid_sync/hybrid-sync-merge.dart';
import 'package:aupp/services/automatic-writes.dart';
import 'package:aupp/services/backup-directory-service.dart';
import 'package:aupp/services/backup-service.dart';
import 'package:aupp/services/category-hierarchy.dart';
import 'package:aupp/services/database/change-log.dart';
import 'package:aupp/services/database/sqlite-database.dart';
import 'package:aupp/services/database/sqlite-migration-service.dart';
import 'package:aupp/services/logger.dart';
import 'package:aupp/services/preferences-backup-service.dart';
import 'package:aupp/services/service-config.dart';
import 'package:aupp/settings/constants/preferences-keys.dart';
import 'package:uuid/uuid.dart';

/// Keeps phone and computer on the same data through one encrypted snapshot
/// (the database file and the portable preferences) in a folder that Syncthing
/// replicates.
///
/// A device sends when the user changed something. Data from another device is
/// joined into this one's by itself ([mergeDatabases]), row by row against the
/// copy of the last data both had (the base, one per revision, kept in
/// [_baseDir]): only what the other device changed arrives, and nothing
/// changed here is lost. Before each join this device's data stays as `.old`.
/// Without a base (the first sync, or the first one after updating the app
/// from before the join) it still asks ([incoming], [conflict]), and taking
/// the other side replaces everything at startup. What the app does by itself
/// ([AutomaticWrites]) is not sent: each device redoes it.
/// Arguments of [_sealDatabase].
typedef _DatabaseSeal = ({
  String preferences,
  Uint8List database,
  SnapshotHeader header,
  Uint8List key,
  Uint8List salt,
});

String _sealDatabase(_DatabaseSeal request) => sealSnapshot((
  plain: packDatabase(request.preferences, request.database),
  header: request.header,
  key: request.key,
  salt: request.salt,
));

class HybridSync {
  static final _logger = Logger.withClass(HybridSync);

  static const fileName = 'aupp_sync.enc';

  /// Read until this name exists, so that the data still written under the
  /// app's old name reaches the first device that updates.
  static const legacyFileName = 'oinkoin_sync.enc';
  static const remoteOldName = '$fileName.old';
  static const _oldSuffix = '.old';
  static const _oldPrefsSuffix = '.old.prefs.json';
  static const _incomingSuffix = '.incoming';

  /// Compatibility level of the data this app writes. Raise it in the version
  /// that changes the meaning or the shape of the data in a way older apps
  /// would read or write wrong (a breaking change). A device on an older app
  /// that finds a higher level stays read-only until updated ([readOnly]); a
  /// newer database schema does the same by itself.
  /// 3 (2026-11-02): an occurrence's own Pix / boleto code sets its amount
  /// (RecurrentRecordPattern.valueFor, also a Pix charge's saved amount); an
  /// older app would store the average.
  /// 4 (2026-11-03): the profiles are gone (new rows have no profile_id; an
  /// older app showing one profile would leave them out), and money between
  /// the user's own accounts is stored, tagged "Entre contas" (an older app
  /// would count both sides as income and expense).
  /// 5 (2026-11-05): an upcoming occurrence edited by hand leaves its
  /// recurrence ("pular:" in payment_codes) and becomes an item of its own;
  /// an older app would show both.
  /// 6 (2026-11-05): C6 Pix without "Pix" in the description and money in
  /// on a bank account are no longer tagged "Débito"; an older app would tag
  /// them back on its next Dinzo pull.
  /// 7 (2026-11-08): money between an everyday bank and a broker is an
  /// Aporte (or Resgate) of the wallet to invest; an older app would see it
  /// as hidden in Dinzo and remove it on its next pull. Deleting an aporte
  /// also deletes the transfer that covered it (`livre:cobre:`); an older
  /// app would leave it behind.
  /// 8 (2026-11-09): money moved inside the banks outside the everyday ones
  /// is left out, and a payment straight from one has a withdrawal (or
  /// aporte) next to it (`livre:pago:`); an older app would bring the first
  /// back as income or expense and leave the second behind when deleting.
  /// 9 (2026-11-09): an aporte whose other side Dinzo does not show (a Pix
  /// to a crypto exchange, a transfer to myself that reached no everyday
  /// bank) is an Aporte (or Resgate) too; an older app would remove it on
  /// its next pull.
  static const dataCompat = 9;
  static const _maxChain = 200;
  static const _keepSafetyCopies = 5;
  static const _pushDelay = Duration(seconds: 8);

  // Device-only: none of these is a portable preference, so they stay out of
  // the backup and of the snapshot.
  static const _folderPathKey = 'hybridSyncFolderPath';
  static const _folderUriKey = 'hybridSyncFolderUri';
  static const _passwordKey = 'hybridSyncPassword';
  static const _chainKey = 'hybridSyncChain';
  static const _dirtyKey = 'hybridSyncDirty';
  static const _prefsHashKey = 'hybridSyncPrefsHash';
  static const _applyPendingKey = 'hybridSyncApplyPending';
  static const _lastEventKey = 'hybridSyncLastEvent';
  static const _restorePendingKey = 'hybridSyncRestorePending';
  static const _restoreOldPendingKey = 'hybridSyncRestoreOldPending';
  static const _backupDayKey = 'hybridSyncBackupDay';
  static const _prefsHashVersionKey = 'hybridSyncPrefsHashVersion';
  static const _lastEditKey = 'hybridSyncLastEdit';
  static const _keepBases = 6;

  /// Raised when the set of portable preferences shrinks: what is hashed
  /// changes, and without this each device would see a change by the user
  /// after updating, then a conflict.
  static const _prefsHashVersion = 4;

  /// Device-only state pointing at the data being replaced (wallet ids change).
  /// The Dinzo key, other logins and the sync bookmarks stay: only the
  /// next sync's work depends on them.
  static const _staleKeys = [
    PreferencesKeys.budgetPlan,
  ];
  static const _staleKeyPrefixes = [
    'homePageWalletFilter_',
    'homePageWalletTotals_',
    'walletsTabWalletFilter_',
  ];

  /// Changes on both sides, waiting for the user (shown by the shell).
  static final conflict = ValueNotifier<SnapshotHeader?>(null);

  /// Newer data from another device with no change here, also waiting for the
  /// user: nothing replaces what is on this device without asking.
  static final incoming = ValueNotifier<SnapshotHeader?>(null);

  /// Data written by a newer app this one cannot follow ([needsNewerApp]):
  /// the database is open without writes and nothing is sent nor applied
  /// until the app is updated. Shown by the shell.
  static final readOnly = ValueNotifier<SnapshotHeader?>(null);

  /// What last happened, for the settings page.
  static final lastEvent = ValueNotifier<String?>(null);

  /// Raised after another device's data was joined into this one's while the
  /// app runs: the screens reload.
  static final dataArrived = ValueNotifier<int>(0);

  /// Something changed (even by the app itself) since today's backup.
  static bool _backupStale = false;

  /// Swapped in the tests, to move to another day.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  static Timer? _pushTimer;
  static Future<void>? _running;
  static bool _rerun = false;
  static String? _keyPassword;
  static Uint8List? _key;
  static Uint8List? _keySalt;

  static String? _string(String key) {
    final value = ServiceConfig.sharedPreferences?.getString(key);
    return value == null || value.isEmpty ? null : value;
  }

  static String? get folderPath => _string(_folderPathKey);
  static String? get folderUri => _string(_folderUriKey);
  static String? get password => _string(_passwordKey);
  static bool get enabled =>
      !DemoMode.active && folderPath != null && password != null;

  static List<String> get _chain =>
      ServiceConfig.sharedPreferences?.getStringList(_chainKey) ?? const [];

  static String get _deviceName =>
      Platform.isAndroid ? 'Celular' : 'Computador (${Platform.localHostname})';

  static Future<void> _event(String message) async {
    lastEvent.value = '$message · ${_clock(DateTime.now())}';
    await ServiceConfig.sharedPreferences?.setString(
      _lastEventKey,
      lastEvent.value!,
    );
    _logger.info(message);
  }

  static String clockText(DateTime at) => _clock(at);

  static String _clock(DateTime at) =>
      '${at.day.toString().padLeft(2, '0')}/${at.month.toString().padLeft(2, '0')} '
      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

  /// "Celular, 30/10 18:40": who wrote a snapshot, for the conflict dialog.
  static String describe(SnapshotHeader header) =>
      '${header.device}, ${_clock(header.at)}';

  // ---------------------------------------------------------------------------
  // The folder

  static Future<String?> _readRemote() async =>
      await _read(fileName) ?? await _read(legacyFileName);

  static Future<String?> _read(String name) async {
    final uri = folderUri;
    if (uri != null) {
      final dir = await getTemporaryDirectory();
      final staged = File(join(dir.path, 'hybrid_sync_read.tmp'));
      try {
        final found = await BackupDirectoryService.readBackupFile(
          uri,
          name,
          staged.path,
        );
        return found ? await staged.readAsString() : null;
      } finally {
        if (await staged.exists()) await staged.delete();
      }
    }
    final file = File(join(folderPath!, name));
    return await file.exists() ? await file.readAsString() : null;
  }

  /// Syncthing replaces files atomically, and a half-written one fails to parse
  /// or to decrypt, so nothing here acts on a partial snapshot.
  static Future<SealedSnapshot?> _remote() async {
    final text = await _readRemote();
    if (text == null) return null;
    return SealedSnapshot.parse(text);
  }

  static Future<void> _writeRemote(String text) => _write(fileName, text);

  static Future<void> _write(String name, String text) async {
    final uri = folderUri;
    if (uri != null) {
      final dir = await getTemporaryDirectory();
      final staged = File(join(dir.path, 'hybrid_sync_write.tmp'));
      await staged.writeAsString(text, flush: true);
      try {
        final ok = await BackupDirectoryService.writeBackupFile(
          uri,
          name,
          staged.path,
        );
        if (!ok) throw StateError('Could not write into the sync folder');
      } finally {
        if (await staged.exists()) await staged.delete();
      }
      return;
    }
    final partial = File(join(folderPath!, '.$name.tmp'));
    await partial.writeAsString(text, flush: true);
    await partial.rename(join(folderPath!, name));
  }

  static Future<List<String>> _listNames() async {
    final uri = folderUri;
    if (uri != null) {
      return [
        for (final entry in await BackupDirectoryService.listBackupFiles(uri))
          entry.name,
      ];
    }
    final dir = Directory(folderPath!);
    if (!await dir.exists()) return const [];
    return [
      await for (final entry in dir.list())
        if (entry is File) basename(entry.path),
    ];
  }

  static Future<void> _delete(String name) async {
    final uri = folderUri;
    if (uri != null) {
      await BackupDirectoryService.deleteBackupFile(uri, name);
    } else {
      await File(join(folderPath!, name)).delete();
    }
  }

  // ---------------------------------------------------------------------------
  // Daily backups

  static String get _deviceSlug {
    if (Platform.isAndroid) return 'celular';
    final host = Platform.localHostname.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9-]'),
      '-',
    );
    return 'pc-$host';
  }

  /// The day's backup follows the data: it is rewritten while the day lasts
  /// and the previous day's stays. An empty database never overwrites one: it
  /// would be the very thing a backup is here to survive.
  static Future<void> _updateDailyBackup({String? sealed}) async {
    final prefs = ServiceConfig.sharedPreferences!;
    final today = clock();
    final name = DailyBackup.nameFor(today, _deviceSlug);
    if (sealed == null && !_backupStale && prefs.getString(_backupDayKey) == name) {
      return;
    }
    if (await _localIsEmpty()) return;
    _backupStale = false;
    await _write(
      name,
      sealed ??
          await _sealCurrent(
            rev: 'backup',
            chain: const [],
          ),
    );
    await prefs.setString(_backupDayKey, name);
    for (final old in backupsToDelete(await _listNames(), today)) {
      await _delete(old);
    }
  }

  /// The backups in the folder, newest first.
  static Future<List<DailyBackup>> listBackups() async {
    if (!enabled) return const [];
    final backups = (await _listNames()).map(DailyBackup.parse).nonNulls.toList()
      ..sort((a, b) => b.day.compareTo(a.day));
    return backups;
  }

  /// Replaces the data with a backup, at the next start (like arriving data).
  /// It then counts as a change by the user, and goes to the other devices.
  static Future<void> restoreBackup(DailyBackup backup) async {
    await ServiceConfig.sharedPreferences!.setString(
      _restorePendingKey,
      backup.name,
    );
    await _restartWhenIdle();
  }

  // ---------------------------------------------------------------------------
  // Keys and local state

  static Future<Uint8List> _keyFor(Uint8List salt) async {
    if (_key != null &&
        _keyPassword == password &&
        listEquals(_keySalt, salt)) {
      return _key!;
    }
    final key = await compute(deriveKey, (password: password!, salt: salt));
    _key = key;
    _keySalt = salt;
    _keyPassword = password;
    return key;
  }

  static Future<(Uint8List, Uint8List)> _writeKey() async {
    final salt =
        _keyPassword == password && _keySalt != null
            ? _keySalt!
            : randomBytes(16);
    return (await _keyFor(salt), salt);
  }

  static String _prefsHash() {
    final prefs = ServiceConfig.sharedPreferences!;
    final exported = PreferencesBackupService.exportPreferences(prefs);
    final keys = exported.keys.toList()..sort();
    return sha256
        .convert(utf8.encode(jsonEncode([for (final k in keys) [k, exported[k]]])))
        .toString();
  }

  static bool get _dirty {
    final prefs = ServiceConfig.sharedPreferences!;
    if (prefs.getBool(_dirtyKey) ?? false) return true;
    final saved = prefs.getString(_prefsHashKey);
    return saved != null && saved != _prefsHash();
  }

  static Future<void> _setBase(List<String> chain) async {
    final prefs = ServiceConfig.sharedPreferences!;
    final capped = chain.length > _maxChain
        ? chain.sublist(chain.length - _maxChain)
        : chain;
    await prefs.setStringList(_chainKey, capped);
    await prefs.setString(_prefsHashKey, _prefsHash());
  }

  static Future<bool> _localIsEmpty() async =>
      await ServiceConfig.database.getCountRecords() == 0;

  // ---------------------------------------------------------------------------
  // Events from the app

  /// After every database write.
  static void noteDatabaseWrite() {
    if (!enabled || readOnly.value != null) return;
    _backupStale = true;
    if (AutomaticWrites.active) return;
    ServiceConfig.sharedPreferences?.setBool(_dirtyKey, true);
    ServiceConfig.sharedPreferences?.setInt(
      _lastEditKey,
      clock().millisecondsSinceEpoch,
    );
    _pushTimer?.cancel();
    _pushTimer = Timer(_pushDelay, () => _serialized(allowRestart: false));
  }

  /// Leaving the app: sends what is waiting without the delay.
  static Future<void> flush() async {
    if (!enabled) return;
    _pushTimer?.cancel();
    await _serialized(allowRestart: false);
  }

  /// Back to the app (or opened the page): new data arriving restarts the app.
  static Future<void> check() async {
    if (!enabled) return;
    await _serialized(allowRestart: true);
  }

  static Future<void> _serialized({required bool allowRestart}) async {
    if (_running != null) {
      _rerun = true;
      return _running;
    }
    final running = _run(allowRestart: allowRestart);
    _running = running;
    try {
      await running;
    } finally {
      _running = null;
    }
    if (_rerun) {
      _rerun = false;
      await _serialized(allowRestart: false);
    }
  }

  static Future<void> _run({required bool allowRestart}) async {
    try {
      final remote = await _remote();
      if (remote != null && _isNewer(remote.header)) {
        await _enterReadOnly(remote.header);
        return;
      }
      final empty = await _localIsEmpty();
      final action = decideSync(
        localChain: _chain,
        dirty: _dirty,
        remote: remote?.header,
        localIsEmpty: empty,
      );
      if (action != SyncAction.apply) incoming.value = null;
      if (action != SyncAction.conflict) conflict.value = null;
      switch (action) {
        case SyncAction.nothing:
          if (remote != null) await _ensureBase(remote);
        case SyncAction.push:
          await _push(remote?.header);
        case SyncAction.apply when empty:
          if (allowRestart) await _restartToApply();
        case SyncAction.apply || SyncAction.conflict:
          final ancestor = await _ancestorFor(remote!.header);
          if (ancestor != null) {
            await Future.wait([
              DinzoAutoSync.whenIdle(),
              SyncExtensions.whenIdle(),
            ]);
            if (await _merge(remote, ancestor)) dataArrived.value++;
          } else if (action == SyncAction.apply) {
            incoming.value = remote.header;
          } else {
            conflict.value = remote.header;
          }
      }
      await _updateDailyBackup();
    } on FormatException catch (e, st) {
      // Mid-transfer or damaged: the next check looks again.
      _logger.handle(e, st, 'Unreadable sync snapshot');
    } catch (e, st) {
      _logger.handle(e, st, 'Hybrid sync failed');
      await _event('Falhou: $e');
    }
  }

  static Future<void> _push(SnapshotHeader? remote) async {
    final prefs = ServiceConfig.sharedPreferences!;
    final rev = const Uuid().v4().substring(0, 13);
    final chain = <String>[
      // Keeping over a conflict: the other device's history is part of this
      // one's, so that it receives this snapshot instead of asking again.
      ...?remote?.chain,
      if (remote != null) remote.rev,
      ..._chain,
    ];
    final unique = [...{...chain}, rev];
    final capped = unique.length > _maxChain
        ? unique.sublist(unique.length - _maxChain)
        : unique;

    // Cleared first: a write landing during the backup marks it again.
    await prefs.setBool(_dirtyKey, false);
    try {
      final sealed = await _sealCurrent(
        rev: rev,
        chain: capped,
        keepAsBase: true,
      );
      await _writeRemote(sealed);
      await _setBase(capped);
      await _event('Enviado para a pasta');
    } catch (_) {
      await prefs.setBool(_dirtyKey, true);
      rethrow;
    }
  }

  /// The database file (a consistent copy, checked before it leaves this
  /// device: a damaged database is never sent) and the portable preferences,
  /// encrypted. All the heavy work runs off the UI thread.
  static Future<String> _sealCurrent({
    required String rev,
    required List<String> chain,
    bool keepAsBase = false,
  }) async {
    final copy = await SqliteDatabase.createDatabaseSnapshot();
    if (copy == null) throw StateError('Could not copy the database');
    final Uint8List database;
    try {
      if (await SqliteDatabase.checkDatabaseFile(copy.path) == null) {
        throw StateError('The database failed its integrity check');
      }
      database = await copy.readAsBytes();
    } finally {
      if (await copy.exists()) await copy.delete();
    }
    final preferences = jsonEncode(
      PreferencesBackupService.exportPreferences(
        ServiceConfig.sharedPreferences!,
      ),
    );
    if (keepAsBase) await _saveBase(rev, database, preferences);
    final (key, salt) = await _writeKey();
    return compute(
      _sealDatabase,
      (
        preferences: preferences,
        database: database,
        header: SnapshotHeader(
          rev: rev,
          chain: chain,
          device: _deviceName,
          at: clock(),
          dbVersion: SqliteDatabase.version,
          compat: dataCompat,
          appVersion: ServiceConfig.version,
          payload: payloadDatabase,
        ),
        key: key,
        salt: salt,
      ),
    );
  }

  static bool _isNewer(SnapshotHeader header) => needsNewerApp(
    header,
    compat: dataCompat,
    dbVersion: SqliteDatabase.version,
  );

  /// Data from a newer app: this device only reads until it is updated.
  static Future<void> _enterReadOnly(SnapshotHeader header) async {
    final first = readOnly.value == null;
    readOnly.value = header;
    conflict.value = null;
    _pushTimer?.cancel();
    if (!SqliteDatabase.readOnly) await SqliteDatabase.reopenReadOnly();
    if (first) {
      await _event(
        'Somente leitura: os dados de ${describe(header)} vêm de um app mais '
        'novo${header.appVersion == null ? '' : ' (${header.appVersion})'}',
      );
    }
  }

  static Future<void> _restartToApply() async {
    await ServiceConfig.sharedPreferences!.setBool(_applyPendingKey, true);
    _logger.info('New data in the sync folder; restarting to apply it');
    await _restartWhenIdle();
  }

  static Future<void> _restartWhenIdle() async {
    await Future.wait([DinzoAutoSync.whenIdle(), SyncExtensions.whenIdle()]);
    await DemoMode.leaveAndRestart();
  }

  // ---------------------------------------------------------------------------
  // Replacing the local data

  /// Called from main() before anything reads the database.
  static Future<void> startup() async {
    final prefs = ServiceConfig.sharedPreferences;
    if (prefs == null) return;
    lastEvent.value = prefs.getString(_lastEventKey);
    if (!enabled) return;
    if (prefs.getInt(_prefsHashVersionKey) != _prefsHashVersion) {
      if (prefs.getString(_prefsHashKey) != null) {
        await prefs.setString(_prefsHashKey, _prefsHash());
      }
      await prefs.setInt(_prefsHashVersionKey, _prefsHashVersion);
    }
    try {
      if (prefs.getBool(_restoreOldPendingKey) ?? false) {
        await prefs.remove(_restoreOldPendingKey);
        await _restoreOld();
        return;
      }
      final restore = prefs.getString(_restorePendingKey);
      if (restore != null) {
        // Cleared first, so a failing restore can never loop.
        await prefs.remove(_restorePendingKey);
        await _restoreFromBackup(restore);
        return;
      }
      final pending = prefs.getBool(_applyPendingKey) ?? false;
      // Cleared first, so a failing restore can never loop.
      await prefs.remove(_applyPendingKey);
      final remote = await _remote();
      if (remote == null) return;
      if (_isNewer(remote.header)) {
        await _enterReadOnly(remote.header);
        return;
      }
      final action = decideSync(
        localChain: _chain,
        dirty: _dirty,
        remote: remote.header,
        localIsEmpty: await _localIsEmpty(),
      );
      // Replacing everything without a choice by the user only when there is
      // nothing here to lose. Otherwise both sides join, if a base is known.
      if (pending || (action == SyncAction.apply && await _localIsEmpty())) {
        await _apply(remote);
      } else if (action == SyncAction.apply || action == SyncAction.conflict) {
        final ancestor = await _ancestorFor(remote.header);
        if (ancestor != null) await _merge(remote, ancestor);
      } else if (action == SyncAction.nothing) {
        await _ensureBase(remote);
      }
    } on FormatException catch (e, st) {
      _logger.handle(e, st, 'Unreadable sync snapshot');
    } catch (e, st) {
      _logger.handle(e, st, 'Hybrid sync failed at startup');
      await _event('Falhou: $e');
    }
  }

  static Future<void> _restoreFromBackup(String name) async {
    final text = await _read(name);
    if (text == null) {
      await _event('Backup não encontrado: nada foi alterado');
      return;
    }
    final backup = SealedSnapshot.parse(text);
    if (!await _replaceWith(backup)) return;
    await ServiceConfig.sharedPreferences!.setBool(_dirtyKey, true);
    await _event('Restaurado o backup de ${describe(backup.header)}');
  }

  /// Takes what is in the folder: this device is now in step with it.
  static Future<void> _apply(SealedSnapshot remote) async {
    if (!await _replaceWith(remote)) return;
    await ServiceConfig.sharedPreferences!.setBool(_dirtyKey, false);
    await _setBase([...remote.header.chain, remote.header.rev]);
    await _ensureBase(remote);
    conflict.value = null;
    incoming.value = null;
    final what = 'Usou os dados de ${describe(remote.header)}';
    await _logDecision('$what; os daqui ficaram em $_oldHint');
    await _event('Atualizado com os dados de ${describe(remote.header)}');
  }

  /// Nothing is touched until the snapshot decrypts and passes the checks, and
  /// a copy of the local data stays in [_safetyDir]; a failed restore puts it
  /// back.
  static Future<bool> _replaceWith(SealedSnapshot remote) async {
    if (_isNewer(remote.header)) {
      await _event(
        'Dados de ${remote.header.device} vêm de um app mais novo: '
        'atualize este aparelho',
      );
      return false;
    }
    final Uint8List opened;
    String? plain;
    try {
      final key = await _keyFor(remote.salt);
      opened = await compute(openSnapshot, remote.openWith(key));
      if (remote.header.payload == null) {
        plain = utf8.decode(opened);
        if ((jsonDecode(plain) as Map<String, dynamic>)['records'] is! List) {
          throw const FormatException('Snapshot without records');
        }
      }
    } catch (e, st) {
      _logger.handle(e, st, 'Could not open the sync snapshot');
      await _event('Senha errada ou arquivo danificado: nada foi alterado');
      return false;
    }
    if (plain == null) {
      final unpacked = await compute(unpackDatabase, opened);
      return _replaceFile(unpacked.database, unpacked.preferences);
    }

    // A file from an app that still sent the backup JSON.
    await _keepOld();
    final safety = await BackupService.createJsonBackupFile(
      backupFileName:
          'hybrid_sync_legacy_safety${BackupService.MANDATORY_BACKUP_SUFFIX}',
      directoryPath: (await getTemporaryDirectory()).path,
    );
    final dir = await getTemporaryDirectory();
    final incoming = File(join(dir.path, 'hybrid_sync_incoming_obackup.json'));
    await incoming.writeAsString(plain, flush: true);
    try {
      var ok = await _replaceDataWith(incoming);
      if (!ok) {
        await _replaceDataWith(safety);
        await _event('Não consegui restaurar: seus dados foram mantidos');
        return false;
      }
    } finally {
      await incoming.delete();
    }
    _backupStale = true;
    return true;
  }

  /// Writes the new file next to the database, checks it there, and only then
  /// keeps a copy of what is here and swaps. Fails with nothing changed if the
  /// file is damaged, or empty while this device has data.
  static Future<bool> _replaceFile(Uint8List database, String preferences) async {
    final dir = await SqliteDatabase.getDatabaseDirectory();
    final target = join(dir, SqliteDatabase.databaseFileName);
    final fresh = File('$target$_incomingSuffix');
    try {
      await fresh.writeAsBytes(database, flush: true);
      final records = await SqliteDatabase.checkDatabaseFile(fresh.path);
      if (records == null || (records == 0 && !await _localIsEmpty())) {
        await _event('Arquivo recebido com problema: nada foi alterado');
        return false;
      }
      await _keepOld();
      final prefs = ServiceConfig.sharedPreferences!;
      await _clearStalePrefs();
      try {
        await SqliteDatabase.swapDatabaseFile(fresh);
      } catch (e, st) {
        _logger.handle(e, st, 'Could not swap the database file');
        await _putOldBack();
        await _event('Não consegui restaurar: seus dados foram mantidos');
        return false;
      }
      final decoded = jsonDecode(preferences) as Map<String, dynamic>;
      await PreferencesBackupService.restorePreferences(prefs, decoded);
      await CategoryHierarchy.refresh();
      _backupStale = true;
      return true;
    } finally {
      if (await fresh.exists()) await fresh.delete();
    }
  }

  static Future<void> _clearStalePrefs() async {
    final prefs = ServiceConfig.sharedPreferences!;
    for (final key in _staleKeys) {
      await prefs.remove(key);
    }
    for (final key in prefs.getKeys().toList()) {
      if (_staleKeyPrefixes.any(key.startsWith)) await prefs.remove(key);
    }
  }

  static Future<bool> _replaceDataWith(File backup) async {
    await ServiceConfig.database.deleteDatabase();
    await _clearStalePrefs();
    final ok = await BackupService.importDataFromBackupFile(backup);
    await CategoryHierarchy.refresh();
    return ok;
  }

  static Future<Directory> _safetyDir() async {
    final base = await getApplicationSupportDirectory();
    return Directory(join(base.path, 'hybrid_sync_safety')).create(
      recursive: true,
    );
  }

  static Future<String> _oldPath() async => join(
    await SqliteDatabase.getDatabaseDirectory(),
    '${SqliteDatabase.databaseFileName}$_oldSuffix',
  );

  static String get _oldHint => '${SqliteDatabase.databaseFileName}$_oldSuffix';

  /// When the data on this device was kept as `.old`; null if there is none.
  static Future<DateTime?> oldDataDate() async {
    final old = File(await _oldPath());
    return await old.exists() ? (await old.stat()).modified : null;
  }

  /// The data here becomes `movements.db.old`, with its preferences next to it
  /// (never in the sync folder); the `.old` it replaces goes to [_safetyDir],
  /// which keeps the last few.
  static Future<void> _keepOld() async {
    final path = await _oldPath();
    final prefsFile = File(
      path.substring(0, path.length - _oldSuffix.length) + _oldPrefsSuffix,
    );
    final old = File(path);
    if (await old.exists()) {
      final dir = await _safetyDir();
      final stamp = (await old.stat()).modified.millisecondsSinceEpoch;
      await old.rename(join(dir.path, 'before_$stamp.db'));
      if (await prefsFile.exists()) {
        await prefsFile.rename(join(dir.path, 'before_$stamp.prefs.json'));
      }
      final copies = dir.listSync().whereType<File>().where(
        (file) => !file.path.endsWith('.prefs.json'),
      ).toList()..sort((a, b) => a.path.compareTo(b.path));
      for (final extra in copies.take(
        (copies.length - _keepSafetyCopies).clamp(0, copies.length),
      )) {
        final sidecar = File(extra.path.replaceAll(RegExp(r'\.db$'), '.prefs.json'));
        if (await sidecar.exists()) await sidecar.delete();
        await extra.delete();
      }
    }
    final copy = await SqliteDatabase.createDatabaseSnapshot();
    if (copy == null) throw StateError('Could not copy the database');
    try {
      await copy.rename(path);
    } on FileSystemException {
      // The temporary directory can be on another disk.
      await copy.copy(path);
      await copy.delete();
    }
    await prefsFile.writeAsString(
      jsonEncode(
        PreferencesBackupService.exportPreferences(
          ServiceConfig.sharedPreferences!,
        ),
      ),
      flush: true,
    );
  }

  /// The swap failed: the `.old` just made goes back in place.
  static Future<void> _putOldBack() async {
    final path = await _oldPath();
    final copy = File('$path$_incomingSuffix');
    await File(path).copy(copy.path);
    await SqliteDatabase.swapDatabaseFile(copy);
  }

  /// Back to the data kept as `.old`; what is here becomes the new `.old`, so
  /// that this can be undone the same way. Counts as a change by the user.
  static Future<void> _restoreOld() async {
    final path = await _oldPath();
    final old = File(path);
    if (!await old.exists()) {
      await _event('Não há versão anterior: nada foi alterado');
      return;
    }
    final prefsFile = File(
      path.substring(0, path.length - _oldSuffix.length) + _oldPrefsSuffix,
    );
    final preferences =
        await prefsFile.exists() ? await prefsFile.readAsString() : '{}';
    if (!await _replaceFile(await old.readAsBytes(), preferences)) return;
    await ServiceConfig.sharedPreferences!.setBool(_dirtyKey, true);
    await _logDecision('Voltou para a versão anterior ($_oldHint)');
    await _event('Voltou para a versão anterior');
  }

  static Future<void> _logDecision(String what) async {
    final db = await SqliteDatabase.instance.database;
    if (db != null) await ChangeLog.syncDecision(db, what);
  }

  // ---------------------------------------------------------------------------
  // Joining both sides

  static Future<Directory> _baseDir() async {
    final base = await getApplicationSupportDirectory();
    return Directory(join(base.path, 'hybrid_sync_base'));
  }

  static Future<File> _baseFile(String rev, String suffix) async =>
      File(join((await _baseDir()).path, '$rev$suffix'));

  /// The data of [rev] as this device sent or received it: what the next join
  /// compares both sides with. The last few stay, for when two devices sent
  /// at the same time and one of them lost the folder.
  static Future<void> _saveBase(
    String rev,
    Uint8List database,
    String preferences,
  ) async {
    final dir = await (await _baseDir()).create(recursive: true);
    final db = await _baseFile(rev, '.db');
    final partial = File('${db.path}.tmp');
    await partial.writeAsBytes(database, flush: true);
    await (await _baseFile(rev, '.prefs.json')).writeAsString(
      preferences,
      flush: true,
    );
    await partial.rename(db.path);
    final saved = dir.listSync().whereType<File>().where(
      (f) => f.path.endsWith('.db'),
    ).toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    for (final old in saved.skip(_keepBases)) {
      final prefs = File(old.path.replaceAll(RegExp(r'\.db$'), '.prefs.json'));
      if (await prefs.exists()) await prefs.delete();
      await old.delete();
    }
  }

  /// The latest revision both this device and [remote] descend from, among
  /// the ones with a base here.
  static Future<String?> _ancestorFor(SnapshotHeader remote) async {
    // A file from an app that still sent the backup JSON has no database.
    if (remote.payload != payloadDatabase) return null;
    for (final rev in _chain.reversed) {
      if (rev != remote.rev && !remote.chain.contains(rev)) continue;
      if (await (await _baseFile(rev, '.db')).exists()) return rev;
    }
    return null;
  }

  /// In step with [remote] but without its base (the first sync after
  /// updating the app): keeps it now, so that the next change joins.
  static Future<void> _ensureBase(SealedSnapshot remote) async {
    final rev = remote.header.rev;
    if (_chain.isEmpty || _chain.last != rev) return;
    if (await (await _baseFile(rev, '.db')).exists()) return;
    final opened = await _openDatabaseSnapshot(remote);
    if (opened != null) {
      await _saveBase(rev, opened.database, opened.preferences);
    }
  }

  /// The database and preferences inside [remote]; null when the password does
  /// not open it or it is from an app that still sent the backup JSON.
  static Future<({String preferences, Uint8List database})?>
  _openDatabaseSnapshot(SealedSnapshot remote) async {
    if (remote.header.payload != payloadDatabase) return null;
    try {
      final key = await _keyFor(remote.salt);
      final opened = await compute(openSnapshot, remote.openWith(key));
      return await compute(unpackDatabase, opened);
    } catch (e, st) {
      _logger.handle(e, st, 'Could not open the sync snapshot');
      return null;
    }
  }

  /// A copy of a database file in this app's current schema, for reading.
  static Future<Database> _openAligned(String path) =>
      databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: SqliteDatabase.version,
          onUpgrade: SqliteMigrationService.onUpgrade,
          onOpen: SqliteMigrationService.ensureForkSchema,
          singleInstance: false,
        ),
      );

  /// Joins [remote] into this device's data against the base of [ancestor].
  /// Returns whether anything here changed. Nothing is touched unless the
  /// file opens and passes the checks; the data here stays as `.old` first.
  static Future<bool> _merge(SealedSnapshot remote, String ancestor) =>
      // Its own writes (the change log too) are not a change by the user.
      AutomaticWrites.run(() => _mergeNow(remote, ancestor));

  static Future<bool> _mergeNow(SealedSnapshot remote, String ancestor) async {
    final header = remote.header;
    final opened = await _openDatabaseSnapshot(remote);
    if (opened == null) {
      await _event('Senha errada ou arquivo danificado: nada foi alterado');
      return false;
    }
    final work = await Directory(
      join((await getTemporaryDirectory()).path, 'hybrid_sync_merge'),
    ).create(recursive: true);
    final remoteFile = File(join(work.path, 'remote.db'));
    final baseFile = File(join(work.path, 'base.db'));
    Database? remoteDb, baseDb;
    try {
      await remoteFile.writeAsBytes(opened.database, flush: true);
      await (await _baseFile(ancestor, '.db')).copy(baseFile.path);
      final records = await SqliteDatabase.checkDatabaseFile(remoteFile.path);
      if (records == null || (records == 0 && !await _localIsEmpty())) {
        await _event('Arquivo recebido com problema: nada foi alterado');
        return false;
      }
      remoteDb = await _openAligned(remoteFile.path);
      baseDb = await _openAligned(baseFile.path);

      final prefs = ServiceConfig.sharedPreferences!;
      final wasDirty = _dirty;
      // A field changed on both sides goes to the most recent edit.
      final lastEdit = prefs.getInt(_lastEditKey);
      final remoteWins = !wasDirty ||
          (lastEdit != null &&
              header.at.isAfter(DateTime.fromMillisecondsSinceEpoch(lastEdit)));

      await _keepOld();
      final local = (await SqliteDatabase.instance.database)!;
      final report = await mergeDatabases(
        local: local,
        base: baseDb,
        remote: remoteDb,
        remoteWins: remoteWins,
      );

      final basePrefsFile = await _baseFile(ancestor, '.prefs.json');
      final basePrefs = await basePrefsFile.exists()
          ? jsonDecode(await basePrefsFile.readAsString()) as Map<String, dynamic>
          : <String, dynamic>{};
      final localPrefs = PreferencesBackupService.exportPreferences(prefs);
      final joined = mergePreferences(
        base: basePrefs,
        local: localPrefs,
        remote: jsonDecode(opened.preferences) as Map<String, dynamic>,
        remoteWins: remoteWins,
      );
      final prefsChanged = await _applyPreferences(localPrefs, joined.merged);

      await _saveBase(header.rev, opened.database, opened.preferences);
      conflict.value = null;
      incoming.value = null;

      final conflicts = [
        ...report.conflicts,
        for (final key in joined.conflicts) 'Ajuste $key mudou nos dois',
      ];
      final changed = report.changed || prefsChanged;
      if (changed || conflicts.isNotEmpty) {
        final count = report.applied;
        await _logDecision(
          'Juntou os dados de ${describe(header)}: '
          '$count ${count == 1 ? 'alteração' : 'alterações'}'
          '${conflicts.isEmpty ? '' : '; ${conflicts.take(12).join('; ')}'}'
          '${conflicts.length > 12 ? '; e mais ${conflicts.length - 12}' : ''}'
          '. Os daqui de antes ficaram em $_oldHint',
        );
      }
      // What changed here still has to reach the other devices.
      if (wasDirty) {
        await _push(header);
      } else {
        await _setBase([...header.chain, header.rev]);
      }
      if (changed) {
        await CategoryHierarchy.refresh();
        SqliteDatabase.notifyChanged();
      }
      await _event(
        changed
            ? 'Recebido de ${describe(header)}'
            : 'Em dia com ${describe(header)}',
      );
      return changed;
    } finally {
      await remoteDb?.close();
      await baseDb?.close();
      for (final file in [remoteFile, baseFile]) {
        if (await file.exists()) await file.delete();
      }
    }
  }

  /// Only the preferences that changed; returns whether any did.
  static Future<bool> _applyPreferences(
    Map<String, dynamic> current,
    Map<String, dynamic> merged,
  ) async {
    final prefs = ServiceConfig.sharedPreferences!;
    final changed = {
      for (final e in merged.entries)
        if (jsonEncode(current[e.key]) != jsonEncode(e.value)) e.key: e.value,
    };
    final removed = current.keys.where((k) => !merged.containsKey(k)).toList();
    if (changed.isNotEmpty) {
      await PreferencesBackupService.restorePreferences(prefs, changed);
    }
    for (final key in removed) {
      await prefs.remove(key);
    }
    return changed.isNotEmpty || removed.isNotEmpty;
  }

  // ---------------------------------------------------------------------------
  // The user's decisions

  /// Saves folder and password. Returns an error for the page to show when the
  /// folder already has a snapshot this password cannot open.
  static Future<String?> configure({
    required String path,
    String? uri,
    required String newPassword,
  }) async {
    final prefs = ServiceConfig.sharedPreferences!;
    final previous = (folderPath, folderUri, password);
    await prefs.setString(_folderPathKey, path);
    await prefs.setString(_folderUriKey, uri ?? '');
    await prefs.setString(_passwordKey, newPassword);
    try {
      final remote = await _remote();
      if (remote != null) {
        final key = await _keyFor(remote.salt);
        await compute(openSnapshot, remote.openWith(key));
      }
    } catch (e, st) {
      _logger.handle(e, st, 'Could not open the snapshot with this password');
      await prefs.setString(_folderPathKey, previous.$1 ?? '');
      await prefs.setString(_folderUriKey, previous.$2 ?? '');
      await prefs.setString(_passwordKey, previous.$3 ?? '');
      return 'Essa senha não abre o arquivo que já está na pasta.';
    }
    await check();
    return null;
  }

  static Future<void> disable() async {
    _pushTimer?.cancel();
    final prefs = ServiceConfig.sharedPreferences!;
    for (final key in [
      _folderPathKey,
      _folderUriKey,
      _passwordKey,
      _chainKey,
      _dirtyKey,
      _prefsHashKey,
      _applyPendingKey,
      _lastEventKey,
      _restorePendingKey,
      _restoreOldPendingKey,
      _backupDayKey,
      _lastEditKey,
    ]) {
      await prefs.remove(key);
    }
    final bases = await _baseDir();
    if (await bases.exists()) await bases.delete(recursive: true);
    conflict.value = null;
    incoming.value = null;
    readOnly.value = null;
    lastEvent.value = null;
    _key = null;
    _keySalt = null;
    _keyPassword = null;
  }

  /// This device's data goes to the folder; what was there stays as `.old`
  /// in the folder, still encrypted.
  static Future<void> keepLocal() async {
    if (readOnly.value != null) return;
    await _serializedAction(() async {
      final text = await _readRemote();
      final remote = text == null ? null : SealedSnapshot.parse(text);
      if (text != null) await _write(remoteOldName, text);
      conflict.value = null;
      incoming.value = null;
      await _push(remote?.header);
      if (remote != null) {
        await _logDecision(
          'Manteve os dados daqui sobre os de ${describe(remote.header)}, '
          'que ficaram em $remoteOldName',
        );
      }
    });
  }

  /// The folder's data replaces this device's (which stays as `.old`).
  static Future<void> useRemote() async {
    await _serializedAction(() async {
      conflict.value = null;
      incoming.value = null;
      await _restartToApply();
    });
  }

  /// Back to what this device kept as `.old`, at the next start.
  static Future<void> restoreOld() async {
    await ServiceConfig.sharedPreferences!.setBool(_restoreOldPendingKey, true);
    await _restartWhenIdle();
  }

  /// Back to what the folder kept as `.old`, at the next start.
  static Future<void> restoreRemoteOld() async {
    await ServiceConfig.sharedPreferences!.setString(
      _restorePendingKey,
      remoteOldName,
    );
    await _restartWhenIdle();
  }

  /// Whether the folder has a `.old`.
  static Future<bool> hasRemoteOld() async =>
      enabled && (await _listNames()).contains(remoteOldName);

  static Future<void> _serializedAction(Future<void> Function() body) async {
    await _running;
    final running = body();
    _running = running;
    try {
      await running;
    } catch (e, st) {
      _logger.handle(e, st, 'Hybrid sync action failed');
      await _event('Falhou: $e');
    } finally {
      _running = null;
    }
  }
}
