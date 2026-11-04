import 'package:flutter_test/flutter_test.dart';
import 'package:aupp/investments/crypto-history.dart';

void main() {
  test('Kraken candles keep their UTC calendar day', () {
    // 2026-10-05 00:00 UTC, close 530.67
    const body =
        '{"error":[],"result":{"XXMRZUSD":[[1791158400,"1","2","0.5","530.67","1","1",1]],"last":1}}';
    final points = CryptoHistory.parseKrakenOhlc(body);
    expect(points.single.key, DateTime(2026, 10, 5));
    expect(points.single.value, 530.67);
  });

  test('USD prices use the last dollar rate on or before each day', () {
    final usd = [
      MapEntry(DateTime(2026, 10, 2), 10.0), // before any rate: dropped
      MapEntry(DateTime(2026, 10, 3), 10.0),
      MapEntry(DateTime(2026, 10, 4), 20.0), // weekend: Friday's rate
      MapEntry(DateTime(2026, 10, 6), 30.0),
    ];
    final rate = CryptoHistory.parseBcbSeries(
      '[{"data":"03/10/2026","valor":"5.0"},{"data":"06/10/2026","valor":"5.5"}]',
    );
    expect(CryptoHistory.convert(usd, rate).map((p) => p.value), [
      50.0,
      100.0,
      165.0,
    ]);
  });

  test('12 months use daily points; since the start, weekly before them', () {
    final now = DateTime(2026, 10, 12);
    final series = CryptoSeries(
      [
        MapEntry(DateTime(2025, 1, 1), 1),
        MapEntry(DateTime(2026, 10, 1), 2),
      ],
      [
        MapEntry(DateTime(2020, 1, 1), 1),
        MapEntry(DateTime(2023, 1, 1), 3),
      ],
    );
    expect(series.pointsFor(CryptoRange.year, now).map((p) => p.value), [2]);
    expect(
      series.pointsFor(CryptoRange.all, now).map((p) => p.value),
      [1, 3, 1, 2],
    );
    expect(
      series
          .pointsFor(CryptoRange.all, now, since: DateTime(2023, 1, 1))
          .map((p) => p.value),
      [3, 1, 2],
    );
  });
}
