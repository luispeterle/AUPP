import 'dart:convert';

import 'package:aupp/investments/asset-lots.dart';
import 'package:aupp/models/category.dart';
import 'package:aupp/services/crypto-quote-service.dart';
import 'package:aupp/services/database/change-log.dart';
import 'package:aupp/services/service-config.dart';
import 'package:aupp/settings/constants/preferences-keys.dart';
import 'package:sqflite/sqflite.dart';

/// Moves data from the model where the wallets had to add up to the real money
/// (yield, tax and adjustment records; wallets for what was invested and for
/// each coin) to the current one: see [DailyMoney]. Every wallet that stays
/// keeps its balance.
///
/// Runs on the schema upgrade and after restoring a backup from before it.
class MoneyModelMigration {
  static const _bookkeeping =
      "dinzo_id LIKE 'livre:rend:%' OR dinzo_id LIKE 'livre:ir:%' "
      "OR dinzo_id = 'livre:inicial' "
      "OR dinzo_id GLOB 'livre:[0-9][0-9][0-9][0-9]-[0-9][0-9]'";

  static bool _isGone(Map<String, Object?> wallet) {
    final name = (wallet['name'] as String? ?? '').trim().toLowerCase();
    return name.startsWith('rendimento') ||
        name.startsWith('investido') ||
        wallet['kind'] == 'free' ||
        _coinOf(wallet) != null;
  }

  static String? _coinOf(Map<String, Object?> wallet) {
    final currency = (wallet['currency'] as String?)?.toUpperCase();
    return CryptoQuoteService.isQuoted(currency) ? currency : null;
  }

  /// Whether the database still has anything of the old model.
  static Future<bool> needed(DatabaseExecutor db) async {
    final old = await db.rawQuery(
      'SELECT 1 FROM records WHERE $_bookkeeping LIMIT 1',
    );
    return old.isNotEmpty || (await db.query('wallets')).any(_isGone);
  }

  static Future<void> run(DatabaseExecutor db) async {
    final device = ChangeLog.device;
    Future<void> log(
      String action,
      String target,
      String title, [
      Map<String, Object?>? before,
      Map<String, Object?>? after,
    ]) => db.insert(ChangeLog.table, {
      'at': DateTime.now().millisecondsSinceEpoch,
      'device': device,
      'action': action,
      'target': target,
      'title': title,
      'before_values': before == null ? null : jsonEncode(before),
      'after_values': after == null ? null : jsonEncode(after),
    });

    await db.rawUpdate(
      "UPDATE wallets SET kind = 'toInvest' WHERE kind = 'normal' "
      "AND lower(trim(name)) LIKE 'investir%'",
    );
    await db.rawUpdate(
      "UPDATE wallets SET kind = 'emergency' WHERE kind = 'normal' "
      "AND lower(trim(name)) LIKE 'reserva de emerg%'",
    );
    await db.rawUpdate(
      "UPDATE wallets SET kind = 'opportunity' WHERE kind = 'normal' "
      "AND lower(trim(name)) LIKE 'reserva de oportun%'",
    );

    final wallets = await db.query('wallets');
    final gone = wallets.where(_isGone).toList();
    final goneIds = {for (final w in gone) w['id'] as int};
    final initial = <int, double>{};

    // What the old records added to each wallet becomes its starting amount.
    final booked = await db.rawQuery(
      'SELECT wallet_id, SUM(value) AS total FROM records '
      'WHERE $_bookkeeping GROUP BY wallet_id',
    );
    for (final row in booked) {
      final id = row['wallet_id'] as int?;
      if (id == null || goneIds.contains(id)) continue;
      initial[id] = (row['total'] as num?)?.toDouble() ?? 0;
    }
    final count = await _delete(db, _bookkeeping, const []);
    if (count > 0) await log('Excluiu', 'records', '$count itens');

    await _keepCoins(db, gone);

    if (goneIds.isNotEmpty) {
      final marks = goneIds.join(',');
      final moving = await db.rawQuery(
        'SELECT * FROM records WHERE wallet_id IN ($marks) '
        'OR transfer_wallet_id IN ($marks)',
      );
      final hasBuys = moving.any(
        (r) =>
            !goneIds.contains(r['wallet_id']) &&
            goneIds.contains(r['transfer_wallet_id']),
      );
      if (hasBuys) await ensureCategory(db, Category.investment());
      for (final row in moving) {
        final id = row['id'] as int;
        final from = row['wallet_id'] as int?;
        final to = row['transfer_wallet_id'] as int?;
        if (!goneIds.contains(from) && goneIds.contains(to)) {
          await db.update(
            'records',
            {
              'transfer_wallet_id': null,
              'transfer_value': null,
              'category_name': Category.investmentName,
              'category_type': Category.investment().categoryType!.index,
              'dinzo_id': row['dinzo_id'] ?? 'livre:inv:old:$id',
            },
            where: 'id = ?',
            whereArgs: [id],
          );
          await log(
            'Editou',
            'records',
            row['title'] as String? ?? '$id',
            {'transfer_wallet_id': to},
            {'category_name': Category.investmentName},
          );
          continue;
        }
        if (goneIds.contains(from) && to != null && !goneIds.contains(to)) {
          final amount =
              ((row['transfer_value'] ?? row['value']) as num).toDouble().abs();
          initial[to] = (initial[to] ?? 0) + amount;
        }
        await _delete(db, 'id = ?', [id]);
      }
      await db.delete(
        'recurrent_record_patterns',
        where: 'wallet_id IN ($marks) OR transfer_wallet_id IN ($marks)',
      );
      await db.delete('wallets', where: 'id IN ($marks)');
      for (final wallet in gone) {
        await log('Excluiu', 'wallets', wallet['name'] as String);
      }
    }

    for (final entry in initial.entries) {
      if (entry.value.abs() < 0.005) continue;
      final wallet = wallets.firstWhere((w) => w['id'] == entry.key);
      final before = (wallet['initial_amount'] as num?)?.toDouble() ?? 0;
      final after = before + entry.value;
      await db.update(
        'wallets',
        {'initial_amount': after},
        where: 'id = ?',
        whereArgs: [entry.key],
      );
      await log(
        'Editou',
        'wallets',
        wallet['name'] as String,
        {'initial_amount': before},
        {'initial_amount': after},
      );
    }

    await db.rawDelete(
      "DELETE FROM categories WHERE name IN "
      "('Rendimentos', 'Ajuste de saldo', 'Saldo inicial', 'Desvalorização') "
      "AND NOT EXISTS (SELECT 1 FROM records r WHERE r.category_name = "
      "categories.name AND r.category_type = categories.category_type)",
    );
    await _cleanPreferences(gone);
  }

