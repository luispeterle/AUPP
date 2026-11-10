import 'dart:async';

import 'package:flutter/material.dart';
import 'package:aupp/dinzo/daily-money.dart';
import 'package:aupp/dinzo/dinzo-sync-service.dart';
import 'package:aupp/helpers/records-utility-functions.dart';
import 'package:aupp/models/wallet.dart';
import 'package:aupp/services/database/database-interface.dart';
import 'package:aupp/services/service-config.dart';
import 'package:aupp/settings/constants/preferences-keys.dart';
import 'package:aupp/wallets/edit-wallet-page.dart';
import 'package:aupp/wallets/wallet-picker-page.dart';
import 'package:aupp/wallets/wallet-sort-option.dart';
import 'package:aupp/wallets/wallets-list.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'bank-balances-page.dart';
import 'investment-classes.dart';
import 'wallet-sections.dart';

class WalletsTabPage extends StatefulWidget {
  WalletsTabPage({Key? key}) : super(key: key);

  @override
  WalletsTabPageState createState() => WalletsTabPageState();
}

class WalletsTabPageState extends State<WalletsTabPage> {
  DatabaseInterface database = ServiceConfig.database;
  List<Wallet>? _wallets;
  List<Wallet> _selectedWallets = [];
  bool _walletPrefsLoaded = false;
  bool _showArchived = false;

  WalletSortOption _selectedSortOption = WalletSortOption.original;
  WalletSortOption _storedDefaultOption = WalletSortOption.original;
  bool _isDefaultOrder = false;
  InvestmentTotals _investments = const InvestmentTotals();

  // When true the user is in drag-to-reorder mode; drag handles and OK button are visible.
  bool _inCustomOrderMode = false;
  // Holds the pending reordered list while the user drags (before pressing OK).
  /// The order dragged in each section, not saved yet.
  final Map<WalletSection, List<Wallet>> _pendingOrder = {};

  @override
  void initState() {
    super.initState();
    DailyBanks.revision.addListener(_loadInvestments);
    _loadWallets().then((_) => _initializeSortPreference());
  }

  @override
  void dispose() {
    DailyBanks.revision.removeListener(_loadInvestments);
    super.dispose();
  }

  Future<void> _initializeSortPreference() async {
    final key = PreferencesKeys.walletListSortOption;
    if (ServiceConfig.sharedPreferences!.containsKey(key)) {
      final savedIndex = ServiceConfig.sharedPreferences?.getInt(key);
      if (savedIndex != null && savedIndex < WalletSortOption.values.length) {
        setState(() {
          _storedDefaultOption = WalletSortOption.values[savedIndex];
          _selectedSortOption = WalletSortOption.values[savedIndex];
        });
      }
    }
  }

  Future<void> _storeOnUserPreferences() async {
    if (_isDefaultOrder) {
      await ServiceConfig.sharedPreferences?.setInt(
          PreferencesKeys.walletListSortOption, _selectedSortOption.index);
      setState(() {
        _storedDefaultOption = _selectedSortOption;
      });
    }
    _isDefaultOrder = false;
  }

  Future<void> _loadInvestments() async {
    final totals = await InvestmentTotals.load();
    if (mounted) setState(() => _investments = totals);
  }

  Future<void> _loadWallets() async {
    unawaited(_loadInvestments());
    final wallets = await database.getAllWallets();
    final allNonArchived = wallets.where((w) => !w.isArchived).toList();

    List<Wallet> updatedSelection = _selectedWallets;
    if (_selectedWallets.isNotEmpty) {
      // Re-sync so balances stay fresh after external edits
      final selectedIds = _selectedWallets.map((w) => w.id).toSet();
      updatedSelection =
          allNonArchived.where((w) => selectedIds.contains(w.id)).toList();
    } else if (!_walletPrefsLoaded) {
      // First load: restore the saved selection
      _walletPrefsLoaded = true;
      updatedSelection = [];
      final prefs = await SharedPreferences.getInstance();
      final savedIds = prefs.getStringList(
              PreferencesKeys.walletsTabWalletFilter) ??
          [];
      if (savedIds.isNotEmpty) {
        final idSet = savedIds.map(int.tryParse).toSet();
        updatedSelection =
            allNonArchived.where((w) => idSet.contains(w.id)).toList();
      }
    }

    setState(() {
      _wallets = wallets;
      _selectedWallets = updatedSelection;
      // Exit custom order mode on reload
      _inCustomOrderMode = false;
      _pendingOrder.clear();
    });
  }

  Future<void> onTabChange() async {
    await _loadWallets();
  }

  /// Confirm the pending drag order and persist it to the database.
  Future<void> _confirmCustomOrder() async {
    final sections = WalletSection.split(_walletsByArchiveStatusSorted);
    final ordered = [
      for (final section in WalletSection.values)
        ...?_pendingOrder[section] ?? sections[section],
    ];
    // Only persist the non-archived wallets order; archived stay unchanged.
    await database.resetWalletOrderIndexes(ordered);
    setState(() {
      _inCustomOrderMode = false;
      _pendingOrder.clear();
    });
    await _loadWallets();
  }

