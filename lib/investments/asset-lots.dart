import 'dart:convert';

import 'package:aupp/services/crypto-quote-service.dart';
import 'package:aupp/services/database/sqlite-database.dart';
import 'package:aupp/services/service-config.dart';
import 'package:aupp/settings/constants/preferences-keys.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'benchmark.dart';
import 'performance.dart';

/// The entry of the statement a purchase is tied to. Besides the id, keeps what
/// the entry looked like, to find it again if the ids change (a restored JSON
/// backup renumbers the records) and to say what it was if it is gone.
class LotRecord {
  final int id;
  final int at;
  final double value;
  final String title;

  const LotRecord(this.id, this.at, this.value, this.title);

  Map<String, dynamic> toJson() => {
    'id': id,
    'at': at,
    'value': value,
    'title': title,
  };

  static LotRecord? fromJson(dynamic json) => json is Map
      ? LotRecord(
          json['id'] as int,
          json['at'] as int,
          (json['value'] as num).toDouble(),
          json['title'] as String? ?? '',
        )
      : null;
}

/// One purchase (or, with a negative [quantity], one sale) of an asset, in
/// crypto or abroad alike. The quantity held is the sum of these, so that each
/// one keeps its own date and price.
class AssetLot {
  final String id;
  final DateTime day;
  final double quantity;

  /// What was paid, in reais. Null: unknown, estimated by the price of the day.
  final double? cost;
  final LotRecord? record;
  final String? note;

  AssetLot({
    String? id,
    required DateTime day,
    required this.quantity,
    this.cost,
    this.record,
    this.note,
  }) : id = id ?? const Uuid().v4(),
       day = DateTime(day.year, day.month, day.day);

  AssetLot copyWith({LotRecord? record, bool unlink = false, double? cost}) =>
      AssetLot(
        id: id,
        day: day,
        quantity: quantity,
        cost: cost ?? this.cost,
        record: unlink ? null : record ?? this.record,
        note: note,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'day': _dayText(day),
    'qty': quantity,
    'cost': ?cost,
    'record': ?record?.toJson(),
    'note': ?note,
  };

  static AssetLot? fromJson(dynamic json) {
    if (json is! Map) return null;
    final day = DateTime.tryParse(json['day']?.toString() ?? '');
    final quantity = (json['qty'] as num?)?.toDouble();
    if (day == null || quantity == null) return null;
    return AssetLot(
      id: json['id'] as String?,
      day: day,
      quantity: quantity,
      cost: (json['cost'] as num?)?.toDouble(),
      record: LotRecord.fromJson(json['record']),
      note: json['note'] as String?,
    );
  }

  static String _dayText(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}

/// Price of an asset in reais on a day; null when the history does not reach it.
typedef PriceOn = double? Function(String asset, DateTime day);

/// One day of a portfolio that followed its real purchases.
class PortfolioPoint {
  final DateTime date;

  /// What was held on that day, at that day's prices.
  final double value;

  /// Money put in up to that day.
  final double invested;

  /// The same money, on the same days, had it gone to the Selic.
  final double selic;

  /// What the holdings did since the first purchase, without counting what
  /// went in as gain (1 = where it began).
  final double index;

  const PortfolioPoint(
    this.date,
    this.value,
    this.invested,
    this.selic,
    this.index,
  );
}

class AssetLots {
  /// Everything held, by asset (a coin's code or a ticker abroad).
  static Map<String, List<AssetLot>> get all {
    final raw = ServiceConfig.sharedPreferences?.getString(
      PreferencesKeys.assetLots,
    );
    if (raw == null) return {};
    try {
      return {
        for (final e in (jsonDecode(raw) as Map).entries)
          e.key.toString(): (e.value as List)
              .map(AssetLot.fromJson)
              .nonNulls
              .toList(),
      };
    } catch (_) {
      return {};
    }
  }

  static List<AssetLot> of(String asset) => sorted(all[asset] ?? const []);

  static List<AssetLot> sorted(Iterable<AssetLot> lots) =>
      lots.toList()..sort((a, b) => a.day.compareTo(b.day));

  static Future<void> save(String asset, List<AssetLot> lots) async {
    final current = all;
    if (lots.isEmpty) {
      current.remove(asset);
    } else {
      current[asset] = lots;
    }
    await ServiceConfig.sharedPreferences!.setString(
      PreferencesKeys.assetLots,
      jsonEncode({
        for (final e in current.entries)
          e.key: [for (final lot in e.value) lot.toJson()],
      }),
    );
  }

  static double quantityOf(Iterable<AssetLot> lots) =>
      lots.fold(0.0, (sum, lot) => sum + lot.quantity);

  /// What a lot cost: what was entered, or its quantity at the price of its
  /// day. Null if neither is known.
  static double? costOf(AssetLot lot, double? Function(DateTime) priceOn) {
    if (lot.cost != null) return lot.cost;
    final price = priceOn(lot.day);
    return price == null ? null : lot.quantity * price;
  }

