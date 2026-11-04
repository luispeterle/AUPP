// Crypto and abroad follow each purchase on its own date.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:aupp/investments/asset-lots.dart';
import 'package:aupp/investments/benchmark.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/services/database/sqlite-database.dart';
import 'package:aupp/services/service-config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest_all.dart' as tz;

import 'helpers/test_database.dart';

void main() {
  group('history', () {
    final start = DateTime(2026, 1, 1);
    DateTime day(int n) => start.add(Duration(days: n));
    final rates = BenchmarkRates(
      {for (var i = 0; i < 10; i++) day(i): 0.01},
      const {},
      day(9),
    );

    test('holds each purchase only from its own day', () {
      final points = AssetLots.history(
        lots: {
          'BTC': [
            AssetLot(day: day(0), quantity: 1, cost: 100),
            AssetLot(day: day(2), quantity: 1, cost: 300),
          ],
        },
        priceOn: (_, d) => d.isBefore(day(2)) ? 100 : 300,
        rates: rates,
        today: day(3),
      );
      expect(points.map((p) => p.value), [100, 100, 600, 600]);
      expect(points.map((p) => p.invested), [100, 100, 400, 400]);
    });

    test('each purchase goes to the Selic on its own day', () {
      final points = AssetLots.history(
        lots: {
          'BTC': [
            AssetLot(day: day(0), quantity: 1, cost: 100),
            AssetLot(day: day(2), quantity: 1, cost: 100),
          ],
        },
        priceOn: (_, _) => 100,
        rates: rates,
        today: day(2),
      );
      expect(points[0].selic, 100);
      expect(points[1].selic, closeTo(101, 1e-9));
      expect(points[2].selic, closeTo(101 * 1.01 + 100, 1e-9));
    });

    test('without the amount paid, costs the price of its day', () {
      final points = AssetLots.history(
        lots: {
          'XMR': [AssetLot(day: day(0), quantity: 2)],
        },
        priceOn: (_, _) => 50,
        rates: rates,
        today: day(0),
      );
      expect(points.single.invested, 100);
    });

    test('a sale takes the money out', () {
      final points = AssetLots.history(
        lots: {
          'BTC': [
            AssetLot(day: day(0), quantity: 2, cost: 200),
            AssetLot(day: day(1), quantity: -1, cost: -150),
          ],
        },
        priceOn: (_, _) => 150,
        rates: rates,
        today: day(1),
      );
      expect(points.last.value, 150);
      expect(points.last.invested, 50);
    });

    test('what goes in is not counted as gain', () {
      final prices = {day(0): 100.0, day(1): 110.0, day(2): 110.0, day(3): 121.0};
      final points = AssetLots.history(
        lots: {
          'BTC': [
            AssetLot(day: day(0), quantity: 1, cost: 100),
            // A big purchase on a flat day.
            AssetLot(day: day(2), quantity: 100, cost: 11000),
          ],
        },
        priceOn: (_, d) => prices[d],
        rates: rates,
        today: day(3),
      );
      final performance = AssetLots.performance(points, rates);
      expect(performance.first.portfolio, 0);
      expect(performance[1].portfolio, closeTo(0.10, 1e-9));
      expect(performance[2].portfolio, closeTo(0.10, 1e-9));
      expect(performance[3].portfolio, closeTo(0.21, 1e-9));
    });

    test('a period starts from 0%, against the Selic of those days', () {
      final prices = {day(0): 100.0, day(1): 200.0, day(2): 220.0};
      final points = AssetLots.history(
        lots: {
          'BTC': [AssetLot(day: day(0), quantity: 1, cost: 100)],
        },
        priceOn: (_, d) => prices[d],
        rates: rates,
        today: day(2),
      );
      final performance = AssetLots.performance(points, rates, from: day(1));
      expect(performance.map((p) => p.date), [day(1), day(2)]);
      expect(performance.first.portfolio, 0);
      expect(performance.last.portfolio, closeTo(0.10, 1e-9));
      expect(performance.last.selic, closeTo(0.01, 1e-9));
    });

    test('a day without a price is skipped, not shown as zero', () {
      final points = AssetLots.history(
        lots: {
          'NVDA': [AssetLot(day: day(0), quantity: 1, cost: 100)],
        },
        priceOn: (_, d) => d.isBefore(day(2)) ? null : 120,
        rates: rates,
        today: day(3),
      );
      expect(points.map((p) => p.date), [day(2), day(3)]);
      expect(points.first.value, 120);
    });
  });

  group('links to the statement', () {
    late Database db;
    final database = SqliteDatabase.instance;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      tz.initializeTimeZones();
      ServiceConfig.localTimezone = 'America/Sao_Paulo';
      SharedPreferences.setMockInitialValues({});
      ServiceConfig.sharedPreferences = await SharedPreferences.getInstance();
      db = await TestDatabaseHelper.setupTestDatabase();
    });

    tearDown(() async {
      await db.close();
      SqliteDatabase.setDatabaseForTesting(null);
    });

    test('an entry that got another id is found again; one that is gone leaves '
        'the purchase, as manual', () async {
      final at = DateTime(2026, 3, 7, 12);
      final id = await database.addRecord(
        Record(-100, 'Compra', null, at.toUtc(), walletId: 1),
      );
      final row = (await db.query('records', where: 'id = ?', whereArgs: [id]))
          .single;
      await AssetLots.save('BTC', [
        AssetLot(
          day: at,
          quantity: 0.001,
          cost: 100,
          record: LotRecord(id, row['datetime'] as int, -100, 'Compra'),
        ),
      ]);

      // A restored backup renumbers the records.
      await db.rawUpdate('UPDATE records SET id = ? WHERE id = ?', [id + 50, id]);
      await AssetLots.checkLinks();
      expect(AssetLots.of('BTC').single.record?.id, id + 50);

      await database.deleteRecordById(id + 50);
      await AssetLots.checkLinks();
      final lot = AssetLots.of('BTC').single;
      expect(lot.record, isNull);
      expect(lot.cost, 100);
      expect(AssetLots.coins, {'BTC': 0.001});
    });

    test('a coin sold entirely is not held', () async {
      await AssetLots.save('XMR', [
        AssetLot(day: DateTime(2026), quantity: 1),
        AssetLot(day: DateTime(2026, 2), quantity: -1),
      ]);
      expect(AssetLots.coins, isEmpty);
    });
  });

  test('the file written by hand reads back', () {
    final lot = AssetLot.fromJson(
      jsonDecode(
        '{"id":"a","day":"2023-10-01","qty":0.5,"note":"x",'
        '"record":{"id":1,"at":2,"value":-3.0,"title":"t"}}',
      ),
    )!;
    expect(lot.day, DateTime(2023, 10, 1));
    expect(lot.quantity, 0.5);
    expect(lot.cost, isNull);
    expect(lot.record?.title, 't');
    expect(lot.toJson()['day'], '2023-10-01');
  });
}