  void _showSortOptions() {
    WalletSortOption pendingOption = _selectedSortOption;
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.only(left: 16.0, top: 16, right: 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Ordenar por',
                        style: const TextStyle(fontSize: 22),
                      ),
                      Row(
                        children: [
                          Checkbox(
                            value: _isDefaultOrder ||
                                pendingOption == _storedDefaultOption,
                            onChanged: (value) {
                              setModalState(() {
                                _isDefaultOrder = value ?? false;
                              });
                            },
                          ),
                          Text('Tornar padrão'),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.reorder),
                  title: Text(
                    'Ordem personalizada',
                    style: TextStyle(
                      color: pendingOption == WalletSortOption.original
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  ),
                  trailing: pendingOption == WalletSortOption.original
                      ? Icon(Icons.check,
                          color: Theme.of(context).colorScheme.primary)
                      : null,
                  onTap: () {
                    setModalState(() {
                      pendingOption = WalletSortOption.original;
                    });
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.abc),
                  title: Text(
                    'Nome (alfabético)',
                    style: TextStyle(
                      color: pendingOption == WalletSortOption.byName
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  ),
                  trailing: pendingOption == WalletSortOption.byName
                      ? Icon(Icons.check,
                          color: Theme.of(context).colorScheme.primary)
                      : null,
                  onTap: () {
                    setModalState(() {
                      pendingOption = WalletSortOption.byName;
                    });
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.arrow_upward),
                  title: Text(
                    'Valor (Crescente)',
                    style: TextStyle(
                      color: pendingOption == WalletSortOption.byAmountAsc
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  ),
                  trailing: pendingOption == WalletSortOption.byAmountAsc
                      ? Icon(Icons.check,
                          color: Theme.of(context).colorScheme.primary)
                      : null,
                  onTap: () {
                    setModalState(() {
                      pendingOption = WalletSortOption.byAmountAsc;
                    });
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.arrow_downward),
                  title: Text(
                    'Valor (Decrescente)',
                    style: TextStyle(
                      color: pendingOption == WalletSortOption.byAmountDesc
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  ),
                  trailing: pendingOption == WalletSortOption.byAmountDesc
                      ? Icon(Icons.check,
                          color: Theme.of(context).colorScheme.primary)
                      : null,
                  onTap: () {
                    setModalState(() {
                      pendingOption = WalletSortOption.byAmountDesc;
                    });
                  },
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 8.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _selectedSortOption = pendingOption;
                          _inCustomOrderMode =
                              pendingOption == WalletSortOption.original;
                          _pendingOrder.clear();
                        });
                        _storeOnUserPreferences();
                        Navigator.pop(context);
                      },
                      child: Text('Aplicar'),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// The wallets used for balance/summary calculations.
  /// Returns the user's filter selection when active; otherwise all non-archived wallets.
  List<Wallet> get _displayWallets {
    if (_wallets == null) return [];
    if (_selectedWallets.isNotEmpty) return _selectedWallets;
    return _wallets!.where((w) => !w.isArchived).toList();
  }

  /// The total: with no filter, the investments shown below the wallets too.
  List<Wallet> get _totalWallets => [
    ..._displayWallets,
    if (_selectedWallets.isEmpty && _investments.total > 0)
      Wallet('', balance: _investments.total),
  ];

  String _displayBalanceString() => formatMoney(_displayBalanceTotal());

  double _displayBalanceTotal() => walletsTotal(_totalWallets);

  String get _headerLabel {
    if (_selectedWallets.isEmpty) return 'Todas as contas';
    if (_selectedWallets.length == 1) return _selectedWallets.first.name;
    return '${_selectedWallets.length.toString()} Carteiras';
  }

  Future<void> _clearWalletFilter() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(PreferencesKeys.walletsTabWalletFilter);
    setState(() {
      _selectedWallets = [];
    });
  }

  Future<void> _navigateToWalletPicker() async {
    final allNonArchived = _wallets!.where((w) => !w.isArchived).toList();
    final result = await Navigator.push<List<Wallet>>(
      context,
      MaterialPageRoute(
        builder: (_) => WalletPickerPage(
          multiSelect: true,
          initiallySelected: _selectedWallets,
          preferencesKey: PreferencesKeys.walletsTabWalletFilter,
        ),
      ),
    );
    if (result != null) {
      setState(() {
        _selectedWallets = result.length == allNonArchived.length ? [] : result;
      });
    }
  }

  /// Wallets filtered by archive status (and active wallet filter) and sorted by the selected sort option.
  List<Wallet> get _walletsByArchiveStatusSorted {
    if (_wallets == null) return [];
    var filtered =
        _wallets!.where((w) => w.isArchived == _showArchived).toList();
    if (!_showArchived && _selectedWallets.isNotEmpty) {
      final selectedIds = _selectedWallets.map((w) => w.id).toSet();
      filtered = filtered.where((w) => selectedIds.contains(w.id)).toList();
    }
    switch (_selectedSortOption) {
      case WalletSortOption.byName:
        filtered.sort((a, b) => a.name.compareTo(b.name));
        break;
      case WalletSortOption.byAmountAsc:
        filtered.sort((a, b) => (a.balance ?? 0.0).compareTo(b.balance ?? 0.0));
        break;
      case WalletSortOption.byAmountDesc:
        filtered.sort((a, b) => (b.balance ?? 0.0).compareTo(a.balance ?? 0.0));
        break;
      case WalletSortOption.original:
        // already ordered by sort_order from the DB query
        break;
    }
    return filtered;
  }

  /// Dia a dia, caixinhas, reservas, then the investments, which only
  /// show what the positions hold. Dragging reorders inside a section.
  List<Widget> _sections() {
    final sections = WalletSection.split(_walletsByArchiveStatusSorted);
    return [
      for (final section in WalletSection.values)
        if (sections[section]!.isNotEmpty) ...[
          _SectionHeader(section.label),
          WalletsList(
            sections[section]!,
            onChanged: _loadWallets,
            enableManualSorting:
                _inCustomOrderMode && section != WalletSection.reserves,
            onReorderPending: (wallets) => _pendingOrder[section] = wallets,
          ),
        ],
      if (_investments.total > 0) ...[
        const _SectionHeader('Investimentos', note: 'só para ver'),
        InvestmentClasses(_investments, dividerOnTop: false),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Scaffold(
      appBar: AppBar(
        title: Text(_showArchived ? 'Archived wallets' : 'Carteiras'),
        leading: _showArchived
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _showArchived = false),
              )
            : _inCustomOrderMode
                ? IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      _inCustomOrderMode = false;
                      _pendingOrder.clear();
                    }),
                  )
                : null,
        // Opened from the Início, so it has a back arrow.
        automaticallyImplyLeading: true,
        actions: [
          if (_inCustomOrderMode)
            TextButton(
              onPressed: _confirmCustomOrder,
              child: Text(
                'OK',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            )
          else ...[
            // What Dinzo says is at each bank.
            if (!_showArchived && DinzoSyncService.apiKey != null)
              IconButton(
                icon: const Icon(Icons.account_balance),
                tooltip: 'Saldo nos bancos',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BankBalancesPage()),
                ),
              ),
            if (!_showArchived)
              IconButton(
                icon: const Icon(Icons.sort),
                onPressed: _showSortOptions,
              ),
            PopupMenuButton<int>(
              icon: const Icon(Icons.more_vert),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(10.0))),
              onSelected: (value) async {
                if (value == 1) {
                  setState(() => _showArchived = !_showArchived);
                }
              },
              itemBuilder: (ctx) => [
                PopupMenuItem<int>(
                  padding: const EdgeInsets.all(20),
                  value: 1,
                  child: Text(
                    _showArchived
                        ? 'Mostrar carteiras ativas'
                        : 'Mostrar carteiras arquivadas',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      body: _wallets == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!_showArchived) ...[
                    // Total balance header (hidden in archived view)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InkWell(
                            onTap: _navigateToWalletPicker,
                            borderRadius: BorderRadius.circular(4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _headerLabel,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.6),
                                      ),
                                ),
                                const SizedBox(width: 2),
                                Icon(
                                  Icons.chevron_right,
                                  size: 16,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.6),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _displayBalanceString(),
                            style: Theme.of(context)
                                .textTheme
                                .headlineLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: getAmountColor(
                                      _displayBalanceTotal(),
                                      brightness),
                                ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(thickness: 0.5),
                  ],
                  if (_showArchived)
                    WalletsList(
                      _walletsByArchiveStatusSorted,
                      onChanged: _loadWallets,
                    )
                  else
                    ..._sections(),
                  if (!_showArchived && _selectedWallets.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: TextButton(
                        onPressed: _clearWalletFilter,
                        child: Text('Mostrar todas as carteiras'),
                      ),
                    ),
                  const SizedBox(height: 75),
                ],
              ),
            ),
      floatingActionButton: (_showArchived || _inCustomOrderMode)
          ? null
          : FloatingActionButton(
              heroTag: null,
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => EditWalletPage(passedWallet: null)),
                );
                await _loadWallets();
              },
              tooltip: 'Nova caixinha',
              child: const Icon(Icons.add),
            ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label, {this.note});

  final String label;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Text.rich(
        TextSpan(
          text: label.toUpperCase(),
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
          ),
          children: [
            if (note != null)
              TextSpan(
                text: '  ·  $note',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  fontWeight: FontWeight.normal,
                  letterSpacing: 0,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
