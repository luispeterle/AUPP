import 'package:flutter/material.dart';
import 'package:aupp/budget_plan/budget-plan.dart';
import 'package:aupp/models/category-type.dart';
import 'package:aupp/models/category.dart';
import 'package:aupp/models/wallet.dart';
import 'package:aupp/records/edit-record-page.dart';
import 'package:aupp/records/components/transfer_wallet_selector.dart';
import 'package:aupp/services/database/database-interface.dart';
import 'package:aupp/services/service-config.dart';

import 'categories-pick-list.dart';

import 'package:aupp/categories/category-sort-option.dart';

class CategoryTabPageView extends StatefulWidget {
  final bool? goToEditMovementPage;
  final int initialTabIndex;

  /// Pre-selected record date carried through the add flow (e.g. from
  /// tapping a day header). Null means "today".
  final DateTime? initialDate;

  CategoryTabPageView({
    this.goToEditMovementPage,
    this.initialTabIndex = 0,
    this.initialDate,
    Key? key,
  }) : super(key: key);

  @override
  CategoryTabPageViewState createState() => CategoryTabPageViewState();
}

class CategoryTabPageViewState extends State<CategoryTabPageView> {
  List<Category?>? _categories;
  CategoryType? categoryType;
  SortOption _selectedSortOption = SortOption.original;
  SortOption _storedDefaultOption = SortOption.original;
  bool _isDefaultOrder = false;
  DatabaseInterface database = ServiceConfig.database;
  bool _searching = false;
  String _query = '';

  /// Budget group the expense list is filtered by (see
  /// [CategoriesPickList.groupFilter]); null shows all.
  String? _groupFilter;
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _closeSearch() {
    _searchController.clear();
    setState(() {
      _searching = false;
      _query = '';
    });
  }

  @override
  void initState() {
    super.initState();
    _fetchCategories().then((_) {
      _initializeSortPreference();
    });
  }

  Future<void> _fetchCategories() async {
    List<Category?> categories = await database.getAllCategories();
    categories = categories.where((element) => !element!.isArchived).toList();
    categories.sort((a, b) => a!.sortOrder!.compareTo(b!.sortOrder!));
    setState(() {
      _categories = categories;
    });
  }

  Future<void> _initializeSortPreference() async {
    _selectedSortOption = SortOption.original;
    String key = 'defaultCategorySortOption';
    if (ServiceConfig.sharedPreferences!.containsKey(key)) {
      final savedSortIndex = ServiceConfig.sharedPreferences?.getInt(key);
      if (savedSortIndex != null) {
        setState(() {
          _storedDefaultOption = SortOption.values[savedSortIndex];
          _selectedSortOption = SortOption.values[savedSortIndex];
        });
        _applySort(_selectedSortOption);
      }
    }
  }

  Future<void> storeOnUserPreferences() async {
    if (_isDefaultOrder) {
      await ServiceConfig.sharedPreferences?.setInt(
        'defaultCategorySortOption',
        _selectedSortOption.index,
      );
      setState(() {
        _storedDefaultOption = _selectedSortOption;
      });
    }
    _isDefaultOrder = false;
  }

  void _applySort(SortOption sortOption) {
    switch (sortOption) {
      case SortOption.lastUsed:
        _sortByLastUsed();
        break;
      case SortOption.mostUsed:
        _sortByMostUsed();
        break;
      case SortOption.original:
        _fetchCategories();
        break;
      case SortOption.alphabetical:
        _sortAlphabetically();
        break;
    }
  }

