import 'package:flutter_test/flutter_test.dart';
import 'package:aupp/models/category-type.dart';
import 'package:aupp/models/category.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/services/service-config.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest_all.dart' as tz;

import '../helpers/test_database.dart';

/// Equal records on the same day (three tolls of R$ 5,50) are real and
/// distinct: the batch insert used by the backup restore dropped all but one,
/// and both batch inserts gave every tag to the first of them.
void main() {
  final db = () => ServiceConfig.database;
  final pedagio = Category('Pedágio', categoryType: CategoryType.expense);

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tz.initializeTimeZones();
    ServiceConfig.localTimezone = 'UTC';
  });

  setUp(() async {
    await TestDatabaseHelper.setupTestDatabase();
    // A fresh database already has it, among the Dinzo categories.
  });

  List<Record> tolls() => [
    for (final (id, tags) in [
      ('tx-1', {'C6', 'Crédito'}),
      ('tx-2', {'C6', 'Crédito'}),
      ('tx-3', {'C6', 'Crédito', 'Viagem'}),
    ])
      Record(
        -5.5,
        'VIASUL PORTO ALEGRE',
        pedagio,
        DateTime.utc(2026, 4, 12, 15),
        walletId: 1,
        dinzoId: id,
        tags: tags,
      ),
  ];

  Future<Map<String, Set<String>>> tagsByDinzoId() async => {
    for (final r in (await db().getAllRecords()).whereType<Record>())
      r.dinzoId!: r.tags,
  };

  test('a restore keeps identical records and each one gets its tags',
      () async {
    await db().addRecordsInBatch(tolls());
    expect(await tagsByDinzoId(), {
      'tx-1': {'C6', 'Crédito'},
      'tx-2': {'C6', 'Crédito'},
      'tx-3': {'C6', 'Crédito', 'Viagem'},
    });
  });

  test('restoring the same records again adds nothing', () async {
    await db().addRecordsInBatch(tolls());
    await db().addRecordsInBatch(tolls());
    expect(await db().getAllRecords(), hasLength(3));
  });

  test('the sync batch gives each identical record its own tags', () async {
    // An older equal record already in the database must not take the tags.
    await db().addRecordsInBatchNoDuplicateCheck([tolls().first]);
    await db().addRecordsInBatchNoDuplicateCheck(tolls().skip(1).toList());
    expect(await tagsByDinzoId(), {
      'tx-1': {'C6', 'Crédito'},
      'tx-2': {'C6', 'Crédito'},
      'tx-3': {'C6', 'Crédito', 'Viagem'},
    });
  });

  test('manual identical records inside one restore are all kept', () async {
    Record coffee() => Record(
      -5,
      'Café',
      pedagio,
      DateTime.utc(2026, 4, 12, 15),
      walletId: 1,
      tags: {'Manual'},
    );
    await db().addRecordsInBatch([coffee(), coffee()]);
    final all = (await db().getAllRecords()).whereType<Record>().toList();
    expect(all, hasLength(2));
    expect(all.every((r) => r.tags.contains('Manual')), isTrue);
  });
}
