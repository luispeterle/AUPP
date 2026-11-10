import 'package:aupp/models/record.dart';
import 'package:aupp/services/database/sqlite-database.dart';
import 'package:aupp/services/service-config.dart';

/// An aporte from the Dinzo ([DinzoSyncEngine.isAporte]) always leaves the
/// wallet to invest. When that wallet did not have the money, the rest came
/// from the default wallet (Conta corrente): the Extrato marks the aporte
/// ([Record.investShortfall]) until the user confirms it, which records a
/// transfer Conta corrente → wallet to invest of what was missing, on the
/// same day, keyed `livre:cobre:<dinzo_id>` ([prefix]). Then the balances,
/// the budget and Liberdade financeira count it as money invested from the
/// Conta corrente. Deleting the aporte deletes the transfer.
class AporteShortfall {
  static const prefix = 'livre:cobre:';

  static String keyFor(String dinzoId) => '$prefix$dinzoId';

  /// An aporte brought by the Dinzo sync into [toInvestId].
  static bool isCandidate(Record r, int toInvestId) =>
      r.id != null &&
      r.isInvestmentBuy &&
      r.walletId == toInvestId &&
      r.dinzoId != null &&
      !r.dinzoId!.startsWith('livre:') &&
      (r.value ?? 0) < 0;

  /// What was missing: the wallet's balance at the end of the aporte's day
  /// below zero, up to the aporte itself.
  static double? shortfallOf(Record aporte, double balanceAtDayEnd) {
    if (balanceAtDayEnd > -0.005) return null;
    final missing = -balanceAtDayEnd;
    final amount = (aporte.value ?? 0).abs();
    return _round(missing < amount ? missing : amount);
  }

  /// Sets [Record.investShortfall] on the aportes in [records].
  static Future<void> mark(Iterable<Record?> records) async {
    final candidates = <Record>[];
    final wallets = await ServiceConfig.database.getAllWallets();
    final toInvest = wallets
        .where((w) => w.isInvestmentReserve && !w.isArchived)
        .firstOrNull;
    for (final r in records) {
      if (r == null) continue;
      r.investShortfall = null;
      if (toInvest?.id != null && isCandidate(r, toInvest!.id!)) {
        candidates.add(r);
      }
    }
    final byDay = <DateTime, double>{};
    for (final aporte in candidates) {
      final end = _dayEnd(aporte);
      final balance =
          byDay[end] ??= await _balanceAt(toInvest!.id!, end) ?? 0;
      aporte.investShortfall = shortfallOf(aporte, balance);
    }
  }

  static Future<double?> _balanceAt(int walletId, DateTime asOf) async {
    final wallets = await ServiceConfig.database.getWalletsBalanceAsOf(asOf);
    final wallet = wallets.where((w) => w.id == walletId).firstOrNull;
    return wallet?.balance ?? wallet?.initialAmount;
  }

  static DateTime _dayEnd(Record r) {
    final d = r.utcDateTime;
    return DateTime.utc(d.year, d.month, d.day, 23, 59, 59, 999);
  }

  /// The transfer that covers [aporte], if confirmed.
  static Future<Record?> coverOf(Record aporte) async {
    if (aporte.dinzoId == null) return null;
    final db = (await SqliteDatabase.instance.database)!;
    final rows = await db.query(
      'records',
      columns: ['id'],
      where: 'dinzo_id = ?',
      whereArgs: [keyFor(aporte.dinzoId!)],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ServiceConfig.database.getRecordById(rows.first['id'] as int);
  }

  /// The user confirmed: the missing [amount] went from the default wallet
  /// to the wallet to invest that day. Confirming again adds to the same
  /// transfer.
  static Future<void> cover(Record aporte, double amount) async {
    final db = ServiceConfig.database;
    final from = await db.getDefaultWallet();
    final to = aporte.walletId;
    if (from?.id == null || to == null || from!.id == to) return;
    final existing = await coverOf(aporte);
    final total = _round(amount + (existing?.value?.abs() ?? 0));
    final transfer = Record(
      -total,
      'Para o aporte: ${aporte.title}',
      null,
      aporte.utcDateTime,
      timeZoneName: aporte.timeZoneName,
      description:
          'O Investir não tinha o dinheiro: o que faltou saiu da '
          '${from.name}.',
      walletId: from.id,
      transferWalletId: to,
      dinzoId: keyFor(aporte.dinzoId!),
    );
    if (existing == null) {
      await db.addRecord(transfer);
    } else {
      transfer.id = existing.id;
      await db.updateRecordById(existing.id, transfer);
    }
  }

  static double _round(double v) => (v * 100).roundToDouble() / 100;
}
