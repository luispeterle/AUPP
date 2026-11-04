import 'package:aupp/services/automatic-writes.dart';
import 'package:aupp/dinzo/dinzo-sync-service.dart';
import 'package:aupp/dinzo/estimate-link.dart';
import 'package:aupp/helpers/datetime-utility-functions.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/models/recurrent-period.dart';
import 'package:aupp/models/recurrent-record-pattern.dart';
import 'package:aupp/services/service-config.dart';
import 'package:timezone/timezone.dart' as tz; // Import the timezone package

import 'database/database-interface.dart';
import 'database/sqlite-database.dart';
import 'logger.dart';

class RecurrentRecordService {
  static final _logger = Logger.withClass(RecurrentRecordService);

  DatabaseInterface database = ServiceConfig.database;
  RecurrentRecordService();

  /// "Já paguei" on one occurrence (or undoes it), saved on its recurrence.
  static Future<void> setMarkedPaid(Record occurrence, bool paid) async {
    final db = ServiceConfig.database;
    final pattern =
        await db.getRecurrentRecordPattern(occurrence.recurrencePatternId);
    if (pattern == null) return;
    pattern.setMarkedPaid(pattern.occurrenceDayOf(occurrence), paid);
    await db.updateRecordPatternById(pattern.id, pattern);
    occurrence.markedPaid = paid;
  }

  /// The day an occurrence shows: its due date when one was read from its
  /// code ([RecurrentRecordPattern.dueDateFor]), at the recurrence's time.
  static tz.TZDateTime _shownDate(
      RecurrentRecordPattern pattern, tz.TZDateTime occurrence) {
    final due = pattern.dueDateFor(occurrence);
    if (due == null) return occurrence;
    return tz.TZDateTime(occurrence.location, due.year, due.month, due.day,
        occurrence.hour, occurrence.minute, occurrence.second);
  }

