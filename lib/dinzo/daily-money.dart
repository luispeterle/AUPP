import 'dart:convert';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:aupp/components/known-tags.dart';
import 'package:aupp/investments/investments-analytics.dart';
import 'package:aupp/investments/investments-cache.dart';
import 'package:aupp/models/category.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/models/wallet.dart';
import 'package:aupp/services/automatic-writes.dart';
import 'package:aupp/services/database/money-model-migration.dart';
import 'package:aupp/services/database/sqlite-database.dart';
import 'package:aupp/services/logger.dart';
import 'package:aupp/services/service-config.dart';
import 'package:aupp/services/total-wallets.dart';
import 'package:aupp/settings/constants/preferences-keys.dart';

import 'dinzo-api.dart';
import 'dinzo-models.dart';
import 'dinzo-taxes.dart';

/// Which banks hold everyday money. Whatever is elsewhere (a broker) is an
/// investment, even fixed income. The user chooses; each bank starts by what it
/// usually is.
class DailyBanks {
  /// Where money usually goes to be invested.
  static const brokers = {
    'BTG',
    'XP',
    'Rico',
    'Clear',
    'AUVP',
    'Modal',
    'Avenue',
    'Toro',
    'Genial',
    'Órama',
    'Warren',
    'Ágora',
    'Binance',
  };

  static Map<String, bool> get _choices {
    final raw = ServiceConfig.sharedPreferences?.getString(
      PreferencesKeys.dailyBanks,
    );
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map).cast<String, bool>();
    } catch (_) {
      return {};
    }
  }

  static bool isDaily(String bank) =>
      _choices[bank] ?? !brokers.contains(bank);

  static Future<void> choose(String bank, bool daily) async {
    await ServiceConfig.sharedPreferences!.setString(
      PreferencesKeys.dailyBanks,
      jsonEncode({..._choices, bank: daily}),
    );
  }

  /// An account without a bank behind it was added by hand: it is everyday.
  static bool holdsAccount(DinzoAccount account) {
    final connector = account.connectorName;
    if (connector == null) return true;
    return isDaily(KnownTag.bankIn(connector)?.name ?? connector);
  }
}

/// Money is what can be spent or moved at its face value: the accounts and the
/// fixed income in the everyday banks ([DailyBanks]), minus the cards. All of it
/// sits together in the banks, whatever it is for: the wallets say what it is
/// for, and the wallet to invest is what they leave. So interest raises it,
/// and money sent to a broker lowers it, without any step in between.
/// A price never gets here: stocks and the like are not money in any bank.
class DailyMoney {
  static final _logger = Logger.withClass(DailyMoney);

  static const fixedIncomeType = 'FIXED_INCOME';
  static const adjustmentPrefix = 'livre:ajuste:';

  static bool isMoney(DinzoInvestment investment) =>
      investment.type == fixedIncomeType &&
      DailyBanks.isDaily(Institution.of(investment).name);

  static double fixedIncomeIn(Iterable<DinzoInvestment> investments) =>
      investments
          .where((i) => !i.archived && isMoney(i))
          .fold<double>(0, (sum, i) => sum + i.balance);

  /// A sync has already brought the history: the first one must bring it all.
  static Future<bool> started() async {
    final db = await SqliteDatabase.instance.database;
    if (db == null) return false;
    final rows = await db.rawQuery(
      "SELECT 1 FROM records WHERE dinzo_id IS NOT NULL "
      "AND dinzo_id NOT LIKE 'livre:%' LIMIT 1",
    );
    return rows.isNotEmpty;
  }

  /// The wallet to invest, once the first sync has made it.
  static Future<int?> toInvestWalletId() async {
    final wallets = await ServiceConfig.database.getAllWallets();
    for (final w in wallets) {
      if (w.isInvestmentReserve && !w.isArchived) return w.id;
    }
    return null;
  }

