import 'package:flutter/material.dart';
import 'package:aupp/helpers/records-utility-functions.dart';
import 'package:aupp/models/wallet.dart';
import 'package:aupp/statistics/statistics-models.dart';
import 'package:aupp/statistics/statistics-page.dart';

import 'budget-plan-service.dart';
import 'budget-plan.dart';

/// The Orçamento bars of a period ([from]..[to]): the 100%, one bar per
/// group (tap opens the period's statistics of that group), what is outside
/// the budget and the categories/wallets still without a group. Shown in the
/// Início card (current month) and in the Extrato statistics (its interval).
class BudgetPlanGroups extends StatelessWidget {
  final BudgetPlanSnapshot snap;
  final DateTime from;
  final DateTime to;

  /// Called after returning from a group's statistics.
  final VoidCallback? onReturn;

  const BudgetPlanGroups({
    super.key,
    required this.snap,
    required this.from,
    required this.to,
    this.onReturn,
  });

  static String _money(double v) =>
      getCurrencyValueString(v);

  void _openGroup(BuildContext context, BudgetGroup g) {
    final wallets = <int, Wallet>{
      for (final w in snap.wallets)
        if (w.id != null) w.id!: w,
    };
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StatisticsPage(
          from,
          to,
          snap.usage.recordsOf(g.id),
          walletMap: wallets,
          label: g.name,
          groupByType: GroupByType.subcategory,
        ),
      ),
    ).then((_) => onReturn?.call());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = snap.plan;
    final usage = snap.usage;
    final missing = snap.unassignedCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          usage.base > 0
              ? '100% = ${_money(usage.base)}'
                    '${usage.baseIsEstimate ? ' (receita estimada)' : ' de receita'}'
              : 'Sem receita neste período ainda',
          style: theme.textTheme.bodySmall,
        ),
        for (final g in budgetGroups)
          if (plan.percentOf(g.id) > 0) _groupRow(context, g),
        if (usage.outside.abs() >= 0.01)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Fora do orçamento: ${_money(usage.outside)}',
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (missing > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    (missing == 1
                            ? '1 categoria/carteira sem grupo'
                            : '$missing categorias/carteiras sem grupo') +
                        (usage.unassigned.abs() >= 0.01
                            ? ' · ${_money(usage.unassigned)} fora da contabilização'
                            : ''),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _groupRow(BuildContext context, BudgetGroup g) {
    final theme = Theme.of(context);
    final usage = snap.usage;
    final used = usage.usedOf(g.id);
    final allowance = usage.allowanceOf(snap.plan, g.id);
    final ratio = usage.ratioOf(snap.plan, g.id);
    final pct = (ratio * 100).round();
    final overLimit = !g.isGoal && allowance > 0 && used > allowance;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _openGroup(context, g),
      child: Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(g.icon, size: 16, color: g.color),
                const SizedBox(width: 6),
                Expanded(child: Text(g.name, style: theme.textTheme.bodyLarge)),
                Text(
                  '$pct%',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: overLimit ? theme.colorScheme.error : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ratio.clamp(0.0, 1.0),
                minHeight: 8,
                color: g.color,
                backgroundColor: g.color.withValues(alpha: 0.18),
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${_money(used)} / ${_money(allowance)}',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
