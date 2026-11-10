import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:aupp/helpers/datetime-utility-functions.dart';
import 'package:aupp/models/category-type.dart';
import 'package:aupp/models/category.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/models/recurrent-period.dart';
import 'package:aupp/models/recurrent-record-pattern.dart';
import 'package:aupp/models/wallet.dart';
import 'package:aupp/records/controllers/tab_records_controller.dart';
import 'package:aupp/services/database/database-interface.dart';
import 'package:aupp/services/database/sqlite-database.dart';
import 'package:aupp/services/service-config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest_all.dart' as tz;

import 'helpers/test_database.dart';

void main() {
  late TabRecordsController controller;
  late SharedPreferences sharedPreferences;
  late DatabaseInterface database;

  final testCategory = Category(
    "Test Category",
    iconCodePoint: 1,
    categoryType: CategoryType.expense,
    color: Colors.blue,
  );

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting('en_US', null);

    // Initialize FFI for sqflite
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // Initialize timezone data
    tz.initializeTimeZones();
    ServiceConfig.localTimezone = "Europe/Vienna";
  });

  setUp(() async {
    // Initialize shared preferences with defaults
    SharedPreferences.setMockInitialValues({
    });
    sharedPreferences = await SharedPreferences.getInstance();
    ServiceConfig.sharedPreferences = sharedPreferences;

    // Create a new isolated in-memory database for each test
    await TestDatabaseHelper.setupTestDatabase();
    database = ServiceConfig.database;

    // Add test category
    await database.addCategory(testCategory);

    controller = TabRecordsController(onStateChanged: () {});
  });

  group('matchesSmartSearch', () {
    test('should match single word query', () {
      expect(
        controller.matchesSmartSearch('Product Name A', 'product'),
        isTrue,
      );
    });

    test('should match multi-word query (all words match)', () {
      expect(
        controller.matchesSmartSearch('Product Name A', 'product name'),
        isTrue,
      );
    });

    test('should match partial second word query', () {
      expect(
        controller.matchesSmartSearch('Product Name A', 'product n'),
        isTrue,
      );
    });

    test('should match when query has only start of each word', () {
      expect(
        controller.matchesSmartSearch('Product Name A', 'pro nam'),
        isTrue,
      );
    });

    test('should match case-insensitively with multi-word query', () {
      expect(
        controller.matchesSmartSearch('PRODUCT NAME A', 'product name'),
        isTrue,
      );
    });

    test('should match description field with multi-word query', () {
      expect(
        controller.matchesSmartSearch('Gas station purchase', 'gas station'),
        isTrue,
      );
    });

    test('should not match when one query term does not match any word', () {
      expect(
        controller.matchesSmartSearch('Product Name A', 'product xyz'),
        isFalse,
      );
    });

    test('should not match when no words match', () {
      expect(controller.matchesSmartSearch('Product Name A', 'xyz'), isFalse);
    });

    test('should return false for null text', () {
      expect(controller.matchesSmartSearch(null, 'query'), isFalse);
    });

    test('should return false for empty text', () {
      expect(controller.matchesSmartSearch('', 'query'), isFalse);
    });

    test('should return false for empty query', () {
      expect(controller.matchesSmartSearch('Product Name A', ''), isFalse);
    });

    test('should match with hyphenated words', () {
      expect(
        controller.matchesSmartSearch('well-known brand', 'well brand'),
        isTrue,
      );
    });

    test('should match single word against partial word', () {
      expect(controller.matchesSmartSearch('Product Name A', 'prod'), isTrue);
    });
  });

  group('shiftMonthWeekYear', () {
    test('should shift month forward by 1 with custom interval set to a full month', () async {
      // Setup: Custom interval is January 2025
      controller.customIntervalFrom = DateTime(2025, 1, 1);
      controller.customIntervalTo = getEndOfMonth(2025, 1);

      // Act: Shift forward by 1 month
      await controller.shiftInterval(1);

      // Assert: Should now be February 2025
      expect(controller.customIntervalFrom, DateTime(2025, 2, 1));
      expect(controller.customIntervalTo!.year, 2025);
      expect(controller.customIntervalTo!.month, 2);
      expect(
        controller.customIntervalTo!.day,
        28,
      ); // February has 28 days in 2025
    });

    test('should shift month backward by 1 with custom interval set to a full month', () async {
      // Setup: Custom interval is March 2025
      controller.customIntervalFrom = DateTime(2025, 3, 1);
      controller.customIntervalTo = getEndOfMonth(2025, 3);

      // Act: Shift backward by 1 month
      await controller.shiftInterval(-1);

      // Assert: Should now be February 2025
      expect(controller.customIntervalFrom, DateTime(2025, 2, 1));
      expect(controller.customIntervalTo!.year, 2025);
      expect(controller.customIntervalTo!.month, 2);
      expect(controller.customIntervalTo!.day, 28);
    });







    test('should update backgroundImageIndex to the new month', () async {
      // Setup: Custom interval is January
      controller.customIntervalFrom = DateTime(2025, 1, 1);
      controller.customIntervalTo = getEndOfMonth(2025, 1);

      // Act: Shift to February
      await controller.shiftInterval(1);

      // Assert: backgroundImageIndex should be February (2)
      expect(controller.backgroundImageIndex, 2);
    });

    test('should update header string when shifting', () async {
      // Setup: Custom interval is January 2025
      controller.customIntervalFrom = DateTime(2025, 1, 1);
      controller.customIntervalTo = getEndOfMonth(2025, 1);

      // Act: Shift to February
      await controller.shiftInterval(1);

      // Assert: Header should be updated (the app is in pt-BR)
      expect(controller.header, isNotEmpty);
      expect(controller.header.toLowerCase(), contains('fevereiro'));
    });

    test('should handle shifting across year boundary', () async {
      // Setup: December 2024
      controller.customIntervalFrom = DateTime(2024, 12, 1);
      controller.customIntervalTo = getEndOfMonth(2024, 12);

      // Act: Shift forward to January 2025
      await controller.shiftInterval(1);

      // Assert: Should be January 2025
      expect(controller.customIntervalFrom, DateTime(2025, 1, 1));
      expect(controller.customIntervalTo!.year, 2025);
      expect(controller.customIntervalTo!.month, 1);
    });

    test('should handle shifting backward across year boundary', () async {
      // Setup: January 2025
      controller.customIntervalFrom = DateTime(2025, 1, 1);
      controller.customIntervalTo = getEndOfMonth(2025, 1);

      // Act: Shift backward to December 2024
      await controller.shiftInterval(-1);

      // Assert: Should be December 2024
      expect(controller.customIntervalFrom, DateTime(2024, 12, 1));
      expect(controller.customIntervalTo!.year, 2024);
      expect(controller.customIntervalTo!.month, 12);
    });



  });

  group('_applyTransferAwareWalletFilter', () {
    final expenseCategory = Category(
      'Expense',
      iconCodePoint: 1,
      categoryType: CategoryType.expense,
      color: Colors.red,
    );
    final incomeCategory = Category(
      'Income',
      iconCodePoint: 2,
      categoryType: CategoryType.income,
      color: Colors.green,
    );

    Record expense({required int walletId, required double value}) => Record(
      value,
      'Expense',
      expenseCategory,
      DateTime(2026, 6, 1).toUtc(),
      walletId: walletId,
    );

    Record income({required int walletId, required double value}) => Record(
      value,
      'Income',
      incomeCategory,
      DateTime(2026, 6, 1).toUtc(),
      walletId: walletId,
    );

    Record transfer({
      required int sourceWalletId,
      required int destWalletId,
      required double value,
    }) => Record(
      value,
      'Transfer',
      expenseCategory,
      DateTime(2026, 6, 1).toUtc(),
      walletId: sourceWalletId,
      transferWalletId: destWalletId,
    );

    test('empty wallet set returns nothing', () {
      final records = [
        expense(walletId: 1, value: -50),
        transfer(sourceWalletId: 1, destWalletId: 2, value: -30),
      ];
      final result = TabRecordsController.applyTransferAwareWalletFilter(
        records,
        {},
      );
      expect(result, isEmpty);
    });

    test('non-transfer records for unselected wallet are excluded', () {
      final records = [
        expense(walletId: 1, value: -50),
        income(walletId: 2, value: 100),
      ];
      final result = TabRecordsController.applyTransferAwareWalletFilter(
        records,
        {1},
      );
      expect(result, hasLength(1));
      expect(result.first!.walletId, 1);
    });

    test('filter by source wallet: transfer included with original value', () {
      final records = [
        expense(walletId: 1, value: -50),
        income(walletId: 2, value: 100),
        transfer(sourceWalletId: 1, destWalletId: 2, value: -30),
      ];
      final result = TabRecordsController.applyTransferAwareWalletFilter(
        records,
        {1},
      );
      expect(result, hasLength(2));
      final t = result[1]!;
      expect(t.value, -30);
      expect(t.walletId, 1);
      expect(t.transferWalletId, 2);
      expect(t.isDestinationTransferView, false);
      // Only the source wallet is in view: color by sign (red), not neutral.
      expect(t.isSingleSideTransferView, true);
    });

    test('filter by destination wallet: transfer shown as positive, wallet IDs unchanged', () {
      final records = [
        expense(walletId: 1, value: -50),
        income(walletId: 2, value: 100),
        transfer(sourceWalletId: 1, destWalletId: 2, value: -30),
      ];
      final result = TabRecordsController.applyTransferAwareWalletFilter(
        records,
        {2},
      );
      expect(result, hasLength(2));
      final t = result[1]!;
      // value becomes positive received amount
      expect(t.value, 30);
      // wallet IDs are NOT swapped — source and destination remain correct
      expect(t.walletId, 1);
      expect(t.transferWalletId, 2);
      expect(t.isDestinationTransferView, true);
      // Only the destination wallet is in view: color by sign (green).
      expect(t.isSingleSideTransferView, true);
      // original record was not mutated
      expect(records[2].isDestinationTransferView, false);
      expect(records[2].isSingleSideTransferView, false);
    });

    test('destination view shows the amount received', () {
      final records = [
        transfer(sourceWalletId: 1, destWalletId: 2, value: -75),
      ];
      final result = TabRecordsController.applyTransferAwareWalletFilter(
        records,
        {2},
      );
      expect(result.first!.value, 75);
    });

    test(
      'both wallets selected: transfer appears once with source perspective',
      () {
        final records = [
          expense(walletId: 1, value: -50),
          income(walletId: 2, value: 100),
          transfer(sourceWalletId: 1, destWalletId: 2, value: -30),
        ];
        final result = TabRecordsController.applyTransferAwareWalletFilter(
          records,
          {1, 2},
        );
        expect(result, hasLength(3));
        final t = result[2]!;
        // Source perspective: unchanged
        expect(t.value, -30);
        expect(t.walletId, 1);
        expect(t.transferWalletId, 2);
        expect(t.isDestinationTransferView, false);
        // Both wallets are in view: neutral color, not red or green.
        expect(t.isSingleSideTransferView, false);
      },
    );

    test('transfer with null value does not crash, value stays null', () {
      final t = Record(
        null,
        'Null transfer',
        expenseCategory,
        DateTime(2026, 6, 1).toUtc(),
        walletId: 1,
        transferWalletId: 2,
      );
      final result = TabRecordsController.applyTransferAwareWalletFilter(
        [t],
        {2},
      );
      expect(result, hasLength(1));
      expect(result.first!.value, null);
      expect(result.first!.isDestinationTransferView, true);
    });

    test('null record in list is skipped', () {
      final result = TabRecordsController.applyTransferAwareWalletFilter(
        [null],
        {1},
      );
      expect(result, isEmpty);
    });
  });

  group('isPastPeriodEnd', () {
    test('a past month end is before today', () {
      final now = DateTime(2026, 7, 7);
      final intervalTo = DateTime(2026, 5, 31, 23, 59, 59);
      expect(TabRecordsController.isPastPeriodEnd(intervalTo, now), isTrue);
    });

    test(
      'the current month end (today still within the month) is not past',
      () {
        final now = DateTime(2026, 7, 7);
        final intervalTo = DateTime(2026, 7, 31, 23, 59, 59);
        expect(TabRecordsController.isPastPeriodEnd(intervalTo, now), isFalse);
      },
    );

    test('a period ending exactly at the start of today is not past', () {
      final now = DateTime(2026, 7, 7, 15, 30);
      final intervalTo = DateTime(2026, 7, 7, 0, 0, 0);
      expect(TabRecordsController.isPastPeriodEnd(intervalTo, now), isFalse);
    });

    test('a period ending yesterday at 23:59:59 is past', () {
      final now = DateTime(2026, 7, 7, 0, 30);
      final intervalTo = DateTime(2026, 7, 6, 23, 59, 59);
      expect(TabRecordsController.isPastPeriodEnd(intervalTo, now), isTrue);
    });

    test('a future period end is not past', () {
      final now = DateTime(2026, 7, 7);
      final intervalTo = DateTime(2026, 12, 31, 23, 59, 59);
      expect(TabRecordsController.isPastPeriodEnd(intervalTo, now), isFalse);
    });
  });

  group('point-in-time wallet balance for past periods', () {
    final testCategory2 = Category(
      'Test Category',
      iconCodePoint: 1,
      categoryType: CategoryType.expense,
      color: Colors.blue,
    );

    Future<void> _insertRecord(
      int walletId,
      double value,
      DateTime datetime,
    ) async {
      final sqliteDb = database as SqliteDatabase;
      final rawDb = (await sqliteDb.database)!;
      await rawDb.rawInsert(
        """
        INSERT INTO records (title, value, datetime, timezone, category_name, category_type, wallet_id)
        VALUES ('Record', ?, ?, 'UTC', ?, ?, ?)
      """,
        [
          value,
          datetime.toUtc().millisecondsSinceEpoch,
          testCategory2.name,
          testCategory2.categoryType!.index,
          walletId,
        ],
      );
    }


    test('the current month shows the balance at its end, including same-month records dated after today', () async {
      final walletId = await database.addWallet(
        Wallet('Test Wallet', initialAmount: 100.0),
      );
      final now = DateTime.now();
      final periodFrom = DateTime(now.year, now.month, 1);
      final periodTo = getEndOfMonth(now.year, now.month);

      // A persisted record dated later in the current month (relative to
      // "now", it may be in the future, but it's already in the DB — same as
      // if the user manually pre-entered it).
      final laterThisMonth = periodTo.isAfter(now.add(const Duration(days: 1)))
          ? now.add(const Duration(days: 1))
          : periodTo;
      await _insertRecord(walletId, -40.0, laterThisMonth);

      controller.updateCustomInterval(periodFrom, periodTo, 'This Month');
      await controller.updateRecurrentRecordsAndFetchRecords();

      expect(controller.balanceAsOfDate, isNotNull);
      final wallet = controller.allWallets.firstWhere((w) => w.id == walletId);
      // balance = initial(100) + record(-40) = 60: the record isn't excluded
      // just because it's dated a day after "now".
      expect(wallet.balance, closeTo(60.0, 0.001));
    });

    test('a future month counts the planned records of the months before it', () async {
      final walletId = await database.addWallet(
        Wallet('Test Wallet', initialAmount: 100.0),
      );
      final boxId = await database.addWallet(
        Wallet('Box', initialAmount: 0.0),
      );
      final now = DateTime.now();
      final firstPlanned = DateTime(now.year, now.month + 1, 10, 12);
      await database.addRecurrentRecordPattern(RecurrentRecordPattern(
        -50.0,
        'Rent',
        testCategory2,
        firstPlanned.toUtc(),
        RecurrentPeriod.EveryMonth,
        walletId: walletId,
      ));
      await database.addRecurrentRecordPattern(RecurrentRecordPattern(
        -20.0,
        'To the box',
        null,
        firstPlanned.toUtc(),
        RecurrentPeriod.EveryMonth,
        walletId: walletId,
        transferWalletId: boxId,
      ));

      final periodFrom = DateTime(now.year, now.month + 3, 1);
      final periodTo = getEndOfMonth(periodFrom.year, periodFrom.month);
      // Stored, but dated after the viewed month.
      await _insertRecord(walletId, -1000.0, periodTo.add(const Duration(days: 5)));

      controller.updateCustomInterval(periodFrom, periodTo, 'In 3 months');
      await controller.updateRecurrentRecordsAndFetchRecords();

      final wallet = controller.allWallets.firstWhere((w) => w.id == walletId);
      final box = controller.allWallets.firstWhere((w) => w.id == boxId);
      // 3 months of rent and transfers (next month up to the viewed one).
      expect(wallet.balance, closeTo(100.0 - 3 * 70.0, 0.001));
      expect(box.balance, closeTo(3 * 20.0, 0.001));
    });


    test('a future month counts every scheduled occurrence up to its end, not only its own', () async {
      final walletId = await database.addWallet(
        Wallet('Test Wallet', initialAmount: 1000.0),
      );
      final now = DateTime.now();
      // Monthly -100 from the 15th of next month on.
      await database.addRecurrentRecordPattern(RecurrentRecordPattern(
        -100.0,
        'Rent',
        testCategory2,
        DateTime(now.year, now.month + 1, 15).toUtc(),
        RecurrentPeriod.EveryMonth,
        walletId: walletId));

      Future<double?> balanceOf(int monthsAhead) async {
        final from = DateTime(now.year, now.month + monthsAhead, 1);
        controller.updateCustomInterval(
            from, getEndOfMonth(from.year, from.month), 'Month');
        await controller.updateRecurrentRecordsAndFetchRecords();
        return controller.allWallets
            .firstWhere((w) => w.id == walletId)
            .balance;
      }

      expect(await balanceOf(0), closeTo(1000.0, 0.001));
      expect(await balanceOf(1), closeTo(900.0, 0.001));
      // Three occurrences (next month, +2, +3), not only the one of +3.
      expect(await balanceOf(3), closeTo(700.0, 0.001));
    });
  });
}
