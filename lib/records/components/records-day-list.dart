import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:aupp/helpers/records-utility-functions.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/models/records-per-day.dart';
import 'package:aupp/records/components/records-per-day-card.dart';

class RecordsDayList extends StatefulWidget {
  /// MovementsPage is the page showing the list of movements grouped per day.
  /// It contains also buttons for filtering the list of movements and add a new movement.

  final List<Record?> records;
  final Function? onListBackCallback;
  final bool isSliver;
  final int batchSize;
  final bool isSelectMode;
  final Set<int> selectedRecordIds;
  final void Function(int)? onRecordLongPressed;
  final void Function(int)? onRecordTapped;
  final void Function(DateTime date)? onDateTapped;
  final Record? linkingEstimate;
  final void Function(Record estimate)? onEstimateLongPressed;
  final void Function(Record target)? onLinkTarget;
  final void Function(Record estimate)? onLinkMatch;

  RecordsDayList(
    this.records, {
    this.onListBackCallback,
    this.isSliver = true,
    this.batchSize = 50,
    this.isSelectMode = false,
    this.selectedRecordIds = const {},
    this.onRecordLongPressed,
    this.onRecordTapped,
    this.onDateTapped,
    this.linkingEstimate,
    this.onEstimateLongPressed,
    this.onLinkTarget,
    this.onLinkMatch,
  });

  @override
  State<RecordsDayList> createState() => _RecordsDayListState();
}

class _RecordsDayListState extends State<RecordsDayList> {
  int _displayedCount = 0;
  late List<RecordsPerDay> _daysShown;

  @override
  void initState() {
    super.initState();
    _updateDaysShown();
  }

  @override
  void didUpdateWidget(RecordsDayList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.records, widget.records) ||
        oldWidget.records.length != widget.records.length) {
      _updateDaysShown();
    }
  }

  void _updateDaysShown() {
    _daysShown = groupRecordsByDay(widget.records);
    _displayedCount = _daysShown.length.clamp(0, widget.batchSize);
  }

  void _loadMore() {
    if (_displayedCount >= _daysShown.length) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _displayedCount =
              (_displayedCount + widget.batchSize).clamp(0, _daysShown.length);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool hasMore = _displayedCount < _daysShown.length;

    if (widget.isSliver) {
      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (BuildContext context, int index) {
            if (index == _displayedCount && hasMore) {
              _loadMore();
              return const SizedBox.shrink();
            }
            return RecordsPerDayCard(
              _daysShown[index],
              onListBackCallback: widget.onListBackCallback,
              isSelectMode: widget.isSelectMode,
              selectedRecordIds: widget.selectedRecordIds,
              onRecordLongPressed: widget.onRecordLongPressed,
              onRecordTapped: widget.onRecordTapped,
              onDateTapped: widget.onDateTapped,
              linkingEstimate: widget.linkingEstimate,
              onEstimateLongPressed: widget.onEstimateLongPressed,
              onLinkTarget: widget.onLinkTarget,
              onLinkMatch: widget.onLinkMatch,
            );
          },
          childCount: _displayedCount + (hasMore ? 1 : 0),
        ),
      );
    } else {
      return ListView.builder(
        shrinkWrap: true,
        physics: NeverScrollableScrollPhysics(),
        itemCount: _displayedCount + (hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _displayedCount && hasMore) {
            _loadMore();
            return const SizedBox.shrink();
          }
          return RecordsPerDayCard(
            _daysShown[index],
            onListBackCallback: widget.onListBackCallback,
            isSelectMode: widget.isSelectMode,
            selectedRecordIds: widget.selectedRecordIds,
            onRecordLongPressed: widget.onRecordLongPressed,
            onRecordTapped: widget.onRecordTapped,
            onDateTapped: widget.onDateTapped,
            linkingEstimate: widget.linkingEstimate,
            onEstimateLongPressed: widget.onEstimateLongPressed,
            onLinkTarget: widget.onLinkTarget,
              onLinkMatch: widget.onLinkMatch,
          );
        },
      );
    }
  }
}
