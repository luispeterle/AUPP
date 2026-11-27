import 'package:aupp/investments/investments-analytics.dart';
import 'package:aupp/models/category.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/services/database/sqlite-database.dart';
import 'package:aupp/services/service-config.dart';

import 'daily-money.dart';
import 'dinzo-taxes.dart';

/// An order a bank shows only in its positions ([BrokerOrders]).
class BrokerOrder {
  final DinzoInvestment position;
  final DinzoInvestmentMovement movement;
  final String bank;

  const BrokerOrder(this.position, this.movement, this.bank);

  bool get isBuy => movement.type == 'BUY';

  String get key =>
      '${BrokerOrders.prefix}${position.assetKey}|${movement.date}|'
      '${movement.type}|${movement.amount}';

  /// The aporte (or the withdrawal) of the wallet to invest.
  Record record(int walletId) {
    final date = DateTime.parse(movement.date);
    final amount = movement.amount!;
    final asset = position.code ?? position.name;
    return Record(
      isBuy ? -amount : amount,
      '${isBuy ? 'Compra' : 'Venda'} de $asset no $bank',
      isBuy ? Category.investment() : Category.withdrawal(),
      DateTime.utc(date.year, date.month, date.day, 12),
      description:
          'Ordem que o $bank mostra só nos investimentos da Dinzo, sem '
          'lançamento na conta.',
      walletId: walletId,
      tags: {bank},
      dinzoId: key,
    );
  }
}

/// Orders of a bank that sends no entries to the Dinzo (the Rico): its
/// positions are the only place they show, as buys and sells. A bank that
/// does send entries has its orders there ([DinzoSyncEngine.orderOf]): read
/// here too, they would count twice. Records keyed `livre:ordem:...`
/// ([prefix]), redone on every sync.
class BrokerOrders {
  static const prefix = 'livre:ordem:';

  /// The orders in [investments] from [since] on (before it, the wallets'
  /// starting balances hold them), of positions that are investments and
  /// banks not in [banksWithEntries].
  static List<BrokerOrder> of(
    Iterable<DinzoInvestment> investments, {
    required Set<String> banksWithEntries,
    required DateTime since,
    bool Function(DinzoInvestment) isMoney = DailyMoney.isMoney,
  }) {
    final from = DateTime(since.year, since.month, since.day);
    return [
      for (final position in investments)
        if (!isMoney(position))
          for (final movement in position.movements)
            if ((movement.type == 'BUY' || movement.type == 'SELL') &&
                (movement.amount ?? 0) > 0 &&
                !DateTime.parse(movement.date).isBefore(from))
              BrokerOrder(position, movement, Institution.of(position).name),
    ].where((o) => !banksWithEntries.contains(o.bank)).toList();
  }

  /// Makes the records match [orders]. Returns lines for the sync history.
  static Future<List<String>> sync(
    List<BrokerOrder> orders,
    int walletId,
  ) async {
    final db = ServiceConfig.database;
    final sqlite = (await SqliteDatabase.instance.database)!;
    final rows = await sqlite.query(
      'records',
      columns: ['id', 'dinzo_id'],
      where: 'dinzo_id LIKE ?',
      whereArgs: ['$prefix%'],
    );
    final existing = {
      for (final r in rows) r['dinzo_id'] as String: r['id'] as int,
    };
    final lines = <String>[];
    final wanted = <String>{};
    for (final order in orders) {
      final record = order.record(walletId);
      wanted.add(record.dinzoId!);
      if (existing.containsKey(record.dinzoId)) continue;
      await SqliteDatabase.ensureCategory(sqlite, record.category!);
      await db.addRecord(record);
      lines.add('+ ${record.title} ${record.value!.toStringAsFixed(2)}');
    }
    final orphans = [
      for (final e in existing.entries)
        if (!wanted.contains(e.key)) e.value,
    ];
    if (orphans.isNotEmpty) {
      await db.deleteRecordsInBatch(orphans);
      lines.add('− ${orphans.length} ordem(ns) que sumiram dos investimentos');
    }
    return lines;
  }
}
