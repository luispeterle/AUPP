import 'package:flutter/material.dart';
import 'package:aupp/desktop/desktop-layout.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/models/wallet.dart';
import 'package:aupp/statistics/statistics-models.dart';
import 'package:aupp/statistics/statistics-utils.dart';
import 'package:aupp/statistics/statistics-summary-card.dart';
import 'package:aupp/records/components/records-day-list.dart';
import '../helpers/datetime-utility-functions.dart';
import 'unified-balance-card.dart';

class BalanceTabPage extends StatefulWidget {
  final List<Record?> records;
  final DateTime? from;
  final DateTime? to;
  final Function(String?, DateTime?)? onIntervalSelected;
  final DateTime? selectedDate;
  final Widget? footer;
  final bool hideTagsSelection;
  final bool hideCategorySelection;
  final bool hideWalletsSelection;
  final bool showRecordsToggle;
  final GroupByType? forceGroupByType;
  final Function? onListBackCallback;

  final Map<int, Wallet> walletMap;

  BalanceTabPage(this.from, this.to, this.records,
      {this.onIntervalSelected,
      this.selectedDate,
      this.footer,
      this.hideTagsSelection = false,
      this.hideCategorySelection = false,
      this.hideWalletsSelection = false,
      this.showRecordsToggle = false,
      this.forceGroupByType,
      this.onListBackCallback,
      this.walletMap = const {}})
      : super();

  @override
  BalanceTabPageState createState() => BalanceTabPageState();
}

class BalanceTabPageState extends State<BalanceTabPage> {
  AggregationMethod? aggregationMethod;
  DateTime? selectedDate;
  late GroupByType groupByType;

  @override
  void initState() {
    super.initState();
    this.aggregationMethod =
        getAggregationMethodGivenTheTimeRange(widget.from!, widget.to!);
    this.selectedDate = widget.selectedDate;
    this.groupByType = widget.forceGroupByType ?? GroupByType.category;
  }

  @override
  void didUpdateWidget(BalanceTabPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedDate != oldWidget.selectedDate) {
      setState(() {
        selectedDate = widget.selectedDate;
      });
    }
  }

  List<Widget> _buildNoRecordSlivers() {
    return [
      SliverFillRemaining(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Image.asset(
              'assets/images/no_entry_3.png',
              width: 200,
            ),
            Text(
              'Nenhum item para mostrar.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22.0,
              ),
            )
          ],
        ),
      )
    ];
  }

  List<Widget> _buildContentSlivers() {
    final List<Widget> slivers = [];

    slivers.add(SliverToBoxAdapter(
      child: UnifiedBalanceCard(
        widget.from,
        widget.to,
        widget.records,
        aggregationMethod,
        selectedDate: selectedDate,
        onSelectionChanged: (date) {
          setState(() {
            selectedDate = date;
            if (widget.onIntervalSelected != null) {
              if (date == null) {
                widget.onIntervalSelected!(null, null);
              } else {
                String title;
                switch (aggregationMethod!) {
                  case AggregationMethod.DAY:
                    title = getDateStr(date);
                    break;
                  case AggregationMethod.WEEK:
                    title = getWeekStr(date);
                    break;
                  case AggregationMethod.MONTH:
                    title = getMonthStr(date);
                    break;
                  case AggregationMethod.YEAR:
                    title = getYearStr(date);
                    break;
                  default:
                    title = getDateRangeStr(widget.from!, widget.to!);
                }
                widget.onIntervalSelected!(title, date);
              }
            }
          });
        },
      ),
    ));
    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 10)));

    if (!(groupByType == GroupByType.records && !widget.showRecordsToggle)) {
      slivers.add(SliverToBoxAdapter(
        child: StatisticsSummaryCard(
          records: widget.records,
          aggregationMethod: aggregationMethod,
          from: widget.from,
          to: widget.to,
          selectedDate: selectedDate,
          groupByType: groupByType,
          showHeaders: true,
          isBalance: true,
          showRecordsToggle: widget.showRecordsToggle,
          hideTagsSelection: widget.hideTagsSelection,
          hideCategorySelection: widget.hideCategorySelection,
          hideWalletsSelection: widget.hideWalletsSelection,
          walletMap: widget.walletMap,
          onGroupByTypeChanged: (newType) {
            setState(() {
              groupByType = newType;
            });
          },
        ),
      ));
    }

    if (groupByType == GroupByType.records) {
      if (widget.footer != null) {
        slivers.add(SliverToBoxAdapter(child: widget.footer!));
      } else {
        List<Record?> recordsForList = widget.records;

        if (selectedDate != null) {
          recordsForList = recordsForList.where((r) {
            return truncateDateTime(r!.dateTime, aggregationMethod) ==
                selectedDate;
          }).toList();
        }

        recordsForList = List.from(recordsForList)
          ..sort((a, b) => b!.dateTime.compareTo(a!.dateTime));

        if (recordsForList.isEmpty) {
          slivers.add(SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                children: [
                  Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[400]),
                  SizedBox(height: 16),
                  Text(
                    'Nenhum item encontrado',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ));
        }
        slivers.add(RecordsDayList(
          recordsForList,
          isSliver: true,
          onListBackCallback: widget.onListBackCallback,
        ));
        slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 75)));
      }
    }

    return slivers;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final slivers = widget.records.isNotEmpty
            ? _buildContentSlivers()
            : _buildNoRecordSlivers();
        if (widget.records.isEmpty ||
            constraints.maxWidth < AdaptiveColumns.minTwoColumnWidth) {
          return CustomScrollView(slivers: slivers);
        }
        // On the computer the chart stays beside the list. The first two
        // slivers are the chart card and its gap.
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: CustomScrollView(
                primary: false,
                slivers: slivers.take(2).toList(),
              ),
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(child: CustomScrollView(slivers: slivers.skip(2).toList())),
          ],
        );
      },
    );
  }
}
