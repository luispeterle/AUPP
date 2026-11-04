import 'package:flutter/material.dart';
import 'package:aupp/components/time-chart.dart';
import 'package:aupp/helpers/records-utility-functions.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/statistics/period-chart-format.dart';
import 'package:aupp/statistics/statistics-models.dart';
import 'package:aupp/statistics/statistics-utils.dart';

/// Expenses or income per period. Tapping a bar picks its period.
class BarChartCard extends StatelessWidget {
  final List<Record?> records;
  final AggregationMethod? aggregationMethod;
  final DateTime? from, to;
  final Function(double?, DateTime?)? onSelectionChanged;
  final DateTime? selectedDate;

  BarChartCard(this.from, this.to, this.records, this.aggregationMethod,
      {this.onSelectionChanged, this.selectedDate});

  @override
  Widget build(BuildContext context) {
    final config = ChartDateRangeConfig.create(aggregationMethod!, from, to);
    final totals = <DateTime, double>{};
    for (final r in aggregateRecordsByDate(
      records
          .where((r) =>
              r != null &&
              !r.dateTime.isBefore(config.start) &&
              !r.dateTime.isAfter(config.end))
          .toList(),
      aggregationMethod,
    )) {
      if (r.time != null) totals[r.time!] = r.value;
    }
    final points = <(DateTime, double)>[];
    for (var d = config.start;
        d.isBefore(config.end);
        d = config.advance(d)) {
      final period = truncateDateTime(d, aggregationMethod);
      points.add((period, (totals[period] ?? 0).abs()));
    }
    final sum = totals.values.fold(0.0, (a, b) => a + b);
    final brightness = Theme.of(context).brightness;
    final color = sum < 0
        ? expenseAmountColor(brightness)
        : incomeAmountColor(brightness);
    final format = PeriodChartFormat(aggregationMethod);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: TimeChart(
        bars: true,
        series: [TimeSeries(sum < 0 ? 'Despesas' : 'Receitas', color, points)],
        format: formatMoney,
        dateLabel: format.box.format,
        axisLabel: format.axis.format,
        pinned: selectedDate,
        onSelect: (date) {
          final value = date == null
              ? null
              : points.firstWhere((p) => p.$1 == date).$2;
          onSelectionChanged?.call(value, date);
        },
      ),
    );
  }
}
