import 'package:aupp/models/record.dart';
import 'package:aupp/services/service-config.dart';

/// The boletos and Pix to pay, for the Início ("Próximas faturas",
/// the red alert) and the calendar widget.
class DueBills {
  /// What is paid by boleto or Pix among the stored [records] and the
  /// [upcoming] occurrences (RecurrentRecordService.updateRecurrentRecords),
  /// already paired with the real ones (EstimateLink.markMatches), by date.
  /// The ones marked "Já paguei" come too ([Record.markedPaid]).
  static Future<List<Record>> find(
    Iterable<Record> records,
    Iterable<Record> upcoming,
  ) async {
    // A plain boleto recurrence stores today's occurrence: it still counts
    // as due today, with the code and the mark of its recurrence.
    final patterns = {
      for (final p in await ServiceConfig.database.getRecurrentRecordPatterns())
        p.id: p,
    };
    final storedToday = <Record>[];
    for (final r in records) {
      final pattern = patterns[r.recurrencePatternId];
      if (pattern == null || daysUntil(r.dateTime) != 0) continue;
      final day = pattern.occurrenceDayOf(r);
      r.paymentCode = pattern.paymentCodeFor(day);
      r.markedPaid = pattern.isMarkedPaid(day);
      r.dueDateUnknown = pattern.dueDateMissing(day);
      storedToday.add(r);
    }
    return [...storedToday, ...upcoming].where(_isBill).toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
  }

  static bool _isBill(Record r) =>
      r.estimateMatch == null &&
      !r.isTransfer &&
      (r.value ?? 0) < 0 &&
      (r.paymentCode != null || Record.billingKindOf(r.tags) != null);

  /// Days from today to [due] (negative: overdue).
  static int daysUntil(DateTime due) {
    final today = DateTime.now();
    return DateTime(
      due.year,
      due.month,
      due.day,
    ).difference(DateTime(today.year, today.month, today.day)).inDays;
  }
}
