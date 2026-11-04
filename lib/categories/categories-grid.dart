import 'package:flutter/material.dart';
import 'package:aupp/models/category.dart';
import 'package:aupp/records/edit-record-page.dart';
import 'package:reorderable_grid/reorderable_grid.dart';

import '../components/category_icon_circle.dart';

class CategoriesGrid extends StatefulWidget {
  final List<Category?> categories;
  final bool? goToEditMovementPage;
  final bool enableManualSorting;
  final Function(List<Category?>) onChangeOrder;
  final bool alignToBottom;

  /// Search text typed in the page's app bar. Empty shows only top-level
  /// categories; otherwise every matching category (parents and children).
  final String query;

  /// Pre-selected record date forwarded to the edit page. Null means "today".
  final DateTime? initialDate;

  CategoriesGrid(
    this.categories, {
    this.goToEditMovementPage,
    required this.enableManualSorting,
    required this.onChangeOrder,
    this.alignToBottom = false,
    this.query = '',
    this.initialDate,
  });

  @override
  CategoriesGridState createState() => CategoriesGridState();
}

class CategoriesGridState extends State<CategoriesGrid> {
  List<Category?> orderedCategories = [];
  bool enableManualSorting = false;
  late ScrollController _scrollController;

  /// Parent whose subcategories are being shown (parent first, then its
  /// children). Tapping the parent again picks it.
  Category? _expanded;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    enableManualSorting = widget.enableManualSorting;
    orderedCategories = List.from(
      widget.categories,
    ); // Initialize with a copy of the categories list
  }

  @override
  void didUpdateWidget(covariant CategoriesGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Check if the categories list has been updated and update orderedCategories accordingly
    if (oldWidget.categories != widget.categories) {
      setState(() {
        orderedCategories = List.from(widget.categories);
        enableManualSorting = widget.enableManualSorting;
        if (_expanded != null &&
            !orderedCategories.any((c) => c?.name == _expanded!.name)) {
          _expanded = null;
        }
      });
    }
    if (oldWidget.query != widget.query) _expanded = null;
  }

  static const _accents = {
    'á': 'a',
    'à': 'a',
    'â': 'a',
    'ã': 'a',
    'ä': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ï': 'i',
    'ó': 'o',
    'ò': 'o',
    'ô': 'o',
    'õ': 'o',
    'ö': 'o',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ç': 'c',
    'ñ': 'n',
  };

  static String _fold(String s) =>
      s.toLowerCase().split('').map((ch) => _accents[ch] ?? ch).join();

  bool _isTopLevel(Category c) =>
      c.parentName == null ||
      !orderedCategories.any((p) => p?.name == c.parentName);

  List<Category> _childrenOf(Category parent) => orderedCategories
      .whereType<Category>()
      .where((c) => c.parentName == parent.name)
      .toList();

  bool get _isSearching => widget.query.trim().isNotEmpty;

  /// Top-level categories only, unless searching or a parent is expanded.
  List<Category> get _visibleCategories {
    if (_expanded != null) return [_expanded!, ..._childrenOf(_expanded!)];
    final all = orderedCategories.whereType<Category>();
    if (_isSearching) {
      final q = _fold(widget.query.trim());
      return all.where((c) => _fold(c.name ?? '').contains(q)).toList();
    }
    return all.where(_isTopLevel).toList();
  }

  void _setExpanded(Category? parent) {
    setState(() => _expanded = parent);
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  void _onCategoryTap(Category category) {
    if (_expanded == null && _childrenOf(category).isNotEmpty) {
      _setExpanded(category);
      return;
    }
    if (widget.goToEditMovementPage != null && widget.goToEditMovementPage!) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => EditRecordPage(
            passedCategory: category,
            initialDate: widget.initialDate,
          ),
        ),
      );
    } else {
      Navigator.pop(context, category);
    }
  }

  /// Builds a single category item
  Widget _buildCategory(Category category) {
    return Container(
      child: Center(
        child: InkWell(
          onTap: () => _onCategoryTap(category),
          child: Container(
            child: Column(
              children: [
                CategoryIconCircle(
                  iconEmoji: category.iconEmoji,
                  iconDataFromDefaultIconSet: category.icon,
                  backgroundColor: category.color,
                ),
                Flexible(
                  child: Container(
                    margin: EdgeInsets.fromLTRB(0, 10, 0, 0),
                    child: Text(
                      category.name!,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Builds the grid of categories with reordering capability
  Widget _buildCategories(BuildContext context) {
    var size = MediaQuery.of(context).size;
    final double itemHeight = 250;
    final double itemWidth = size.width / 2;

    final visible = _visibleCategories;
    final canReorder =
        enableManualSorting && _expanded == null && !_isSearching;

    final generatedChildren = List.generate(visible.length, (index) {
      return Container(
        key: ValueKey(index.toString()), // Ensure each item has a unique key
        child: _buildCategory(visible[index]),
      );
    });

    final grid = ReorderableGridView.extent(
      controller: _scrollController,
      onReorder: (int oldIndex, int newIndex) async {
        // Only top-level categories are reordered; children keep their order.
        final reordered = List<Category>.from(visible);
        reordered.insert(newIndex, reordered.removeAt(oldIndex));
        setState(() {
          orderedCategories = [
            ...reordered,
            ...orderedCategories.where((c) => !reordered.contains(c)),
          ];
        });
        await widget.onChangeOrder(reordered);
      },
      itemDragEnable: (index) {
        return canReorder;
      },
      childAspectRatio: (itemWidth / itemHeight),
      padding: EdgeInsets.only(top: 10),
      crossAxisSpacing: 5.0,
      mainAxisSpacing: 5.0,
      maxCrossAxisExtent: size.width / 4,
      shrinkWrap: widget.alignToBottom,
      children: generatedChildren,
    );

    if (!widget.alignToBottom) {
      return grid;
    }

    // When bottom-aligned, anchor the grid to the bottom so thumb-reachable.
    // shrinkWrap lets the grid take only the space it needs, and the Column
    // pushes it to the bottom of the available area. The outer scroll view
    // still allows scrolling when there are many categories.
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [grid],
            ),
          ),
        );
      },
    );
  }

  Widget _buildExpandedHeader() {
    return InkWell(
      onTap: () => _setExpanded(null),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            const Icon(Icons.arrow_back, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _expanded!.name!,
                style: Theme.of(context).textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoResults() {
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Text(
        'Nenhuma categoria encontrada',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 16,
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_expanded == null && _isSearching && _visibleCategories.isEmpty) {
      return _buildNoResults();
    }
    if (_expanded == null) return _buildCategories(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _setExpanded(null);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildExpandedHeader(),
          Expanded(child: _buildCategories(context)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.all(15),
      child: widget.categories.isEmpty
          ? Column(
              children: <Widget>[
                Image.asset('assets/images/no_entry_2.png', width: 200),
                Text(
                  'Nenhuma categoria ainda.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22.0),
                ),
              ],
            )
          : _buildBody(context),
    );
  }
}