  static Future<int> _delete(
    DatabaseExecutor db,
    String where,
    List<Object?> args,
  ) async {
    await db.rawDelete(
      'DELETE FROM records_tags WHERE record_id IN '
      '(SELECT id FROM records WHERE $where)',
      args,
    );
    return db.delete('records', where: where, whereArgs: args);
  }

  /// Whatever a coin's wallet held beyond its purchases becomes one purchase,
  /// so that no coin is lost with the wallet.
  static Future<void> _keepCoins(
    DatabaseExecutor db,
    List<Map<String, Object?>> gone,
  ) async {
    final held = <String, double>{};
    for (final wallet in gone) {
      final coin = _coinOf(wallet);
      if (coin == null) continue;
      final id = wallet['id'] as int;
      final out = await db.rawQuery(
        'SELECT COALESCE(SUM(value), 0) AS total FROM records '
        'WHERE wallet_id = ?',
        [id],
      );
      final into = await db.rawQuery(
        'SELECT COALESCE(SUM(ABS(COALESCE(transfer_value, value))), 0) '
        'AS total FROM records WHERE transfer_wallet_id = ?',
        [id],
      );
      held[coin] =
          (held[coin] ?? 0) +
          ((wallet['initial_amount'] as num?)?.toDouble() ?? 0) +
          (out.first['total'] as num).toDouble() +
          (into.first['total'] as num).toDouble();
    }
    if (ServiceConfig.sharedPreferences == null) return;
    for (final entry in held.entries) {
      final lots = AssetLots.of(entry.key);
      final missing = entry.value - AssetLots.quantityOf(lots);
      if (missing.abs() < 1e-9) continue;
      await AssetLots.save(entry.key, [
        ...lots,
        AssetLot(
          day: DateTime.now(),
          quantity: missing,
          note: 'Saldo que estava na carteira: ajuste a data',
        ),
      ]);
    }
  }

  static Future<void> _cleanPreferences(List<Map<String, Object?>> gone) async {
    final prefs = ServiceConfig.sharedPreferences;
    if (prefs == null) return;
    await prefs.remove('dinzoInvestedAnchors');
    await prefs.remove('cryptoPurchases');
    await prefs.remove('dinzoInvestLinks');
    final raw = prefs.getString(PreferencesKeys.budgetPlan);
    if (raw == null) return;
    try {
      final plan = jsonDecode(raw) as Map<String, dynamic>;
      final groups = plan['wallets'] as Map<String, dynamic>?;
      if (groups == null) return;
      for (final wallet in gone) {
        groups.remove((wallet['name'] as String).trim().toLowerCase());
        groups.remove(wallet['name'] as String);
      }
      await prefs.setString(PreferencesKeys.budgetPlan, jsonEncode(plan));
    } catch (_) {
      // A plan that cannot be read stays as it is.
    }
  }

  /// A category only exists once used.
  static Future<void> ensureCategory(
    DatabaseExecutor db,
    Category category,
  ) async {
    final found = await db.query(
      'categories',
      where: 'name = ? AND category_type = ?',
      whereArgs: [category.name, category.categoryType!.index],
      limit: 1,
    );
    if (found.isEmpty) await db.insert('categories', category.toMap());
  }
}
