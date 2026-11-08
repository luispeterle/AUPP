// A record typed by hand moves the paper money wallet, never the default one.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:aupp/models/category-type.dart';
import 'package:aupp/models/category.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/models/wallet.dart';
import 'package:aupp/records/edit-record-page.dart';
import 'package:aupp/services/cash-wallet.dart';
import 'package:aupp/services/service-config.dart';
import 'package:aupp/settings/constants/preferences-keys.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest_all.dart' as tz;

import 'helpers/test_database.dart';

final _category = Category(
  'Mercado',
  color: Colors.green,
  categoryType: CategoryType.expense,
);

Finder _fieldByIdentifier(String identifier) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.identifier == identifier,
);

void main() {
  Future<void> start(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    ServiceConfig.sharedPreferences = await SharedPreferences.getInstance();
  }

  group('CashWallet', () {
    final conta = Wallet('Conta corrente', id: 1, isDefault: true);
    final papel = Wallet('Dinheiro em Papel', id: 2);

    test('nothing chosen: none', () async {
      await start({});
      expect(CashWallet.findIn([conta, papel]), isNull);
    });

    test('chosen by name, whatever the case and spaces', () async {
      await start({PreferencesKeys.cashWallet: ' dinheiro em papel'});
      expect(CashWallet.findIn([conta, papel]), papel);
    });

    test('an archived wallet is not used', () async {
      await start({PreferencesKeys.cashWallet: 'Dinheiro em Papel'});
      final archived = Wallet('Dinheiro em Papel', id: 2, isArchived: true);
      expect(CashWallet.findIn([conta, archived]), isNull);
    });

    test('a renamed wallet stays chosen', () async {
      await start({PreferencesKeys.cashWallet: 'Papel'});
      await CashWallet.rename('papel', 'Dinheiro em Papel');
      expect(CashWallet.name, 'Dinheiro em Papel');
    });
  });

  group('new record', () {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      tz.initializeTimeZones();
      ServiceConfig.localTimezone = 'America/Sao_Paulo';
      await initializeDateFormatting('en_US', null);
    });

    setUp(() async {
      await start({
        'amountInputKeyboardType': 0,
        PreferencesKeys.cashWallet: 'Dinheiro em Papel',
      });
      ServiceConfig.currencyLocale = const Locale('en', 'US');
      ServiceConfig.currencyNumberFormat = null;
      ServiceConfig.currencyNumberFormatWithoutGrouping = null;
      await TestDatabaseHelper.setupTestDatabase();
    });

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    /// Types 25 in a new expense, saves it and returns its wallet.
    Future<int?> saveExpense(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(home: EditRecordPage(passedCategory: _category)),
      );
      // The page reads its wallets from the database (real async).
      await settle(tester);
      await tester.enterText(
        find.descendant(
          of: _fieldByIdentifier('amount-field'),
          matching: find.byType(TextFormField),
        ),
        '25',
      );
      await tester.pump();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await settle(tester);
      late List<Record?> records;
      await tester.runAsync(() async {
        records = await ServiceConfig.database.getAllRecords();
      });
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);
      expect(records, hasLength(1));
      return records.single!.walletId;
    }

    late int contaId;
    late int papelId;

    Future<void> addWallets(WidgetTester tester) async {
      await tester.runAsync(() async {
        final db = ServiceConfig.database;
        await db.addCategory(_category);
        contaId = (await db.getDefaultWallet())!.id!;
        papelId = await db.addWallet(Wallet('Dinheiro em Papel', sortOrder: 1));
      });
    }

    testWidgets('goes to the paper money wallet', (tester) async {
      await addWallets(tester);
      expect(await saveExpense(tester), papelId);
    });

    testWidgets('without one chosen, stays on the default wallet', (
      tester,
    ) async {
      await ServiceConfig.sharedPreferences!.remove(PreferencesKeys.cashWallet);
      await addWallets(tester);
      expect(await saveExpense(tester), contaId);
    });
  });
}
