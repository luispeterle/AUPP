import 'package:aupp/accounts/money-accounts.dart';
import 'package:aupp/dinzo/estimate-link.dart';
import 'package:aupp/fiscal/fiscal-data.dart';
import 'package:aupp/fiscal/fiscal-estimates.dart';
import 'package:aupp/fiscal/fiscal-tables.dart';
import 'package:aupp/models/category-type.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/services/recurrent-record-service.dart';
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

  final now = DateTime.now();

  setUp(() async {
    await TestDatabaseHelper.setupTestDatabase();
    SharedPreferences.setMockInitialValues({});
    ServiceConfig.sharedPreferences = await SharedPreferences.getInstance();
    await MoneyAccounts.saveCompanies([
      Company(
        'Empresa Teste',
        ['Banco PJ'],
        null,
        FiscalData(
          regimes: [Regime(RegimeKind.simples, DateTime(now.year - 1, 1, 1))],
          autoEstimates: true,
          otherPayments: [
            OtherPayment('p1', YearMonth.of(now), 500, 'Taxa avulsa', day: 28),
          ],
        ),
      ),
    ]);
  });

  String? paymentPattern() =>
      MoneyAccounts.companies().single.fiscal.otherPayments.single.patternId;

  Future<List<String?>> titles() async => [
    for (final p in await ServiceConfig.database.getRecurrentRecordPatterns())
      p.title,
  ];

  test('a one-off payment linked to what paid it is not created again',
      () async {
    final db = ServiceConfig.database;
    await FiscalEstimates.refresh();
    final id = paymentPattern()!;
    expect(await db.getRecurrentRecordPattern(id), isNotNull);

    final occurrence = (await RecurrentRecordService().updateRecurrentRecords(
      DateTime.utc(now.year, now.month + 1),
    ))
        .singleWhere((r) => r.recurrencePatternId == id);
    final category =
        await db.getCategory('Impostos/Taxas', CategoryType.expense);
    final paid = await db.addRecord(
      Record(-500, 'Pix', category, DateTime.utc(now.year, now.month, 1, 12)),
    );
    await EstimateLink.link(occurrence, paid);
    expect(await db.getRecurrentRecordPattern(id), isNull);

    await FiscalEstimates.refresh();
    expect(paymentPattern(), id);
    expect(await titles(), isNot(contains('Taxa avulsa')));
  });

  test('a one-off payment whose estimate was deleted gets it back', () async {
    final db = ServiceConfig.database;
    await FiscalEstimates.refresh();
    final id = paymentPattern()!;
    await db.deleteRecurrentRecordPatternById(id);

    await FiscalEstimates.refresh();
    expect(paymentPattern(), isNot(id));
    expect(await titles(), contains('Taxa avulsa'));
  });
}
