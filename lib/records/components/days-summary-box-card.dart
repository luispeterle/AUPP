import 'package:flutter/material.dart';
import 'package:aupp/budget_plan/budget-plan.dart';
import 'package:aupp/helpers/records-utility-functions.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/models/wallet.dart';
import 'package:aupp/statistics/statistics-page.dart';

class DaysSummaryBox extends StatefulWidget {
  /// DaysSummaryBox is a card that, given a list of records,
  /// shows the total income, total expenses, total balance resulting from
  /// all the movements in input days.
  ///
  /// The top row shows [walletLabel] and [walletBalanceString], and is tappable
  /// via [onWalletRowTap] to open the wallet filter picker.

  final List<Record?> records;
  final String walletLabel;

  /// Two to five wallets: the row shows "a + b + c =" (each balance in its
  /// wallet's color) instead of [walletLabel]. Empty otherwise.
  final List<Wallet> walletBreakdown;
  final String walletBalanceString;
  final double? walletBalance;

  /// Wallets by id, to tell invested from set-aside money.
  final Map<int, Wallet> walletMap;

  /// The Investido / Guardado / Retirado row (there are wallets
  /// outside the counted ones). Shown even when zero, so it doesn't jump.
  final bool showSetAside;
  final VoidCallback? onWalletRowTap;

  /// Tapping Rendas / Despesas / Saldo: the chart on that tab.
  final void Function(StatisticsTab tab)? onStatTap;

  /// Tapping Investido / Guardado / Retirado: the records behind it.
  final void Function(String label, List<Record> records)? onSetAsideTap;


  DaysSummaryBox(
    this.records, {
    required this.walletLabel,
    this.walletBreakdown = const [],
    required this.walletBalanceString,
    this.walletBalance,
    this.walletMap = const {},
    this.showSetAside = false,
    this.onWalletRowTap,
    this.onStatTap,
    this.onSetAsideTap,
  });

  @override
  DaysSummaryBoxState createState() => DaysSummaryBoxState();
}

class DaysSummaryBoxState extends State<DaysSummaryBox> {
  final _biggerFont = const TextStyle(fontSize: 18.0);
  final _subtitleFont = const TextStyle(fontSize: 13.0);
  final _walletRowFont = const TextStyle(fontSize: 15.0);
  final _smallLabelFont = const TextStyle(fontSize: 12.0);
  final _smallAmountFont =
      const TextStyle(fontSize: 14.0, fontWeight: FontWeight.w500);
  static const _footnoteHeight = 16.0;

  // A transfer counts only when the wallet filter shows one of its sides
  // (see Record.countsTowardTotals).
  Iterable<Record?> get _incomeRecords =>
      widget.records.where((record) => record?.countsAsIncome ?? false);

  Iterable<Record?> get _expenseRecords =>
      widget.records.where((record) => record?.countsAsExpense ?? false);

  Iterable<Record?> get _balanceRecords =>
      widget.records.where((record) => record?.countsTowardTotals ?? false);

  /// Money set aside in / taken back from other wallets, shown under
  /// the row (it moves the balance but is neither income nor expense).
  /// Second row, under income / expenses / balance and in the same columns:
  /// money invested, set aside and taken back ([SetAsideSplit]; invested =
  /// the destination wallet's budget group is Liberdade Financeira).
  Widget _buildSetAsideRow({required Color dimColor}) {
    final plan = BudgetPlan.saved;
    final split = SetAsideSplit(widget.records, (id) {
      final to = widget.walletMap[id];
      return to != null && plan.isInvestmentWallet(to.name);
    });
    Widget cell(String label, List<Record> records) {
      final amount = formatMoney(recordsTotal(records, isAbsValue: true));
      return Expanded(
        child: InkWell(
          onTap: widget.onSetAsideTap == null
              ? null
              : () => widget.onSetAsideTap!(label, records),
          child: Column(
          children: [
            Text(label,
                style: _smallLabelFont.copyWith(color: dimColor),
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(amount,
                style: _smallAmountFont.copyWith(
                    color: records.isEmpty ? dimColor : null),
                overflow: TextOverflow.ellipsis),
          ],
        ),
        ),
      );
    }

    // Same spacing as the dividers of the row above, so columns line up.
    const gap = SizedBox(width: 16);
    return Row(children: [
      cell('Investido', split.invested),
      gap,
      cell('Guardado', split.saved),
      gap,
      cell('Retirado', split.taken),
    ]);
  }

  Widget _buildAmountWidget(Iterable<Record?> records,
      {bool isAbsValue = true,
      Color? color,
      double? precomputed}) {
    final style =
        color != null ? _biggerFont.copyWith(color: color) : _biggerFont;
    final result = precomputed ??
        recordsTotal(records,
            isAbsValue: isAbsValue);
    return Text(formatMoney(result),
        style: style, overflow: TextOverflow.ellipsis);
  }

  Widget _buildStatColumn(String label, Iterable<Record?> records,
      {required StatisticsTab tab,
      bool isAbsValue = true,
      Color? color,
      double? precomputed,
      String? footnote,
      Color? footnoteColor}) {
    return Expanded(
      child: InkWell(
        onTap: widget.onStatTap == null ? null : () => widget.onStatTap!(tab),
        child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(label, style: _subtitleFont, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          _buildAmountWidget(records,
              isAbsValue: isAbsValue,
              color: color,
              precomputed: precomputed),
          // Always reserved, so nothing moves when a footnote shows up.
          SizedBox(
            height: _footnoteHeight,
            child: footnote == null
                ? null
                : Text(footnote,
                    style: _smallLabelFont.copyWith(color: footnoteColor),
                    overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      ),
    );
  }

  /// Each counted wallet as its icon (in the wallet's color) and balance,
  /// in wallet order; the total stays on the right of the row.
  Widget _buildBreakdown(Color dimColor) {
    final wallets = widget.walletBreakdown;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < wallets.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          _walletBadge(wallets[i]),
          const SizedBox(width: 5),
          Text(
            formatMoney(wallets[i].balance ?? 0.0),
            style: _walletRowFont.copyWith(fontSize: 14),
          ),
        ],
      ],
    );
  }

  Widget _walletBadge(Wallet w) {
    final color = w.color ?? Colors.grey;
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: w.iconEmoji != null
          ? Text(w.iconEmoji!, style: const TextStyle(fontSize: 11))
          : Icon(w.icon ?? Icons.account_balance_wallet,
              size: 11, color: Colors.white),
    );
  }