  void _showSortOptions() {
    SortOption pendingOption = _selectedSortOption;
    String? pendingGroup = _groupFilter;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            Widget groupChip(String? value, String label, {Color? color}) =>
                ChoiceChip(
                  label: Text(label),
                  selected: pendingGroup == value,
                  avatar: color == null
                      ? null
                      : CircleAvatar(radius: 6, backgroundColor: color),
                  showCheckmark: false,
                  onSelected: (_) =>
                      setModalState(() => pendingGroup = value),
                );
            return SafeArea(
              child: SingleChildScrollView(
                child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(
                    left: 16.0,
                    top: 16,
                    right: 16.0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Ordenar por', style: TextStyle(fontSize: 22)),
                      Row(
                        children: [
                          Checkbox(
                            value:
                                _isDefaultOrder ||
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
                Divider(),
                ListTile(
                  leading: Icon(Icons.update),
                  title: Text(
                    'Último uso',
                    style: TextStyle(
                      color: pendingOption == SortOption.lastUsed
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  ),
                  trailing: pendingOption == SortOption.lastUsed
                      ? Icon(
                          Icons.check,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  onTap: () {
                    setModalState(() {
                      pendingOption = SortOption.lastUsed;
                    });
                  },
                ),
                ListTile(
                  leading: Icon(Icons.abc),
                  title: Text(
                    'Nome (alfabético)',
                    style: TextStyle(
                      color: pendingOption == SortOption.alphabetical
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  ),
                  trailing: pendingOption == SortOption.alphabetical
                      ? Icon(
                          Icons.check,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  onTap: () {
                    setModalState(() {
                      pendingOption = SortOption.alphabetical;
                    });
                  },
                ),
                ListTile(
                  leading: Icon(Icons.trending_up),
                  title: Text(
                    'Mais Usados',
                    style: TextStyle(
                      color: pendingOption == SortOption.mostUsed
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  ),
                  trailing: pendingOption == SortOption.mostUsed
                      ? Icon(
                          Icons.check,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  onTap: () {
                    setModalState(() {
                      pendingOption = SortOption.mostUsed;
                    });
                  },
                ),
                ListTile(
                  leading: Icon(Icons.reorder),
                  title: Text(
                    'Ordem original',
                    style: TextStyle(
                      color: pendingOption == SortOption.original
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  ),
                  trailing: pendingOption == SortOption.original
                      ? Icon(
                          Icons.check,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  onTap: () {
                    setModalState(() {
                      pendingOption = SortOption.original;
                    });
                  },
                ),
                Divider(),
                // Filter the expenses by budget group.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Grupo do orçamento (despesas)',
                        style: TextStyle(fontSize: 18),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          groupChip(null, 'Todos'),
                          for (final g in budgetGroups)
                            groupChip(g.id, g.name, color: g.color),
                          groupChip(
                            CategoriesPickList.noGroup,
                            'Sem grupo',
                            color: Theme.of(context).colorScheme.error,
                          ),
                          groupChip(
                            outOfBudget,
                            'Fora',
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _selectedSortOption = pendingOption;
                          _groupFilter = pendingGroup;
                        });
                        _applySort(pendingOption);
                        storeOnUserPreferences();
                        Navigator.pop(context);
                      },
                      child: Text('Aplicar'),
                    ),
                  ),
                ),
              ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _sortByLastUsed() {
    setState(() {
      _selectedSortOption = SortOption.lastUsed;
      _categories?.sort((a, b) {
        final aLastUsed = a?.lastUsed;
        final bLastUsed = b?.lastUsed;

        if (aLastUsed == null && bLastUsed == null)
          return 0; // keep original order
        if (aLastUsed == null) return 1; // 'a' comes after 'b' if 'a' is null
        if (bLastUsed == null) return -1; // 'a' comes before 'b' if 'b' is null

        return bLastUsed.compareTo(
          aLastUsed,
        ); // Regular comparison if both are non-null
      });
    });
  }

  void _sortByMostUsed() {
    setState(() {
      _selectedSortOption = SortOption.mostUsed;
      _categories?.sort((a, b) => b!.recordCount!.compareTo(a!.recordCount!));
    });
  }

  void _sortAlphabetically() {
    setState(() {
      _selectedSortOption = SortOption.alphabetical;
      _categories?.sort((a, b) => a!.name!.compareTo(b!.name!));
    });
  }

  refreshCategories() async {
    await _initializeSortPreference();
    await _fetchCategories();
  }

  void _openTransferEditPage(Wallet origin, Wallet destination) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditRecordPage(
          initialWallet: origin,
          initialDestinationWallet: destination,
          isTransferFlow: true,
          initialDate: widget.initialDate,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showTransferTab = widget.goToEditMovementPage == true;
    return DefaultTabController(
      length: showTransferTab ? 3 : 2,
      initialIndex: widget.initialTabIndex,
      child: Scaffold(
        appBar: AppBar(
          title: _searching
              ? TextField(
                  controller: _searchController,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    hintText: 'Buscar categoria',
                    border: InputBorder.none,
                  ),
                  onChanged: (value) => setState(() => _query = value),
                )
              : Text(
                  widget.goToEditMovementPage == true
                      ? 'Adicionar novo Item'
                      : 'Selecione a categoria',
                ),
          actions: [
            Builder(
              builder: (context) {
                final tabController = DefaultTabController.of(context);
                return AnimatedBuilder(
                  animation: tabController,
                  builder: (context, child) {
                    final isTransferTab =
                        showTransferTab && tabController.index == 2;
                    if (isTransferTab) return const SizedBox.shrink();
                    if (_searching) {
                      return IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: _closeSearch,
                      );
                    }
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.search),
                          onPressed: () => setState(() => _searching = true),
                        ),
                        IconButton(
                          icon: Badge(
                            isLabelVisible: _groupFilter != null,
                            smallSize: 8,
                            child: const Icon(Icons.sort),
                          ),
                          onPressed: _showSortOptions,
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ],
          bottom: TabBar(
            tabs: [
              Semantics(
                identifier: 'expenses-tab',
                child: Tab(text: 'Despesas'.toUpperCase()),
              ),
              Semantics(
                identifier: 'income-tab',
                child: Tab(text: 'Rendas'.toUpperCase()),
              ),
              if (showTransferTab)
                Semantics(
                  identifier: 'transfer-tab',
                  child: Tab(text: 'Transf.'.toUpperCase()),
                ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _categories != null
                ? CategoriesPickList(
                    _categories!
                        .where(
                          (element) =>
                              element!.categoryType == CategoryType.expense,
                        )
                        .toList(),
                    goToEditMovementPage: widget.goToEditMovementPage,
                    initialDate: widget.initialDate,
                    groupFilter: _groupFilter,
                    query: _query,
                  )
                : Container(),
            _categories != null
                ? CategoriesPickList(
                    _categories!
                        .where(
                          (element) =>
                              element!.categoryType == CategoryType.income,
                        )
                        .toList(),
                    goToEditMovementPage: widget.goToEditMovementPage,
                    initialDate: widget.initialDate,
                    groupFilter: _groupFilter,
                    query: _query,
                  )
                : Container(),
            if (showTransferTab)
              TransferWalletSelector(onContinue: _openTransferEditPage),
          ],
        ),
      ),
    );
  }
}
