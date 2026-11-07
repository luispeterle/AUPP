import 'package:aupp/budget_plan/budget-plan-tab.dart';
import 'package:aupp/desktop/desktop-layout.dart';
import 'package:aupp/dinzo/dinzo-auto-sync.dart';
import 'package:aupp/services/sync-extensions.dart';
import 'package:aupp/dinzo/dinzo-sync-history-page.dart';
import 'package:aupp/dinzo/dinzo-sync-service.dart';
import 'package:aupp/dinzo/dinzo-sync-page.dart';
import 'package:aupp/dinzo/estimate-link.dart';
import 'package:aupp/models/record.dart';
import 'dart:core';

import 'package:flutter/material.dart';
import 'package:aupp/helpers/title-case.dart';
import 'package:aupp/services/home-widget-service.dart';
import 'package:aupp/services/logger.dart';

import '../models/wallet.dart';
import '../accounts/accounts-sheet.dart';
import '../accounts/money-accounts.dart';
import '../services/service-config.dart';
import 'components/days-summary-box-card.dart';
import 'components/records-day-list.dart';
import 'records-list-page.dart';
import 'components/tab_records_app_bar.dart';
import 'components/tab_records_date_picker.dart';
import 'components/tab_records_search_app_bar.dart';
import 'components/tab_records_selection_app_bar.dart';
import 'controllers/tab_records_controller.dart';
import 'package:aupp/dinzo/daily-money.dart';

class TabRecords extends StatefulWidget {
  /// MovementsPage is the page showing the list of movements grouped per day.
  /// It contains also buttons for filtering the list of movements and add a new movement.

  TabRecords({Key? key}) : super(key: key);

  @override
  TabRecordsState createState() => TabRecordsState();
}

class TabRecordsState extends State<TabRecords> {
  static final _logger = Logger.withContext('TabRecords');

  late final TabRecordsController _controller;
  late final AppLifecycleListener _listener;
  bool _isAppBarExpanded = true;
  bool _isSelectMode = false;
  Set<int> _selectedRecordIds = {};

  /// Estimate occurrence held to be linked to a real record (EstimateLink).
  Record? _linkingEstimate;

