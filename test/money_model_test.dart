import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:aupp/dinzo/daily-money.dart';
import 'package:aupp/dinzo/dinzo-models.dart';
import 'package:aupp/investments/aportes.dart';
import 'package:aupp/dinzo/dinzo-taxes.dart';
import 'package:aupp/models/category.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/models/wallet.dart';
import 'package:aupp/services/crypto-quote-service.dart';
import 'package:aupp/services/database/sqlite-database.dart';
import 'package:aupp/services/service-config.dart';
import 'package:aupp/settings/constants/preferences-keys.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest_all.dart' as tz;

import 'helpers/test_database.dart';

void main() {
  final database = () => ServiceConfig.database;
  late Database db;

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
    db = await TestDatabaseHelper.setupTestDatabase();
  });

  tearDown(() async {
    await db.close();
    SqliteDatabase.setDatabaseForTesting(null);
  });

  Future<Map<String, double>> balances() async => {
    for (final w in await database().getWalletsBalanceAsOf(DateTime(2030)))
      w.name: w.balance ?? w.initialAmount,
  };

  Future<int> addWallet(
    String name, {
    double initial = 0,
    WalletKind kind = WalletKind.normal,
  }) => database().addWallet(
    Wallet(name, initialAmount: initial, kind: kind),
  );

  group('the wallet to invest is what the others leave', () {
    Future<int> toInvest() =>
        addWallet('Guardar', kind: WalletKind.toInvest);

    Future<Record?> adjustment() async => (await database().getAllRecords())
        .whereType<Record>()
        .where((r) => r.isAdjustment)
        .firstOrNull;

    final today = DateTime(2026, 11, 15);

    test('interest raises only it, in one entry per month', () async {
      await addWallet('Viagem', initial: 300);
      await toInvest();
      await DailyMoney.reconcile(1000, now: today);
      await DailyMoney.reconcile(1010, now: today);
      final after = await balances();
      expect(after['Guardar'], 710);
      expect(after['Viagem'], 300);
      final entry = (await adjustment())!;
      expect(entry.value, 710);
      expect(entry.countsAsIncome, isFalse);
      expect(entry.countsAsExpense, isFalse);
      expect(entry.countsTowardTotals, isFalse);
    });

    test('money sent to a broker lowers it, and it can go negative', () async {
      await toInvest();
      await DailyMoney.reconcile(400, now: today);
      await DailyMoney.reconcile(100, now: today);
      expect((await balances())['Guardar'], 100);
      await DailyMoney.reconcile(-50, now: today);
      expect((await balances())['Guardar'], -50);
    });

    test('separating money for it keeps the sum', () async {
      final main = (await database().getDefaultWallet())!;
      final id = await toInvest();
      main.initialAmount = 5000;
      await database().updateWallet(main.id!, main);
      await DailyMoney.reconcile(5400, now: today);
      await database().addRecord(
        Record(
          -3000,
          'Separar',
          null,
          DateTime.utc(2026, 11, 2),
          walletId: main.id,
          transferWalletId: id,
        ),
      );
      await DailyMoney.reconcile(5400, now: today);
      final after = await balances();
      expect(after[main.name], 2000);
      expect(after['Guardar'], 3400);
    });

    test('an aporte split between wallets leaves nothing to adjust', () async {
      final main = (await database().getDefaultWallet())!;
      main.initialAmount = 5000;
      await database().updateWallet(main.id!, main);
      await toInvest();
      await DailyMoney.reconcile(5400, now: today);
      final before = (await adjustment())!.value;
      // An aporte from an older version: one entry in each wallet.
      final guardar = (await database().getAllWallets())
          .firstWhere((w) => w.isInvestmentReserve);
      for (final (n, walletId, value) in [
        (1, guardar.id, -400.0),
        (2, main.id, -2600.0),
      ]) {
        await database().addRecord(
          Record(
            value,
            'Aporte',
            Category.investment(),
            DateTime.utc(2026, 11, 10, 12),
            walletId: walletId,
            dinzoId: '${Aportes.prefix}k#$n',
          ),
        );
      }
      await DailyMoney.reconcile(2400, now: today);
      final after = await balances();
      expect(after[main.name], 2400);
      expect(after['Guardar'], 0);
      expect((await adjustment())!.value, before);

      final entries = (await database().getAllRecords())
          .whereType<Record>()
          .where((r) => r.isInvestmentBuy);
      expect(entries.map((r) => r.value).toSet(), {-400.0, -2600.0});
      expect(entries.every((r) => !r.countsAsExpense), isTrue);

      await Aportes.delete('k');
      expect(
        (await database().getAllRecords()).whereType<Record>().where(
          (r) => r.isInvestmentBuy,
        ),
        isEmpty,
      );
    });

    test('the first sync starts from the accounts, without an entry', () async {
      final main = (await database().getDefaultWallet())!;
      await database().addRecord(
        Record(
          -8000,
          'Histórico',
          Category('Mercado'),
          DateTime.utc(2026, 1, 1),
          walletId: main.id,
          dinzoId: 'dinzo-1',
        ),
      );
      await DailyMoney.reconcile(5000, spendable: 120, now: today);
      final after = await balances();
      expect(after[main.name], 120);
      expect(after[Wallet.toInvestName], 4880);
      expect(await adjustment(), isNull);
    });

    test('a coin is worth its last quote, or the ratio of its currency', () async {
      await ServiceConfig.sharedPreferences!.setString(
        PreferencesKeys.cryptoQuotesMain,
        jsonEncode({'BTC': 400000.0}),
      );
      expect(CryptoQuoteService.priceInMain('btc'), 400000.0);
      expect(CryptoQuoteService.priceInMain('XMR'), isNull);
    });
  });

  group('everyday banks', () {
    DinzoInvestment position(String type, String broker, double balance) =>
        DinzoInvestment(
          assetKey: '$type$broker',
          name: 'Ativo',
          type: type,
          balance: balance,
          broker: broker,
          movements: const [],
        );

    test('what an everyday bank holds is money, whatever it is', () {
      expect(
        DailyMoney.parkedIn([
          position('FIXED_INCOME', 'Nubank', 1000),
          position('EQUITY', 'Nubank', 700),
          position('MUTUAL_FUND', 'C6', 50),
          position('FIXED_INCOME', 'BTG', 400),
        ]),
        1750,
      );
    });

    test('a product can go against its bank, and the rest follows it', () async {
      DinzoInvestment product(String type, String? subType, String broker) =>
          DinzoInvestment.fromJson({
            'asset_key': '$type$subType$broker',
            'name': 'Ativo',
            'type': type,
            'sub_type': subType,
            'balance': 100,
            'broker': broker,
          });
      final cdb = product('FIXED_INCOME', 'CDB', 'Nubank');
      final stock = product('EQUITY', 'STOCK', 'Nubank');
      final fund = product('MUTUAL_FUND', null, 'Nubank');
      final atRico = product('EQUITY', 'STOCK', 'Rico');
      expect(DailyMoney.isMoney(stock), isTrue);
      expect(DailyMoney.isMoney(atRico), isFalse);

      await DailyBanks.chooseProduct('Nubank', 'Ações', false);
      expect(DailyMoney.isMoney(stock), isFalse);
      expect(DailyMoney.isMoney(fund), isTrue);
      expect(DailyBanks.isException('Nubank', 'Ações'), isTrue);
      expect(DailyBanks.isException('Nubank', 'CDB'), isFalse);

      // The bank changes what follows it; the exception keeps its side.
      await DailyBanks.choose('Nubank', false);
      expect(DailyMoney.isMoney(cdb), isFalse);
      expect(DailyMoney.isMoney(stock), isFalse);
      expect(DailyBanks.isException('Nubank', 'Ações'), isFalse);

      // Choosing what the bank is takes the exception away.
      await DailyBanks.choose('Nubank', true);
      await DailyBanks.chooseProduct('Nubank', 'Ações', true);
      expect(DailyBanks.isException('Nubank', 'Ações'), isFalse);
      await DailyBanks.chooseProduct('Nubank', 'Fundo', false);
      await DailyBanks.followBank('Nubank');
      expect(DailyMoney.parkedIn([cdb, stock, fund, atRico]), 300);
    });

    test('the user decides, against what each bank usually is', () async {
      expect(DailyBanks.isDaily('Nubank'), isTrue);
      expect(DailyBanks.isDaily('BTG'), isFalse);
      await DailyBanks.choose('BTG', true);
      await DailyBanks.choose('Nubank', false);
      expect(DailyBanks.isDaily('BTG'), isTrue);
      expect(DailyBanks.isDaily('Nubank'), isFalse);
      expect(
        DailyMoney.isMoney(position('FIXED_INCOME', 'BTG', 1)),
        isTrue,
      );
    });

    test('money at a broker is not in the balances', () async {
      final balances = DailyMoney.balances(
        [
          DinzoAccount(id: '1', type: 'BANK', title: 'x', balance: 10, connectorName: 'Nubank'),
          DinzoAccount(id: '2', type: 'BANK', title: 'y', balance: 99, connectorName: 'BTG Pactual'),
          DinzoAccount(id: '3', type: 'BANK', title: 'z', balance: 5),
          DinzoAccount(id: '4', type: 'CREDIT', title: 'c', balance: 3, connectorName: 'BTG Pactual'),
        ],
        [position('FIXED_INCOME', 'Nubank', 100)],
      );
      expect(balances.bank, 15);
      expect(balances.cardDebt, 3);
      expect(balances.money, 112);
      expect(balances.spendable, 12);
      expect(balances.complete, isTrue);
    });

    test('a card without a balance leaves the totals incomplete', () {
      final balances = DailyMoney.balances([
        DinzoAccount(id: '1', type: 'BANK', title: 'x', balance: 10, connectorName: 'Nubank'),
        DinzoAccount(id: '2', type: 'CREDIT', title: 'c', connectorName: 'C6 Bank'),
        // Not in the totals anyway: no balance is no loss.
        DinzoAccount(id: '3', type: 'BANK', title: 'y', connectorName: 'BTG Pactual'),
        DinzoAccount(id: '4', type: 'CREDIT', title: 'd', archived: true),
      ], const []);
      expect(balances.complete, isFalse);
      expect(balances.unknown, ['C6 Bank']);
    });
  });
}
