import 'package:flutter_test/flutter_test.dart';
import 'package:aupp/budget_plan/budget-plan.dart';
import 'package:aupp/dinzo/split-payment.dart';
import 'package:aupp/models/category-type.dart';
import 'package:aupp/models/category.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/models/wallet.dart';
import 'package:aupp/services/service-config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest_all.dart' as tz;

import '../helpers/test_database.dart';

/// A Dinzo purchase paid partly with a caixinha (bike indoor: 1.630,80 of
/// which 600 came from Caixinha Saude).
void main() {
  final compras = Category('Compras', categoryType: CategoryType.expense);
  final db = () => ServiceConfig.database;
  late int saude;

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
    // A fresh database already has it, among the Dinzo categories.
    saude = await db().addWallet(
      Wallet('Caixinha Saude', initialAmount: 1255.5),
    );
  });

  Future<Record> bike() async {
    await db().addRecord(
      Record(
        -1630.8,
        'Bike Indoor',
        compras,
        DateTime.utc(2026, 10, 2, 15),
        walletId: 1,
        dinzoId: 'tx-bike',
      ),
    );
    return (await db().getAllRecords()).whereType<Record>().single;
  }

  Future<Map<String, double>> balances() async => {
    for (final w in await db().getWalletsBalanceAsOf(DateTime(2026, 10, 13)))
      w.name: w.balance ?? 0,
  };

  test('the caixinha pays its part: balances move, one purchase stays',
      () async {
    final purchase = await bike();
    final wallet = (await SplitPayment.payers(purchase)).single;
    expect(wallet.name, 'Caixinha Saude');

    await SplitPayment.save(purchase, wallet, 600);

    final b = await balances();
    expect(b['Caixinha Saude'], closeTo(655.5, 0.001));
    final part = (await SplitPayment.partOf(purchase))!;
    expect(part.isTransfer, isTrue);
    expect(part.walletId, saude);
    expect(part.transferWalletId, 1);
    expect(part.value, -600);
    expect(part.splitParentDinzoId, 'tx-bike');
  });

  test('saving again changes the part instead of adding another', () async {
    final purchase = await bike();
    final wallet = (await SplitPayment.payers(purchase)).single;
    await SplitPayment.save(purchase, wallet, 600);
    await SplitPayment.save(purchase, wallet, 500);
    final parts = (await db().getAllRecords())
        .whereType<Record>()
        .where((r) => r.isSplitPart)
        .toList();
    expect(parts, hasLength(1));
    expect(parts.single.value, -500);

    await SplitPayment.remove(purchase);
    expect(await SplitPayment.partOf(purchase), isNull);
  });

  test('deleting the purchase deletes the caixinha part', () async {
    final purchase = await bike();
    final wallet = (await SplitPayment.payers(purchase)).single;
    await SplitPayment.save(purchase, wallet, 600);

    await db().deleteRecordById(purchase.id);
    expect(await db().getAllRecords(), isEmpty);

    final again = await bike();
    await SplitPayment.save(again, wallet, 600);
    await db().deleteRecordsInBatch([again.id!]);
    expect(await db().getAllRecords(), isEmpty);
  });

  test('the budget counts only what left this month\'s money', () async {
    final purchase = await bike();
    final wallet = (await SplitPayment.payers(purchase)).single;
    await SplitPayment.save(purchase, wallet, 600);

    final plan = BudgetPlan(
      categories: {'Compras': 'conforto'},
      wallets: {'Caixinha Saude': 'metas'},
    );
    final usage = BudgetPlanUsage.compute(
      plan: plan,
      records: (await db().getAllRecords()).whereType<Record>(),
      walletsById: {
        for (final w in await db().getAllWallets()) w.id!: w,
      },
      defaultWalletId: 1,
      month: DateTime(2026, 10, 13),
      now: DateTime(2026, 10, 13, 18),
    );
    expect(usage.usedOf('conforto'), closeTo(1030.8, 0.001));
    expect(usage.usedOf('metas'), 0); // not a withdrawal from the goals
    final net = usage
        .recordsOf('conforto')
        .fold<double>(0, (t, r) => t + (r.value ?? 0));
    expect(net, closeTo(-1030.8, 0.001)); // drill-down nets the refund
  });
}
