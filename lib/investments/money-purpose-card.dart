import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:aupp/dinzo/daily-money.dart';
import 'package:aupp/helpers/records-utility-functions.dart';
import 'package:aupp/services/database/sqlite-database.dart';
import 'package:aupp/services/service-config.dart';
import 'package:aupp/services/total-wallets.dart';

import 'investments-cache.dart';

/// What the money in the everyday banks is for, by the wallets: to spend, set
/// aside, waiting to be invested.
class MoneyPurposeCard extends StatefulWidget {
  const MoneyPurposeCard({super.key});

  @override
  State<MoneyPurposeCard> createState() => _MoneyPurposeCardState();
}

class _MoneyPurposeCardState extends State<MoneyPurposeCard> {
  ({double spending, double goals, double toInvest, double? money})? _parts;

  @override
  void initState() {
    super.initState();
    _load();
    SqliteDatabase.dataChangeNotifier.addListener(_load);
  }

  @override
  void dispose() {
    SqliteDatabase.dataChangeNotifier.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final db = ServiceConfig.database;
    final defaultWallet = await db.getDefaultWallet();
    if (defaultWallet == null) return;
    double spending = 0, goals = 0, toInvest = 0;
    for (final w in await db.getWalletsBalanceAsOf(DateTime.now())) {
      final balance = w.balance ?? w.initialAmount;
      if (w.id == defaultWallet.id) {
        spending = balance;
      } else if (w.isArchived) {
        continue;
      } else if (w.isInvestmentReserve) {
        toInvest += balance;
      } else if (TotalWallets.isGoal(w, defaultWallet.id)) {
        goals += balance;
      }
    }
    final snapshot = await InvestmentsCache.load();
    final money = snapshot == null
        ? null
        : snapshot.bankBalance +
              DailyMoney.fixedIncomeIn(snapshot.investments) -
              snapshot.cardDebt;
    if (!mounted) return;
    setState(
      () => _parts = (
        spending: spending,
        goals: goals,
        toInvest: toInvest,
        money: money,
      ),
    );
  }

  static String _money(double v) => getCurrencyValueString(v);

  static String _pct(double v) =>
      '${NumberFormat('0.0', 'pt_BR').format(v)}%';

  @override
  Widget build(BuildContext context) {
    final r = _parts;
    if (r == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final parts = [
      ('Conta corrente', r.spending, const Color(0xFF43A047)),
      ('Caixinhas e reservas', r.goals, const Color(0xFF8E24AA)),
      ('Para investir', r.toInvest, const Color(0xFF1E88E5)),
    ];
    final total = parts.fold<double>(
      0,
      (sum, part) => sum + (part.$2 > 0 ? part.$2 : 0),
    );
    if (total <= 0) return const SizedBox.shrink();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Para que serve o dinheiro', style: theme.textTheme.titleSmall),
            if (r.money != null)
              Text(
                'Bancos do dia a dia − cartão (${_money(r.money!)})',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 22,
                child: Row(
                  children: [
                    for (final (_, value, color) in parts)
                      if (value > 0)
                        Expanded(
                          flex: (value / total * 1000).round().clamp(1, 1000),
                          child: Container(color: color),
                        ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            for (final (label, value, color) in parts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Container(width: 10, height: 10, color: color),
                    const SizedBox(width: 8),
                    Expanded(child: Text(label)),
                    Text('${_money(value)}  ${_pct(value / total * 100)}'),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
