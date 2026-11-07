
import 'package:aupp/accounts/money-accounts.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:aupp/statistics/statistics-page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../categories/categories-tab-page-view.dart';
import '../../helpers/alert-dialog-builder.dart';
import '../../helpers/datetime-utility-functions.dart';
import '../../helpers/records-utility-functions.dart';
import '../../models/category.dart';
import '../../models/record.dart';
import '../../models/wallet.dart';
import '../../wallets/wallet-picker-page.dart';
import '../../services/database/database-interface.dart';
import '../../services/recurrent-record-service.dart';
import '../../services/service-config.dart';
import '../../services/total-wallets.dart';
import '../../settings/constants/homepage-time-interval.dart';
import '../../settings/constants/overview-time-interval.dart';
import '../../settings/constants/preferences-keys.dart';
import '../components/filter_modal_content.dart';
import '../components/tab_records_date_picker.dart' show shownPeriodOf;
import 'package:aupp/dinzo/estimate-link.dart';

class TabRecordsController {
  final VoidCallback onStateChanged;
  final DatabaseInterface _database = ServiceConfig.database;
  final TextEditingController _searchController = TextEditingController();
  final GlobalKey<CategoryTabPageViewState> _categoryTabPageViewStateKey =
      GlobalKey();

  // State variables
  List<Record?> records = [];
  List<Record?>? overviewRecords;
  List<Record?> filteredRecords = [];

  /// What the list shows: [filteredRecords], without the upcoming
  /// occurrences unless [showUpcoming].
  List<Record?> listedRecords = [];
  List<Category?> categories = [];
  List<String> tags = [];

  // Filters state variable
  List<Category?> selectedCategories = [];
  List<String> selectedTags = [];
  bool categoryTagOrLogic = true;
  bool tagORLogic = false;

  // Wallet filter state
  List<Wallet> allWallets = [];
  List<Wallet> selectedWallets = [];

  /// Fork: wallets counted in the top totals and balance; empty = the
  /// listed ones ([selectedWallets]).
  List<Wallet> totalWallets = [];

  /// Records after search/category/tag filters but before the wallet filter,
  /// and the overview records unfiltered: the totals filter them by
  /// [totalWallets].
  List<Record?> _beforeWalletFilter = [];

  /// Fork: whether the list also shows records tagged [Record.hiddenTag].
  bool showHidden = ServiceConfig.sharedPreferences
          ?.getBool(PreferencesKeys.extratoShowHidden) ??
      false;

  /// Fork: whether the list shows the occurrences not stored yet
  /// (recurrences, estimates); those of today always show. Off at every
  /// start of the app. Only the list: totals and statistics count them.
  static bool showUpcoming = false;

  /// The list before hidden records are dropped: hiding only takes them off
  /// the list, the totals still count them.
  List<Record?> _listedWithHidden = [];
  List<Record?>? _overviewAll;
  bool _walletPrefsLoaded = false;

  // Future records state (for adjusting wallet balances)
  List<Record> _futureRecords = [];

  // Point-in-time balance state: when the selected period has fully elapsed
  // (its end is before today), wallet balances are overridden to reflect
  // their value as of the end of that period, instead of the live total.
  DateTime? _balanceAsOfDate;

  String header = "";
  int backgroundImageIndex = DateTime.now().month;
  DateTime? customIntervalFrom;
  DateTime? customIntervalTo;
  bool isSearchingEnabled = false;
  bool _isNavigating = false;

  TabRecordsController({required this.onStateChanged}) {
    _searchController.addListener(_onSearchChanged);
  }

  Future<void> initialize() async {
    await updateRecurrentRecordsAndFetchRecords();
    await _fetchCategories();
    await _loadWallets();
  }

  Future<void> onResume() async {
    await updateRecurrentRecordsAndFetchRecords();
    await _loadWallets();
  }

  Future<void> onTabChange() async {
    await updateRecurrentRecordsAndFetchRecords();
    await _loadWallets();
    await _categoryTabPageViewStateKey.currentState?.refreshCategories();
  }

  void dispose() {
    _searchController.dispose();
  }

  // Search functionality
  void _onSearchChanged() => filterRecords();

  void startSearch() {
    isSearchingEnabled = true;
    _searchController.clear();
    selectedCategories = [];
    selectedTags = [];
    filterRecords();
    onStateChanged();
  }

