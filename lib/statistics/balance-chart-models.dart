import 'package:aupp/models/category-type.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/statistics/statistics-models.dart';
import 'package:aupp/statistics/statistics-utils.dart';

/// Data model for comparison chart entries.
/// Tracks income, expenses, and cumulative savings for a time period.
class ComparisonData {
  final String period;
  final DateTime dateTime;
  double expenses;
  double income;
  double cumulativeSavings = 0;

  ComparisonData(this.period, this.dateTime, this.expenses, this.income);

  /// Returns the net savings (income - expenses) for this period.
  double get netSavings => income - expenses;
}

// ChartDateRangeConfig is now imported from statistics-utils.dart
// and is shared between bar-chart and balance-chart for consistency.

/// Aggregates records by time period for comparison chart display.
class ComparisonDataAggregator {
  final AggregationMethod aggregationMethod;

  ComparisonDataAggregator(this.aggregationMethod);

  /// Aggregates records into comparison data points.
  Map<String, ComparisonData> aggregate(
    List<Record?> records,
    ChartDateRangeConfig config,
  ) {
    final data = <String, ComparisonData>{};

    // Initialize all time periods with zero values
    var current = config.start;
    while (current.isBefore(config.end)) {
      final key = config.getKey(current);
      data[key] = ComparisonData(key, current, 0, 0);
      current = config.advance(current);
    }

    // Aggregate records into periods
    for (var record in records) {
      if (record == null) continue;

      final truncated = truncateDateTime(record.dateTime, aggregationMethod);
      final key = config.getKey(truncated);

      if (data.containsKey(key) && !record.isOwnMove) {
        // Income/expenses are stored as positive magnitudes in this model
        // (netSavings = income - expenses), so abs() is applied at the model
        // boundary .
        final value = record.value!;
        if (record.category?.categoryType == CategoryType.expense) {
          data[key]!.expenses += value.abs();
        } else {
          data[key]!.income += value.abs();
        }
      }
    }

    // Calculate cumulative savings
    _calculateCumulativeSavings(data);

    return data;
  }

  /// Calculates cumulative savings across all periods.
  void _calculateCumulativeSavings(Map<String, ComparisonData> data) {
    final sortedValues = data.values.toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));

    var runningSum = 0.0;
    for (var item in sortedValues) {
      runningSum += item.netSavings;
      item.cumulativeSavings = runningSum;
    }
  }
}