  List<Record> generateRecurrentRecordsFromDateTime(
      RecurrentRecordPattern recordPattern, DateTime utcEndDate) {
    try {
      _logger.debug(
          'Generating recurrent records for pattern: ${recordPattern.title}');
      final List<Record> newRecurrentRecords = [];

      // 1. Get the TZLocation for the pattern's original timezone
      final tz.Location patternLocation =
          getLocation(recordPattern.timeZoneName!);

      // 2. Convert the start and end dates to TZDateTime objects
      final tz.TZDateTime startDate =
          tz.TZDateTime.from(recordPattern.utcDateTime, patternLocation);

      // Use the pattern's end date if it exists and is before the requested end date
      DateTime effectiveEndDate = utcEndDate;
      if (recordPattern.utcEndDate != null &&
          recordPattern.utcEndDate!.isBefore(utcEndDate)) {
        effectiveEndDate = recordPattern.utcEndDate!;
        _logger.debug('Using pattern end date: ${effectiveEndDate}');
      }

      final tz.TZDateTime endDateTz =
          tz.TZDateTime.from(effectiveEndDate, patternLocation);

      // 3. Determine the last update date in the pattern's timezone
      tz.TZDateTime? lastUpdateTz = recordPattern.utcLastUpdate != null
          ? tz.TZDateTime.from(recordPattern.utcLastUpdate!, patternLocation)
          : null;

      if (lastUpdateTz == null) {
        // If there's no last update, add the initial record.
        final newRecord = Record(
          recordPattern.valueFor(startDate),
          recordPattern.title,
          recordPattern.category,
          _shownDate(recordPattern, startDate).toUtc(),
          timeZoneName: patternLocation.name,
          description: recordPattern.description,
          recurrencePatternId: recordPattern.id,
          walletId: recordPattern.walletId,
          transferWalletId: recordPattern.transferWalletId,
          transferValue: recordPattern.transferValue,
          tags: recordPattern.tags,
        );
        newRecord.occurrenceUtc = startDate.toUtc();
        newRecurrentRecords.add(newRecord);
        lastUpdateTz = startDate;
      }

      if (endDateTz.isBefore(lastUpdateTz)) {
        return [];
      }

      // Helper function to add records with a given interval.
      // Fork: every occurrence sits on the start date's grid (start + k
      // periods), counted from the start and not from the last stored one:
      // a start date changed later (another weekday, another day of the
      // month) moves the occurrences still to come.
      void addRecordsByPeriod(int periodValue, {bool isMonth = false}) {
        final tz.TZDateTime after = lastUpdateTz!;

        // Store the original day, hour, minute, and second from the pattern's start date.
        // This is crucial for maintaining consistency across DST changes and month-end rollovers.
        final int originalStartDay = recordPattern.localDateTime.day;
        final int originalHour = recordPattern.localDateTime.hour;
        final int originalMinute = recordPattern.localDateTime.minute;
        final int originalSecond = recordPattern.localDateTime.second;

        tz.TZDateTime occurrence(int k) {
          if (!isMonth) {
            // Calendar days, not durations: DST changes don't shift the time.
            return tz.TZDateTime(
              patternLocation,
              startDate.year,
              startDate.month,
              startDate.day + k * periodValue,
              originalHour,
              originalMinute,
              originalSecond,
            );
          }
          final int months = startDate.month - 1 + k * periodValue;
          final int targetYear = startDate.year + months ~/ 12;
          final int targetMonth = months % 12 + 1;
          final candidate = tz.TZDateTime(
            patternLocation,
            targetYear,
            targetMonth,
            originalStartDay,
            originalHour,
            originalMinute,
            originalSecond,
          );
          // Day 31 in a shorter month: the last day of that month.
          if (candidate.month != targetMonth) {
            return tz.TZDateTime(
              patternLocation,
              targetYear,
              targetMonth + 1,
              0,
              originalHour,
              originalMinute,
              originalSecond,
            );
          }
          return candidate;
        }

        // First occurrence after the last one stored (or the start).
        final int elapsed = isMonth
            ? (after.year - startDate.year) * 12 + after.month - startDate.month
            : DateTime.utc(after.year, after.month, after.day)
                .difference(
                    DateTime.utc(startDate.year, startDate.month, startDate.day))
                .inDays;
        int k = elapsed <= 0 ? 0 : elapsed ~/ periodValue;
        while (k > 0 && occurrence(k - 1).isAfter(after)) {
          k--;
        }
        while (!occurrence(k).isAfter(after)) {
          k++;
        }

        while (true) {
          final tz.TZDateTime nextDate = occurrence(k++);

          // Check if the newly calculated date is within the bounds.
          if (nextDate.isBefore(endDateTz) ||
              nextDate.isAtSameMomentAs(endDateTz)) {
            final newRecord = Record(
              recordPattern.valueFor(nextDate),
              recordPattern.title,
              recordPattern.category,
              _shownDate(recordPattern, nextDate).toUtc(),
              timeZoneName: patternLocation.name,
              description: recordPattern.description,
              recurrencePatternId: recordPattern.id,
              walletId: recordPattern.walletId,
              transferWalletId: recordPattern.transferWalletId,
              transferValue: recordPattern.transferValue,
              tags: recordPattern.tags,
            );
            newRecord.occurrenceUtc = nextDate.toUtc();
            newRecurrentRecords.add(newRecord);
          } else {
            // We've gone past the end date, so stop.
            break;
          }
        }
      }

      switch (recordPattern.recurrentPeriod) {
        case RecurrentPeriod.EveryDay:
          addRecordsByPeriod(1);
          break;
        case RecurrentPeriod.EveryWeek:
          addRecordsByPeriod(7);
          break;
        case RecurrentPeriod.EveryTwoWeeks:
          addRecordsByPeriod(14);
          break;
        case RecurrentPeriod.EveryFourWeeks:
          addRecordsByPeriod(28);
          break;
        case RecurrentPeriod.EveryMonth:
          addRecordsByPeriod(1, isMonth: true);
          break;
        case RecurrentPeriod.EveryThreeMonths:
          addRecordsByPeriod(3, isMonth: true);
          break;
        case RecurrentPeriod.EveryFourMonths:
          addRecordsByPeriod(4, isMonth: true);
          break;
        case RecurrentPeriod.EveryYear:
          addRecordsByPeriod(12, isMonth: true);
          break;
        case RecurrentPeriod.Custom:
          final unit = recordPattern.customIntervalUnit;
          final value = recordPattern.customIntervalValue;
          if (unit == null || value == null || value <= 0) {
            _logger.warning(
                'Skipping pattern with invalid custom interval: ${recordPattern.title}');
            break;
          }
          switch (unit) {
            case CustomIntervalUnit.day:
              addRecordsByPeriod(value);
              break;
            case CustomIntervalUnit.week:
              addRecordsByPeriod(value * 7);
              break;
            case CustomIntervalUnit.month:
              addRecordsByPeriod(value, isMonth: true);
              break;
            case CustomIntervalUnit.year:
              addRecordsByPeriod(value * 12, isMonth: true);
              break;
          }
          break;
        default:
          break;
      }

      _logger.info(
          'Generated ${newRecurrentRecords.length} recurrent records for: ${recordPattern.title}');
      return newRecurrentRecords;
    } catch (e, st) {
      _logger.handle(e, st,
          'Failed to generate recurrent records for: ${recordPattern.title}');
      rethrow;
    }
  }

  /// The update running now. Several screens ask for one when the app opens:
  /// run together, each read the patterns before the other saved them and the
  /// same occurrence was stored twice. One at a time, the next one sees what
  /// the previous one stored.
  static Future<void> _running = Future.value();

