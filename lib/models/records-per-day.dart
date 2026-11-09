import 'package:aupp/dashboard/dashboard-data.dart';
import 'package:aupp/models/record.dart';

class RecordsPerDay {
  /// Object containing a list of records (movements).
  /// Used for grouping together movements with the same day.
  /// Contains also utility getters to retrieve easily the amount of expenses,
  /// income and balance.

  List<Record?>? records;
  DateTime? dateTime;

  /// Fork: card bills due this day, shown only as reminders: never in the
  /// totals.
  List<UpcomingBill> reminders = [];

  RecordsPerDay(this.dateTime, {this.records}) {
    if (this.records == null) {
      this.records = [];
    }
  }

  double get expenses {
    double total = 0;
    List<Record?> expenseRecords = this
        .records!
        .where((e) => e?.countsAsExpense ?? false)
        .toList();
    for (var movement in expenseRecords) {
      total += movement!.value!;
    }
    return total;
  }

  double get income {
    double total = 0;
    List<Record?> incomeRecords = this
        .records!
        .where((e) => e?.countsAsIncome ?? false)
        .toList();
    for (var movement in incomeRecords) {
      total += movement!.value!;
    }
    return total;
  }

  /// Fork: money set aside (negative) or taken back (positive), see
  /// [Record.countsAsSetAside].
  double get setAside => records!
      .where((e) => (e?.countsAsSetAside ?? false) || (e?.isInvestmentFlow ?? false))
      .fold(0.0, (total, e) => total + (e!.value ?? 0));

  double get balance {
    return income - (expenses * -1) + setAside;
  }

  void addMovement(Record movement) {
    records!.add(movement);
  }
}
