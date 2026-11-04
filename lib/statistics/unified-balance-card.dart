import 'package:flutter/material.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/statistics/overview-card.dart';
import 'package:aupp/statistics/statistics-models.dart';
import 'package:aupp/statistics/statistics-utils.dart';
import 'package:aupp/statistics/balance-chart-models.dart';
import 'package:aupp/components/time-chart.dart';
import 'package:aupp/helpers/records-utility-functions.dart';
import 'package:aupp/statistics/period-chart-format.dart';
import 'package:aupp/statistics/record-filters.dart';

/// A card displaying balance overview with an interactive comparison chart.
///
/// Features:
/// - Income and expense bars side by side, or the cumulative savings as a
///   line
/// - Interactive period selection
/// - Overview card integration showing totals for selected period
class UnifiedBalanceCard extends StatefulWidget {
  final List<Record?> records;
  final AggregationMethod? aggregationMethod;
  final DateTime? from;
  final DateTime? to;
  final Function(DateTime?)? onSelectionChanged;
  final DateTime? selectedDate;

  const UnifiedBalanceCard(
    this.from,
    this.to,
    this.records,
    this.aggregationMethod, {
    this.onSelectionChanged,
    this.selectedDate,
  }) : super();

  @override
  _UnifiedBalanceCardState createState() => _UnifiedBalanceCardState();
}

class _UnifiedBalanceCardState extends State<UnifiedBalanceCard> {
  late Map<String, ComparisonData> comparisonData;
  late ChartDateRangeConfig dateConfig;

  String? _selectedPeriodKey;
  bool _showCumulativeLine = false;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  @override
  void didUpdateWidget(UnifiedBalanceCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (_shouldReinitializeData(oldWidget)) {
      _initializeData();
    }

    if (widget.selectedDate != oldWidget.selectedDate) {
      _updateSelectionFromDate();
    }
  }

  bool _shouldReinitializeData(UnifiedBalanceCard oldWidget) {
    return widget.records != oldWidget.records ||
        widget.aggregationMethod != oldWidget.aggregationMethod ||
        widget.from != oldWidget.from ||
        widget.to != oldWidget.to;
  }

  void _initializeData() {
    dateConfig = ChartDateRangeConfig.create(
      widget.aggregationMethod!,
      widget.from,
      widget.to,
    );

    final aggregator = ComparisonDataAggregator(widget.aggregationMethod!);
    comparisonData = aggregator.aggregate(widget.records, dateConfig);

    _updateSelectionFromDate();
  }

  void _updateSelectionFromDate() {
    if (widget.selectedDate == null) {
      _selectedPeriodKey = null;
    } else {
      _selectedPeriodKey = dateConfig.getKey(widget.selectedDate!);
      if (!comparisonData.containsKey(_selectedPeriodKey)) {
        _selectedPeriodKey = null;
      }
    }
  }

  void _onSelect(DateTime? date) {
    setState(() {
      if (date == null) {
        _clearSelection();
        return;
      }
      _selectedPeriodKey = dateConfig.getKey(date);
      widget.onSelectionChanged?.call(date);
    });
  }

  void _clearSelection() {
    _selectedPeriodKey = null;
    widget.onSelectionChanged?.call(null);
  }

  void _toggleCumulativeLine() {
    setState(() {
      _showCumulativeLine = !_showCumulativeLine;
    });
  }

  /// Filters records based on the currently selected period.
  List<Record?> _getFilteredRecords() {
    if (_selectedPeriodKey == null) {
      return widget.records;
    }

    final selectedDate = comparisonData[_selectedPeriodKey!]!.dateTime;
    return RecordFilters.byDate(
      widget.records,
      selectedDate,
      widget.aggregationMethod,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        OverviewCard(
          widget.from,
          widget.to,
          _getFilteredRecords(),
          widget.aggregationMethod,
          isBalance: true,
          actions: [
            OverviewCardAction(
              icon: _showCumulativeLine
                  ? Icons.compare_arrows
                  : Icons.show_chart,
              onTap: _toggleCumulativeLine,
              tooltip: _showCumulativeLine
                  ? 'Separar barras de renda e despesas'
                  : 'Ver o saldo acumulado',
            ),
          ],
        ),
        const Divider(height: 1, indent: 24, endIndent: 24),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: _chart(context),
        ),
      ],
    );
  }

  Widget _chart(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final periods = comparisonData.values.toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
    final format = PeriodChartFormat(widget.aggregationMethod);
    final List<TimeSeries> series;
    if (_showCumulativeLine) {
      series = [
        TimeSeries('Saldo acumulado', Theme.of(context).colorScheme.primary,
            [for (final p in periods) (p.dateTime, p.cumulativeSavings)]),
      ];
    } else {
      series = [
        TimeSeries('Receitas', incomeAmountColor(brightness),
            [for (final p in periods) (p.dateTime, p.income)]),
        TimeSeries('Despesas', expenseAmountColor(brightness),
            [for (final p in periods) (p.dateTime, p.expenses)]),
      ];
    }
    final pinned = _selectedPeriodKey == null
        ? null
        : comparisonData[_selectedPeriodKey!]?.dateTime;
    return TimeChart(
      bars: !_showCumulativeLine,
      area: _showCumulativeLine,
      series: series,
      format: formatMoney,
      dateLabel: format.box.format,
      axisLabel: format.axis.format,
      pinned: pinned,
      onSelect: _onSelect,
    );
  }
}
