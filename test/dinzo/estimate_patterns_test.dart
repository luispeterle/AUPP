import 'package:flutter_test/flutter_test.dart';
import 'package:aupp/dinzo/dinzo-sync-service.dart';
import 'package:aupp/dinzo/estimate-link.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/models/category-type.dart';
import 'package:aupp/models/category.dart';
import 'package:aupp/models/recurrent-period.dart';
import 'package:aupp/models/recurrent-record-pattern.dart';
import 'package:aupp/services/recurrent-record-service.dart';
import 'package:aupp/services/service-config.dart';
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

  setUp(() async {
    await TestDatabaseHelper.setupTestDatabase();
  });

  final salary = Category('Salário', categoryType: CategoryType.income);

  /// "Salário" is already one of a new database's default categories.
  Future<void> addSalary() async {
    final db = ServiceConfig.database;
    if (await db.getCategory(salary.name!, salary.categoryType!) == null) {
      await db.addCategory(salary);
    }
  }
  final now = DateTime.now().toUtc();

  test(
    'estimates never become real records; future ones are only shown',
    () async {
      final db = ServiceConfig.database;
      await addSalary();
      final pattern = RecurrentRecordPattern(
        9000,
        'Salário (estimado)',
        salary,
        DateTime.utc(now.year, now.month - 3, 5, 12),
        RecurrentPeriod.EveryMonth,
        tags: {DinzoSyncService.estimateTag},
      );
      await db.addRecurrentRecordPattern(pattern);

      final future = await RecurrentRecordService().updateRecurrentRecords(
        DateTime.utc(now.year, now.month + 3, 28),
      );

      expect(await db.getAllRecords(), isEmpty);
      expect(future, isNotEmpty);
      expect(future.every((r) => r.isFutureRecord), isTrue);
      expect(
        future.every((r) => r.tags.contains(DinzoSyncService.estimateTag)),
        isTrue,
      );
      // Still there for the coming months.
      expect(await db.getRecurrentRecordPatterns(), hasLength(1));
    },
  );

  final accounting =
      Category('Contabilidade', categoryType: CategoryType.expense);

  Future<int> addReal(String title, DateTime day) =>
      ServiceConfig.database.addRecord(Record(-398, title, accounting, day));

  test('a past estimate stays until linked; linking renames the real record '
      'and deletes the estimate', () async {
    final db = ServiceConfig.database;
    await db.addCategory(accounting);
    final day = DateTime.utc(now.year, now.month, now.day - 2, 12);
    await db.addRecurrentRecordPattern(RecurrentRecordPattern(
      -400,
      'Contabilidade',
      accounting,
      day,
      RecurrentPeriod.EveryMonth,
      utcEndDate: day,
      tags: {DinzoSyncService.estimateTag},
    ));
    final end = DateTime.utc(now.year, now.month + 1, 28);

    final shown = await RecurrentRecordService().updateRecurrentRecords(end);
    expect(shown, hasLength(1));
    expect(EstimateLink.isOccurrence(shown.single), isTrue);
    expect(await db.getRecurrentRecordPatterns(), hasLength(1));

    final id = await addReal('PIX ESCRITORIO CONTABIL',
        DateTime.utc(now.year, now.month, now.day - 3, 9));
    expect(await EstimateLink.link(shown.single, id), isTrue);

    final real = (await db.getRecordById(id))!;
    expect(real.title, 'Contabilidade');
    expect(real.value, -398);
    final link = EstimateLink.decode(real.estimateLink)!;
    expect(link.patternId, shown.single.recurrencePatternId);
    expect(link.utcDateTime, day);
    expect(link.value, -400);
    expect(await db.getRecurrentRecordPatterns(), isEmpty);
    expect(await RecurrentRecordService().updateRecurrentRecords(end), isEmpty);
  });

  test('linking one month of a monthly estimate keeps the others', () async {
    final db = ServiceConfig.database;
    await db.addCategory(accounting);
    await db.addRecurrentRecordPattern(RecurrentRecordPattern(
      -400,
      'Contabilidade',
      accounting,
      DateTime.utc(now.year, now.month - 2, 1, 12),
      RecurrentPeriod.EveryMonth,
      tags: {DinzoSyncService.estimateTag},
    ));
    final end = DateTime.utc(now.year, now.month + 1, 1);

    final shown = await RecurrentRecordService().updateRecurrentRecords(end);
    expect(shown, hasLength(3));
    final id = await addReal('Contador', shown[1].utcDateTime);
    await EstimateLink.link(shown[1], id);

    final left = await RecurrentRecordService().updateRecurrentRecords(end);
    expect(left.map((r) => r.utcDateTime),
        [shown[0].utcDateTime, shown[2].utcDateTime]);
    expect(await db.getRecurrentRecordPatterns(), hasLength(1));
    expect(await db.getAllRecords(), hasLength(1));
  });

  test('an estimate consumed before links existed is still deleted', () async {
    final db = ServiceConfig.database;
    await db.addCategory(accounting);
    final day = DateTime.utc(now.year, now.month, now.day - 2, 12);
    await db.addRecurrentRecordPattern(RecurrentRecordPattern(
      -500,
      'Dentista',
      accounting,
      day,
      RecurrentPeriod.EveryMonth,
      utcEndDate: day,
      utcLastUpdate: day,
      tags: {DinzoSyncService.estimateTag},
    ));

    await RecurrentRecordService().updateRecurrentRecords(
      DateTime.utc(now.year, now.month + 1, 28),
    );

    expect(await db.getAllRecords(), isEmpty);
    expect(await db.getRecurrentRecordPatterns(), isEmpty);
  });

  test('normal recurrences still store their past occurrences', () async {
    final db = ServiceConfig.database;
    await addSalary();
    await db.addRecurrentRecordPattern(
      RecurrentRecordPattern(
        9000,
        'Salário',
        salary,
        DateTime.utc(now.year, now.month - 2, 5, 12),
        RecurrentPeriod.EveryMonth,
      ),
    );
    await RecurrentRecordService().updateRecurrentRecords(now);
    expect(await db.getAllRecords(), isNotEmpty);
  });
}
