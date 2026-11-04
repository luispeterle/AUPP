import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:aupp/models/category-type.dart';
import 'package:aupp/models/category.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/records/edit-record-page.dart';
import 'package:aupp/services/service-config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest_all.dart' as tz;

import 'helpers/test_database.dart';

final _testCategory = Category(
  'Groceries',
  color: Colors.green,
  categoryType: CategoryType.expense,
);

Widget _buildTestApp(Widget child) {
  return MaterialApp(home: child);
}

Finder _fieldByIdentifier(String identifier) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.identifier == identifier,
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tz.initializeTimeZones();
    // The machine's own zone: the page compares its date with the clock's day.
    ServiceConfig.localTimezone = 'America/Sao_Paulo';
    await initializeDateFormatting('en_US', null);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      // Use the plain text-field keyboard mode so the amount can be typed with
      // tester.enterText without dealing with the in-app keyboard overlay.
      'amountInputKeyboardType': 0,
      // Fork: "Dinzo only" mode (manual records off): one-off records are
      // estimates. A fresh install allows manual records.
      'allowManualRecords': false,
    });
    ServiceConfig.sharedPreferences = await SharedPreferences.getInstance();
    ServiceConfig.currencyLocale = const Locale('en', 'US');
    ServiceConfig.currencyNumberFormat = null;
    ServiceConfig.currencyNumberFormatWithoutGrouping = null;
    await TestDatabaseHelper.setupTestDatabase();
  });

  tearDown(() {
  });

  Future<void> pumpEditRecordPage(
    WidgetTester tester, {
    Record? passedRecord,
  }) async {
    await tester.pumpWidget(
      _buildTestApp(
        EditRecordPage(
          passedCategory: _testCategory,
          passedRecord: passedRecord,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder amountField() => find.descendant(
    of: _fieldByIdentifier('amount-field'),
    matching: find.byType(TextFormField),
  );

  // Runs real async work (the sqflite_common_ffi calls triggered by saving)
  // while still pumping frames, since widget tests otherwise use a fake clock.
  Future<void> settleWithRealAsync(
    WidgetTester tester, {
    int rounds = 40,
  }) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    await settleWithRealAsync(tester);
  }

  Future<List<Record?>> allRecords(WidgetTester tester) async {
    late List<Record?> records;
    await tester.runAsync(() async {
      records = await ServiceConfig.database.getAllRecords();
    });
    return records;
  }

  // Flush the amount listener's 2s debounce so no Timer is left pending.
  Future<void> flushTimers(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 3));
    await settleWithRealAsync(tester);
  }

  testWidgets(
    'with manual records off, a one-off record is an estimate, never a real record',
    (WidgetTester tester) async {
      await tester.runAsync(
        () => ServiceConfig.database.addCategory(_testCategory),
      );
      await pumpEditRecordPage(tester);

      expect(find.textContaining('vira estimativa'), findsOneWidget);
      await tester.enterText(amountField(), '25');
      await tester.pump();
      await tapSave(tester);

      // Today is not a future date: nothing is saved and the user is told why.
      expect(await allRecords(tester), isEmpty);
      expect(find.textContaining('precisa de uma data futura'), findsOneWidget);

      await flushTimers(tester);
    },
  );
}
