// The Carteira tab: every class as a real day-by-day series, and several of
// them added up without making anything up.
import 'package:flutter_test/flutter_test.dart';
import 'package:aupp/dinzo/dinzo-taxes.dart';
import 'package:aupp/investments/asset-lots.dart';
import 'package:aupp/investments/benchmark.dart';
import 'package:aupp/investments/performance.dart';
import 'package:aupp/investments/portfolio.dart';

void main() {
  DateTime day(int d) => DateTime(2026, 10, d);

  test('the Dinzo purchases of a stock become its lots', () {
    final inv = DinzoInvestment.fromJson({
      'id': '1',
      'asset_key': 'k',
      'name': 'PETROBRAS PN',
      'code': 'PETR4',
      'type': 'EQUITY',
      'balance': 2635.5,
      'transactions': [
        {
          'id': 'a',
          'type': 'BUY',
          'date': '2026-10-26',
          'amount': 2456.22,
          'quantity': 47,
        },
        {
          'id': 'b',
          'type': 'BUY',
          'date': '2026-10-26',
          'amount': 156.81,
          'quantity': 3,
        },
        {
          'id': 'c',
          'type': 'SELL',
          'date': '2026-10-28',
          'amount': 100,
          'quantity': 2,
        },
        {'id': 'd', 'type': 'DIVIDEND', 'date': '2026-10-29', 'amount': 5},
      ],
    });
    final lots = dinzoLots([inv])['PETR4']!;
    expect(lots.map((l) => (l.quantity, l.cost)), [
      (47.0, 2456.22),
      (3.0, 156.81),
      (-2.0, -100.0),
    ]);
    expect(AssetLots.quantityOf(lots), 48);
  });

  test('two portfolios add up, and each day returns what the whole did', () {
    // A doubles from day 2 to day 3; B is bought on day 3 and stays.
    final a = [
      PortfolioPoint(day(1), 100, 100, 100, 1),
      PortfolioPoint(day(2), 100, 100, 100, 1),
      PortfolioPoint(day(3), 200, 100, 100, 2),
    ];
    final b = [PortfolioPoint(day(3), 300, 300, 300, 1)];
    final both = combineSeries([a, b]);
    expect(both.map((p) => p.value), [100, 100, 500]);
    expect(both.map((p) => p.invested), [100, 100, 400]);
    // What came in on day 3 is not gain: only A's doubling is.
    expect(both.last.index, 2);
  });

  test('a day missing in one keeps its last day', () {
    final a = [
      PortfolioPoint(day(1), 100, 100, 100, 1),
      PortfolioPoint(day(3), 110, 100, 100, 1.1),
    ];
    final b = [
      PortfolioPoint(day(1), 100, 100, 100, 1),
      PortfolioPoint(day(2), 100, 100, 100, 1),
      PortfolioPoint(day(3), 100, 100, 100, 1),
    ];
    final both = combineSeries([a, b]);
    expect(both.map((p) => p.value), [200, 200, 210]);
    expect(both.last.index, closeTo(1.05, 1e-9));
  });

  test('fixed income grows at its contracted rate from each deposit', () {
    final rates = BenchmarkRates({day(1): 0.001}, {day(1): 0.001}, day(3));
    final cdb = DinzoInvestment.fromJson({
      'id': '1',
      'asset_key': 'cdb',
      'name': 'CDB',
      'type': 'FIXED_INCOME',
      'balance': 1000,
      'rate': 100,
      'rate_type': 'CDI',
      'transactions': [
        {'id': 'a', 'type': 'BUY', 'date': '2026-10-01', 'amount': 1000},
      ],
    });
    final points = Performance.history([cdb], rates, day(3));
    expect(points.map((p) => p.date), [day(1), day(2), day(3)]);
    expect(points.last.value, closeTo(1000 * 1.001 * 1.001, 1e-6));
    expect(points.last.invested, 1000);
    expect(points.last.index, closeTo(1.001 * 1.001, 1e-9));
  });

  group('fixed income net of tax', () {
    final rates = BenchmarkRates(
      {for (var d = 1; d <= 31; d++) day(d): 0.001},
      {for (var d = 1; d <= 31; d++) day(d): 0.001},
      day(31),
    );
    DinzoInvestment cdb(double balance, List<Map<String, dynamic>> moves) =>
        DinzoInvestment.fromJson({
          'id': '1',
          'asset_key': 'cdb',
          'name': 'CDB',
          'type': 'FIXED_INCOME',
          'balance': balance,
          'rate': 100,
          'rate_type': 'CDI',
          'transactions': moves,
        });

    test('a sale leaves at what reached the account, and it ends at the '
        'balance the bank reports', () {
      final inv = cdb(520, [
        {'id': 'a', 'type': 'BUY', 'date': '2026-10-01', 'amount': 1000},
        {
          'id': 'b',
          'type': 'SELL',
          'date': '2026-10-03',
          'amount': 500,
          'net_amount': 490,
        },
      ]);
      final gross = Performance.history([inv], rates, day(5));
      expect(gross.last.invested, 500);
      final net = Performance.history([inv], rates, day(5), net: true);
      expect(net.last.invested, 510);
      expect(net.last.value, closeTo(520, 1e-9));
    });

    test('a position sold out holds nothing after its last sale', () {
      final inv = cdb(0, [
        {'id': 'a', 'type': 'BUY', 'date': '2026-10-01', 'amount': 1000},
        {
          'id': 'b',
          'type': 'SELL',
          'date': '2026-10-03',
          'amount': 900,
          'net_amount': 895,
        },
      ]);
      final gross = Performance.history([inv], rates, day(5));
      final net = Performance.history([inv], rates, day(5), net: true);
      expect(gross.last.value, 0);
      expect(net.last.value, 0);
      // The IR of the holding period is out from the first day.
      expect(net[1].value, lessThan(gross[1].value));
    });

    test('bought before the history: the tax withheld, as IR of 20%, gives '
        'back the cost and the day it went in', () {
      final inv = cdb(0, [
        {
          'id': 'b',
          'type': 'SELL',
          'date': '2026-10-20',
          'amount': 1100,
          'net_amount': 1080,
        },
      ]);
      final net = Performance.history([inv], rates, day(31), net: true);
      // 20 withheld = 20% of 100 of profit: 1000 went in.
      expect(net.first.invested, 1000);
      expect(net.first.date.isBefore(day(1)), isTrue);
      expect(net.last.invested, closeTo(-80, 1e-9));
      expect(net.last.value, 0);
    });

    test('a sale without tax from before the history is left out', () {
      final inv = cdb(0, [
        {
          'id': 'b',
          'type': 'SELL',
          'date': '2026-10-20',
          'amount': 1100,
          'net_amount': 1100,
        },
      ]);
      expect(Performance.history([inv], rates, day(31), net: true), isEmpty);
    });
  });
}
