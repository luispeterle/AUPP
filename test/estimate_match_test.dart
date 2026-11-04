import 'package:flutter_test/flutter_test.dart';
import 'package:aupp/dinzo/dinzo-sync-service.dart';
import 'package:aupp/dinzo/estimate-link.dart';
import 'package:aupp/models/category-type.dart';
import 'package:aupp/models/category.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/models/records-per-day.dart';
import 'package:aupp/services/service-config.dart';
import 'package:timezone/data/latest_all.dart' as tz;

void main() {
  setUpAll(() {
    tz.initializeTimeZones();
    ServiceConfig.localTimezone = 'UTC';
  });

  final income = Category('Vale', categoryType: CategoryType.income);

  Record real(double value, int day, {int id = 1, String? dinzoId}) => Record(
    value,
    'real',
    income,
    DateTime.utc(2026, 11, day, 3),
    id: id,
    walletId: 1,
    dinzoId: dinzoId,
  );

  Record estimate(double value, int day) => Record(
    value,
    'estimativa',
    income,
    DateTime.utc(2026, 11, day),
    walletId: 1,
    recurrencePatternId: 'p',
    tags: {DinzoSyncService.estimateTag},
  )..isFutureRecord = true;

  test('same day and amount: only the real one counts', () {
    final occurrence = estimate(1300, 2);
    final received = real(1300, 2, dinzoId: 'livre:nikos:x');
    EstimateLink.markMatches([occurrence, received]);
    expect(occurrence.estimateMatch, same(received));
    expect(occurrence.countsAsIncome, isFalse);
    expect(occurrence.countsTowardTotals, isFalse);
    expect(occurrence.isOwnMove, isTrue);
    expect(received.countsAsIncome, isTrue);
    final day = RecordsPerDay(DateTime(2026, 11, 2), records: [occurrence, received]);
    expect(day.income, 1300);
  });

  test('another day or amount stays an estimate of its own', () {
    final otherDay = estimate(1300, 3);
    final otherAmount = estimate(1299.99, 2);
    EstimateLink.markMatches([otherDay, otherAmount, real(1300, 2)]);
    expect(otherDay.estimateMatch, isNull);
    expect(otherDay.countsAsIncome, isTrue);
    expect(otherAmount.estimateMatch, isNull);
  });

  test('one real record pairs with one estimate', () {
    final first = estimate(1300, 2);
    final second = estimate(1300, 2);
    EstimateLink.markMatches([first, second, real(1300, 2)]);
    expect(first.estimateMatch, isNotNull);
    expect(second.estimateMatch, isNull);
  });

  test('a record already linked is not offered again', () {
    final occurrence = estimate(1300, 2);
    final linked = real(1300, 2)..estimateLink = '{}';
    EstimateLink.markMatches([occurrence, linked]);
    expect(occurrence.estimateMatch, isNull);
  });

  test('a record made by the app can be linked; money moves cannot', () {
    expect(EstimateLink.canBeLinked(real(1300, 2, dinzoId: 'livre:nikos:x')), isTrue);
    final aporte = Record(
      -100,
      'Aporte',
      Category.investment(),
      DateTime.utc(2026, 11, 2),
      id: 2,
      walletId: 1,
    );
    expect(EstimateLink.canBeLinked(aporte), isFalse);
    expect(EstimateLink.canBeLinked(estimate(1300, 2)), isFalse);
  });
}
