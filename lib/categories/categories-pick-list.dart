import 'package:flutter/material.dart';
import 'package:aupp/budget_plan/budget-plan-page.dart';
import 'package:aupp/budget_plan/budget-plan.dart';
import 'package:aupp/models/category-type.dart';
import 'package:aupp/models/category.dart';
import 'package:aupp/records/edit-record-page.dart';
import 'package:aupp/services/service-config.dart';
import 'package:aupp/settings/constants/preferences-keys.dart';

import '../components/category_icon_circle.dart';

/// Category picker laid out like the Orçamento's category list: parents in
/// bold with their subcategories indented below, the budget group pill on
/// the right (expenses). Searching keeps the parent of a matching
/// subcategory as its header ("inss" shows Impostos › INSS).
class CategoriesPickList extends StatefulWidget {
  /// [groupFilter] value for categories without a budget group.
  static const noGroup = '_none';

  /// Already sorted (the page's sort option); the tree keeps this order.
  final List<Category?> categories;
  final bool? goToEditMovementPage;
  final bool alignToBottom;
  final String query;

  /// Budget group id to show (expenses only; [noGroup], [outOfBudget]);
  /// null shows all.
  final String? groupFilter;

  /// Pre-selected record date forwarded to the edit page. Null means "today".
  final DateTime? initialDate;

  const CategoriesPickList(
    this.categories, {
    super.key,
    this.goToEditMovementPage,
    this.alignToBottom = false,
    this.query = '',
    this.groupFilter,
    this.initialDate,
  });

  @override
  State<CategoriesPickList> createState() => _CategoriesPickListState();
}

class _CategoriesPickListState extends State<CategoriesPickList> {
  static const _accents = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', //
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', //
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', //
    'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', //
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', //
    'ç': 'c', 'ñ': 'n',
  };

  static String _fold(String s) =>
      s.toLowerCase().split('').map((ch) => _accents[ch] ?? ch).join();

  bool get _isExpense =>
      widget.categories.any((c) => c?.categoryType == CategoryType.expense);

  /// Parents in the given order, each followed by its children.
  List<(Category, bool)> _tree() {
    final all = widget.categories.whereType<Category>().toList();
    final names = {for (final c in all) c.name};
    return [
      for (final root in all.where(
          (c) => c.parentName == null || !names.contains(c.parentName))) ...[
        (root, false),
        for (final child in all.where((c) => c.parentName == root.name))
          (child, true),
      ],
    ];
  }

  void _pick(Category category) {
    if (widget.goToEditMovementPage == true) {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.categories.isEmpty) {
      return Column(
        children: <Widget>[
          const SizedBox(height: 15),
          Image.asset('assets/images/no_entry_2.png', width: 200),
          Text(
            'Nenhuma categoria ainda.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22.0),
          ),
        ],
      );
    }

    final plan = _isExpense
        ? BudgetPlan.decode(ServiceConfig.sharedPreferences
            ?.getString(PreferencesKeys.budgetPlan))
        : null;
    String groupOf(Category c) =>
        plan?.groupOfCategory(c.name) ?? CategoriesPickList.noGroup;
    final filter = plan == null ? null : widget.groupFilter;
    bool inGroup(Category c) => filter == null || groupOf(c) == filter;

    final tree = _tree();
    final q = _fold(widget.query.trim());
    bool matches(Category c) =>
        inGroup(c) && (q.isEmpty || _fold(c.name ?? '').contains(q));
    // A match keeps its parent visible as a header; a matching parent also
    // shows its subcategories when searching.
    final matching = {
      for (final (c, isChild) in tree)
        if (matches(c) ||
            (isChild &&
                q.isNotEmpty &&
                inGroup(c) &&
                tree.any((t) =>
                    !t.$2 && t.$1.name == c.parentName && matches(t.$1))))
          c.name,
    };
    final visible = [
      for (final (c, isChild) in tree)
        if (matching.contains(c.name) ||
            (!isChild &&
                tree.any((t) =>
                    t.$2 &&
                    t.$1.parentName == c.name &&
                    matching.contains(t.$1.name))))
          (c, isChild),
    ];

    final rows = <Widget>[
      if (visible.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 40),
          child: Text(
            'Nenhuma categoria encontrada',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: theme.colorScheme.outline),
          ),
        ),
      for (final (c, isChild) in visible)
        ListTile(
          contentPadding: EdgeInsets.only(left: isChild ? 32 : 0),
          dense: true,
          leading: CategoryIconCircle(
            iconEmoji: c.iconEmoji,
            iconDataFromDefaultIconSet: c.icon,
            backgroundColor: c.color,
            circleSize: isChild ? 28 : 34,
            mainIconSize: isChild ? 14 : 17,
          ),
          title: Text(
            c.name!,
            style:
                isChild ? null : const TextStyle(fontWeight: FontWeight.w600),
          ),
          trailing: plan == null
              ? null
              : BudgetGroupLabel(plan.groupOfCategory(c.name)),
          onTap: () => _pick(c),
        ),
    ];

    const padding = EdgeInsets.fromLTRB(16, 12, 16, 24);
    if (!widget.alignToBottom) {
      return ListView(padding: padding, children: rows);
    }
    // Anchored to the bottom (thumb-reachable), still scrollable.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: padding,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 36),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rows,
          ),
        ),
      ),
    );
  }
}
