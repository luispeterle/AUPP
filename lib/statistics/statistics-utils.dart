import 'dart:math';

import 'package:intl/intl.dart';
import 'package:aupp/helpers/datetime-utility-functions.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/statistics/statistics-models.dart';

/// Calculates the number of days between two dates (inclusive).
int computeNumberOfDays(DateTime from, DateTime to) {
  if (from.isAfter(to)) return 0;
  return to.difference(from).inDays + 1;
}

int computeNumberOfIntervals(
    DateTime from, DateTime to, AggregationMethod method,
    {DateTime? now}) {
  DateTime effectiveNow = now ?? DateTime.now();

  // The range we are interested in is [from, to]
  // We cap it at the interval containing 'now' if 'to' is in the future.
  DateTime effectiveTo = to.isAfter(effectiveNow) ? effectiveNow : to;

  DateTime start = truncateDateTime(from, method);
  DateTime end = truncateDateTime(effectiveTo, method);

  if (start.isAfter(end)) {
    // If the entire range starts after today's interval
    return 0;
  }

  int count = 0;
  DateTime current = start;
  while (!current.isAfter(end)) {
    count++;
    switch (method) {
      case AggregationMethod.DAY:
        current = DateTime(current.year, current.month, current.day + 1);
        break;
      case AggregationMethod.WEEK:
        if (current.day == 1) {
          current = DateTime(current.year, current.month, 8);
        } else if (current.day == 8) {
          current = DateTime(current.year, current.month, 15);
        } else if (current.day == 15) {
          current = DateTime(current.year, current.month, 22);
        } else if (current.day == 22) {
          current = DateTime(current.year, current.month, 29);
        } else {
          current = DateTime(current.year, current.month + 1, 1);
        }
        break;
      case AggregationMethod.MONTH:
        current = DateTime(current.year, current.month + 1, 1);
        break;
      case AggregationMethod.YEAR:
        current = DateTime(current.year + 1, 1, 1);
        break;
      default:
        // For NOT_AGGREGATED, we might just return 1 or something consistent
        return 1;
    }
  }
  return count;
}

DateTime truncateDateTime(
    DateTime dateTime, AggregationMethod? aggregationMethod) {
  DateTime newDateTime;
  switch (aggregationMethod!) {
    case AggregationMethod.DAY:
      newDateTime = DateTime(dateTime.year, dateTime.month, dateTime.day);
      break;
    case AggregationMethod.WEEK:
      // Truncate to the first day given the bin 1-7, 8-14, 15-21, 22-end of month
      int truncatedDay;
      if (dateTime.day <= 7) {
        truncatedDay = 1;
      } else if (dateTime.day <= 14) {
        truncatedDay = 8;
      } else if (dateTime.day <= 21) {
        truncatedDay = 15;
      } else if (dateTime.day <= 28) {
        truncatedDay = 22;
      } else {
        truncatedDay = 29;
      }
      newDateTime = DateTime(dateTime.year, dateTime.month, truncatedDay);
      break;
    case AggregationMethod.MONTH:
      newDateTime = DateTime(dateTime.year, dateTime.month);
      break;
    case AggregationMethod.YEAR:
      newDateTime = DateTime(dateTime.year);
      break;
    case AggregationMethod.NOT_AGGREGATED:
      newDateTime = dateTime;
      break;
  }
  return newDateTime;
}

/// Sums the records' signed values per period; callers apply `abs()` only
/// where a magnitude is needed for representation.
List<DateTimeSeriesRecord> aggregateRecordsByDate(
    List<Record?> records, AggregationMethod? aggregationMethod,
    {bool useTagWeight = false}) {
  /// Record Day 1: 100 euro Food, 20 euro Food, 30 euro Transport
  /// Record Day 1: 150 euro,
  /// Available grouping: by day, month, year.
  Map<DateTime?, DateTimeSeriesRecord> aggregatedByDay = {};
  for (var record in records) {
    if (record == null || record.isOwnMove || record.value == null) continue;
    DateTime? dateTime = truncateDateTime(record.dateTime, aggregationMethod);
    // Keep real (signed) values in the aggregation; consumers apply abs()
    // where the magnitude is needed for rendering.
    double valueToAdd = record.value!;
    if (useTagWeight) {
      valueToAdd *= record.tags.length;
    }
    aggregatedByDay.update(dateTime,
        (tsr) => DateTimeSeriesRecord(dateTime, tsr.value + valueToAdd),
        ifAbsent: () => DateTimeSeriesRecord(dateTime, valueToAdd));
  }
  List<DateTimeSeriesRecord> data = aggregatedByDay.values.toList();
  data.sort((a, b) => a.value.abs().compareTo(b.value.abs()));
  return data;
}

DateTime getEndOfInterval(
    DateTime start, AggregationMethod? aggregationMethod) {
  switch (aggregationMethod!) {
    case AggregationMethod.DAY:
      return DateTime(start.year, start.month, start.day, 23, 59, 59);
    case AggregationMethod.WEEK:
      // Calculate the end of the week bin (1-7, 8-14, 15-21, 22-28, 29-end)
      // based on the start day, matching truncateDateTime bins
      int endDay;
      int startDay = start.day;
      if (startDay == 1) {
        endDay = 7;
      } else if (startDay == 8) {
        endDay = 14;
      } else if (startDay == 15) {
        endDay = 21;
      } else if (startDay == 22) {
        endDay = 28;
      } else {
        // Day 29+ — last partial bin to end of month
        endDay = DateTime(start.year, start.month + 1, 0).day;
      }
      return DateTime(start.year, start.month, endDay, 23, 59, 59);
    case AggregationMethod.MONTH:
      return getEndOfMonth(start.year, start.month);
    case AggregationMethod.YEAR:
      return DateTime(start.year, 12, 31, 23, 59, 59);
    case AggregationMethod.NOT_AGGREGATED:
      return start;
  }
}

