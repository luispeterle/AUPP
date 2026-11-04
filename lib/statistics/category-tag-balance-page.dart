import 'package:flutter/material.dart';
import 'package:aupp/models/category.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/models/wallet.dart';
import 'package:aupp/statistics/balance-tab-page.dart';
import 'package:aupp/statistics/statistics-models.dart';
import 'package:aupp/statistics/statistics-utils.dart';
import 'package:aupp/services/service-config.dart';

class CategoryTagBalancePage extends StatefulWidget {
  final String title;
  final List<Record?> records;
  final DateTime from;
  final DateTime to;
  final AggregationMethod? aggregationMethod;
  final Category? category;
  final String? walletName;
  final DateTime? selectedDate;

  CategoryTagBalancePage({
    required this.title,
    required this.records,
    required this.from,
    required this.to,
    required this.aggregationMethod,
    this.category,
    this.walletName,
    this.selectedDate,
  });

  @override
  _CategoryTagBalancePageState createState() => _CategoryTagBalancePageState();
}

class _CategoryTagBalancePageState extends State<CategoryTagBalancePage> {
  late List<Record?> _currentRecords;
  String? _selectedIntervalTitle;
  DateTime? _selectedIntervalDate;
  Map<int, Wallet> _effectiveWalletMap = {};

  @override
  void initState() {
    super.initState();
    _currentRecords = List.from(widget.records);
    _selectedIntervalDate = widget.selectedDate;

    if (_selectedIntervalDate != null) {
      AggregationMethod currentViewAggregation =
          getAggregationMethodGivenTheTimeRange(widget.from, widget.to);
      _currentRecords = widget.records.where((r) {
        return truncateDateTime(r!.dateTime, currentViewAggregation) ==
            _selectedIntervalDate;
      }).toList();
    }

    _currentRecords.sort((a, b) => b!.dateTime.compareTo(a!.dateTime));

    _loadWalletData();
  }

  Future<void> _loadWalletData() async {
    final db = ServiceConfig.database;
    final wallets = await db.getAllWallets();
    if (!mounted) return;
    setState(() {
      _effectiveWalletMap = {
        for (final w in wallets)
          if (w.id != null) w.id!: w
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    String title = _selectedIntervalTitle ?? widget.title;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: BalanceTabPage(
        widget.from,
        widget.to,
        widget.records,
        selectedDate: _selectedIntervalDate,
        showRecordsToggle: true,
        forceGroupByType: GroupByType.records,
        hideCategorySelection: widget.category != null,
        hideTagsSelection: widget.category == null && widget.walletName == null,
        hideWalletsSelection: widget.walletName != null,
        walletMap: _effectiveWalletMap,
        onListBackCallback: () {
          setState(() {});
        },
        onIntervalSelected: (newTitle, date) {
          setState(() {
            _selectedIntervalTitle =
                newTitle != null ? "${widget.title} - $newTitle" : null;
            _selectedIntervalDate = date;
          });
        },
      ),
    );
  }
}
