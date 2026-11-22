import 'dart:io';

import 'package:aupp/dinzo/dinzo-sync-service.dart';
import 'package:aupp/models/category-type.dart';
import 'package:aupp/models/category.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/services/database/sqlite-migration-service.dart';
import 'package:aupp/services/service-config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest_all.dart' as tz;

import '../helpers/test_database.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tz.initializeTimeZones();
    ServiceConfig.localTimezone = 'UTC';
  });

  test('schema 35 gets the budget_group column, records untouched', () async {
    final dir = await Directory.systemTemp.createTemp('aupp_budget_group_');
    final path = '${dir.path}/movements.db';
    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 35,
        onCreate: (db, version) async {
          await SqliteMigrationService.onCreate(db, version);
          final columns = (await db.rawQuery('PRAGMA table_info(records)'))
              .map((c) => c['name']);
          // The schema-35 records table had no budget_group.
          if (columns.contains('budget_group')) {
            await db.execute('ALTER TABLE records DROP COLUMN budget_group');
          }
        },
      ),
    );
    await old.insert('records', {
      'title': 'Mercado',
      'value': -10.0,
      'datetime': 0,
      'category_name': 'Supermercado',
      'category_type': CategoryType.expense.index,
    });
    await old.close();

    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 36,
        onUpgrade: SqliteMigrationService.onUpgrade,
      ),
    );
    final row = (await db.query('records')).single;
    expect(row.containsKey('budget_group'), isTrue);
    expect(row['budget_group'], isNull);
    expect(row['title'], 'Mercado');
    expect(row['category_name'], 'Supermercado');
    await db.close();
  });

  test('a Dinzo-linked record keeps its own group through a sync update',
      () async {
    SharedPreferences.setMockInitialValues({});
    ServiceConfig.sharedPreferences = await SharedPreferences.getInstance();
    await TestDatabaseHelper.setupTestDatabase();
    final db = ServiceConfig.database;
    await db.addRecord(
      Record(
        -68,
        'Sorveteria',
        Category('Compras', categoryType: CategoryType.expense),
        DateTime.utc(2026, 10, 5, 12),
        walletId: 1,
        dinzoId: 'tx-a',
      )..budgetGroup = 'prazeres',
    );
    // What the sync's update does: load the linked record, change it, save.
    final linked = (await DinzoSyncService.linkedRecords()).single;
    expect(linked.budgetGroup, 'prazeres');
    linked.title = 'Sorveteria X';
    await db.updateRecordById(linked.id, linked);
    final back = (await db.getAllRecords()).whereType<Record>().single;
    expect(back.title, 'Sorveteria X');
    expect(back.budgetGroup, 'prazeres');
  });
}