AggregationMethod getAggregationMethodGivenTheTimeRange(
    DateTime from, DateTime to) {
  Duration difference = to.difference(from);
  if (difference.inDays <= 7) {
    return AggregationMethod.DAY;
  } else if (difference.inDays <= 35) {
    // Increased slightly to handle 5-week months
    return AggregationMethod.WEEK;
  } else if (from.year != to.year) {
    return AggregationMethod.YEAR;
  } else {
    return AggregationMethod.MONTH;
  }
}

/// Configuration for chart date ranges and formatting.
/// Shared between bar-chart and balance-chart to ensure consistent behavior.
class ChartDateRangeConfig {
  /// Maximum number of yearly bars/ticks shown on YEAR-aggregated charts.
  static const int maxYearsShown = 5;

  final DateTime start;
  final DateTime end;
  final DateFormat formatter;
  final String scopeLabel;
  final AggregationMethod aggregationMethod;

  ChartDateRangeConfig._({
    required this.start,
    required this.end,
    required this.formatter,
    required this.scopeLabel,
    required this.aggregationMethod,
  });

  factory ChartDateRangeConfig.create(
    AggregationMethod method,
    DateTime? from,
    DateTime? to,
  ) {
    switch (method) {
      case AggregationMethod.DAY:
        // Truncate dates to midnight to ensure full day ranges
        final startDate = DateTime(from!.year, from.month, from.day);
        final endDate = DateTime(to!.year, to.month, to.day);
        return ChartDateRangeConfig._(
          formatter: DateFormat("dd"),
          start: startDate,
          end: endDate,
          scopeLabel:
              "${startDate.month}/${startDate.day}-${endDate.month}/${endDate.day}",
          aggregationMethod: method,
        );

      case AggregationMethod.WEEK:
        final startDate = DateTime(from!.year, from.month);
        final endDate = DateTime(
            from.year, from.month + 1, 0, 23, 59, 59); // Last day of month
        return ChartDateRangeConfig._(
          formatter: DateFormat("'W'w"),
          start: startDate,
          end: endDate,
          scopeLabel: DateFormat("yyyy/MM").format(startDate),
          aggregationMethod: method,
        );

      case AggregationMethod.MONTH:
        final endDate =
            DateTime(to!.year, 12, 31, 23, 59, 59); // Last day of December
        return ChartDateRangeConfig._(
          formatter: DateFormat("MM"),
          start: DateTime(from!.year),
          end: endDate,
          scopeLabel: DateFormat("yyyy").format(from),
          aggregationMethod: method,
        );

      case AggregationMethod.YEAR:
        final endDate =
            DateTime(to!.year, 12, 31, 23, 59, 59); // Last day of last year
        // Cap the chart to the most recent [maxYearsShown] years. Without
        // this, a very wide range (e.g. the "All Time" filter, spanning
        // back to 1970) generates one bar/tick per year and the x-axis
        // becomes unreadably cramped.
        final effectiveFromYear =
            max(from!.year, to.year - ChartDateRangeConfig.maxYearsShown + 1);
        return ChartDateRangeConfig._(
          formatter: DateFormat("yyyy"),
          start: DateTime(effectiveFromYear),
          end: endDate,
          scopeLabel:
              "${DateFormat("yyyy").format(from)} - ${DateFormat("yyyy").format(to)}",
          aggregationMethod: method,
        );

      default:
        throw ArgumentError('Unknown aggregation method: $method');
    }
  }

  /// Generates a key for a given date based on the aggregation method.
  /// Used for data aggregation and lookup.
  /// For DAY aggregation, this matches the tick label format exactly.
  String getKey(DateTime date) {
    if (aggregationMethod == AggregationMethod.WEEK) {
      return _getWeekLabel(date);
    } else if (aggregationMethod == AggregationMethod.DAY) {
      // For DAY aggregation, match the tick generation logic:
      // Only show month at the start of a month (day 1)
      // Example: 30 March to 3 April -> "30 31 1/4 2 3"
      final bool isMonthStart = date.day == 1;

      if (isMonthStart) {
        return "${date.month}/${date.day}";
      } else {
        return "${date.day}";
      }
    }
    return formatter.format(date).replaceFirst(RegExp(r'^0+(?=\d)'), '');
  }

  /// Advances a date by one period based on the aggregation method.
  DateTime advance(DateTime current) {
    switch (aggregationMethod) {
      case AggregationMethod.DAY:
        return current.add(Duration(days: 1));
      case AggregationMethod.WEEK:
        return current.add(Duration(days: 7));
      case AggregationMethod.MONTH:
        return DateTime(current.year, current.month + 1);
      case AggregationMethod.YEAR:
        return DateTime(current.year + 1);
      default:
        return current.add(Duration(days: 1));
    }
  }

  /// Gets the label for a week range (e.g., "1-7" or "25-31").
  static String _getWeekLabel(DateTime date) {
    final startDay = date.day;
    var weekEnd = date.add(Duration(days: 6));
    if (weekEnd.month != date.month) {
      weekEnd = DateTime(date.year, date.month + 1, 0);
    }
    final endDay = weekEnd.day;
    return '$startDay-$endDay';
  }
}
