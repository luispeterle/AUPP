import 'package:aupp/services/automatic-writes.dart';
import 'package:aupp/dinzo/dinzo-sync-service.dart';
import 'package:aupp/dinzo/estimate-link.dart';
import 'package:aupp/dinzo/pix-charge.dart';
import 'package:aupp/dinzo/pix-code.dart';
import 'package:aupp/helpers/datetime-utility-functions.dart';
import 'package:aupp/helpers/records-utility-functions.dart';
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
  /// Paid, it moves to today; undone, back to its day.
  static Future<void> setMarkedPaid(Record occurrence, bool paid) async {
    final db = ServiceConfig.database;
    final pattern =
        await db.getRecurrentRecordPattern(occurrence.recurrencePatternId);
    if (pattern == null) return;
    final day = pattern.occurrenceDayOf(occurrence);
    pattern.setMarkedPaid(day, paid, on: DateTime.now());
    await db.updateRecordPatternById(pattern.id, pattern);
    occurrence.markedPaid = paid;
    // Stored already (a plain recurrence's occurrence of today): its date
    // stays.
    if (occurrence.id != null) return;
    final location = getLocation(pattern.timeZoneName!);
    final time = pattern.localDateTime;
    final generated = tz.TZDateTime(location, day.year, day.month, day.day,
        time.hour, time.minute, time.second);
    occurrence.occurrenceUtc ??= generated.toUtc();
    occurrence.utcDateTime = _shownDate(pattern, generated).toUtc();
  }

  /// Saves the hand edits of one upcoming occurrence: [edited] is the
  /// occurrence with its new data. A recurrence that happens once takes them
  /// itself. Otherwise the occurrence leaves the recurrence and becomes an
  /// item of its own, on its new day, with its code and marks: editing the
  /// recurrence later leaves it as it is, and that day gets no other
  /// occurrence. Null when the recurrence is gone.
  static Future<RecurrentRecordPattern?> saveOccurrence(Record edited) async {
    final db = ServiceConfig.database;
    final pattern =
        await db.getRecurrentRecordPattern(edited.recurrencePatternId);
    if (pattern == null) return null;
    final day = pattern.occurrenceDayOf(edited);
    final newDay = edited.localDateTime;
    if (pattern.happensOnce) {
      final updated = RecurrentRecordPattern.fromRecord(
        edited,
        pattern.recurrentPeriod!,
        id: pattern.id,
        utcEndDate: edited.utcDateTime,
        customIntervalValue: pattern.customIntervalValue,
        customIntervalUnit: pattern.customIntervalUnit,
      )
        ..tags = Set.of(edited.tags)
        ..utcLastUpdate = pattern.utcLastUpdate
        ..paymentCodes = Map.of(pattern.paymentCodes);
      updated.moveOccurrenceTo(updated, day, newDay);
      await db.updateRecordPatternById(pattern.id, updated);
      return updated;
    }
    final item = RecurrentRecordPattern.fromRecord(
      edited,
      RecurrentPeriod.EveryMonth,
      utcEndDate: edited.utcDateTime,
    )..tags = Set.of(edited.tags);
    for (final key in [
      RecurrentRecordPattern.defaultPixKey,
      RecurrentRecordPattern.pixNameKey,
    ]) {
      final v = pattern.paymentCodes[key];
      if (v != null) item.paymentCodes[key] = v;
    }
    pattern.moveOccurrenceTo(item, day, newDay);
    pattern.skip(day);
    await db.addRecurrentRecordPattern(item);
    await db.updateRecordPatternById(pattern.id, pattern);
    return item;
  }

  /// Deletes one upcoming occurrence: the whole item when it happens once,
  /// otherwise only that day leaves the recurrence.
  static Future<void> deleteOccurrence(Record occurrence) async {
    final db = ServiceConfig.database;
    final pattern =
        await db.getRecurrentRecordPattern(occurrence.recurrencePatternId);
    if (pattern == null) return;
    if (pattern.happensOnce) {
      await db.deleteFutureRecordsByPatternId(
          pattern.id!, DateTime.now().toUtc());
      await db.deleteRecurrentRecordPatternById(pattern.id);
      return;
    }
    final day = pattern.occurrenceDayOf(occurrence);
    // Its code and marks go with it.
    pattern.moveOccurrenceTo(
        RecurrentRecordPattern.fromRecord(occurrence, RecurrentPeriod.EveryMonth),
        day,
        day);
    pattern.skip(day);
    await db.updateRecordPatternById(pattern.id, pattern);
  }

  /// Saves the Pix / boleto [code] of one occurrence on its recurrence (null
  /// removes it). A Pix charge keeps the amount the bank says; a code with a
  /// due date moves the occurrence to that day. Null when the recurrence is
  /// gone.
  static Future<PaymentCodeSaved?> savePaymentCode(
      Record occurrence, String? code) async {
    final db = ServiceConfig.database;
    final pattern =
        await db.getRecurrentRecordPattern(occurrence.recurrencePatternId);
    if (pattern == null) return null;
    // Codes and marks stay on the recurrence's day, even once moved.
    final day = pattern.occurrenceDayOf(occurrence);
    final key = RecurrentRecordPattern.occurrenceKey(day);
    final chargeKey = RecurrentRecordPattern.chargeValueKey(day);
    final dueBefore = pattern.dueDateFor(day);
    pattern.paymentCodes.remove(chargeKey);
    DateTime? due;
    if (code == null) {
      pattern.paymentCodes.remove(key);
    } else {
      pattern.paymentCodes[key] = code;
      // A Pix charge (electricity bill) keeps its amount at the bank.
      final charge = await PixCharge.fetch(code);
      if (charge != null && charge.isOpen) {
        pattern.paymentCodes[chargeKey] = charge.amount.toStringAsFixed(2);
      }
      due = charge?.dueDate ?? PixCode.dueDateOf(code);
    }
    pattern.setDueDate(day, due);
    await db.updateRecordPatternById(pattern.id, pattern);
    return PaymentCodeSaved(pattern, day, dueBefore);
  }

  /// The day an occurrence shows: the day it was paid
  /// ([RecurrentRecordPattern.paidDateFor]), else its due date when one was
  /// read from its code ([RecurrentRecordPattern.dueDateFor]), at the
  /// recurrence's time.
  static tz.TZDateTime _shownDate(
      RecurrentRecordPattern pattern, tz.TZDateTime occurrence,
      {bool paid = true}) {
    final due = (paid ? pattern.paidDateFor(occurrence) : null) ??
        pattern.dueDateFor(occurrence);
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
      // Every occurrence sits on the start date's grid (start + k
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

      // Occurrences taken out by hand (edited into an item of their own, or
      // deleted alone) are not generated again.
      newRecurrentRecords.removeWhere(
          (r) => recordPattern.isSkipped(recordPattern.occurrenceDayOf(r)));

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
        // Estimates are forecasts, never stored. Every occurrence is
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

        // A read-only database (data from a newer app) stores nothing:
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
          // A paid one counts by its own day, not the payment's: until
          // then the mark can still be undone. Stored, it keeps the
          // payment's day.
          final location = getLocation(pattern.timeZoneName!);
          final firstFuture = allRecords.indexWhere((r) => _shownDate(
                  pattern, tz.TZDateTime.from(r.occurrenceIdUtc, location),
                  paid: false)
              .isAfter(endOfToday));
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

/// What [RecurrentRecordService.savePaymentCode] changed on an occurrence.
class PaymentCodeSaved {
  final RecurrentRecordPattern pattern;

  /// The occurrence's day on the recurrence (local).
  final DateTime day;

  /// Its due date before the save, null when it had none.
  final DateTime? dueBefore;

  PaymentCodeSaved(this.pattern, this.day, this.dueBefore);

  DateTime? get dueAfter => pattern.dueDateFor(day);

  /// The day it shows now.
  DateTime get shown => dueAfter ?? day;

  /// It now shows on another day than before.
  bool get moved {
    final a = dueBefore ?? day;
    final b = shown;
    return DateTime(a.year, a.month, a.day) != DateTime(b.year, b.month, b.day);
  }

  /// Its amount now (the code's, or the recurrence's).
  double? get value => pattern.valueFor(day);

  /// What changed, for the message after saving: the amount, the day, or
  /// just that the code was saved. [before] is the amount it had.
  String message(String? code, double? before) {
    final after = value;
    final day = getDateStr(shown);
    if (after != null && before != null && (after - before).abs() >= 0.005) {
      return (moved ? 'Vencimento $day. ' : '') +
          (code == null
              ? 'Valor desta conta voltou para '
                  '${getCurrencyValueString(after.abs())}.'
              : 'Valor desta conta alterado de '
                  '${getCurrencyValueString(before.abs())} para '
                  '${getCurrencyValueString(after.abs())}, que é o valor '
                  'do ${PixCharge.urlOf(code) != null ? 'Pix de cobrança' : Record.paymentCodeKind(code)}. '
                  'O recorrente continua com '
                  '${getCurrencyValueString(pattern.value?.abs())}.');
    }
    if (moved) {
      return code == null
          ? 'Esta conta voltou para $day.'
          : 'Esta conta passou para $day, o vencimento do código.';
    }
    return code == null ? 'Código removido.' : 'Código salvo.';
  }
}