  void stopSearch() {
    isSearchingEnabled = false;
    _searchController.clear();
    selectedCategories = [];
    selectedTags = [];
    filterRecords();
    onStateChanged();
  }

  void filterRecords() {
    List<Record?> tempRecords;

    final hasSearch = _searchController.text.isNotEmpty;
    final hasCategories = selectedCategories.isNotEmpty;
    final hasTags = selectedTags.isNotEmpty;

    if (!hasSearch && !hasCategories && !hasTags) {
      tempRecords = records;
    } else {
      final query = _searchController.text.toLowerCase().trim();

      tempRecords = records.where((record) {
        bool matchesSearch = !hasSearch;
        if (hasSearch) {
          matchesSearch = matchesSmartSearch(record?.title, query) ||
              matchesSmartSearch(record?.description, query) ||
              matchesSmartSearch(record?.category?.name, query) ||
              matchesSmartSearch(record?.tags.join(" "), query);
        }

        // Categories
        bool matchesCategories = !hasCategories;
        if (hasCategories) {
          matchesCategories = selectedCategories.contains(record?.category);
        }

        // Tags
        bool matchesTags = !hasTags;
        if (hasTags && record?.tags != null) {
          if (tagORLogic) {
            // OR logic: any tag matches
            matchesTags = selectedTags.any((tag) => record!.tags.contains(tag));
          } else {
            // AND logic: all tags must match
            matchesTags =
                selectedTags.every((tag) => record!.tags.contains(tag));
          }
        }

        // Combine Categories + Tags depending on user choice
        bool matchesCategoryTagCombo;
        if (hasCategories && hasTags) {
          if (categoryTagOrLogic) {
            // OR between categories and tags
            matchesCategoryTagCombo = matchesCategories || matchesTags;
          } else {
            // AND between categories and tags
            matchesCategoryTagCombo = matchesCategories && matchesTags;
          }
        } else {
          // If only one of them is active, just use that result
          matchesCategoryTagCombo = matchesCategories && matchesTags;
        }

        // Final check includes search
        return matchesSearch && matchesCategoryTagCombo;
      }).toList();
    }

    _beforeWalletFilter = tempRecords;
    // Wallet filter
    if (selectedWallets.isNotEmpty) {
      final selectedIds = selectedWallets.map((w) => w.id).toSet();
      tempRecords = applyTransferAwareWalletFilter(tempRecords, selectedIds);
    }

    _listedWithHidden = tempRecords;
    if (!showHidden) tempRecords = withoutHidden(tempRecords);

    if (!const DeepCollectionEquality().equals(filteredRecords, tempRecords)) {
      filteredRecords = tempRecords;
      _updateListed();
      onStateChanged();
    }
  }

  void toggleUpcoming() {
    showUpcoming = !showUpcoming;
    _updateListed();
    onStateChanged();
  }

  void _updateListed() {
    if (showUpcoming) {
      listedRecords = filteredRecords;
      return;
    }
    final now = DateTime.now();
    listedRecords = filteredRecords.where((r) {
      if (r == null || !r.isFutureRecord) return true;
      final d = r.dateTime;
      return d.year == now.year && d.month == now.month && d.day == now.day;
    }).toList();
  }

  /// [records] without the hidden ones. A purchase's caixinha part
  /// ([Record.isSplitPart]) goes with it.
  static List<Record?> withoutHidden(List<Record?> records) {
    final hiddenDinzoIds = {
      for (final r in records)
        if (r != null && r.isHidden && r.dinzoId != null) r.dinzoId,
    };
    return records
        .where((r) =>
            r == null ||
            !(r.isHidden || hiddenDinzoIds.contains(r.splitParentDinzoId)))
        .toList();
  }

  /// Records in the period tagged [Record.hiddenTag].
  int get hiddenCount => records.where((r) => r?.isHidden ?? false).length;

