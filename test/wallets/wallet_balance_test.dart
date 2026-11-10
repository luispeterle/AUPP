import 'package:flutter_test/flutter_test.dart';
import 'package:aupp/models/wallet.dart';
import 'package:aupp/services/database/database-interface.dart';
import 'package:aupp/services/database/sqlite-database.dart';
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
    ServiceConfig.localTimezone = "Europe/Vienna";
  });

  setUp(() async {
    await TestDatabaseHelper.setupTestDatabase();
  });

  Future<void> _insertRecord(dynamic rawDb, int walletId, double value) async {
    await rawDb.rawInsert("""
      INSERT INTO records (title, value, datetime, timezone, category_name, category_type, wallet_id)
      VALUES ('Record', ?, 1000000, 'UTC', 'House', 0, ?)
    """, [value, walletId]);
  }

  Future<void> _insertTransfer(dynamic rawDb, int srcWalletId, int destWalletId,
      double value) async {
    await rawDb.rawInsert(
      """
      INSERT INTO records (title, value, datetime, timezone, category_name, category_type, wallet_id, transfer_wallet_id)
      VALUES ('Transfer', ?, 1000000, 'UTC', 'House', 0, ?, ?)
    """,
      [value, srcWalletId, destWalletId],
    );
  }

  test('balance = SUM(records) + initial_amount', () async {
    DatabaseInterface db = ServiceConfig.database;
    SqliteDatabase sqliteDb = ServiceConfig.database as SqliteDatabase;
    final rawDb = (await sqliteDb.database)!;

    final walletId = await db.addWallet(Wallet('Test', initialAmount: 100.0));

    await _insertRecord(rawDb, walletId, -30.0); // expense
    await _insertRecord(rawDb, walletId, 50.0); // income

    final wallet = await db.getWalletById(walletId);
    // balance = (-30 + 50) + 100 = 120
    expect(wallet!.balance, closeTo(120.0, 0.001));
  });

  test('balance with no records equals initial_amount', () async {
    DatabaseInterface db = ServiceConfig.database;

    final walletId = await db.addWallet(Wallet('Empty', initialAmount: 500.0));
    final wallet = await db.getWalletById(walletId);
    expect(wallet!.balance, closeTo(500.0, 0.001));
  });

  test('updating initial_amount changes displayed balance', () async {
    DatabaseInterface db = ServiceConfig.database;
    SqliteDatabase sqliteDb = ServiceConfig.database as SqliteDatabase;
    final rawDb = (await sqliteDb.database)!;

    final walletId = await db.addWallet(Wallet('W', initialAmount: 0.0));
    await _insertRecord(rawDb, walletId, -20.0);

    // User wants balance to be 80: initial_amount = 80 - (-20) = 100
    final updated = Wallet('W', initialAmount: 100.0);
    await db.updateWallet(walletId, updated);

    final wallet = await db.getWalletById(walletId);
    // balance = (-20) + 100 = 80
    expect(wallet!.balance, closeTo(80.0, 0.001));
  });

  test('getAllWallets includes balance for each wallet', () async {
    DatabaseInterface db = ServiceConfig.database;
    SqliteDatabase sqliteDb = ServiceConfig.database as SqliteDatabase;
    final rawDb = (await sqliteDb.database)!;

    final id1 = await db.addWallet(Wallet('W1', initialAmount: 200.0));
    final id2 = await db.addWallet(Wallet('W2', initialAmount: 0.0));

    await _insertRecord(rawDb, id1, -50.0);
    await _insertRecord(rawDb, id2, 300.0);

    final wallets = await db.getAllWallets();
    final w1 = wallets.firstWhere((w) => w.id == id1);
    final w2 = wallets.firstWhere((w) => w.id == id2);

    expect(w1.balance, closeTo(150.0, 0.001)); // -50 + 200
    expect(w2.balance, closeTo(300.0, 0.001)); // 300 + 0
  });

  test('a transfer moves its amount to the destination', () async {
    DatabaseInterface db = ServiceConfig.database;
    SqliteDatabase sqliteDb = ServiceConfig.database as SqliteDatabase;
    final rawDb = (await sqliteDb.database)!;

    final w1 = await db.addWallet(Wallet('W1', initialAmount: 0));
    final w2 = await db.addWallet(Wallet('W2', initialAmount: 0));
    await _insertTransfer(rawDb, w1, w2, -50.0);

    expect((await db.getWalletById(w1))!.balance, closeTo(-50.0, 0.001));
    expect((await db.getWalletById(w2))!.balance, closeTo(50.0, 0.001));
  });
}
