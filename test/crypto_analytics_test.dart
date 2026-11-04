import 'package:flutter_test/flutter_test.dart';
import 'package:aupp/investments/crypto-analytics.dart';
import 'package:aupp/investments/crypto-history.dart';

void main() {
  test('a position has its cost, what it made and its average', () {
    final p = CryptoPosition('XMR', 2, 300, cost: 200, costIsEstimate: true);
    expect(p.averagePrice, 100);
    expect(p.profit, 400);
    expect(p.profitPct, 200);
    expect(CryptoPosition('XMR', 2, 300).profit, isNull);
  });

  test('the price on a day is the last one known', () {
    final points = [
      MapEntry(DateTime(2026, 1, 1), 10.0),
      MapEntry(DateTime(2026, 1, 8), 20.0),
    ];
    expect(CryptoAnalytics.priceOn(points, DateTime(2025, 12, 31)), isNull);
    expect(CryptoAnalytics.priceOn(points, DateTime(2026, 1, 1)), 10);
    expect(CryptoAnalytics.priceOn(points, DateTime(2026, 1, 7)), 10);
    expect(CryptoAnalytics.priceOn(points, DateTime(2026, 2, 1)), 20);
  });

  test('daily history replaces weekly where both exist', () {
    final merged = CryptoAnalytics.merged(
      CryptoSeries(
        [MapEntry(DateTime(2025, 1, 1), 2)],
        [MapEntry(DateTime(2024, 1, 1), 1), MapEntry(DateTime(2025, 1, 6), 9)],
      ),
    );
    expect(merged.map((p) => p.value), [1, 2]);
  });

  test('next halving at block 1,050,000', () {
    expect(BtcHalving.nextHeight(971127), 1050000);
    final date = BtcHalving.estimate(1050000, 971127, DateTime(2026, 10, 12));
    expect(date.year, 2028);
    expect(
      BtcHalving.guessTip(DateTime.utc(2026, 10, 12)),
      closeTo(971000, 2000),
    );
  });
}