  /// Filters [records] to those belonging to [selectedWalletIds], treating
  /// transfers as visible from both source and destination perspectives.
  ///
  /// - Source match: include the record unchanged (negative value, money out).
  /// - Destination-only match: include a copy with [value] set to the received
  ///   amount ([transferValue] for cross-currency, otherwise `value.abs()`).
  ///   [isDestinationTransferView] is set to true so the UI resolves the
  ///   display currency from [transferWalletId] instead of [walletId].
  /// - Both wallets selected: include once via the source match (no duplicate).
  ///
  /// For a transfer, [isSingleSideTransferView] is set to true exactly when
  /// only one of its two wallets is in [selectedWalletIds] - i.e. the source
  /// match above did NOT also match the destination, or vice versa. The UI
  /// uses this to color the amount by sign (this side's perspective) instead
  /// of the neutral color a fully-visible (or unfiltered) transfer gets.
  /// Also used by the home screen's month totals (fork).
  static List<Record?> applyTransferAwareWalletFilter(
    List<Record?> records,
    Set<int?> selectedWalletIds,
  ) {
    final result = <Record?>[];
    for (final r in records) {
      final matchesSource = selectedWalletIds.contains(r?.walletId);
      final matchesDest = r?.isTransfer == true &&
          selectedWalletIds.contains(r?.transferWalletId);

      if (matchesSource) {
        result.add(r?.isTransfer == true
            ? r!.copyWith(isSingleSideTransferView: !matchesDest)
            : r);
      } else if (matchesDest) {
        // Show from destination perspective: use the received amount as value.
        // transferValue holds the destination-currency amount for cross-currency
        // transfers; fall back to value.abs() for same-currency ones.
        final receivedAmount =
            r!.transferValue ?? (r.value != null ? r.value!.abs() : null);
        result.add(r.copyWith(
          value: receivedAmount,
          sourceTransferValue: r.value,
          isDestinationTransferView: true,
          // matchesDest-only (this branch) means the source wallet was not
          // selected, so by construction only one side is visible here.
          isSingleSideTransferView: true,
        ));
      }
    }
    return result;
  }

  /// Returns true when [intervalTo] (the end of a viewed period) falls
  /// entirely before the start of [now]'s calendar day — i.e. the period has
  /// fully elapsed and its wallet balance should be a point-in-time snapshot
  /// rather than the live total.
  @visibleForTesting
  static bool isPastPeriodEnd(DateTime intervalTo, DateTime now) {
    final startOfToday = DateTime(now.year, now.month, now.day);
    return intervalTo.isBefore(startOfToday);
  }

  @visibleForTesting
  bool matchesSmartSearch(String? text, String query) {
    if (text == null || text.isEmpty || query.isEmpty) return false;

    final textLower = text.toLowerCase();
    final queryLower = query.toLowerCase();

    // Split both the text and query into words (handling multiple spaces, punctuation, etc.)
    final words = textLower
        .split(RegExp(r'[\s\-_.,;:!?()]+'))
        .where((word) => word.isNotEmpty)
        .toList();

    final queryTerms = queryLower
        .split(RegExp(r'[\s\-_.,;:!?()]+'))
        .where((term) => term.isNotEmpty)
        .toList();

    if (words.isEmpty || queryTerms.isEmpty) return false;

    // All query terms must match at least one word (AND logic)
    return queryTerms
        .every((term) => words.any((word) => word.startsWith(term)));
  }

