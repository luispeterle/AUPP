// Phone and computer sharing one encrypted snapshot: nothing is lost on a wrong
// password, a damaged file, a newer app or changes on both sides.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aupp/hybrid_sync/hybrid-sync-core.dart';
import 'package:aupp/hybrid_sync/hybrid-sync.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/services/automatic-writes.dart';
import 'package:aupp/services/backup-service.dart';
import 'package:aupp/services/database/sqlite-database.dart';
import 'package:aupp/services/service-config.dart';
import 'package:aupp/settings/constants/preferences-keys.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest_all.dart' as tz;

SnapshotHeader _header(
  String rev,
  List<String> chain, {
  int? dbVersion,
  int? compat,
}) => SnapshotHeader(
  rev: rev,
  chain: chain,
  device: 'Computador (x)',
  at: DateTime(2026, 10, 30, 12),
  dbVersion: dbVersion ?? SqliteDatabase.version,
  compat: compat ?? HybridSync.dataCompat,
  appVersion: '9.9.9',
);

void main() {
  group('decideSync', () {
    SyncAction decide(
      List<String> local,
      bool dirty,
      SnapshotHeader? remote, {
      bool empty = false,
    }) => decideSync(
      localChain: local,
      dirty: dirty,
      remote: remote,
      localIsEmpty: empty,
    );

    test('first device sends', () {
      expect(decide([], false, null), SyncAction.push);
    });
    test('in step: only sends when the user changed something', () {
      expect(decide(['a'], false, _header('a', [])), SyncAction.nothing);
      expect(decide(['a'], true, _header('a', [])), SyncAction.push);
      expect(decide(['a'], false, null), SyncAction.nothing);
      expect(decide(['a'], true, null), SyncAction.push);
    });
    test('remote ahead: takes it, unless the user changed something', () {
      final remote = _header('b', ['a']);
      expect(decide(['a'], false, remote), SyncAction.apply);
      expect(decide(['a'], true, remote), SyncAction.conflict);
    });
    test('an old copy coming back never replaces newer data', () {
      expect(decide(['a', 'b'], false, _header('a', [])), SyncAction.push);
    });
    test('both moved on while apart: asks, even with nothing dirty', () {
      expect(decide(['a', 'c'], false, _header('b', ['a'])), SyncAction.conflict);
    });
    test('an empty database receives, whatever it had synced before', () {
      final remote = _header('b', ['a']);
      expect(decide(['b'], false, remote, empty: true), SyncAction.apply);
      expect(decide(['a'], false, remote, empty: true), SyncAction.apply);
      expect(decide(['b'], true, remote, empty: true), SyncAction.conflict);
      expect(decide(['b'], false, null, empty: true), SyncAction.nothing);
    });
    test('a new device takes the data only if it has none of its own', () {
      final remote = _header('a', []);
      expect(decide([], false, remote, empty: true), SyncAction.apply);
      expect(decide([], false, remote), SyncAction.conflict);
    });
  });

  group('backupsToDelete', () {
    final today = DateTime(2026, 10, 30);
    String name(int daysAgo, [String device = 'celular']) => DailyBackup.nameFor(
      DateTime(today.year, today.month, today.day - daysAgo),
      device,
    );

    test('goes after 90 days, not on the 90th', () {
      final names = [for (var i = 0; i < 12; i++) name(i), name(90), name(91)];
      expect(backupsToDelete(names, today), [name(91)]);
    });
    test('the 10 latest stay, however old', () {
      final names = [for (var i = 200; i < 215; i++) name(i)];
      final deleted = backupsToDelete(names, today);
      expect(deleted, hasLength(5));
      expect(deleted, containsAll([for (var i = 210; i < 215; i++) name(i)]));
    });
    test('each device keeps its own', () {
      final names = [
        for (var i = 200; i < 205; i++) name(i, 'celular'),
        for (var i = 200; i < 215; i++) name(i, 'pc-casa'),
      ];
      final deleted = backupsToDelete(names, today);
      expect(deleted, hasLength(5));
      expect(deleted.every((n) => n.contains('pc-casa')), isTrue);
    });
    test('ignores anything else in the folder', () {
      final names = [
        for (var i = 200; i < 215; i++) name(i),
        'aupp_sync.enc',
        'aupp_backup_2020-01-01_celular.sync-conflict-20200101-000000-AAAAAAA.enc',
        'Notas.md',
      ];
      expect(backupsToDelete(names, today), hasLength(5));
      expect(DailyBackup.parse('aupp_sync.enc'), isNull);
    });
    test('still sees the backups written under the old name', () {
      final backup = DailyBackup.parse('oinkoin_backup_2026-10-30_celular.enc');
      expect(backup?.device, 'celular');
      expect(DailyBackup.parse(DailyBackup.nameFor(today, 'pc')), isNotNull);
    });
  });

  group('needsNewerApp', () {
    bool needs(SnapshotHeader remote) =>
        needsNewerApp(remote, compat: 2, dbVersion: 10);

    test('a higher compatibility level or a newer schema', () {
      expect(needs(_header('a', [], dbVersion: 10, compat: 2)), isFalse);
      expect(needs(_header('a', [], dbVersion: 10, compat: 1)), isFalse);
      expect(needs(_header('a', [], dbVersion: 10, compat: 3)), isTrue);
      expect(needs(_header('a', [], dbVersion: 11, compat: 2)), isTrue);
    });

    test('a file from before the level existed is level 1', () {
      final old = SnapshotHeader.fromJson({
        'rev': 'a',
        'chain': <String>[],
        'device': 'Celular',
        'at': '2026-10-30T12:00:00.000Z',
        'dbVersion': 10,
      });
      expect(old.compat, 1);
      expect(old.appVersion, isNull);
      final again = SnapshotHeader.fromJson(
        jsonDecode(jsonEncode(_header('b', [], compat: 4).toJson()))
            as Map<String, dynamic>,
      );
      expect((again.compat, again.appVersion), (4, '9.9.9'));
    });
  });

  group('snapshot file', () {
    final salt = randomBytes(16);
    final key = deriveKey((password: 'senha-certa', salt: salt));

    test('round trip, and unreadable with another password', () {
      final text = sealSnapshot((
        plain: utf8.encode('{"segredo":"Caixinha"}'),
        header: _header('a', []),
        key: key,
        salt: salt,
      ));
      expect(text, isNot(contains('Caixinha')));
      final sealed = SealedSnapshot.parse(text);
      expect(sealed.header.rev, 'a');
      expect(
        utf8.decode(openSnapshot(sealed.openWith(key))),
        '{"segredo":"Caixinha"}',
      );
      final wrong = deriveKey((password: 'outra-senha', salt: sealed.salt));
      expect(() => openSnapshot(sealed.openWith(wrong)), throwsA(anything));
    });

    test('a snapshot written under the old name still opens', () {
      final text = sealSnapshot((
        plain: utf8.encode('{}'),
        header: _header('a', []),
        key: key,
        salt: salt,
      ));
      expect(text, contains('aupp-sync-1'));
      final old = text.replaceFirst('aupp-sync-1', 'oinkoin-sync-1');
      expect(SealedSnapshot.parse(old).header.rev, 'a');
    });

    test('altered header or content does not open', () {
      final json =
          jsonDecode(
                sealSnapshot((
                  plain: utf8.encode('{}'),
                  header: _header('a', []),
                  key: key,
                  salt: salt,
                )),
              )
              as Map<String, dynamic>;
      final altered = {
        ...json,
        'header': jsonEncode(_header('b', ['x']).toJson()),
      };
      expect(
        () => openSnapshot(
          SealedSnapshot.parse(jsonEncode(altered)).openWith(key),
        ),
        throwsA(anything),
      );
    });

    test('a half-written file is rejected', () {
      final text = sealSnapshot((
        plain: utf8.encode('{}'),
        header: _header('a', []),
        key: key,
        salt: salt,
      ));
      expect(
        () => SealedSnapshot.parse(text.substring(0, text.length ~/ 2)),
        throwsFormatException,
      );
      expect(() => SealedSnapshot.parse('{}'), throwsFormatException);
    });
  });

  group('between devices', () {
    late Directory tmp;
    late Directory folder;
    late File snapshotFile;
    const password = 'senha-certa';

    Future<List<String>> titles() async =>
        (await ServiceConfig.database.getAllRecords())
            .whereType<Record>()
            .map((r) => r.title ?? '')
            .toList();

    Future<void> addRecord(String title) => ServiceConfig.database.addRecord(
      Record(-10, title, null, DateTime.utc(2026, 9, 1), walletId: 1),
    );

    /// What an app from before the database payload would have written: the
    /// full backup JSON, with the records' titles changed.
    Future<void> writeFromOtherDevice(
      String title, {
      String rev = 'outro',
      List<String>? chain,
      String pass = password,
      int? dbVersion,
      int? compat,
    }) async {
      final current = SealedSnapshot.parse(await snapshotFile.readAsString());
      final backup = await BackupService.createJsonBackupFile(
        backupFileName: 'other_obackup.json',
        directoryPath: tmp.path,
      );
      final data =
          jsonDecode(await backup.readAsString()) as Map<String, dynamic>;
      await backup.delete();
      for (final record in data['records'] as List) {
        record['title'] = title;
      }
      final salt = randomBytes(16);
      await snapshotFile.writeAsString(
        sealSnapshot((
          plain: utf8.encode(jsonEncode(data)),
          header: _header(
            rev,
            chain ?? [...current.header.chain],
            dbVersion: dbVersion,
            compat: compat,
          ),
          key: deriveKey((password: pass, salt: salt)),
          salt: salt,
        )),
      );
    }

    /// The user chose "Usar de ...": the app restarts with this flag.
    Future<void> startupAfterChoosingRemote() async {
      await ServiceConfig.sharedPreferences!.setBool(
        'hybridSyncApplyPending',
        true,
      );
      await AutomaticWrites.run(HybridSync.startup);
    }

    /// A snapshot in the current format, from another device.
    Future<void> writeDatabaseFromOtherDevice(
      Uint8List database, {
      String rev = 'outro',
    }) async {
      final current = SealedSnapshot.parse(await snapshotFile.readAsString());
      final salt = randomBytes(16);
      await snapshotFile.writeAsString(
        sealSnapshot((
          plain: packDatabase('{}', database),
          header: SnapshotHeader(
            rev: rev,
            chain: current.header.chain,
            device: 'Computador (x)',
            at: DateTime(2026, 10, 30, 12),
            dbVersion: SqliteDatabase.version,
            compat: HybridSync.dataCompat,
            payload: payloadDatabase,
          ),
          key: deriveKey((password: password, salt: salt)),
          salt: salt,
        )),
      );
    }

    File oldFile() => File('${tmp.path}/aupp/movements.db.old');

    bool fileHasText(File file, String text) =>
        String.fromCharCodes(file.readAsBytesSync()).contains(text);

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      tz.initializeTimeZones();
      ServiceConfig.localTimezone = 'America/Sao_Paulo';
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/package_info'),
        (call) async => {
          'appName': 'AUPP',
          'packageName': 'x',
          'version': '1.15.14',
          'buildNumber': '1',
        },
      );
      tmp = await Directory.systemTemp.createTemp('hybrid_sync');
      folder = await Directory('${tmp.path}/Syncthing').create();
      snapshotFile = File('${folder.path}/${HybridSync.fileName}');
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => tmp.path,
      );
      SharedPreferences.setMockInitialValues({
        PreferencesKeys.dinzoApiKey: 'dz_live_keep',
      });
      ServiceConfig.sharedPreferences = await SharedPreferences.getInstance();
      // The day's backup is named after it: the same day whenever this runs.
      HybridSync.clock = () => DateTime(2026, 10, 30, 9);
      // The sync swaps the database file: this one needs a real file.
      SqliteDatabase.setDatabaseForTesting(null);
      BackupService.database = ServiceConfig.database;
      SqliteDatabase.onDatabaseChanged = HybridSync.noteDatabaseWrite;
      await addRecord('segredo local');
      expect(
        await HybridSync.configure(path: folder.path, newPassword: password),
        isNull,
      );
    });

    tearDown(() async {
      SqliteDatabase.onDatabaseChanged = null;
      HybridSync.clock = DateTime.now;
      await HybridSync.disable();
      await (await SqliteDatabase.instance.database)?.close();
      SqliteDatabase.setDatabaseForTesting(null);
      await tmp.delete(recursive: true);
    });

    test('the first device writes it encrypted', () async {
      final text = await snapshotFile.readAsString();
      expect(text, isNot(contains('segredo local')));
      expect(text, isNot(contains('dz_live_keep')));
      expect(HybridSync.conflict.value, isNull);
    });

    test('a user edit is sent; an automatic write is not', () async {
      final before = await snapshotFile.readAsString();
      await AutomaticWrites.run(() => addRecord('da dinzo'));
      await HybridSync.flush();
      expect(await snapshotFile.readAsString(), before);

      await addRecord('do usuario');
      await HybridSync.flush();
      expect(await snapshotFile.readAsString(), isNot(before));
    });

    test('newer data asks first, and nothing changes until the user chooses',
        () async {
      await writeFromOtherDevice('do outro');
      await AutomaticWrites.run(HybridSync.startup);
      await HybridSync.check();
      expect(await titles(), ['segredo local']);
      expect(HybridSync.incoming.value?.rev, 'outro');
      expect(HybridSync.conflict.value, isNull);
    });

    test('data under the old file name still arrives, and the new name wins',
        () async {
      await writeFromOtherDevice('do outro');
      final legacy = File('${folder.path}/${HybridSync.legacyFileName}');
      await snapshotFile.rename(legacy.path);
      await AutomaticWrites.run(HybridSync.startup);
      await HybridSync.check();
      expect(HybridSync.incoming.value?.rev, 'outro');

      final sent = await legacy.readAsString();
      await legacy.writeAsString('arquivo velho, ilegível');
      await snapshotFile.writeAsString(sent);
      await HybridSync.check();
      expect(HybridSync.incoming.value?.rev, 'outro');
    });

    test('a database file from another device replaces the local one, which '
        'stays as .old, and it can go back', () async {
      final other = await SqliteDatabase.createDatabaseSnapshot();
      await addRecord('so aqui');
      await writeDatabaseFromOtherDevice(await other!.readAsBytes());

      await startupAfterChoosingRemote();
      expect(await titles(), ['segredo local']);
      expect(oldFile().existsSync(), isTrue);
      expect(fileHasText(oldFile(), 'so aqui'), isTrue);
      expect(HybridSync.lastEvent.value, contains('Atualizado'));
      // In step now: nothing to send back.
      final sent = await snapshotFile.readAsString();
      await HybridSync.flush();
      expect(await snapshotFile.readAsString(), sent);

      // Back to .old: what was in use becomes the new .old, and it counts as a
      // change to send.
      await ServiceConfig.sharedPreferences!.setBool(
        'hybridSyncRestoreOldPending',
        true,
      );
      await AutomaticWrites.run(HybridSync.startup);
      expect(await titles(), containsAll(['segredo local', 'so aqui']));
      expect(fileHasText(oldFile(), 'so aqui'), isFalse);
      expect(ServiceConfig.sharedPreferences!.getBool('hybridSyncDirty'), isTrue);
    });

    test("another device's changes join in by themselves, and what changed "
        'here stays and goes to the folder', () async {
      final copy = await SqliteDatabase.createDatabaseSnapshot();
      await AutomaticWrites.run(() async {
        final db = await databaseFactory.openDatabase(copy!.path);
        await db.insert('records', {
          'id': 900,
          'datetime': DateTime.utc(2026, 9, 2).millisecondsSinceEpoch,
          'value': -5,
          'title': 'do outro',
          'category_name': 'x',
          'category_type': 0,
          'wallet_id': 1,
        });
        await db.close();
      });
      await writeDatabaseFromOtherDevice(await copy!.readAsBytes());
      await addRecord('tambem local');
      await HybridSync.flush();

      expect(HybridSync.conflict.value, isNull);
      expect(HybridSync.incoming.value, isNull);
      expect(
        await titles(),
        containsAll(['segredo local', 'tambem local', 'do outro']),
      );
      expect(oldFile().existsSync(), isTrue);
      final written = SealedSnapshot.parse(await snapshotFile.readAsString());
      expect(written.header.rev, isNot('outro'));
      expect(written.header.chain, contains('outro'));
      expect(ServiceConfig.sharedPreferences!.getBool('hybridSyncDirty'), isFalse);

      // Nothing new since: a check changes nothing.
      final sent = await snapshotFile.readAsString();
      await HybridSync.check();
      expect(await snapshotFile.readAsString(), sent);
    });

    test('newer data with nothing changed here arrives without asking',
        () async {
      final copy = await SqliteDatabase.createDatabaseSnapshot();
      await AutomaticWrites.run(() async {
        final db = await databaseFactory.openDatabase(copy!.path);
        await db.update('records', {'title': 'editado no outro'});
        await db.close();
      });
      await writeDatabaseFromOtherDevice(await copy!.readAsBytes());
      var arrived = 0;
      void count() => arrived++;
      HybridSync.dataArrived.addListener(count);
      await HybridSync.check();
      HybridSync.dataArrived.removeListener(count);
      expect(await titles(), ['editado no outro']);
      expect(HybridSync.incoming.value, isNull);
      expect(arrived, 1);
    });

    test('a damaged database file changes nothing', () async {
      final bytes = Uint8List.fromList(List.filled(8192, 7));
      await writeDatabaseFromOtherDevice(bytes);
      await startupAfterChoosingRemote();
      expect(await titles(), ['segredo local']);
      expect(oldFile().existsSync(), isFalse);
      expect(HybridSync.lastEvent.value, contains('problema'));
    });

    test('an empty database file never replaces data', () async {
      final copy = await SqliteDatabase.createDatabaseSnapshot();
      await AutomaticWrites.run(() async {
        final db = await databaseFactory.openDatabase(copy!.path);
        await db.delete('records');
        await db.close();
      });
      await writeDatabaseFromOtherDevice(await copy!.readAsBytes());
      await startupAfterChoosingRemote();
      expect(await titles(), ['segredo local']);
      expect(HybridSync.lastEvent.value, contains('problema'));
    });

    test('keeping the local data leaves the other one as .old in the folder',
        () async {
      await writeFromOtherDevice('do outro');
      final theirs = await snapshotFile.readAsString();
      await HybridSync.check();
      await HybridSync.keepLocal();
      expect(HybridSync.incoming.value, isNull);
      expect(
        await File('${folder.path}/${HybridSync.remoteOldName}').readAsString(),
        theirs,
      );
      expect(await snapshotFile.readAsString(), isNot(theirs));
    });

    test('a file with the old backup JSON is still followed', () async {
      await writeFromOtherDevice('do outro');
      await startupAfterChoosingRemote();

      expect(await titles(), ['do outro']);
      final prefs = ServiceConfig.sharedPreferences!;
      expect(prefs.getString(PreferencesKeys.dinzoApiKey), 'dz_live_keep');
      expect(fileHasText(oldFile(), 'segredo local'), isTrue);

      // In step now: replacing it did not count as a change to send back.
      final after = await snapshotFile.readAsString();
      await HybridSync.flush();
      expect(await snapshotFile.readAsString(), after);
    });

    test('changes on both sides ask, and touch nothing', () async {
      await writeFromOtherDevice('do outro');
      final remote = await snapshotFile.readAsString();
      await addRecord('tambem local');
      await HybridSync.flush();

      expect(HybridSync.conflict.value?.rev, 'outro');
      expect(await snapshotFile.readAsString(), remote);
      expect(await titles(), containsAll(['segredo local', 'tambem local']));

      // Startup does not resolve it either.
      await AutomaticWrites.run(HybridSync.startup);
      expect(await titles(), containsAll(['segredo local', 'tambem local']));

      // Keeping the local data: the other device's history is included, so it
      // receives this snapshot instead of asking again.
      await HybridSync.keepLocal();
      expect(HybridSync.conflict.value, isNull);
      final written = SealedSnapshot.parse(await snapshotFile.readAsString());
      expect(written.header.chain, contains('outro'));
      expect(
        decideSync(
          localChain: const ['outro'],
          dirty: false,
          remote: written.header,
          localIsEmpty: false,
        ),
        SyncAction.apply,
      );
    });

    test('a database that disappeared gets the data back, and never sends '
        'the empty one', () async {
      final before = await snapshotFile.readAsString();
      await AutomaticWrites.run(() async {
        await ServiceConfig.database.deleteDatabase();
      });
      expect(await titles(), isEmpty);

      await HybridSync.flush();
      expect(await snapshotFile.readAsString(), before);

      await AutomaticWrites.run(HybridSync.startup);
      expect(await titles(), ['segredo local']);
    });

    group('daily backups', () {
      List<String> backupFiles() =>
          folder
              .listSync()
              .map((e) => e.path.split('/').last)
              .where((n) => DailyBackup.parse(n) != null)
              .toList()
            ..sort();

      test('one per day: updated during the day, the previous one stays', () async {
        HybridSync.clock = () => DateTime(2026, 10, 30, 9);
        await addRecord('dia 30');
        await HybridSync.flush();
        expect(backupFiles(), hasLength(1));
        final first = backupFiles().single;
        final before = await File('${folder.path}/$first').readAsString();

        await addRecord('dia 30 de novo');
        await HybridSync.flush();
        expect(backupFiles(), [first]);
        final after = await File('${folder.path}/$first').readAsString();
        expect(after, isNot(before));

        HybridSync.clock = () => DateTime(2026, 10, 31, 9);
        await HybridSync.check();
        expect(backupFiles(), hasLength(2));
        expect(await File('${folder.path}/$first').readAsString(), after);
      });

      test('what the app writes by itself also reaches the backup', () async {
        HybridSync.clock = () => DateTime(2026, 10, 30, 9);
        await HybridSync.flush();
        final name = backupFiles().single;
        final before = await File('${folder.path}/$name').readAsString();
        await AutomaticWrites.run(() => addRecord('da dinzo'));
        await HybridSync.flush();
        expect(await File('${folder.path}/$name').readAsString(), isNot(before));
      });

      test('an empty database never overwrites a backup', () async {
        HybridSync.clock = () => DateTime(2026, 10, 30, 9);
        await HybridSync.flush();
        final name = backupFiles().single;
        final before = await File('${folder.path}/$name').readAsString();
        await ServiceConfig.database.deleteDatabase();
        await HybridSync.flush();
        expect(await File('${folder.path}/$name').readAsString(), before);
      });

      test('old ones go, keeping at least 10', () async {
        HybridSync.clock = () => DateTime(2026, 10, 30, 9);
        final old = [
          for (var i = 100; i < 115; i++)
            DailyBackup.nameFor(DateTime(2026, 10, 30 - i), 'pc-velho'),
        ];
        for (final name in old) {
          await File('${folder.path}/$name').writeAsString('x');
        }
        // Old ones are cleaned when the day's backup is written.
        await addRecord('novo');
        await HybridSync.flush();
        expect(backupFiles().where((n) => n.contains('pc-velho')), hasLength(10));
      });

      test('restoring brings the data back and counts as a change', () async {
        HybridSync.clock = () => DateTime(2026, 10, 30, 9);
        await HybridSync.flush();
        final name = backupFiles().single;
        await addRecord('depois do backup');
        await HybridSync.flush();
        // Today's follows the data: take the older copy as a backup of yesterday.
        final yesterday = DailyBackup.nameFor(DateTime(2026, 10, 29), 'celular');
        final original = SealedSnapshot.parse(
          await File('${folder.path}/$name').readAsString(),
        );
        expect(original.header.rev, 'backup');
        await File(
          '${folder.path}/$name',
        ).copy('${folder.path}/$yesterday');
        await addRecord('mais um');

        await ServiceConfig.sharedPreferences!.setString(
          'hybridSyncRestorePending',
          yesterday,
        );
        await AutomaticWrites.run(HybridSync.startup);
        expect(await titles(), containsAll(['segredo local', 'depois do backup']));
        expect(await titles(), isNot(contains('mais um')));
        expect(
          ServiceConfig.sharedPreferences!.getString('hybridSyncRestorePending'),
          isNull,
        );
        expect(ServiceConfig.sharedPreferences!.getBool('hybridSyncDirty'), isTrue);
      });
    });

    test('a wrong password leaves the data alone', () async {
      await writeFromOtherDevice('do outro', pass: 'outra-senha');
      await startupAfterChoosingRemote();
      expect(await titles(), ['segredo local']);
      expect(HybridSync.lastEvent.value, contains('Senha errada'));

      await HybridSync.disable();
      await HybridSync.configure(path: folder.path, newPassword: password)
          .then((error) => expect(error, isNotNull));
    });

    test('a newer database leaves the data alone, read-only', () async {
      await writeFromOtherDevice(
        'do outro',
        dbVersion: SqliteDatabase.version + 1,
      );
      await AutomaticWrites.run(HybridSync.startup);
      expect(await titles(), ['segredo local']);
      expect(HybridSync.readOnly.value?.appVersion, '9.9.9');
      expect(SqliteDatabase.readOnly, isTrue);
      expect(HybridSync.lastEvent.value, contains('Somente leitura'));
    });

    test('a breaking change from a newer app: read-only, nothing is sent '
        'nor applied', () async {
      await writeFromOtherDevice(
        'do outro',
        compat: HybridSync.dataCompat + 1,
      );
      final newer = await snapshotFile.readAsString();
      await AutomaticWrites.run(HybridSync.startup);
      expect(await titles(), ['segredo local']);
      expect(HybridSync.readOnly.value, isNotNull);

      // The database refuses the edit, and nothing is sent over the newer data.
      await expectLater(addRecord('do usuario'), throwsA(anything));
      await HybridSync.flush();
      expect(await snapshotFile.readAsString(), newer);
      expect(HybridSync.conflict.value, isNull);
    });

    test('the same level from a newer app is followed as usual', () async {
      await writeFromOtherDevice('do outro');
      await startupAfterChoosingRemote();
      expect(await titles(), ['do outro']);
      expect(HybridSync.readOnly.value, isNull);
    });

    test('a damaged file changes nothing', () async {
      final text = await snapshotFile.readAsString();
      await snapshotFile.writeAsString(text.substring(0, text.length ~/ 2));
      await AutomaticWrites.run(HybridSync.startup);
      expect(await titles(), ['segredo local']);
    });

    test('a pending apply survives only one start', () async {
      await writeFromOtherDevice('do outro', pass: 'outra-senha');
      await ServiceConfig.sharedPreferences!.setBool(
        'hybridSyncApplyPending',
        true,
      );
      await AutomaticWrites.run(HybridSync.startup);
      expect(
        ServiceConfig.sharedPreferences!.getBool('hybridSyncApplyPending'),
        isNull,
      );
      expect(await titles(), ['segredo local']);
    });
  });
}
