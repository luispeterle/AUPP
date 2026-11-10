import 'package:community_charts_flutter/community_charts_flutter.dart'
    as charts;
import 'package:flutter/material.dart';
import 'package:aupp/components/category_icon_circle.dart';
import 'package:aupp/helpers/records-utility-functions.dart';
import 'package:aupp/models/category-type.dart';
import 'package:aupp/models/category.dart';
import 'package:aupp/models/wallet.dart';

import 'budget-plan-service.dart';
import 'budget-plan.dart';

/// Settings → Orçamento: how the month's income is split
/// between the six groups and which categories/wallets feed each one.
class BudgetPlanPage extends StatefulWidget {
  const BudgetPlanPage({super.key});

  @override
  State<BudgetPlanPage> createState() => _BudgetPlanPageState();
}

/// Filter of the category list: everything, only unassigned, or a group.
const String _all = '*';
const String _none = '-';

class _BudgetPlanPageState extends State<BudgetPlanPage> {
  BudgetPlanSnapshot? _snap;
  late BudgetPlan _plan;
  bool _dirty = false;
  String _filter = _all;
  final _categoriesKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final snap = await BudgetPlanService.load();
    if (!mounted) return;
    setState(() {
      _snap = snap;
      _plan = snap.plan.copy();
      _dirty = false;
      if (snap.unassignedCount > 0) _filter = _none;
    });
  }

  String _money(double v) => getCurrencyValueString(v);

  void _change(VoidCallback fn) => setState(() {
    fn();
    _dirty = true;
  });

  Future<void> _save() async {
    await BudgetPlanService.savePlan(_plan);
    if (!mounted) return;
    setState(() => _dirty = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Orçamento salvo')));
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Descartar alterações?'),
        content: const Text('O que você mudou nesta tela ainda não foi salvo.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continuar editando'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snap;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          setState(() => _dirty = false);
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Orçamento'),
          actions: [
            IconButton(
              icon: const Icon(Icons.restart_alt),
              tooltip: 'Voltar aos percentuais padrão',
              onPressed: snap == null
                  ? null
                  : () => _change(() {
                      for (final g in budgetGroups) {
                        _plan.percents[g.id] = g.defaultPercent;
                      }
                    }),
            ),
          ],
        ),
        body: snap == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  _buildAlert(),
                  _buildDonut(),
                  _buildSliders(),
                  _buildCategories(),
                  _buildIncome(),
                  _buildWallets(),
                ],
              ),
        bottomNavigationBar: snap == null
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: FilledButton(
                    onPressed: _dirty && _plan.totalPercent == 100
                        ? _save
                        : null,
                    child: Text(
                      _plan.totalPercent == 100
                          ? (_dirty ? 'Salvar' : 'Salvo')
                          : 'A soma precisa dar 100% (está em '
                                '${_plan.totalPercent}%)',
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _card({required String title, String? subtitle, required Widget child,
      Key? key}) {
    final theme = Theme.of(context);
    return Card(
      key: key,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ alert

  Widget _buildAlert() {
    final snap = _snap!;
    final categories = _plan.unassignedCategories(snap.categories);
    final wallets = _plan.unassignedWallets(snap.wallets, snap.defaultWalletId);
    if (categories.isEmpty && wallets.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final names = [
      ...categories.map((c) => c.name!),
      ...wallets.map((w) => 'carteira ${w.name}'),
    ];
    final count = names.length;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      color: theme.colorScheme.errorContainer,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          setState(() => _filter = _none);
          final target = _categoriesKey.currentContext;
          if (target != null) {
            Scrollable.ensureVisible(
              target,
              duration: const Duration(milliseconds: 300),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: theme.colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      count == 1
                          ? '1 item fora da contabilização'
                          : '$count itens fora da contabilização',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Sem grupo: ${names.take(6).join(', ')}'
                      '${count > 6 ? ' e mais ${count - 6}' : ''}. '
                      'Gastos neles não entram em nenhum grupo. '
                      'Toque para escolher.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ donut

  Widget _buildDonut() {
    final theme = Theme.of(context);
    final total = _plan.totalPercent;
    final slices = [
      for (final g in budgetGroups)
        if (_plan.percentOf(g.id) > 0) g,
    ];
    final usage = _snap!.usage;
    return _card(
      title: 'Divisão da receita',
      subtitle: usage.base > 0
          ? 'Receita do mês: ${_money(usage.base)}'
                '${usage.baseIsEstimate ? ' (estimada)' : ''}'
          : 'Sem receita neste mês ainda',
      child: Column(
        children: [
          SizedBox(
            height: 200,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (slices.isNotEmpty)
                  charts.PieChart<String>(
                    [
                      charts.Series<BudgetGroup, String>(
                        id: 'plan',
                        data: slices,
                        domainFn: (g, _) => g.name,
                        measureFn: (g, _) => _plan.percentOf(g.id),
                        colorFn: (g, _) =>
                            charts.ColorUtil.fromDartColor(g.color),
                      ),
                    ],
                    animate: false,
                    defaultRenderer: charts.ArcRendererConfig(arcWidth: 28),
                  ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$total%',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: total == 100 ? null : theme.colorScheme.error,
                      ),
                    ),
                    Text('Total', style: theme.textTheme.bodySmall),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              for (final g in budgetGroups)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(radius: 6, backgroundColor: g.color),
                    const SizedBox(width: 6),
                    Text(g.name, style: theme.textTheme.bodySmall),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- sliders

  Widget _buildSliders() {
    final theme = Theme.of(context);
    final base = _snap!.usage.base;
    final total = _plan.totalPercent;
    return _card(
      title: 'Quanto vai para cada grupo',
      subtitle: total == 100
          ? 'Somando 100% da receita do mês'
          : total < 100
          ? 'Faltam ${100 - total}% para fechar 100%'
          : 'Passou ${total - 100}% de 100%',
      child: Column(
        children: [
          for (final g in budgetGroups) ...[
            Row(
              children: [
                Icon(g.icon, size: 18, color: g.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    g.name,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${_plan.percentOf(g.id)}%',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: g.color,
                thumbColor: g.color,
                inactiveTrackColor: g.color.withValues(alpha: 0.18),
                overlayColor: g.color.withValues(alpha: 0.12),
              ),
              child: Slider(
                value: _plan.percentOf(g.id).toDouble(),
                min: 0,
                max: 100,
                divisions: 100,
                label: '${_plan.percentOf(g.id)}%',
                onChanged: (v) =>
                    _change(() => _plan.percents[g.id] = v.round()),
              ),
            ),
            if (base > 0)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '≈ ${_money(base * _plan.percentOf(g.id) / 100)} '
                    'por mês',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------- categories

  /// Expense categories in tree order: each parent followed by its children.
  List<(Category, bool)> _categoryTree() {
    final expense = [
      for (final c in _snap!.categories)
        if (c.categoryType == CategoryType.expense &&
            c.name != null &&
            (!c.isArchived || _plan.categories.containsKey(c.name)))
          c,
    ];
    final names = {for (final c in expense) c.name!};
    int byName(Category a, Category b) =>
        a.name!.toLowerCase().compareTo(b.name!.toLowerCase());
    final roots = expense
        .where((c) => c.parentName == null || !names.contains(c.parentName))
        .toList()
      ..sort(byName);
    return [
      for (final root in roots) ...[
        (root, false),
        for (final child
            in expense.where((c) => c.parentName == root.name).toList()
              ..sort(byName))
          (child, true),
      ],
    ];
  }

  bool _matchesFilter(String? group) {
    if (_filter == _all) return true;
    if (_filter == _none) return group == null;
    return group == _filter;
  }

  Widget _buildCategories() {
    final theme = Theme.of(context);
    final tree = _categoryTree();
    final counts = <String, int>{};
    for (final (c, _) in tree) {
      final g = _plan.groupOfCategory(c.name) ?? _none;
      counts[g] = (counts[g] ?? 0) + 1;
    }
    // A child that matches keeps its parent visible as a header.
    final matching = {
      for (final (c, _) in tree)
        if (_matchesFilter(_plan.groupOfCategory(c.name))) c.name,
    };
    final visible = [
      for (final (c, isChild) in tree)
        if (matching.contains(c.name) ||
            (!isChild &&
                tree.any(
                  (t) =>
                      t.$2 &&
                      t.$1.parentName == c.name &&
                      matching.contains(t.$1.name),
                )))
          (c, isChild),
    ];
    Widget filterChip(String value, String label, {Color? color}) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: _filter == value,
        avatar: color == null
            ? null
            : CircleAvatar(radius: 6, backgroundColor: color),
        showCheckmark: false,
        onSelected: (_) => setState(() => _filter = value),
      ),
    );
    return _card(
      key: _categoriesKey,
      title: 'Categorias',
      subtitle: 'Gastos das carteiras do Total entram no grupo da sua '
          'categoria. Toque para trocar.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                filterChip(_all, 'Todas (${tree.length})'),
                if ((counts[_none] ?? 0) > 0)
                  filterChip(
                    _none,
                    'Sem grupo (${counts[_none]})',
                    color: theme.colorScheme.error,
                  ),
                for (final g in budgetGroups)
                  filterChip(
                    g.id,
                    '${g.name} (${counts[g.id] ?? 0})',
                    color: g.color,
                  ),
                filterChip(
                  outOfBudget,
                  'Fora (${counts[outOfBudget] ?? 0})',
                  color: theme.colorScheme.outline,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                _filter == _none
                    ? 'Todas as categorias têm grupo.'
                    : 'Nenhuma categoria aqui.',
                textAlign: TextAlign.center,
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
                style: isChild ? null : const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
              trailing: BudgetGroupLabel(_plan.groupOfCategory(c.name)),
              onTap: () => _pickCategoryGroup(c, tree),
            ),
        ],
      ),
    );
  }

  Future<void> _pickCategoryGroup(
    Category category,
    List<(Category, bool)> tree,
  ) async {
    final children = [
      for (final (c, isChild) in tree)
        if (isChild && c.parentName == category.name) c,
    ];
    final picked = await _pickGroup(
      title: category.name!,
      current: _plan.groupOfCategory(category.name),
      childrenCount: children.length,
    );
    if (picked == null) return;
    _change(() {
      _plan.categories[category.name!] = picked.group;
      if (picked.applyToChildren) {
        for (final c in children) {
          _plan.categories[c.name!] = picked.group;
        }
      }
    });
  }

  // ----------------------------------------------------------------- income

  /// Income categories and whether each is part of the 100% (a loan is
  /// money in, but not the month's income).
  Widget _buildIncome() {
    final income = [
      for (final c in _snap!.categories)
        if (c.categoryType == CategoryType.income &&
            c.name != null &&
            (!c.isArchived || _plan.incomeOut.contains(c.name)))
          c,
    ]..sort((a, b) => a.name!.toLowerCase().compareTo(b.name!.toLowerCase()));
    if (income.isEmpty) return const SizedBox.shrink();
    return _card(
      title: 'Receitas',
      subtitle: 'Desligue o que entra mas não é renda do mês (ex. empréstimo): '
          'continua no Extrato, mas fica fora dos 100%.',
      child: Column(
        children: [
          for (final c in income)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(c.name!),
              subtitle: c.parentName == null ? null : Text(c.parentName!),
              value: _plan.countsAsIncome(c.name),
              onChanged: (on) => _change(
                () => on
                    ? _plan.incomeOut.remove(c.name)
                    : _plan.incomeOut.add(c.name!),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- wallets

  Widget _buildWallets() {
    final snap = _snap!;
    final wallets = [
      for (final w in snap.wallets)
        if (!BudgetPlan.isBaseWallet(w, snap.defaultWalletId) &&
            (!w.isArchived ||
                _plan.wallets.containsKey(BudgetPlan.walletKey(w.name))))
          w,
    ];
    if (wallets.isEmpty) return const SizedBox.shrink();
    return _card(
      title: 'Carteiras',
      subtitle: 'Transferências da Conta corrente para a carteira contam no '
          'grupo dela; tirar dinheiro de volta desconta.',
      child: Column(
        children: [
          for (final w in wallets)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const CircleAvatar(
                radius: 17,
                child: Icon(Icons.account_balance_wallet, size: 18),
              ),
              title: Text(w.name),
              trailing: BudgetGroupLabel(_plan.groupOfWallet(w.name)),
              onTap: () => _pickWalletGroup(w),
            ),
        ],
      ),
    );
  }

  Future<void> _pickWalletGroup(Wallet wallet) async {
    final picked = await _pickGroup(
      title: wallet.name,
      current: _plan.groupOfWallet(wallet.name),
    );
    if (picked == null) return;
    _change(
      () => _plan.wallets[BudgetPlan.walletKey(wallet.name)] = picked.group,
    );
  }

  // ----------------------------------------------------------------- picker

  Future<({String group, bool applyToChildren})?> _pickGroup({
    required String title,
    required String? current,
    int childrenCount = 0,
  }) {
    var applyToChildren = childrenCount > 0;
    return showModalBottomSheet<({String group, bool applyToChildren})>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          Widget option(String id, String name, Widget leading) => ListTile(
            leading: leading,
            title: Text(name),
            trailing: current == id ? const Icon(Icons.check) : null,
            onTap: () => Navigator.pop(context, (
              group: id,
              applyToChildren: applyToChildren,
            )),
          );
          return SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (childrenCount > 0)
                    SwitchListTile(
                      title: Text(
                        'Aplicar também às $childrenCount subcategorias',
                      ),
                      value: applyToChildren,
                      onChanged: (v) => setSheet(() => applyToChildren = v),
                    ),
                  for (final g in budgetGroups)
                    option(
                      g.id,
                      g.name,
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: g.color,
                        child: Icon(g.icon, size: 16, color: Colors.white),
                      ),
                    ),
                  option(
                    outOfBudget,
                    'Fora do orçamento (não contar)',
                    const CircleAvatar(
                      radius: 16,
                      child: Icon(Icons.block, size: 16),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Small coloured label with the group a category/wallet belongs to.
/// Pill with a budget group's name and color ("Sem grupo" in red, "Fora").
class BudgetGroupLabel extends StatelessWidget {
  final String? group;

  const BudgetGroupLabel(this.group);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = budgetGroupById(group);
    final Color color;
    final String label;
    if (g != null) {
      color = g.color;
      label = g.name;
    } else if (group == outOfBudget) {
      color = theme.colorScheme.outline;
      label = 'Fora';
    } else {
      color = theme.colorScheme.error;
      label = 'Sem grupo';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: g == null && group != outOfBudget ? color : null,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