  // Data fetching
  Future<void> updateRecurrentRecordsAndFetchRecords() async {
    var recurrentRecordService =
        RecurrentRecordService();
    final int startDay = getHomepageRecordsMonthStartDay();
    HomepageTimeInterval hti = getHomepageTimeIntervalEnumSetting();

    DateTime intervalFrom;
    DateTime intervalTo;

    if (customIntervalFrom != null) {
      // If the user has manual navigation (Forward/Back), respect it
      intervalFrom = customIntervalFrom!;
      intervalTo = customIntervalTo!;
    } else if (startDay != 1 && hti == HomepageTimeInterval.CurrentMonth) {
      // If it's a custom start day and we are in "Month" view, calculate the cycle
      var cycle = calculateMonthCycle(DateTime.now(), startDay);
      intervalFrom = cycle[0];
      intervalTo = cycle[1];
      header =
          "${getShortDateStr(intervalFrom)} - ${getShortDateStr(intervalTo)}";
    } else {
      // Standard logic (Week, Year, or Day 1 Month)
      var interval =
          await getTimeIntervalFromHomepageTimeInterval(_database, hti);
      intervalFrom = interval[0];
      intervalTo = interval[1];
      header = getHeaderFromHomepageTimeInterval(hti);
    }

    // Fork: wallet balances are always the balance at the end of the shown
    // period (the upstream "Wallet balance" option is ignored): past periods
    // are a snapshot, current and future ones add every scheduled occurrence
    // up to the period end (see _loadWallets).
    _balanceAsOfDate = ServiceConfig.walletsEnabled ? intervalTo : null;

    // Update recurrent records and get future records
    List<Record> futureRecords =
        await recurrentRecordService.updateRecurrentRecords(intervalTo);

    // Fetch records from database
    List<Record?> newRecords;
    newRecords = await getRecordsByInterval(_database, intervalFrom, intervalTo);
    backgroundImageIndex = isFullYear(intervalFrom, intervalTo)
        ? DateTime.now().month
        : intervalFrom.month;

    // Filter future records to only include those within the current time interval.
    // Use calendar-date comparison in the record's own timezone to avoid cross-timezone
    // bleed (e.g. a Vienna-timezone May 1 record appearing in the April London view).
    final fromDate =
        DateTime(intervalFrom.year, intervalFrom.month, intervalFrom.day);
    final toDate = DateTime(intervalTo.year, intervalTo.month, intervalTo.day);

    List<Record> filteredFutureRecords = futureRecords.where((record) {
      final recordLocal = record.dateTime;
      final recordDate =
          DateTime(recordLocal.year, recordLocal.month, recordLocal.day);
      return !recordDate.isBefore(fromDate) && !recordDate.isAfter(toDate);
    }).toList();

    // Every occurrence not stored yet, up to the period end: the wallet
    // balance at the end of a current or future period includes them all,
    // not only the ones inside the period.
    _futureRecords = futureRecords;

    // The same money twice counts once, whatever the period shows.
    EstimateLink.markMatches([...newRecords, ...futureRecords]);

    // Merge future records with database records.
    // Fork: only the accounts switched on (person button).
    List<Record?> allRecords =
        MoneyAccounts.shown([...newRecords, ...filteredFutureRecords]);

    records = allRecords;
    filteredRecords = allRecords;
    _updateListed();
    _extractTags(allRecords);
    _extractCategories(allRecords);
    filterRecords();

    // Handle overview records
    OverviewTimeInterval overviewTimeIntervalEnum =
        getHomepageOverviewWidgetTimeIntervalEnumSetting();
    if (overviewTimeIntervalEnum == OverviewTimeInterval.DisplayedRecords) {
      // When set to DisplayedRecords, use the filtered records
      overviewRecords = null;
      _overviewAll = null;
    } else {
      HomepageTimeInterval recordTimeIntervalEnum =
          mapOverviewTimeIntervalToHomepageTimeInterval(
              overviewTimeIntervalEnum);
      var overviewInterval = await getTimeIntervalFromHomepageTimeInterval(
          _database, recordTimeIntervalEnum);
      var overviewFrom = overviewInterval[0];
      var overviewTo = overviewInterval[1];
      var overviewDbRecords = await getRecordsByInterval(
          _database, overviewFrom, overviewTo);

      // Also merge future records
      // that fall within the overview interval, keeping the wallet balance
      // consistent with the income/expenses displayed in the summary card.
      if (futureRecords.isNotEmpty) {
        final fromDate =
            DateTime(overviewFrom.year, overviewFrom.month, overviewFrom.day);
        final toDate =
            DateTime(overviewTo.year, overviewTo.month, overviewTo.day);
        final matchingFuture = futureRecords.where((record) {
          final recordLocal = record.dateTime;
          final recordDate =
              DateTime(recordLocal.year, recordLocal.month, recordLocal.day);
          return !recordDate.isBefore(fromDate) && !recordDate.isAfter(toDate);
        }).toList();
        overviewRecords =
            MoneyAccounts.shown([...overviewDbRecords, ...matchingFuture]);
      } else {
        overviewRecords = MoneyAccounts.shown(overviewDbRecords);
      }
      _overviewAll = overviewRecords;
    }

    // Refresh wallet balances since records have changed
    await _loadWallets();

    onStateChanged();
  }

  void _extractTags(List<Record?> records) {
    final Set<String> uniqueTags = {};
    for (var record in records) {
      if (record != null) {
        uniqueTags.addAll(record.tags);
      }
    }
    tags = uniqueTags.toList();
  }

  void _extractCategories(List<Record?> records) {
    final Set<Category?> uniqueCategories = {};
    for (var record in records) {
      if (record != null && record.category != null) {
        uniqueCategories.add(record.category);
      }
    }
    categories = uniqueCategories.toList();
  }

  Future<void> _fetchCategories() async {
    categories = await _database.getAllCategories();
    onStateChanged();
  }

