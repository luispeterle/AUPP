// Fork: an upcoming occurrence edited by hand leaves its recurrence.
import 'package:aupp/models/category.dart';
import 'package:aupp/models/recurrent-period.dart';
import 'package:aupp/models/recurrent-record-pattern.dart';
import 'package:aupp/services/recurrent-record-service.dart';
import 'package:aupp/services/service-config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz;

void main() {
  setUpAll(() {
    tz.initializeTimeZones();
    ServiceConfig.localTimezone = 'UTC';
  });

  RecurrentRecordPattern water() => RecurrentRecordPattern(
        -100,
        'Água',
        Category('Água'),
        DateTime.utc(2030, 1, 10, 10),
        RecurrentPeriod.EveryMonth,
      )..timeZoneName = 'UTC';

  test('a skipped day is not generated, the others are', () {
    final pattern = water()..skip(DateTime(2030, 2, 10));
    final records = RecurrentRecordService()
        .generateRecurrentRecordsFromDateTime(pattern, DateTime.utc(2030, 3, 31));
    expect(records.map((r) => r.localDateTime.month), [1, 3]);
  });

  test('the skip outlives an edit of the recurrence (same map)', () {
    final pattern = water()..skip(DateTime(2030, 2, 10));
    final map = pattern.toMap()..['category'] = null;
    final back = RecurrentRecordPattern.fromMap(map)..timeZoneName = 'UTC';
    // The recurrence's amount changed; February stays out.
    back.value = -150;
    final records = RecurrentRecordService()
        .generateRecurrentRecordsFromDateTime(back, DateTime.utc(2030, 3, 31));
    expect(records.map((r) => r.localDateTime.month), [1, 3]);
    expect(records.every((r) => r.value == -150), isTrue);
  });

  test('code and marks go with the occurrence to its new day', () {
    final from = DateTime(2030, 2, 10);
    final to = DateTime(2030, 2, 14);
    final pattern = water()
      ..paymentCodes[RecurrentRecordPattern.occurrenceKey(from)] = '000201pix'
      ..setMarkedPaid(from, true)
      ..paymentCodes[RecurrentRecordPattern.chargeValueKey(from)] = '87.40'
      ..setDueDate(from, DateTime(2030, 2, 12));
    final item = RecurrentRecordPattern(-87.4, 'Água', null,
        DateTime.utc(2030, 2, 14), RecurrentPeriod.EveryMonth);

    pattern.moveOccurrenceTo(item, from, to);

    expect(pattern.paymentCodeFor(from), isNull);
    expect(pattern.isMarkedPaid(from), isFalse);
    expect(pattern.dueDateFor(from), isNull);
    expect(item.paymentCodeFor(to), '000201pix');
    expect(item.isMarkedPaid(to), isTrue);
    expect(item.paymentCodes[RecurrentRecordPattern.chargeValueKey(to)],
        '87.40');
    // The day was set by hand: the code counts as checked.
    expect(item.dueDateMissing(to), isFalse);
  });

  test('moving within the same item (a one-off changing day)', () {
    final from = DateTime(2030, 2, 10);
    final to = DateTime(2030, 2, 20);
    final once = water()
      ..utcEndDate = DateTime.utc(2030, 1, 10, 10)
      ..paymentCodes[RecurrentRecordPattern.occurrenceKey(from)] = '000201pix';
    once.moveOccurrenceTo(once, from, to);
    expect(once.paymentCodes.keys, containsAll(['2030-02-20', 'data:2030-02-20']));
    expect(once.paymentCodes.containsKey('2030-02-10'), isFalse);
  });

  test('happens once: ends on the day it starts', () {
    expect(water().happensOnce, isFalse);
    expect((water()..utcEndDate = DateTime.utc(2030, 1, 10, 10)).happensOnce,
        isTrue);
    expect((water()..utcEndDate = DateTime.utc(2030, 5, 10)).happensOnce,
        isFalse);
  });

  test('paid, an occurrence shows on the day it was paid; undone, back', () {
    final feb = DateTime(2030, 2, 10);
    final pattern = water()
      ..setDueDate(feb, DateTime(2030, 2, 12))
      ..setMarkedPaid(feb, true, on: DateTime(2030, 2, 5));
    List<String> days() => RecurrentRecordService()
        .generateRecurrentRecordsFromDateTime(pattern, DateTime.utc(2030, 3, 31))
        .map((r) => RecurrentRecordPattern.occurrenceKey(r.localDateTime))
        .toList();

    expect(days(), ['2030-01-10', '2030-02-05', '2030-03-10']);
    final paid = RecurrentRecordService()
        .generateRecurrentRecordsFromDateTime(pattern, DateTime.utc(2030, 3, 31))[1]
      ..occurrenceUtc = null;
    // The day it was paid still finds the recurrence's day.
    expect(pattern.occurrenceDayOf(paid), feb);

    pattern.setMarkedPaid(feb, false);
    expect(days()[1], '2030-02-12');
  });

  test('a mark from an older app leaves the occurrence on its day', () {
    final feb = DateTime(2030, 2, 10);
    final pattern = water()..setMarkedPaid(feb, true);
    expect(pattern.isMarkedPaid(feb), isTrue);
    expect(pattern.paidDateFor(feb), isNull);
    final records = RecurrentRecordService()
        .generateRecurrentRecordsFromDateTime(pattern, DateTime.utc(2030, 3, 31));
    expect(RecurrentRecordPattern.occurrenceKey(records[1].localDateTime),
        '2030-02-10');
  });
}
