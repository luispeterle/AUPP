import 'package:flutter/material.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/statistics/statistics-models.dart';
import 'package:aupp/statistics/statistics-utils.dart';
import 'package:aupp/statistics/statistics-calculator.dart';
import '../helpers/records-utility-functions.dart';

class OverviewCardAction {
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;
  final String? tooltip;

  OverviewCardAction({
    required this.icon,
    required this.onTap,
    this.color,
    this.tooltip,
  });
}

class OverviewCard extends StatelessWidget {
  final List<Record?> records;
  final AggregationMethod? aggregationMethod;
  final DateTime? from;
  final DateTime? to;
  final List<DateTimeSeriesRecord> aggregatedRecords;
  final double? selectedAmount;
  final DateTime? selectedDate;

  /// The records underlying the current selection (e.g. the pie slice or bar
  /// period). Used to detect the currencies involved so the selected amount is
  /// shown converted to the primary currency (with the original secondary
  /// currency as a second line when the selection is a single non-default
  /// currency). When empty, the selection is derived from [selectedDate].
  final List<Record?> selectedRecords;

  final bool isBalance;
  final List<OverviewCardAction> actions;
  final double _total;
  final double _signedTotal;

  OverviewCard(this.from, this.to, this.records, this.aggregationMethod,
      {this.selectedAmount,
      this.selectedDate,
      this.selectedRecords = const [],
      this.isBalance = false,
      this.actions = const []})
      : aggregatedRecords = aggregateRecordsByDate(records, aggregationMethod),
        _total = recordsTotal(records,
            isAbsValue: !isBalance),
        _signedTotal = recordsTotal(records);

  double get averageValue {
    switch (aggregationMethod) {
      case AggregationMethod.WEEK:
        // For WEEK: show daily average instead of weekly bin average
        return StatisticsCalculator.calculateDailyAverage(records, from, to,
            isBalance: isBalance);

      default:
        // DAY, MONTH, and YEAR: keep existing period-based calculation
        return StatisticsCalculator.calculateAverage(
            records, aggregationMethod, from, to,
            isBalance: isBalance);
    }
  }

  double get medianValue {
    switch (aggregationMethod) {
      case AggregationMethod.WEEK:
        // For WEEK: show daily median for consistency with daily average
        return StatisticsCalculator.calculateDailyMedian(records, from, to,
            isBalance: isBalance);

      default:
        // DAY, MONTH, and YEAR: keep existing period-based calculation
        return StatisticsCalculator.calculateMedian(
            records, aggregationMethod, from, to,
            isBalance: isBalance);
    }
  }

  /// Returns the records that belong to the selected bar (filtered by [selectedDate]).
  List<Record?> _getSelectedRecords() {
    if (selectedDate == null) return [];
    return records.where((r) {
      if (r == null) return false;
      final recordDate = truncateDateTime(r.localDateTime, aggregationMethod);
      return recordDate == selectedDate;
    }).toList();
  }

  Widget _buildMainAmountWidget(BuildContext context, {Color? amountColor}) {
    final mainStyle = Theme.of(context).textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: amountColor ?? Theme.of(context).colorScheme.onSurface,
        );
    final double amount;
    if (selectedAmount == null) {
      amount = _total;
    } else {
      final selection = selectedRecords.isNotEmpty
          ? selectedRecords
          : (selectedDate != null ? _getSelectedRecords() : const <Record?>[]);
      amount = selection.isEmpty
          ? selectedAmount!
          : recordsTotal(selection, isAbsValue: !isBalance);
    }
    return Text(formatMoney(amount), style: mainStyle);
  }

  /// Builds a labeled stat line (e.g. "Average of %s a day") where the amount
  /// is colored by sign via [getAmountColor], matching the coloring of the
  /// main total above it.
  ///
  /// On the expenses/income tabs [value] is an absolute (positive) amount, so
  /// the color is driven by the sign of the underlying data (the signed total)
  /// to keep expenses red and income green.
  Widget _buildStatAmountLine(
      BuildContext context, String labelKey, double value) {
    final brightness = Theme.of(context).brightness;
    final baseStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context)
              .textTheme
              .bodySmall
              ?.color
              ?.withAlpha(179),
        );
    final idx = labelKey.indexOf('%s');
    final prefix = idx >= 0 ? labelKey.substring(0, idx) : labelKey;
    final suffix = idx >= 0 ? labelKey.substring(idx + 2) : '';

    final colorValue = isBalance ? value : _signedTotal;
    final amountColor = getAmountColor(colorValue, brightness);
    final amountStyle =
        amountColor == null ? null : TextStyle(color: amountColor);

    final amountSpans = <InlineSpan>[
      TextSpan(text: formatMoney(value), style: amountStyle),
    ];

    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [TextSpan(text: prefix), ...amountSpans, TextSpan(text: suffix)],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) return SizedBox.shrink();

    // Cache computed values — getters iterate over all records each call
    final average = averageValue;
    final median = medianValue;

    String averageLabelKey;
    String medianLabelKey;
    switch (aggregationMethod) {
      // WEEK intentionally uses daily labels for intuitive comparison
      case AggregationMethod.WEEK:
      case AggregationMethod.DAY:
        averageLabelKey = 'Média de %s por dia';
        medianLabelKey = 'Mediana de %s por dia';
        break;
      case AggregationMethod.MONTH:
        averageLabelKey = 'Média de %s por mês';
        medianLabelKey = 'Mediana de %s por mês';
        break;
      case AggregationMethod.YEAR:
        averageLabelKey = 'Média de %s por ano';
        medianLabelKey = 'Mediana de %s por ano';
        break;
      default:
        averageLabelKey = 'Média de %s';
        medianLabelKey = 'Mediana de %s';
    }

    final brightness = Theme.of(context).brightness;
    final amountColor = getAmountColor(_signedTotal, brightness);
    final color =
        amountColor ?? (_signedTotal >= 0 ? Colors.green : Colors.redAccent);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 24.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildMainAmountWidget(context, amountColor: amountColor),
                const SizedBox(height: 2),
                _buildStatAmountLine(
                    context, averageLabelKey, average),
                const SizedBox(height: 2),
                _buildStatAmountLine(
                    context, medianLabelKey, median),
              ],
            ),
          ),
          const SizedBox(width: 16),
          if (actions.isNotEmpty)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Tooltip(
                    message: actions[i].tooltip ?? '',
                    child: InkWell(
                      onTap: actions[i].onTap,
                      borderRadius: BorderRadius.circular(30),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: (actions[i].color ?? color).withAlpha(26),
                          shape: BoxShape.circle,
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          transitionBuilder:
                              (Widget child, Animation<double> animation) {
                            return ScaleTransition(
                                scale: animation, child: child);
                          },
                          child: Icon(
                            actions[i].icon,
                            key: ValueKey<int>(i),
                            color: actions[i].color ?? color,
                            size: 36,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}
