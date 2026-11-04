import 'crypto-history.dart';

/// One coin held (all wallets of that coin together), in one currency.
class CryptoPosition {
  final String code;
  final double quantity;

  /// Price of one coin now.
  final double price;

  /// What was paid, adding its purchases. Null when one of them is unknown.
  final double? cost;

  /// Part of [cost] comes from the price of the day, not from what was paid.
  final bool costIsEstimate;

  CryptoPosition(
    this.code,
    this.quantity,
    this.price, {
    this.cost,
    this.costIsEstimate = false,
  });

  double get value => quantity * price;

  double? get averagePrice =>
      cost == null || quantity <= 0 ? null : cost! / quantity;
  double? get profit => cost == null ? null : value - cost!;
  double? get profitPct =>
      cost == null || cost! <= 0 ? null : (value / cost! - 1) * 100;
}

class CryptoAnalytics {
  /// Last price on or before [day] (null before the first point).
  static double? priceOn(
    List<MapEntry<DateTime, double>> points,
    DateTime day,
  ) {
    var low = 0, high = points.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (points[middle].key.isAfter(day)) {
        high = middle;
      } else {
        low = middle + 1;
      }
    }
    return low == 0 ? null : points[low - 1].value;
  }

  /// Daily points where there are any, weekly before that: the longest and
  /// finest history of a coin.
  static List<MapEntry<DateTime, double>> merged(CryptoSeries series) {
    final firstDaily = series.daily.isEmpty ? null : series.daily.first.key;
    return [
      for (final p in series.weekly)
        if (firstDaily == null || p.key.isBefore(firstDaily)) p,
      ...series.daily,
    ];
  }
}

/// Bitcoin halvings: every 210,000 blocks, ~10 minutes each.
class BtcHalving {
  static const int interval = 210000;

  /// Past halvings (UTC dates).
  static final past = [
    DateTime(2012, 11, 28),
    DateTime(2016, 7, 9),
    DateTime(2020, 5, 11),
    DateTime(2024, 4, 20),
  ];

  static int nextHeight(int height) => (height ~/ interval + 1) * interval;

  /// When block [height] is expected, from the current [tip] at [now].
  static DateTime estimate(int height, int tip, DateTime now) =>
      now.add(Duration(minutes: (height - tip) * 10));

  /// Rough tip from the last halving, when the network is unreachable.
  static int guessTip(DateTime now) =>
      4 * interval +
      now.difference(DateTime.utc(2024, 4, 20, 0, 9)).inMinutes ~/ 10;
}
