import 'package:aupp/accounts/money-accounts.dart';
import 'package:aupp/dinzo/dinzo-sync-service.dart';
import 'package:aupp/dinzo/estimate-link.dart';
import 'package:aupp/models/category-type.dart';
import 'package:aupp/models/category.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/models/wallet.dart';
import 'package:aupp/services/logger.dart';
import 'package:aupp/services/recurrent-record-service.dart';
import 'package:aupp/services/service-config.dart';
import 'package:aupp/settings/constants/preferences-keys.dart';

import 'budget-plan.dart';

/// Everything the Orçamento screens show for a period (the current month on
/// the Início).
class BudgetPlanSnapshot {
  final BudgetPlan plan;
  final BudgetPlanUsage usage;
  final List<Category> categories;
  final List<Wallet> wallets;
  final int? defaultWalletId;

  BudgetPlanSnapshot({
    required this.plan,
    required this.usage,
    required this.categories,
    required this.wallets,
    required this.defaultWalletId,
  });

  List<Category> get unassignedCategories =>
      plan.unassignedCategories(categories);

  List<Wallet> get unassignedWallets =>
      plan.unassignedWallets(wallets, defaultWalletId);

  int get unassignedCount =>
      unassignedCategories.length + unassignedWallets.length;
}

class BudgetPlanService {
  static final _logger = Logger.withClass(BudgetPlanService);

  /// The saved plan. Categories and wallets not assigned yet get their
  /// default group when there is one (e.g. "Diarista" → Conforto) and the
  /// plan is saved; anything without a known default stays unassigned and
  /// raises the alert.
  static Future<BudgetPlan> loadPlan({
    required List<Category> categories,
    required List<Wallet> wallets,
    required int? defaultWalletId,
  }) async {
    final prefs = ServiceConfig.sharedPreferences;
    final saved = BudgetPlan.decode(prefs?.getString(PreferencesKeys.budgetPlan));
    final plan = saved ?? BudgetPlan();
    if (plan.assignDefaults(categories, wallets, defaultWalletId) ||
        saved == null) {
      await savePlan(plan);
      _logger.info(
        'Budget plan defaults applied: ${plan.categories.length} '
        'categories, ${plan.wallets.length} wallets',
      );
    }
    return plan;
  }

  static Future<void> savePlan(BudgetPlan plan) async {
    await ServiceConfig.sharedPreferences?.setString(
      PreferencesKeys.budgetPlan,
      plan.encode(),
    );
  }

  static Future<BudgetPlanSnapshot> load({DateTime? now}) {
    now ??= DateTime.now();
    return loadRange(
      from: DateTime(now.year, now.month, 1),
      to: DateTime(now.year, now.month + 1, 1)
          .subtract(const Duration(milliseconds: 1)),
      now: now,
    );
  }

  /// The plan over [from]..[to] (e.g. the Extrato's interval), month by
  /// month: past months use the income received; the current one and those
  /// ahead also the estimates as the 100%, and upcoming occurrences of every
  /// recurrence count before their day comes.
  static Future<BudgetPlanSnapshot> loadRange({
    required DateTime from,
    required DateTime to,
    DateTime? now,
  }) async {
    now ??= DateTime.now();
    final db = ServiceConfig.database;
    final categories = (await db.getAllCategories()).whereType<Category>()
        .toList();
    final wallets = await db.getAllWallets();
    final defaultWallet = await db.getDefaultWallet();
    final plan = await loadPlan(
      categories: categories,
      wallets: wallets,
      defaultWalletId: defaultWallet?.id,
    );
    final walletsById = {
      for (final w in wallets)
        if (w.id != null) w.id!: w,
    };
    final until = DateTime(to.year, to.month + 1, 1);
    final estimates = await _recurrentOccurrences(until, estimates: true);
    final stored = MoneyAccounts.withoutTransfers(await db.getAllRecords())
        .whereType<Record>();
    final open = EstimateLink.withoutLinked(
      estimates,
      await EstimateLink.linkedOccurrences(),
    );
    EstimateLink.markMatches([...stored, ...open]);
    final records = [
      ...stored,
      // Passed occurrences are stored (or, for estimates, only the forecast
      // of real records); the upcoming ones count before their day.
      for (final r in [
        // Linked or paired = the real record already counts.
        ...open.where((r) => r.estimateMatch == null),
        ...await _recurrentOccurrences(until, estimates: false),
      ])
        if (r.dateTime.isAfter(now)) r..isFutureRecord = true,
    ];
    final months = <BudgetPlanUsage>[];
    final thisMonth = DateTime(now.year, now.month);
    for (var month = DateTime(from.year, from.month);
        !month.isAfter(to);
        month = DateTime(month.year, month.month + 1)) {
      months.add(BudgetPlanUsage.compute(
        plan: plan,
        records: records,
        walletsById: walletsById,
        defaultWalletId: defaultWallet?.id,
        month: month,
        now: now,
        from: from,
        to: to,
        estimatedIncome: month.isBefore(thisMonth)
            ? 0
            : _estimatedIncome(
                plan, estimates, month, walletsById, defaultWallet?.id),
      ));
    }
    final usage = BudgetPlanUsage.combine(months);
    return BudgetPlanSnapshot(
      plan: plan,
      usage: usage,
      categories: categories,
      wallets: wallets,
      defaultWalletId: defaultWallet?.id,
    );
  }

  /// Occurrences of the recurrences before [until]. Estimates (tagged
  /// "Estimativa") from the pattern start, past ones included: they drop
  /// those once their day comes. The others from their last stored one.
  static Future<List<Record>> _recurrentOccurrences(
    DateTime until, {
    required bool estimates,
  }) async {
    try {
      final patterns = await ServiceConfig.database
          .getRecurrentRecordPatterns();
      final service = RecurrentRecordService();
      final end = until.subtract(const Duration(milliseconds: 1)).toUtc();
      final result = <Record>[];
      for (final p in patterns) {
        if (p.tags.contains(DinzoSyncService.estimateTag) != estimates) {
          continue;
        }
        if (estimates) p.utcLastUpdate = null; // fresh copy, not saved
        result.addAll(service.generateRecurrentRecordsFromDateTime(p, end));
      }
      return result;
    } catch (e, st) {
      _logger.handle(e, st, 'Failed to generate recurrent occurrences');
      return [];
    }
  }

  /// Income the [estimates] expect in [month] in the base wallets, counting
  /// the occurrences already past too.
  static double _estimatedIncome(
    BudgetPlan plan,
    List<Record> estimates,
    DateTime month,
    Map<int, Wallet> walletsById,
    int? defaultWalletId,
  ) {
    var total = 0.0;
    for (final r in estimates) {
      final d = r.dateTime;
      if (d.year != month.year || d.month != month.month) continue;
      if (r.tags.contains(outOfBudgetTag)) continue;
      if (r.transferWalletId != null) continue;
      if (r.category?.categoryType != CategoryType.income) continue;
      if (!plan.countsAsIncome(r.category?.name)) continue;
      final wallet = r.walletId == null ? null : walletsById[r.walletId];
      if (r.walletId != null &&
          (wallet == null ||
              !BudgetPlan.isBaseWallet(wallet, defaultWalletId))) {
        continue;
      }
      total += (r.value ?? 0).abs();
    }
    return total;
  }
}