  /// Leaves in the wallet to invest what [money] has beyond the other wallets.
  /// The difference goes in one entry per month, where a hole shows up. On the
  /// very first sync ([spendable]) there is nothing to explain: the default
  /// wallet starts at the accounts minus the cards, and that wallet at the rest.
  static Future<void> reconcile(
    double money, {
    double? spendable,
    DateTime? now,
  }) async {
    if (SqliteDatabase.readOnly) return;
    final db = ServiceConfig.database;
    final today = now ?? DateTime.now();
    final defaultWallet = await db.getDefaultWallet();
    if (defaultWallet?.id == null) return;
    await AutomaticWrites.run(() async {
      var wallets = await db.getWalletsBalanceAsOf(today);
      if (!wallets.any((w) => w.isInvestmentReserve && !w.isArchived)) {
        await db.addWallet(
          Wallet(
            Wallet.toInvestName,
            kind: WalletKind.toInvest,
            iconCodePoint: FontAwesomeIcons.seedling.data.codePoint,
            sortOrder: wallets.length,
          ),
        );
      }
      if (spendable != null) {
        final current = wallets.firstWhere((w) => w.id == defaultWallet!.id);
        defaultWallet!.initialAmount +=
            spendable - (current.balance ?? current.initialAmount);
        await db.updateWallet(defaultWallet.id!, defaultWallet);
      }
      wallets = await db.getWalletsBalanceAsOf(today);
      Wallet? toInvest;
      var claimed = 0.0;
      for (final w in wallets) {
        if (w.isInvestmentReserve && !w.isArchived && toInvest == null) {
          toInvest = w;
        } else if (w.id == defaultWallet!.id ||
            !TotalWallets.includes(w, defaultWallet.id)) {
          // The other spending wallets (cash, food allowance) are not in the
          // banks that [money] comes from.
          claimed += w.balance ?? w.initialAmount;
        }
      }
      if (toInvest == null) return;
      final difference =
          money - claimed - (toInvest.balance ?? toInvest.initialAmount);
      if (difference.abs() < 0.005) return;
      if (spendable != null) {
        toInvest.initialAmount += difference;
        await db.updateWallet(toInvest.id!, toInvest);
      } else {
        await _adjust(toInvest, difference, today);
      }
    });
  }

  static Future<void> _adjust(
    Wallet wallet,
    double difference,
    DateTime today,
  ) async {
    final sqlite = (await SqliteDatabase.instance.database)!;
    await MoneyModelMigration.ensureCategory(sqlite, Category.adjustment());
    final db = ServiceConfig.database;
    final month =
        '${today.year}-${today.month.toString().padLeft(2, '0')}';
    final id = '$adjustmentPrefix$month';
    final rows = await sqlite.rawQuery(
      'SELECT id FROM records WHERE dinzo_id = ? LIMIT 1',
      [id],
    );
    final existing = rows.isEmpty
        ? null
        : await db.getRecordById(rows.first['id'] as int);
    final value = _round((existing?.value ?? 0) + difference);
    if (existing != null) {
      if (value.abs() < 0.005) {
        await db.deleteRecordById(existing.id);
      } else {
        existing
          ..value = value
          ..walletId = wallet.id;
        await db.updateRecordById(existing.id, existing);
      }
      return;
    }
    await db.addRecord(
      Record(
        value,
        'Ajuste de ${today.month.toString().padLeft(2, '0')}/${today.year}',
        Category.adjustment(),
        DateTime.utc(today.year, today.month, 1, 12),
        walletId: wallet.id,
        dinzoId: id,
        description:
            'Diferença entre o dinheiro nos bancos do dia a dia e as carteiras: '
            'juros, e o que faltou lançar.',
      ),
    );
  }

  static double _round(double v) => (v * 100).roundToDouble() / 100;

  /// With the positions just saved.
  static Future<void> refreshFromCache() async {
    try {
      final snapshot = await InvestmentsCache.load();
      if (snapshot == null || !snapshot.balancesComplete) return;
      if (!await started()) return;
      await reconcile(
        snapshot.bankBalance +
            fixedIncomeIn(snapshot.investments) -
            snapshot.cardDebt,
      );
    } catch (e, st) {
      _logger.handle(e, st, 'Failed to refresh the wallet to invest');
    }
  }

  /// What the accounts and positions say, as of now.
  static DinzoBalances balances(
    List<DinzoAccount> accounts,
    List<DinzoInvestment> investments,
  ) {
    double bank = 0, cardDebt = 0;
    final unknown = <String>[];
    for (final a in accounts) {
      if (a.archived || a.excludeFromTotals) continue;
      final counts = a.isCreditCard || DailyBanks.holdsAccount(a);
      if (a.balance == null) {
        if (counts) unknown.add(a.connectorName ?? a.title);
        continue;
      }
      if (a.isCreditCard) {
        cardDebt += a.balance!;
      } else if (DailyBanks.holdsAccount(a)) {
        bank += a.balance!;
      }
    }
    return DinzoBalances(
      bank: bank,
      cardDebt: cardDebt,
      fixedIncome: fixedIncomeIn(investments),
      unknown: unknown,
    );
  }
}
