// What is changed by hand leaves a trace with the before and the after; what
// the app does by itself does not.
import 'package:flutter_test/flutter_test.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/models/wallet.dart';
import 'package:aupp/services/automatic-writes.dart';
import 'package:aupp/services/database/change-log.dart';
import 'package:aupp/services/database/sqlite-database.dart';
import 'package:aupp/services/service-config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest_all.dart' as tz;

import 'helpers/test_database.dart';

void main() {
  late Database db;
  final database = SqliteDatabase.instance;

  Record record(double value, {String title = 'Mercado'}) =>
      Record(value, title, null, DateTime.utc(2026, 4, 30), walletId: 1);

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tz.initializeTimeZones();
    ServiceConfig.localTimezone = 'America/Sao_Paulo';
    SharedPreferences.setMockInitialValues({});
    db = await TestDatabaseHelper.setupTestDatabase();
  });

  tearDown(() async {
    await db.close();
    SqliteDatabase.setDatabaseForTesting(null);
  });

  test('an edit keeps only what changed, before and after', () async {
    final id = await database.addRecord(record(-8000));
    final changed = (await database.getRecordById(id))!..value = -12000;
    await database.updateRecordById(id, changed);

    final entries = await ChangeLog.read(db);
    expect(entries.map((e) => e.action), ['Editou', 'Criou']);
    expect(entries.first.target, 'records');
    expect(entries.first.title, 'Mercado');
    expect(entries.first.before, {'value': -8000.0});
    expect(entries.first.after, {'value': -12000.0});
  });

  test('saving without changes logs nothing', () async {
    final id = await database.addRecord(record(-10));
    await database.updateRecordById(id, (await database.getRecordById(id))!);
    expect((await ChangeLog.read(db)).map((e) => e.action), ['Criou']);
  });

  test('a change in the tags counts', () async {
    final id = await database.addRecord(record(-10));
    final changed = (await database.getRecordById(id))!..tags = {'Pix'};
    await database.updateRecordById(id, changed);
    expect((await ChangeLog.read(db)).first.after, {'tags': 'Pix'});
  });

  test('a deleted record keeps what it was', () async {
    final id = await database.addRecord(record(-2500, title: 'Investir'));
    await database.deleteRecordById(id);
    final entry = (await ChangeLog.read(db)).first;
    expect(entry.action, 'Excluiu');
    expect(entry.title, 'Investir');
    expect(entry.before?['value'], -2500.0);
    expect(entry.after, isNull);
  });

  test('what the app does by itself is not logged', () async {
    await AutomaticWrites.run(() async {
      final id = await database.addRecord(record(-10));
      final changed = (await database.getRecordById(id))!..value = -20;
      await database.updateRecordById(id, changed);
      await database.deleteRecordById(id);
    });
    expect(await ChangeLog.read(db), isEmpty);
  });

  test('wallets are logged too', () async {
    final id = await database.addWallet(Wallet('Caixinha'));
    final wallet = (await database.getWalletById(id))!;
    wallet.name = 'Caixinha Nova';
    await database.updateWallet(id, wallet);
    final entry = (await ChangeLog.read(db)).first;
    expect(entry.target, 'wallets');
    expect(entry.before, {'name': 'Caixinha'});
    expect(entry.after, {'name': 'Caixinha Nova'});
  });

  test('many rows at once become one entry', () async {
    final ids = [
      for (var i = 0; i < 25; i++) await database.addRecord(record(-1.0 - i)),
    ];
    await database.deleteRecordsInBatch(ids);
    final entry = (await ChangeLog.read(db)).first;
    expect(entry.action, 'Excluiu');
    expect(entry.title, '25 itens');
  });

  group('how long it stays', () {
    Future<void> entry(DateTime at) => db.insert(ChangeLog.table, {
      'at': at.millisecondsSinceEpoch,
      'device': 'x',
      'action': 'Editou',
      'target': 'records',
      'title': 't',
    });

    test('older than a year goes, newer stays', () async {
      final now = DateTime(2026, 11, 1);
      await entry(DateTime(2025, 10, 1));
      await entry(DateTime(2025, 12, 1));
      await db.delete(ChangeLog.table, where: 'at = ?', whereArgs: [0]);
      // Without the guard of the latest ones: more than it always keeps.
      for (var i = 0; i < ChangeLog.keepAtLeast; i++) {
        await entry(DateTime(2026, 10, 1));
      }
      await ChangeLog.prune(db, now: now);
      final left = await ChangeLog.read(db);
      expect(left, hasLength(ChangeLog.keepAtLeast + 1));
      expect(left.last.at, DateTime(2025, 12, 1));
    });

    test('the latest ones stay even when old', () async {
      await entry(DateTime(2020, 1, 1));
      await ChangeLog.prune(db, now: DateTime(2026, 11, 1));
      expect(await ChangeLog.read(db), hasLength(1));
    });
  });
}
