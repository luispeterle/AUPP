import 'package:flutter_test/flutter_test.dart';
import 'package:aupp/dinzo/aporte-shortfall.dart';
import 'package:aupp/models/category.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/models/wallet.dart';
import 'package:aupp/services/service-config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest_all.dart' as tz;

import '../helpers/test_database.dart';

/// R$ 100 sent to a broker with only R$ 30 in the wallet to invest.
void main() {
  final db = () => ServiceConfig.database;
  late int investir;

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
    await db().addCategory(Category.investment());
    investir = await db().addWallet(
      Wallet('Investir', kind: WalletKind.toInvest, initialAmount: 30),
    );
  });

  Future<Record> aporte({double value = -100, String id = 'tx-1'}) async {
    await db().addRecord(
      Record(
        value,
        'Aporte no BTG',
        Category.investment(),
        DateTime.utc(2026, 11, 2, 12),
        walletId: investir,
        dinzoId: id,
      ),
    );
    final all = (await db().getAllRecords()).whereType<Record>();
    return all.firstWhere((r) => r.dinzoId == id);
  }

  Future<Map<String, double>> balances() async => {
    for (final w in await db().getWalletsBalanceAsOf(DateTime(2026, 11, 8)))
      w.name: w.balance ?? 0,
  };

  test('what the wallet to invest did not have is flagged', () async {
    final r = await aporte();
    await AporteShortfall.mark([r]);
    expect(r.investShortfall, 70);
  });

  test('enough money: nothing to flag', () async {
    final r = await aporte(value: -20);
    await AporteShortfall.mark([r]);
    expect(r.investShortfall, isNull);
  });

  test('confirming moves the rest from the default wallet', () async {
    final r = await aporte();
    final before = await balances();
    await AporteShortfall.cover(r, 70);

    final after = await balances();
    expect(after['Investir'], closeTo(0, 0.001));
    final defaultName = (await db().getDefaultWallet())!.name;
    expect(after[defaultName], closeTo(before[defaultName]! - 70, 0.001));

    final cover = (await AporteShortfall.coverOf(r))!;
    expect(cover.isTransfer, isTrue);
    expect(cover.transferWalletId, investir);
    expect(cover.value, -70);

    await AporteShortfall.mark([r]);
    expect(r.investShortfall, isNull);
  });

  test('deleting the aporte deletes its cover', () async {
    final r = await aporte();
    await AporteShortfall.cover(r, 70);
    await db().deleteRecordById(r.id);
    expect(await db().getAllRecords(), isEmpty);
  });

  test('only aportes from the Dinzo', () async {
    final r = await aporte(id: 'livre:inv:old:1');
    await AporteShortfall.mark([r]);
    expect(r.investShortfall, isNull);
  });
}