  /// Day by day from the first purchase to [today]: what the lots were worth,
  /// what had gone in, and the same contributions at the Selic. A lot whose
  /// cost is unknown has no contribution to follow, and a day with an asset
  /// without a price is skipped, so the line only says what it knows.
  static List<PortfolioPoint> history({
    required Map<String, List<AssetLot>> lots,
    required PriceOn priceOn,
    required BenchmarkRates rates,
    required DateTime today,
  }) {
    final entries = [
      for (final e in lots.entries)
        for (final lot in e.value) (asset: e.key, lot: lot),
    ]..sort((a, b) => a.lot.day.compareTo(b.lot.day));
    if (entries.isEmpty) return const [];
    final last = DateTime(today.year, today.month, today.day);
    final held = <String, double>{};
    final result = <PortfolioPoint>[];
    var invested = 0.0;
    var selic = 0.0;
    var index = 1.0;
    final lastPrice = <String, double>{};
    var next = 0;
    for (
      var day = entries.first.lot.day;
      !day.isAfter(last);
      day = DateTime(day.year, day.month, day.day + 1)
    ) {
      selic *= 1 + BenchmarkRates.rateOn(rates.selic, day);
      // What was held coming into the day, before today's purchases.
      var before = 0.0, after = 0.0;
      for (final e in held.entries) {
        final price = priceOn(e.key, day);
        final previous = lastPrice[e.key];
        if (price == null || previous == null || e.value <= 0) continue;
        before += e.value * previous;
        after += e.value * price;
      }
      if (before > 0) index *= after / before;
      while (next < entries.length && !entries[next].lot.day.isAfter(day)) {
        final entry = entries[next++];
        held[entry.asset] = (held[entry.asset] ?? 0) + entry.lot.quantity;
        final cost = costOf(entry.lot, (d) => priceOn(entry.asset, d));
        if (cost != null) {
          invested += cost;
          selic += cost;
        }
      }
      var value = 0.0;
      var complete = true;
      for (final e in held.entries) {
        final price = priceOn(e.key, day);
        if (price == null) {
          complete = false;
          continue;
        }
        lastPrice[e.key] = price;
        value += e.value * price;
      }
      if (complete) {
        result.add(PortfolioPoint(day, value, invested, selic, index));
      }
    }
    return result;
  }

  /// [points] from [from] on (all of them when null) as returns from 0%, next
  /// to the Selic over the same days: the measure of the other portfolios.
  static List<PerformancePoint> performance(
    List<PortfolioPoint> points,
    BenchmarkRates rates, {
    DateTime? from,
  }) {
    final shown = from == null
        ? points
        : points.where((p) => !p.date.isBefore(from)).toList();
    if (shown.isEmpty) return const [];
    final result = <PerformancePoint>[];
    var selic = 1.0;
    var day = shown.first.date;
    for (final point in shown) {
      while (day.isBefore(point.date)) {
        selic *= 1 + BenchmarkRates.rateOn(rates.selic, day);
        day = DateTime(day.year, day.month, day.day + 1);
      }
      result.add(
        PerformancePoint(
          point.date,
          point.index / shown.first.index - 1,
          selic - 1,
        ),
      );
    }
    return result;
  }

  /// A lot's entry may have got another id, or be gone: looks for it by its
  /// date and value, and a lot without an entry stays, as a manual one.
  static Future<List<AssetLot>> _checkLinks(
    Database db,
    List<AssetLot> lots,
  ) async {
    final result = <AssetLot>[];
    for (final lot in lots) {
      final record = lot.record;
      if (record == null) {
        result.add(lot);
        continue;
      }
      final same = await db.query(
        'records',
        columns: ['id'],
        where: 'id = ? AND datetime = ? AND value = ?',
        whereArgs: [record.id, record.at, record.value],
      );
      if (same.isNotEmpty) {
        result.add(lot);
        continue;
      }
      final moved = await db.query(
        'records',
        columns: ['id'],
        where: 'datetime = ? AND value = ? AND title IS ?',
        whereArgs: [record.at, record.value, record.title],
        limit: 1,
      );
      result.add(
        moved.isEmpty
            ? lot.copyWith(unlink: true, cost: record.value.abs())
            : lot.copyWith(
                record: LotRecord(
                  moved.first['id'] as int,
                  record.at,
                  record.value,
                  record.title,
                ),
              ),
      );
    }
    return result;
  }

  /// A lot's entry may have got another id (a restored backup renumbers them),
  /// or be gone. Run when the purchases are about to be shown.
  static Future<void> checkLinks() async {
    final db = await SqliteDatabase.instance.database;
    if (db == null || SqliteDatabase.readOnly) return;
    for (final entry in all.entries) {
      await save(entry.key, sorted(await _checkLinks(db, entry.value)));
    }
  }

  /// Each coin held and how much, from its purchases.
  static Map<String, double> get coins {
    final result = <String, double>{};
    for (final entry in all.entries) {
      if (!CryptoQuoteService.isQuoted(entry.key)) continue;
      final quantity = quantityOf(entry.value);
      if (quantity > 0) result[entry.key.toUpperCase()] = quantity;
    }
    return result;
  }

  /// What the coins are worth in the main currency, at the last quotes.
  static double get coinsValue => coins.entries.fold(
    0.0,
    (sum, coin) =>
        sum + coin.value * (CryptoQuoteService.priceInMain(coin.key) ?? 0),
  );
}
