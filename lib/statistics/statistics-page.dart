import 'package:flutter/material.dart';
import 'package:aupp/budget_plan/budget-plan-tab.dart';
import 'package:aupp/helpers/datetime-utility-functions.dart';
import 'package:aupp/models/category-type.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/models/wallet.dart';
import 'package:aupp/records/controllers/tab_records_controller.dart';
import 'package:aupp/statistics/statistics-models.dart';
import 'package:aupp/statistics/statistics-tab-page.dart';
import 'package:aupp/statistics/balance-tab-page.dart';

/// The tabs after "Orçamento".
enum StatisticsTab { expenses, income, balance }

class StatisticsPage extends StatefulWidget {
  final List<Record?> records;
  final DateTime? from;
  final DateTime? to;
  final Map<int, Wallet> walletMap;

  /// Shown before the interval in the title (e.g. a budget group).
  final String? label;

  /// Initial grouping of the expense/income tabs.
  final GroupByType? groupByType;

  /// First tab "Orçamento" with the budget plan over the interval
  /// (opened from the Extrato).
  final bool showBudget;

  /// The Extrato's controller. When set, the title gets the Extrato's
  /// arrows and month ↔ year switch, moving both screens together.
  final TabRecordsController? navigation;

  /// Tab shown first; null = the first one.
  final StatisticsTab? initialTab;

  StatisticsPage(
    this.from,
    this.to,
    this.records, {
    this.walletMap = const {},
    this.label,
    this.groupByType,
    this.showBudget = false,
    this.navigation,
    this.initialTab,
  });

  @override
  _StatisticsPageState createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage>
    with SingleTickerProviderStateMixin {
  String? _selectedIntervalTitle;
  DateTime? _selectedDate;
  late TabController _tabController;
  late DateTime? _from = widget.from;
  late DateTime? _to = widget.to;
  late List<Record?> _records = widget.records;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: widget.showBudget ? 4 : 3,
      vsync: this,
      initialIndex: widget.initialTab == null
          ? 0
          : widget.initialTab!.index + (widget.showBudget ? 1 : 0),
    );
    _tabController.addListener(_handleTabSelection);
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabSelection);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabSelection() {
    if (_tabController.indexIsChanging) {
      setState(() {
        _selectedIntervalTitle = null;
        _selectedDate = null;
      });
    }
  }

  /// Moves the Extrato ([StatisticsPage.navigation]) and shows its new period.
  Future<void> _move(Future<void> Function(TabRecordsController) move) async {
    final nav = widget.navigation!;
    await move(nav);
    if (!mounted) return;
    setState(() {
      _from = nav.customIntervalFrom ?? _from;
      _to = nav.customIntervalTo ?? _to;
      _records = nav.filteredRecords;
      _selectedIntervalTitle = null;
      _selectedDate = null;
    });
  }

  Widget _buildTitle(String title) {
    final nav = widget.navigation;
    if (nav == null || !nav.isNavigable) return Text(title);
    Widget button(
      IconData icon,
      String? tooltip,
      Future<void> Function(TabRecordsController) move,
    ) => IconButton(
      icon: Icon(icon),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: () => _move(move),
    );
    return Row(
      children: [
        button(Icons.arrow_left, null, (c) => c.shiftInterval(-1)),
        Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
        button(Icons.arrow_right, null, (c) => c.shiftInterval(1)),
        if (nav.canToggleMonthYear)
          button(
            Icons.swap_horiz,
            nav.showsYear ? 'Ver mês' : 'Ver ano',
            (c) => c.toggleMonthYear(),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    String title =
        _selectedIntervalTitle ??
        (widget.navigation?.header ?? getDateRangeStr(_from!, _to!));
    if (widget.label != null) title = '${widget.label} · $title';
    // New period → fresh tabs (they read the interval only when created).
    final period =
        '${_from?.millisecondsSinceEpoch}-${_to?.millisecondsSinceEpoch}';

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
          return <Widget>[
            SliverAppBar(
              title: _buildTitle(title),
              pinned: false,
              floating: false,
              snap: false,
              forceElevated: innerBoxIsScrolled,
              bottom: TabBar(
                controller: _tabController,
                tabs: [
                  if (widget.showBudget) Tab(text: 'ORÇAMENTO'),
                  Tab(text: 'Despesas'.toUpperCase()),
                  Tab(text: 'Rendas'.toUpperCase()),
                  Tab(text: 'Saldo'.toUpperCase()),
                ],
              ),
            ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: [
            if (widget.showBudget)
              KeyedSubtree(
                key: ValueKey('budget-$period'),
                child: BudgetPlanTab(from: _from!, to: _to!),
              ),
            KeyedSubtree(
              key: ValueKey('expenses-$period'),
              child: StatisticsTabPage(
                _from,
                _to,
                _records
                    .where(
                      (element) =>
                          element?.category?.categoryType ==
                              CategoryType.expense &&
                          !element!.isOwnMove,
                    )
                    .toList(),
                selectedDate: _selectedDate,
                showRecordsToggle: true,
                startWithPieChart: true,
                forceGroupByType: widget.groupByType,
                walletMap: widget.walletMap,
                onIntervalSelected: (newTitle, date, amount) {
                  setState(() {
                    _selectedIntervalTitle = newTitle;
                    _selectedDate = date;
                  });
                },
              ),
            ),
            KeyedSubtree(
              key: ValueKey('income-$period'),
              child: StatisticsTabPage(
                _from,
                _to,
                _records
                    .where(
                      (element) =>
                          element?.category?.categoryType ==
                              CategoryType.income &&
                          !element!.isOwnMove,
                    )
                    .toList(),
                selectedDate: _selectedDate,
                showRecordsToggle: true,
                startWithPieChart: true,
                forceGroupByType: widget.groupByType,
                walletMap: widget.walletMap,
                onIntervalSelected: (newTitle, date, amount) {
                  setState(() {
                    _selectedIntervalTitle = newTitle;
                    _selectedDate = date;
                  });
                },
              ),
            ),
            KeyedSubtree(
              key: ValueKey('balance-$period'),
              child: BalanceTabPage(
                _from,
                _to,
                _records.where((element) => !element!.isOwnMove).toList(),
                selectedDate: _selectedDate,
                showRecordsToggle: true,
                walletMap: widget.walletMap,
                onIntervalSelected: (newTitle, date) {
                  setState(() {
                    _selectedIntervalTitle = newTitle;
                    _selectedDate = date;
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