  Future<void> _loadWallets() async {
    if (!ServiceConfig.walletsEnabled) {
      // Wallets feature is disabled: clear wallet state so the homepage shows
      // no wallet-related UI and no wallet-based record filtering.
      allWallets = [];
      selectedWallets = [];
      _walletPrefsLoaded = false;
      onStateChanged();
      return;
    }

    final wallets = await _database.getAllWallets();
    allWallets = wallets.where((w) => !w.isArchived).toList();

    // Balance at the end of the shown period: what is stored up to then, plus,
    // for a period not over yet, every occurrence not stored yet (recurrences,
    // estimates still unlinked) dated up to its end. A period already over is
    // only what really happened.
    if (_balanceAsOfDate != null) {
      final asOfWallets = await _database.getWalletsBalanceAsOf(
          _balanceAsOfDate!);
      final asOfBalanceById = {
        for (final w in asOfWallets)
          if (w.id != null) w.id!: w.balance
      };
      for (final wallet in allWallets) {
        if (wallet.id != null && asOfBalanceById.containsKey(wallet.id)) {
          wallet.balance = asOfBalanceById[wallet.id];
        }
      }
      if (!isPastPeriodEnd(_balanceAsOfDate!, DateTime.now())) {
        final asOfUtc = _balanceAsOfDate!.toUtc();
        _addFutureRecords(
            _futureRecords.where(
              (r) => !r.utcDateTime.isAfter(asOfUtc) && r.estimateMatch == null,
            ));
      }
    }

    if (totalWallets.isNotEmpty) {
      final totalIds = totalWallets.map((w) => w.id).toSet();
      totalWallets = allWallets.where((w) => totalIds.contains(w.id)).toList();
    }
    if (selectedWallets.isNotEmpty) {
      // Re-sync selectedWallets so balances stay fresh after external edits
      final selectedIds = selectedWallets.map((w) => w.id).toSet();
      selectedWallets =
          allWallets.where((w) => selectedIds.contains(w.id)).toList();
    } else if (!_walletPrefsLoaded) {
      // First load: restore the saved selection
      _walletPrefsLoaded = true;
      selectedWallets = [];
      final prefs = await SharedPreferences.getInstance();
      totalWallets = TotalWallets.chosenIn(allWallets);
      final savedIds = prefs
              .getStringList(PreferencesKeys.homePageWalletFilter) ??
          [];
      if (savedIds.isNotEmpty) {
        final idSet = savedIds.map(int.tryParse).toSet();
        selectedWallets =
            allWallets.where((w) => idSet.contains(w.id)).toList();
        // Apply the wallet filter to already-fetched records
        filterRecords();
        // Also filter overview records if they were fetched separately
        if (overviewRecords != null) {
          overviewRecords =
              applyTransferAwareWalletFilter(overviewRecords!, idSet);
        }
        return;
      }
    }
    onStateChanged();
  }

  /// Adds generated (never stored) records to the wallet balances.
  void _addFutureRecords(Iterable<Record> records) {
    final futureSumByWallet = <int, double>{};
    for (final record in records) {
      if (record.walletId != null) {
        futureSumByWallet.update(
          record.walletId!,
          (sum) => sum + (record.value ?? 0.0),
          ifAbsent: () => (record.value ?? 0.0),
        );
      }
      // For transfers, also credit the destination wallet. Same-currency
      // transfers store no transferValue: fall back to abs(value), like the
      // persisted-balance query (ABS(COALESCE(transfer_value, value))).
      if (record.transferWalletId != null) {
        final received = record.transferValue ?? record.value;
        if (received != null) {
          futureSumByWallet.update(
            record.transferWalletId!,
            (sum) => sum + received.abs(),
            ifAbsent: () => received.abs(),
          );
        }
      }
    }
    for (final wallet in allWallets) {
      if (wallet.id != null && futureSumByWallet.containsKey(wallet.id)) {
        wallet.balance = (wallet.balance ?? 0.0) + futureSumByWallet[wallet.id]!;
      }
    }
  }