  @override
  void initState() {
    super.initState();
    _controller = TabRecordsController(
      onStateChanged: () => setState(() {}),
    );

    _listener = AppLifecycleListener(
      onStateChange: _handleOnResume,
    );

    DinzoAutoSync.status.addListener(_onDinzoStatus);
    for (final e in SyncExtensions.all) {
      e.status.addListener(_onExtensionStatus);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.initialize();
      // Paint home screen widgets on cold start too, not just on resume.
      HomeWidgetService.refreshAll();
    });
  }

  void _handleOnResume(AppLifecycleState value) {
    if (value == AppLifecycleState.resumed) {
      _controller.onResume();
      HomeWidgetService.refreshAll();
    }
  }

  /// Records changed under us when an automatic sync applied: reload.
  void _onDinzoStatus() {
    if (!mounted) return;
    setState(() {});
    if (DinzoAutoSync.status.value?.state == DinzoAutoSyncState.applied) {
      _controller.updateRecurrentRecordsAndFetchRecords();
    }
  }

  /// Same for the sync extensions.
  void _onExtensionStatus() {
    if (!mounted) return;
    setState(() {});
    if (SyncExtensions.all.any(
      (e) => e.status.value?.state == DinzoAutoSyncState.applied,
    )) {
      _controller.updateRecurrentRecordsAndFetchRecords();
    }
  }

  @override
  void dispose() {
    DinzoAutoSync.status.removeListener(_onDinzoStatus);
    for (final e in SyncExtensions.all) {
      e.status.removeListener(_onExtensionStatus);
    }
    _listener.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  /// Computer shortcuts (see ShellState).
  void addRecordFromShortcut() => _controller.navigateToAddNewRecord(context);
  void searchFromShortcut() => _controller.startSearch();
  Future<void> refreshFromShortcut() => _pullToSync();

  void _enterSelectMode(int id) {
    _logger.debug('Entering select mode, initial record ID: $id');
    setState(() {
      _isSelectMode = true;
      _selectedRecordIds = {id};
    });
  }

  void _exitSelectMode() {
    _logger.debug(
        'Exiting select mode (${_selectedRecordIds.length} records were selected)');
    setState(() {
      _isSelectMode = false;
      _selectedRecordIds = {};
    });
  }

  void _toggleRecord(int id) {
    setState(() {
      if (_selectedRecordIds.contains(id)) {
        _selectedRecordIds.remove(id);
      } else {
        _selectedRecordIds.add(id);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedRecordIds = _controller.listedRecords
          .where((r) => r?.id != null)
          .map((r) => r!.id!)
          .toSet();
    });
  }

  void _startLinking(Record estimate) {
    if (EstimateLink.sameOccurrence(estimate, _linkingEstimate)) {
      _stopLinking();
      return;
    }
    setState(() => _linkingEstimate = estimate);
  }

  void _stopLinking() {
    if (!mounted) return;
    setState(() => _linkingEstimate = null);
  }

  /// Hint shown while an estimate is held for linking.
  Widget? _buildLinkingBar() {
    final estimate = _linkingEstimate;
    if (estimate == null) return null;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
          child: Row(
            children: [
              Icon(Icons.link, color: scheme.onSecondaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Toque no lançamento real de '
                  '"${estimate.title ?? estimate.category?.name ?? ''}"',
                  style: TextStyle(color: scheme.onSecondaryContainer),
                ),
              ),
              TextButton(
                onPressed: _stopLinking,
                child: Text('Cancelar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _linkTo(Record target) async {
    final estimate = _linkingEstimate;
    if (estimate == null || target.id == null) return;
    await _link(estimate, target);
  }

  Future<void> _link(Record estimate, Record target) async {
    final linked = await confirmEstimateLink(context, estimate, target);
    if (!linked || !mounted) return;
    _stopLinking();
    await _controller.updateRecurrentRecordsAndFetchRecords();
    if (mounted) setState(() {});
  }

  Future<void> _batchDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Excluir registros?'),
        content: Text('Tem certeza de que deseja excluir ${_selectedRecordIds.length.toString()} registro(s)?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // Copy IDs before async operations
    final idsToDelete = List<int>.from(_selectedRecordIds);
    _logger.info('Batch deleting ${idsToDelete.length} records: $idsToDelete');

    // Exit select mode immediately
    if (mounted) {
      _exitSelectMode();
    }

    // Batch delete in database
    try {
      // Deleted Dinzo imports must not come back on the next sync.
      final dinzoIds = <String>[];
      for (final id in idsToDelete) {
        final record = await ServiceConfig.database.getRecordById(id);
        if (record?.dinzoId != null) dinzoIds.add(record!.dinzoId!);
      }
      await DinzoSyncService.ignoreDeleted(dinzoIds);
      await ServiceConfig.database.deleteRecordsInBatch(idsToDelete);
      // Refresh list after deletion complete
      if (mounted) {
        await _controller.updateRecurrentRecordsAndFetchRecords();
        if (mounted) {
          setState(() {});
        }
      }
    } catch (e, st) {
      _logger.handle(e, st, 'Error during batch delete');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting records: $e')),
        );
      }
    }
  }

  Future<void> _batchDuplicate() async {
    // Copy IDs before async operations
    final idsToDuplicate = List<int>.from(_selectedRecordIds);
    _logger.info(
        'Batch duplicating ${idsToDuplicate.length} records: $idsToDuplicate');

    // Exit select mode immediately
    if (mounted) {
      _exitSelectMode();
    }

    try {
      // Batch duplicate in database
      await ServiceConfig.database.duplicateRecordsInBatch(idsToDuplicate);
      // Refresh list after duplication complete
      if (mounted) {
        await _controller.updateRecurrentRecordsAndFetchRecords();
        if (mounted) {
          setState(() {});
        }
      }
    } catch (e, st) {
      _logger.handle(e, st, 'Error during batch duplicate');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error duplicating records: $e')),
        );
      }
    }
  }

  Future<void> _batchMoveToWallet() async {
    final wallets = await ServiceConfig.database
        .getAllWallets();
    if (!mounted) return;
    final chosenWallet = await showDialog<Wallet>(
      context: context,
      builder: (_) => _WalletPickerDialog(wallets: wallets),
    );
    if (chosenWallet == null) return;

    // Copy IDs before async operations
    final idsToMove = List<int>.from(_selectedRecordIds);
    _logger.info(
        'Batch moving ${idsToMove.length} records to wallet "${chosenWallet.name}" (ID ${chosenWallet.id})');

    // Exit select mode immediately
    if (mounted) {
      _exitSelectMode();
    }

    try {
      // Batch update wallet IDs (skips transfers with filter in DB)
      await ServiceConfig.database
          .updateRecordWalletInBatch(idsToMove, chosenWallet.id);
      // Refresh list after all updates complete
      if (mounted) {
        await _controller.updateRecurrentRecordsAndFetchRecords();
        if (mounted) {
          setState(() {});
        }
      }
    } catch (e, st) {
      _logger.handle(e, st, 'Error during batch move to wallet');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error moving records: $e')),
        );
      }
    }
  }

  /// Renames the selected records to title case ("Paçoca de Goiaba").
  /// Dinzo imports are renamed there too, so the next sync doesn't undo it;
  /// the app's own records keep their names.
  Future<void> _batchTitleCase() async {
    final ids = List<int>.from(_selectedRecordIds);
    _logger.info('Batch title-casing ${ids.length} records');
    if (mounted) _exitSelectMode();

    var renamed = 0;
    var dinzoFailed = 0;
    for (final id in ids) {
      final record = await ServiceConfig.database.getRecordById(id);
      if (record == null || record.title == null) continue;
      final title = titleCasePtBr(record.title!);
      if (title == record.title) continue;
      record.title = title;
      await ServiceConfig.database.updateRecordById(id, record);
      renamed++;
      // Records the app makes itself are not in Dinzo: renamed only here.
      if (record.dinzoId != null &&
          !DinzoSyncService.isSynthetic(record.dinzoId)) {
        try {
          await DinzoSyncService.pushTitle(record);
        } catch (e, st) {
          _logger.handle(e, st, 'Failed to rename record $id in Dinzo');
          dinzoFailed++;
        }
      }
    }

    if (!mounted) return;
    await _controller.updateRecurrentRecordsAndFetchRecords();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(dinzoFailed == 0
          ? '$renamed renomeado(s)'
          : '$renamed renomeado(s); $dinzoFailed não foram renomeados na Dinzo'),
    ));
  }

  /// Whether every selected record is hidden: the menu then offers to show
  /// them again instead of hiding.
  bool get _selectionAllHidden {
    final selected = _controller.filteredRecords
        .where((r) => r?.id != null && _selectedRecordIds.contains(r!.id));
    return selected.isNotEmpty && selected.every((r) => r!.isHidden);
  }

  /// Hides the selected records from the Extrato (tag [Record.hiddenTag]),
  /// or shows them again when all of them are already hidden. Nothing is
  /// deleted and the totals don't change.
  Future<void> _batchToggleHidden() async {
    final ids = List<int>.from(_selectedRecordIds);
    final hide = !_selectionAllHidden;
    _logger.info('Batch ${hide ? 'hiding' : 'unhiding'} ${ids.length} records');
    if (mounted) _exitSelectMode();

    var changed = 0;
    for (final id in ids) {
      final record = await ServiceConfig.database.getRecordById(id);
      if (record == null || record.isHidden == hide) continue;
      if (hide) {
        record.tags.add(Record.hiddenTag);
      } else {
        record.tags.remove(Record.hiddenTag);
      }
      await ServiceConfig.database.updateRecordById(id, record);
      changed++;
    }

    if (!mounted) return;
    await _controller.updateRecurrentRecordsAndFetchRecords();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(hide
          ? '$changed oculto(s). Para ver: carteiras → Exibir ocultos'
          : '$changed voltou(aram) a aparecer'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isSelectMode && _linkingEstimate == null,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (!didPop && _linkingEstimate != null) {
          _stopLinking();
        } else if (!didPop && _isSelectMode) {
          _exitSelectMode();
        }
      },
      child: Scaffold(
        body: _buildBody(),
        appBar: _buildAppBar(),
        bottomNavigationBar: _buildLinkingBar(),
        floatingActionButton:
            _linkingEstimate == null ? _buildFloatingActionButton() : null,
      ),
    );
  }

  /// Fork: the Extrato on the computer, in the idea of the Início: the picture
  /// on top with a sheet rising over it, the summaries on the left and the list
  /// on the right. The summaries stay put while the list scrolls.
  static const double _sheetOverlap = 24;
  static const double _summaryWidth = 420;

  Widget _buildWideBody() {
    final theme = Theme.of(context);
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: _summaryWidth,
          child: CustomScrollView(
            primary: false,
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
              // A rounded block, aligned with the budget below: no edge
              // runs along the whole screen.
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _buildSummaryBox(),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: BudgetPlanSummaryCard(
                  title: _controller.header,
                  interval: _controller.currentInterval,
                  revision: Object.hash(
                    _controller.header,
                    identityHashCode(_controller.filteredRecords),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: RefreshIndicator(
              key: ValueKey(_controller.header),
              onRefresh: _pullToSync,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  const SliverToBoxAdapter(child: SizedBox(height: 8)),
                  if (_controller.listedRecords.isEmpty) _buildEmptyState(),
                  _buildRecordList(),
                  const SliverToBoxAdapter(child: SizedBox(height: 75)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
    // Searching: the search bar is the Scaffold's, there is no picture.
    if (_controller.isSearchingEnabled) return content;

    final height = TabRecordsAppBar.expandedHeightFor(context);
    final overlap = _sheetOverlap;
    // Everything positioned: the Stack takes all the height it is given. A
    // child with its own size would make it only as tall as that child.
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: height,
          child: CustomScrollView(
            physics: const NeverScrollableScrollPhysics(),
            primary: false,
            slivers: [_buildMainSliverAppBar(titleLift: overlap)],
          ),
        ),
        Positioned.fill(
          top: height - overlap,
          // A Material, so that the list rows can paint their ink on it.
          child: Material(
            clipBehavior: Clip.antiAlias,
            color: theme.scaffoldBackgroundColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(overlap),
              ),
            ),
            child: content,
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (isWideLayout(context)) return _buildWideBody();
    return GestureDetector(
      onHorizontalDragEnd: (DragEndDetails details) {
        // Swipe left to right (positive velocity) = shift back (-1)
        // Swipe right to left (negative velocity) = shift forward (+1)
        if (details.primaryVelocity != null) {
          if (details.primaryVelocity! > 500) {
            // Swiped left to right - go back
            if (_controller.canShiftBack()) {
              _controller.shiftInterval(-1);
            }
          } else if (details.primaryVelocity! < -500) {
            // Swiped right to left - go forward
            if (_controller.canShiftForward()) {
              _controller.shiftInterval(1);
            }
          }
        }
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 600),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: NotificationListener<ScrollNotification>(
          key: ValueKey(_controller.header),
          onNotification: (scrollInfo) {
            final isExpanded = scrollInfo.metrics.pixels < 100;
            if (_isAppBarExpanded != isExpanded) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() {
                    _isAppBarExpanded = isExpanded;
                  });
                }
              });
            }
            return true;
          },
          child: RefreshIndicator(
            onRefresh: _pullToSync,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: _buildSlivers(),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onRecordListBack() async {
    await _controller.updateRecurrentRecordsAndFetchRecords();
    HomeWidgetService.refreshAll();
  }

  List<Widget> _buildSlivers() {
    return <Widget>[
      if (!_controller.isSearchingEnabled) _buildMainSliverAppBar(),
      _buildSummarySection(),
      if (_controller.listedRecords.isEmpty) _buildEmptyState(),
      _buildRecordList(),
      const SliverToBoxAdapter(
        child: SizedBox(height: 75),
      ),
    ];
  }

  Widget _buildRecordList() => RecordsDayList(
    _controller.listedRecords,
    onListBackCallback: _onRecordListBack,
    isSelectMode: _isSelectMode,
    selectedRecordIds: _selectedRecordIds,
    onRecordLongPressed: _enterSelectMode,
    onRecordTapped: _toggleRecord,
    onDateTapped: (date) =>
        _controller.navigateToAddNewRecord(context, initialDate: date),
    linkingEstimate: _linkingEstimate,
    onEstimateLongPressed: _startLinking,
    onLinkTarget: _linkTo,
    onLinkMatch: (estimate) => _link(estimate, estimate.estimateMatch!),
  );

  Widget _buildMainSliverAppBar({double titleLift = 0}) {
    return TabRecordsAppBar(
      controller: _controller,
      // On the computer the bar never collapses (the list scrolls below it).
      isAppBarExpanded: titleLift > 0 || _isAppBarExpanded,
      titleLift: titleLift,
      onAccountsTapped: _showAccounts,
      accountsFiltered: MoneyAccounts.filtering,
      syncPill: _syncPill(),
      onUpcomingPressed: () => _controller.toggleUpcoming(),
      onDatePickerPressed: () => _showDatePicker(),
      onPeriodTapped: () => TabRecordsDatePicker.pickSamePeriod(
          context, _controller, () => setState(() {})),
      onStatisticsPressed: () => _controller.navigateToStatisticsPage(context),
      onSearchPressed: () => _controller.startSearch(),
      isSelectMode: _isSelectMode,
      selectedCount: _selectedRecordIds.length,
      onClose: _exitSelectMode,
      onDelete: _batchDelete,
      onSelectAll: _selectAll,
      onDuplicate: _batchDuplicate,
      onMoveToWallet: ServiceConfig.walletsEnabled ? _batchMoveToWallet : null,
      onTitleCase: _batchTitleCase,
      onToggleHidden: _batchToggleHidden,
      selectionAllHidden: _selectionAllHidden,
    );
  }

  Future<void> _showAccounts() async {
    final before = MoneyAccounts.changes.value;
    await AccountsSheet.show(context);
    if (MoneyAccounts.changes.value == before || !mounted) return;
    await _controller.updateRecurrentRecordsAndFetchRecords();
    setState(() {});
  }

  PreferredSizeWidget? _buildAppBar() {
    if (!_controller.isSearchingEnabled) return null;

    if (_isSelectMode) {
      return TabRecordsSelectionAppBar(
        selectedCount: _selectedRecordIds.length,
        onClose: _exitSelectMode,
        onDelete: _batchDelete,
        onSelectAll: _selectAll,
        onDuplicate: _batchDuplicate,
        onMoveToWallet: ServiceConfig.walletsEnabled ? _batchMoveToWallet : null,
        onTitleCase: _batchTitleCase,
        onToggleHidden: _batchToggleHidden,
        selectionAllHidden: _selectionAllHidden,
      );
    }

    return TabRecordsSearchAppBar(
      controller: _controller,
      onBackPressed: () => _controller.stopSearch(),
      onDatePickerPressed: () => _showDatePicker(),
      onStatisticsPressed: () => _controller.navigateToStatisticsPage(context),
      onFilterPressed: () => _controller.showFilterModal(context),
      hasActiveFilters: _controller.hasActiveFilters,
    );
  }

  /// Automatic sync (Dinzo or an extension): running, applied, waiting for
  /// review or failed.
  /// Fork: sync state as a pill next to the person button, instead of a
  /// banner over the list (2026-10-29): spinning while Dinzo / an
  /// extension sync, "⚠ Dinzo" when something needs a look (review, failure).
  /// Nothing when all went fine.
  /// Tapping opens the review or the history and clears it.
  Widget? _syncPill() {
    final dinzo = DinzoAutoSync.status.value;
    bool running(DinzoAutoSyncStatus? s) =>
        s?.state == DinzoAutoSyncState.running;
    bool attention(DinzoAutoSyncStatus? s) =>
        s != null &&
        (s.state == DinzoAutoSyncState.needsReview ||
            s.state == DinzoAutoSyncState.failed);
    Widget pill(String label, {bool busy = false, VoidCallback? onTap}) =>
        Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Material(
            color: Colors.black.withValues(alpha: 0.28),
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    busy
                        ? const SizedBox(
                            width: 13,
                            height: 13,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.8,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.warning_amber_rounded,
                            size: 16, color: Color(0xFFFFC107)),
                    const SizedBox(width: 5),
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
    if (running(dinzo)) return pill('Dinzo', busy: true);
    for (final e in SyncExtensions.all) {
      if (running(e.status.value)) return pill(e.shortName, busy: true);
    }
    if (attention(dinzo)) return pill('Dinzo', onTap: _openDinzoReview);
    for (final e in SyncExtensions.all) {
      if (attention(e.status.value)) {
        return pill(e.shortName, onTap: () {
          e.clearStatus();
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DinzoSyncHistoryPage()),
          );
        });
      }
    }
    return null;
  }

  /// Pull to refresh: the quick Dinzo and extension syncs right away, with
  /// the result in the banner. The sync screen only opens when it needs the
  /// user: the first (full) sync, or a plan waiting for review.
  Future<void> _pullToSync() async {
    if (DinzoSyncService.apiKey != null &&
        (DinzoSyncService.lastSync == null ||
            !await DailyMoney.started())) {
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const DinzoSyncPage()),
      );
    } else {
      await Future.wait([
        DinzoAutoSync.run(force: true).then((_) => DinzoAutoSync.whenIdle()),
        SyncExtensions.runAllForced(),
      ]);
    }
    await _controller.updateRecurrentRecordsAndFetchRecords();
    if (mounted &&
        DinzoAutoSync.status.value?.state == DinzoAutoSyncState.needsReview) {
      await _openDinzoReview();
    }
  }

  /// Review opens the sync screen with the plan already fetched; anything
  /// else opens it fresh.
  Future<void> _openDinzoReview() async {
    final status = DinzoAutoSync.status.value;
    if (status?.state == DinzoAutoSyncState.applied) {
      // Already imported: show what came in.
      DinzoAutoSync.clear();
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const DinzoSyncHistoryPage()),
      );
      return;
    }
    final prepared = status?.state == DinzoAutoSyncState.needsReview
        ? status!.prepared
        : null;
    if (status?.state != DinzoAutoSyncState.needsReview) DinzoAutoSync.clear();
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DinzoSyncPage(prepared: prepared)),
    );
    await _controller.updateRecurrentRecordsAndFetchRecords();
  }

  Widget _buildSummarySection() => SliverToBoxAdapter(child: _buildSummaryBox());

  Widget _buildSummaryBox() {
    // Hide the wallet/accounts bar when the wallets feature is disabled or the
    // "Show wallet bar on the homepage" toggle is off. The Income/Expenses/
    // Balance stats are always shown.
    final showWalletBar =
        ServiceConfig.walletsEnabled && ServiceConfig.showWalletBarOnHomepage;
    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      child: DaysSummaryBox(
        _controller.summaryRecords,
        walletLabel: _controller.walletRowLabel,
        walletBreakdown: _controller.walletBreakdown,
        walletBalanceString: _controller.selectedWalletsBalanceString,
        walletBalance: _controller.selectedWalletsBalance,
        walletMap: _controller.walletMap,
        showSetAside: _controller.hasWalletsOutsideTotal,
        onWalletRowTap: () => _controller.navigateToWalletPicker(context),
        onStatTap: (tab) =>
            _controller.navigateToStatisticsPage(context, tab: tab),
        onSetAsideTap: (label, records) => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RecordsListPage(
              title: '$label · ${_controller.header}',
              records: records,
            ),
          ),
        ),
        showWalletRow: showWalletBar,
      ),
    );
  }

  Widget _buildEmptyState() {
    return SliverToBoxAdapter(
      child: Column(
        children: [
          Image.asset('assets/images/no_entry.png', width: 200),
          const SizedBox(height: 10),
          Text(
            'Sem registros ainda.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingActionButton() {
    // No hero animation: all shell tabs stay mounted, so default FAB hero
    // tags would collide on any root-navigator push (duplicate-hero crash).
    return FloatingActionButton(
      heroTag: null,
      onPressed: () => _controller.navigateToAddNewRecord(context),
      tooltip: 'Adicionar novo Item',
      child: Semantics(
        identifier: 'add-record',
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _showDatePicker() async {
    await showDialog(
      context: context,
      builder: (context) => TabRecordsDatePicker(
        controller: _controller,
        onDateSelected: () => setState(() {}),
      ),
    );
  }

  // Public method for external navigation callbacks
  onTabChange() async {
    await _controller.onTabChange();
  }
}

class _WalletPickerDialog extends StatelessWidget {
  final List<Wallet> wallets;

  const _WalletPickerDialog({required this.wallets});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Escolher carteira'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: wallets.length,
          itemBuilder: (context, index) {
            final wallet = wallets[index];
            return ListTile(
              title: Text(wallet.name),
              onTap: () => Navigator.pop(context, wallet),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancelar'),
        ),
      ],
    );
  }
}