  Future<List<Record>> updateRecurrentRecords(DateTime endDate) {
    final update = _running.then(
      (_) => AutomaticWrites.run(() => _updateRecurrentRecords(endDate)),
    );
    _running = update.then((_) {}, onError: (_) {});
    return update;
  }

  Future<List<Record>> _updateRecurrentRecords(DateTime endDate) async {
    try {
      _logger.info('Starting recurrent records update...');
      List<RecurrentRecordPattern> patterns =
          await database.getRecurrentRecordPatterns();

      _logger.debug('Processing ${patterns.length} recurrent patterns');

      // Use end of current day (23:59:59.999) in local device time for splitting
      // past/future records. Using UTC would prematurely persist records that are
      // still "tomorrow" from the device's local perspective.
      final DateTime nowLocal = DateTime.now();
      final DateTime endOfToday = DateTime(
        nowLocal.year,
        nowLocal.month,
        nowLocal.day,
        23,
        59,
        59,
        999,
      );

      int totalRecordsAdded = 0;
      List<Record> allFutureRecords = [];
      Map<String, Set<int>>? linked;

      for (var pattern in patterns) {
        // Generate records up to the specified endDate
        var allRecords = generateRecurrentRecordsFromDateTime(pattern, endDate);
        // Fork: estimates are forecasts, never stored. Every occurrence is
        // shown (past ones too) until it is linked to the real record it
        // forecast (see EstimateLink); the estimate is deleted once it ends
        // with nothing left.
        if (pattern.tags.contains(DinzoSyncService.estimateTag)) {
          linked ??= await EstimateLink.linkedOccurrences();
          if (!SqliteDatabase.readOnly &&
              await EstimateLink.deleteIfDone(pattern, linked)) {
            continue;
          }
          for (final r in EstimateLink.withoutLinked(allRecords, linked)) {
            r.isFutureRecord = true;
            r.paymentCode = pattern.paymentCodeFor(pattern.occurrenceDayOf(r));
            r.markedPaid = pattern.isMarkedPaid(pattern.occurrenceDayOf(r));
            r.dueDateUnknown =
                pattern.dueDateMissing(pattern.occurrenceDayOf(r));
            allFutureRecords.add(r);
          }
          continue;
        }

        // Fork: a read-only database (data from a newer app) stores nothing:
        // what is due shows as upcoming until the app is updated.
        if (SqliteDatabase.readOnly) {
          for (final r in allRecords) {
            r.isFutureRecord = true;
            r.paymentCode = pattern.paymentCodeFor(pattern.occurrenceDayOf(r));
            r.markedPaid = pattern.isMarkedPaid(pattern.occurrenceDayOf(r));
            r.dueDateUnknown =
                pattern.dueDateMissing(pattern.occurrenceDayOf(r));
          }
          allFutureRecords.addAll(allRecords);
          continue;
        }

        if (allRecords.isNotEmpty) {
          // Split records into past (up to end of today) and future (after end of today)
          // In the recurrence's order: a due date can move one occurrence
          // past the next, and the stored ones must come before the rest
          // (the last stored one is where the next update starts).
          final firstFuture =
              allRecords.indexWhere((r) => r.utcDateTime.isAfter(endOfToday));
          final pastRecords = firstFuture < 0
              ? allRecords
              : allRecords.sublist(0, firstFuture);
          final futureRecords = firstFuture < 0
              ? <Record>[]
              : allRecords.sublist(firstFuture);

          // Mark future records; a boleto / Pix recurrence shows the code
          // already pasted for each upcoming occurrence.
          for (var record in futureRecords) {
            record.isFutureRecord = true;
            record.paymentCode = pattern.paymentCodeFor(pattern.occurrenceDayOf(record));
            record.markedPaid = pattern.isMarkedPaid(pattern.occurrenceDayOf(record));
            record.dueDateUnknown =
                pattern.dueDateMissing(pattern.occurrenceDayOf(record));
          }

          // Add only past records to the database
          if (pastRecords.isNotEmpty) {
            await database.addRecordsInBatch(pastRecords);
            totalRecordsAdded += pastRecords.length;

            // Update the last update date of the pattern with the latest UTC time.
            // We use the UTC time from the last generated past record.
            pattern.utcLastUpdate = pastRecords.last.occurrenceIdUtc;
            await database.updateRecordPatternById(pattern.id, pattern);
          }

          // Collect future records to return
          allFutureRecords.addAll(futureRecords);
        }
      }

      _logger.info(
          'Recurrent records update completed: ${totalRecordsAdded} records added to database, ${allFutureRecords.length} future records generated from ${patterns.length} patterns');
      return allFutureRecords;
    } catch (e, st) {
      _logger.handle(e, st, 'Failed to update recurrent records');
      rethrow;
    }
  }
}