  Future<void> navigateToWalletPicker(BuildContext context) async {
    final picked = await Navigator.push<WalletPickerResult>(
      context,
      MaterialPageRoute(
        builder: (_) => WalletPickerPage(
          multiSelect: true,
          initiallySelected: selectedWallets,
          preferencesKey: PreferencesKeys.homePageWalletFilter,
          asOfDate: _balanceAsOfDate,
          balances: {
            for (final w in allWallets)
              if (w.id != null) w.id!: w.balance ?? 0.0
          },
          initiallyCounted: totalWallets,
          initiallyShowHidden: showHidden,
          hiddenCount: hiddenCount,
        ),
      ),
    );
    if (picked != null) {
      final result = picked.listed;
      // The totals choice is a display setting: always kept.
      totalWallets =
          picked.counted.length == allWallets.length ? [] : picked.counted;
      final prefs = await SharedPreferences.getInstance();
      showHidden = picked.showHidden;
      await prefs.setBool(PreferencesKeys.extratoShowHidden, showHidden);
      await TotalWallets.save(totalWallets);
      // If every wallet is selected, treat it the same as "All accounts"
      selectedWallets = result.length == allWallets.length ? [] : result;
      filterRecords();
      onStateChanged();
    }
  }

  // Navigation methods
  Future<void> navigateToAddNewRecord(BuildContext context,
      {DateTime? initialDate}) async {
    if (_isNavigating) return;
    _isNavigating = true;
    try {
      var categoryIsSet = await _isThereSomeCategory();
      // Transfers do not require a category, but they do require the wallets
      // feature to be available. Let the add flow open when wallets exist even
      // if the user has not created any categories yet.
      if (categoryIsSet || ServiceConfig.walletsEnabled) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CategoryTabPageView(
              goToEditMovementPage: true,
              key: _categoryTabPageViewStateKey,
              initialDate: initialDate,
            ),
          ),
        );
        await updateRecurrentRecordsAndFetchRecords();
        await _loadWallets();
      } else {
        await _showNoCategoryDialog(context);
      }
    } finally {
      _isNavigating = false;
    }
  }

  /// The period on screen.
  Future<(DateTime, DateTime)> currentInterval() async {
    if (customIntervalFrom != null && customIntervalTo != null) {
      return (customIntervalFrom!, customIntervalTo!);
    }
    final interval = await getTimeIntervalFromHomepageTimeInterval(
      _database,
      getHomepageTimeIntervalEnumSetting(),
    );
    return (interval[0], interval[1]);
  }

  void navigateToStatisticsPage(BuildContext context, {StatisticsTab? tab}) {
    final wallets = walletMap;
    if (customIntervalTo == null) {
      var hti = getHomepageTimeIntervalEnumSetting();
      getTimeIntervalFromHomepageTimeInterval(_database, hti)
          .then((userDefinedInterval) => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => StatisticsPage(userDefinedInterval[0],
                      userDefinedInterval[1], filteredRecords,
                      walletMap: wallets,
                      showBudget: true,
                      navigation: this,
                      initialTab: tab),
                ),
              ));
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => StatisticsPage(
              customIntervalFrom, customIntervalTo, filteredRecords,
              walletMap: wallets,
              showBudget: true,
              navigation: this,
              initialTab: tab),
        ),
      );
    }
  }

  Future<void> showFilterModal(BuildContext context) async {
    List<Category?> usedCategories =
        records.map((record) => record?.category).toSet().toList();
    List<String> usedTags = records
        .expand((record) => record?.tags ?? {})
        .cast<String>()
        .toSet()
        .toList();
    await showModalBottomSheet(
      isScrollControlled: true, // This allows the modal to take more space
      context: context,
      builder: (context) {
        return FilterModalContent(
          categories: usedCategories,
          tags: usedTags,
          currentlySelectedCategories: selectedCategories,
          currentlySelectedTags: selectedTags,
          currentCategoryTagOrLogic: categoryTagOrLogic,
          currentTagsOrLogic: tagORLogic,
          onApplyFilters:
              (selectedCategories, selectedTags, categoryOR, tagOR) {
            this.selectedCategories = selectedCategories;
            this.selectedTags = selectedTags;
            this.categoryTagOrLogic = categoryOR;
            this.tagORLogic = tagOR;
            filterRecords();
          },
        );
      },
    );
  }

  // Helper methods
  Future<bool> _isThereSomeCategory() async {
    var categories = await _database.getAllCategories();
    return categories.isNotEmpty;
  }

  Future<void> _showNoCategoryDialog(BuildContext context) async {
    AlertDialogBuilder noCategoryDialog = AlertDialogBuilder(
            'Nenhuma Categoria foi definida ainda.')
        .addTrueButtonName("OK")
        .addSubtitle(
            'Você precisa definir uma categoria primeiro. Vá para a aba Categoria e adicione uma nova categoria.');

    await showDialog(
      context: context,
      builder: (context) => noCategoryDialog.build(context),
    );
  }

  // Date manipulation methods
  void updateCustomInterval(DateTime from, DateTime to, String newHeader) {
    customIntervalFrom = from;
    customIntervalTo = to;
    header = newHeader;
  }

  /// TODO Resets the homepage navigation to the default "Current" view.
  /// Call this whenever preferences (like Start Day or Interval) are changed.
  void resetHomepageInterval() {
    customIntervalFrom = null;
    customIntervalTo = null;
  }

  /// Navigates the homepage view forward or backward by a specific number of intervals.
  ///
  /// [shift] - An integer representing the number of periods to move.
  /// Positive moves forward in time, negative moves backward.
  ///
  /// This method:
  /// 1. Determines the current viewing period (defaults to 'now' if first load).
  /// 2. Calculates the new target period using [calculateInterval].
  /// 3. Updates the global [customIntervalFrom], [customIntervalTo], and [header].
  /// 4. Triggers a database fetch for the new date range.
  Future<void> shiftInterval(int shift) async {
    final int startDay = getHomepageRecordsMonthStartDay();
    final HomepageTimeInterval hti =
        _navPeriod ?? getHomepageTimeIntervalEnumSetting();

    DateTime baseDate = customIntervalFrom ?? DateTime.now();

    DateTime targetRef;
    if (hti == HomepageTimeInterval.CurrentMonth) {
      // We add the shift to the month.
      targetRef = DateTime(baseDate.year, baseDate.month + shift, startDay);
    } else if (hti == HomepageTimeInterval.CurrentYear) {
      targetRef = DateTime(baseDate.year + shift, 1, 1);
    } else {
      // Weekly shift - use date-only arithmetic to avoid DST boundary issues.
      // Duration(days: N) adds exactly N*24 hours which can cross DST transitions
      // and land on a different local date than intended.
      targetRef =
          DateTime(baseDate.year, baseDate.month, baseDate.day + 7 * shift);
    }

    await _showPeriod(hti, targetRef);
  }

  /// Fork: the switch next to the arrows. Month → the year containing it;
  /// year → the month seen before switching (if in that year), else the
  /// current month (this year) or January.
  Future<void> toggleMonthYear() async {
    final now = DateTime.now();
    final base = customIntervalFrom ?? now;
    if (_navPeriod == HomepageTimeInterval.CurrentMonth) {
      // The cycle's end (a cycle from the 25th is the next month's).
      _monthBeforeYear = customIntervalTo ?? now;
      await _showPeriod(
        HomepageTimeInterval.CurrentYear,
        DateTime(base.year, 1, 1),
      );
      return;
    }
    final year = base.year;
    final remembered = _monthBeforeYear;
    final DateTime month = remembered != null && remembered.year == year
        ? remembered
        : year == now.year
        ? now
        : DateTime(year, 1, 1);
    // The month (cycle) containing that date.
    await _showPeriod(HomepageTimeInterval.CurrentMonth, month);
  }

  DateTime? _monthBeforeYear;

  /// Fork: whether the switch month ↔ year is shown (month or year on screen).
  bool get canToggleMonthYear =>
      _navPeriod == HomepageTimeInterval.CurrentMonth ||
      _navPeriod == HomepageTimeInterval.CurrentYear;

  bool get showsYear => _navPeriod == HomepageTimeInterval.CurrentYear;

  /// The period the arrows move by: the one on screen (fork: a year picked
  /// while the setting is "month" moves by year), else the setting. Null =
  /// not navigable ("All" or a picked range under the "All" setting).
  HomepageTimeInterval? get _navPeriod {
    final setting = getHomepageTimeIntervalEnumSetting();
    final shown = shownPeriodOf(customIntervalFrom, customIntervalTo, setting);
    if (shown == HomepageTimeInterval.CurrentMonth ||
        shown == HomepageTimeInterval.CurrentYear) {
      return shown;
    }
    return setting == HomepageTimeInterval.All ? null : setting;
  }

  Future<void> _showPeriod(HomepageTimeInterval hti, DateTime targetRef) async {
    final int startDay = getHomepageRecordsMonthStartDay();
    List<DateTime> newInterval = calculateInterval(
      hti,
      targetRef,
      monthStartDay: startDay,
    );

    // Update the state
    customIntervalFrom = newInterval[0];
    customIntervalTo = newInterval[1];

    // Update Header (Slightly cleaner logic for Day 1 vs Cycle)
    if (hti == HomepageTimeInterval.CurrentMonth) {
      header = (startDay == 1)
          ? getMonthStr(customIntervalFrom!)
          : "${getShortDateStr(customIntervalFrom!)} - ${getShortDateStr(customIntervalTo!)}";
    } else if (hti == HomepageTimeInterval.CurrentYear) {
      header = getYearStr(customIntervalFrom!);
    } else {
      header = getWeekStr(customIntervalFrom!);
    }

    backgroundImageIndex = isFullYear(customIntervalFrom!, customIntervalTo!)
        ? DateTime.now().month
        : customIntervalFrom!.month;

    // Fetch records (now sees customIntervalFrom is not null and uses it)
    await updateRecurrentRecordsAndFetchRecords();
  }

  // Computed properties
  double getHeaderFontSize() => header.length > 13 ? 18.0 : 22.0;
  double getHeaderPaddingBottom() => header.length > 13 ? 15.0 : 13.0;

  bool canShiftBack() => isNavigable;

  bool canShiftForward() => isNavigable;

  /// Shifting is disabled only for the [HomepageTimeInterval.All] view.
  bool get isNavigable => _navPeriod != null;

  TextEditingController get searchController => _searchController;

  DatabaseInterface get database => _database;


  get hasActiveFilters =>
      selectedTags.isNotEmpty || selectedCategories.isNotEmpty;

  // Wallet computed properties
  double get totalWalletsBalance =>
      allWallets.fold(0.0, (sum, w) => sum + (w.balance ?? 0.0));

  /// The wallets behind the top totals: [totalWallets] when set, else the
  /// listed ones.
  List<Wallet> get _countedWallets =>
      totalWallets.isNotEmpty ? totalWallets : selectedWallets;

  /// Fork: whether some wallet is outside the ones behind the totals (money
  /// can be invested / set aside / taken back from it).
  bool get hasWalletsOutsideTotal {
    final counted = {for (final w in _countedWallets) w.id};
    if (counted.isEmpty) return false;
    return allWallets.any((w) => !w.isArchived && !counted.contains(w.id));
  }

  double get selectedWalletsBalance {
    if (_countedWallets.isEmpty) return totalWalletsBalance;
    return _countedWallets.fold(0.0, (sum, w) => sum + (w.balance ?? 0.0));
  }

  String get selectedWalletsBalanceString {
    final wallets = _countedWallets.isEmpty
        ? allWallets.where((w) => !w.isArchived).toList()
        : _countedWallets;
    return formatMoney(walletsTotal(wallets));
  }

  /// Records behind the top totals (income, expenses, balance).
  List<Record?> get summaryRecords {
    if (totalWallets.isEmpty) return overviewRecords ?? _listedWithHidden;
    return applyTransferAwareWalletFilter(
      _overviewAll ?? _beforeWalletFilter,
      totalWallets.map((w) => w.id).toSet(),
    );
  }

  Map<int, Wallet> get walletMap => {
        for (final w in allWallets)
          if (w.id != null) w.id!: w
      };

  /// The end-of-period date wallet balances are currently snapshotted to, or
  /// null when showing the live balance (current/future period).
  DateTime? get balanceAsOfDate => _balanceAsOfDate;

  /// The wallets behind the top balance, in wallet order, when there are two
  /// to five: the wallet row shows each balance instead of a label. More
  /// than that would not fit, so the label stays.
  List<Wallet> get walletBreakdown {
    if (_countedWallets.length < 2 || _countedWallets.length > 5) {
      return const [];
    }
    final ids = _countedWallets.map((w) => w.id).toSet();
    return allWallets.where((w) => ids.contains(w.id)).toList();
  }

  String get walletRowLabel {
    if (totalWallets.isNotEmpty) {
      return totalWallets.length <= 2
          ? totalWallets.map((w) => w.name).join(' + ')
          : '${totalWallets.length} carteiras no total';
    }
    if (selectedWallets.isEmpty) return 'Todas as contas';
    if (selectedWallets.length == 1) return selectedWallets.first.name;
    return '${selectedWallets.length.toString()} Carteiras';
  }
}