  /// Thin bar with each wallet's share of the total, in the wallet colors.
  /// Only when every balance is positive (a share of a debt means nothing).
  Widget _buildShareBar(BuildContext context) {
    final wallets = widget.walletBreakdown;
    final balances = [for (final w in wallets) w.balance ?? 0.0];
    final total = balances.fold(0.0, (t, b) => t + b);
    if (total <= 0 || balances.any((b) => b < 0)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: SizedBox(
          height: 4,
          child: Row(children: [
            for (var i = 0; i < wallets.length; i++)
              if (balances[i] > 0)
                Expanded(
                  flex: (balances[i] / total * 1000).round().clamp(1, 1000),
                  child: Container(color: wallets[i].color ?? Colors.grey),
                ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final dimColor =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    final balanceResult = recordsTotal(_balanceRecords,
        isAbsValue: false);
    final balanceColor = getAmountColor(balanceResult, brightness);
    final incomeColor = getAmountColor(
        recordsTotal(_incomeRecords),
        brightness);
    // The big number is what the month really paid; below it, when it
    // differs (something was paid with a caixinha), the total of everything
    // spent (purchases at full value; never transfers).
    final realExpenseRecords = realExpenses(widget.records);
    final expenseColor = getAmountColor(
        recordsTotal(realExpenseRecords),
        brightness);
    final expenseTotal = purchaseParts(widget.records).isEmpty
        ? null
        : 'total ${formatMoney(recordsTotal(_expenseRecords).abs())}';
    return Card(
        elevation: 1,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Wallet header row
            ...[
              InkWell(
                onTap: widget.onWalletRowTap,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                  Row(
                    children: [
                      // Full size when it fits; shrinks only when it doesn't.
                      if (widget.walletBreakdown.isNotEmpty) ...[
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: _buildBreakdown(dimColor),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ] else ...[
                        Text(
                          widget.walletLabel,
                          style: _walletRowFont,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Spacer(),
                      ],
                      Text(
                        widget.walletBalanceString,
                        style: (widget.walletBalance != null
                                ? _walletRowFont.copyWith(
                                    color: getAmountColor(
                                        widget.walletBalance!, brightness))
                                : _walletRowFont)
                            .copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.chevron_right, size: 18, color: dimColor),
                    ],
                  ),
                  if (widget.walletBreakdown.isNotEmpty)
                    _buildShareBar(context),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
            ],
            // Income / Expenses / Balance, and under them (same columns)
            // Investido / Guardado / Retirado. Fixed slots: nothing moves.
            // Tapping one opens what is behind it.
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IntrinsicHeight(
                    child: Row(
                      children: <Widget>[
                        _buildStatColumn('Rendas', _incomeRecords,
                            tab: StatisticsTab.income, color: incomeColor),
                        VerticalDivider(endIndent: 4, indent: 4),
                        _buildStatColumn('Despesas', realExpenseRecords,
                            tab: StatisticsTab.expenses,
                            color: expenseColor,
                            footnote: expenseTotal,
                            footnoteColor: dimColor),
                        VerticalDivider(endIndent: 4, indent: 4),
                        _buildStatColumn('Saldo', _balanceRecords,
                            tab: StatisticsTab.balance,
                            isAbsValue: false,
                            color: balanceColor,
                            precomputed: balanceResult),
                      ],
                    ),
                  ),
                  if (widget.showSetAside) ...[
                    const Divider(height: 10, indent: 12, endIndent: 12),
                    const SizedBox(height: 2),
                    _buildSetAsideRow(dimColor: dimColor),
                  ],
                ],
              ),
            ),
          ],
        ));
  }
}
