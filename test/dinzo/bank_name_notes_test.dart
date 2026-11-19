import 'package:flutter_test/flutter_test.dart';
import 'package:aupp/dinzo/dinzo-models.dart';
import 'package:aupp/dinzo/dinzo-sync-engine.dart';
import 'package:aupp/dinzo/dinzo-sync-service.dart';
import 'package:aupp/models/category-type.dart';
import 'package:aupp/models/category.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/services/service-config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest_all.dart' as tz;

import '../helpers/test_database.dart';

/// Records imported before the "No banco: …" line get it on the next sync,
/// next to whatever the user wrote in the notes.
void main() {
  final compras = Category('Compras', categoryType: CategoryType.expense);
  final db = () => ServiceConfig.database;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tz.initializeTimeZones();
    ServiceConfig.localTimezone = 'UTC';
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ServiceConfig.sharedPreferences = await SharedPreferences.getInstance();
    await TestDatabaseHelper.setupTestDatabase();
  });

  DinzoTransaction tx(String id) => DinzoTransaction(
    id: id,
    date: '2026-10-05',
    type: 'DEBIT',
    amount: 68,
    description: 'Sorveteria',
    originalDescription: 'Compra a Vista sem Juros MasterCard',
    accountId: 'card',
  );

  Future<Record> linked(String dinzoId, {String? notes}) async {
    await db().addRecord(
      Record(
        -68,
        'Sorveteria',
        compras,
        DateTime.utc(2026, 10, 5, 12),
        walletId: 1,
        description: notes,
        dinzoId: dinzoId,
      ),
    );
    return (await db().getAllRecords())
        .whereType<Record>()
        .firstWhere((r) => r.dinzoId == dinzoId);
  }

  test('existing records get the bank name, the user notes stay', () async {
    final plain = await linked('a');
    final noted = await linked('b', notes: 'Era o mercado');
    final gone = await linked('c');
    await DinzoSyncService.writeBankNames(
      DinzoSyncPlan([
        DinzoPlanItem(
          kind: DinzoPlanKind.unchanged,
          transaction: tx('a'),
          existing: plain,
        ),
        DinzoPlanItem(
          kind: DinzoPlanKind.update,
          transaction: tx('b'),
          existing: noted,
        ),
        DinzoPlanItem(
          kind: DinzoPlanKind.remove,
          transaction: tx('c'),
          existing: gone,
        ),
      ]),
    );

    final notes = {
      for (final r in (await db().getAllRecords()).whereType<Record>())
        r.dinzoId: r.description,
    };
    expect(notes['a'], 'No banco: Compra a Vista sem Juros MasterCard');
    expect(
      notes['b'],
      'Era o mercado\nNo banco: Compra a Vista sem Juros MasterCard',
    );
    expect(notes['c'], isNull);
  });
}
