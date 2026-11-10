import 'package:aupp/models/category-type.dart';
import 'package:aupp/models/category.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/services/database/sqlite-database.dart';
import 'package:aupp/services/service-config.dart';

import 'dinzo-sync-engine.dart';

/// Money paid to someone else (or received from someone else) straight from
/// a bank outside the everyday ones ([DailyBanks]), like a Pix from the BTG
/// Banking. The expense (or income) is a record like any other, in its
/// wallet; next to it the app keeps a withdrawal (or an aporte) of the same
/// value, on the same day and wallet, keyed `livre:pago:<dinzo_id>`
/// ([prefix]). Together they leave the wallet as the everyday banks are, and
/// the month counts the money as taken from (or put into) the investments.
/// Deleting the record deletes it.
class BrokerPayment {
  static const prefix = 'livre:pago:';

  static String keyFor(String dinzoId) => '$prefix$dinzoId';

  /// What [record] needs next to it when [bank] (outside the everyday banks)
  /// paid it or got it; null when [bank] is null or [record] is not an
  /// expense or income brought by the Dinzo.
  static Record? companionFor(Record record, String? bank) {
    final type = record.category?.categoryType;
    if (bank == null ||
        record.dinzoId == null ||
        record.dinzoId!.startsWith('livre:') ||
        record.isTransfer ||
        (type != CategoryType.expense && type != CategoryType.income)) {
      return null;
    }
    final value = record.value ?? 0;
    if (value.abs() < 0.005) return null;
    final paid = value < 0;
    return Record(
      -value,
      paid ? 'Resgate do $bank' : 'Aporte no $bank',
      paid ? Category.withdrawal() : Category.investment(),
      record.utcDateTime,
      timeZoneName: record.timeZoneName,
      description: paid
          ? 'Pago direto do $bank: o dinheiro saiu dos investimentos.'
          : 'Recebido direto no $bank: o dinheiro foi para os investimentos.',
      walletId: record.walletId,
      tags: {bank},
      dinzoId: keyFor(record.dinzoId!),
    );
  }

  /// Makes the companions match [records] (every record linked to the
  /// Dinzo). [bankOf] names the bank outside the everyday ones a Dinzo
  /// account belongs to, or gives null. Returns lines for the sync history.
  static Future<List<String>> sync(
    List<Record> records,
    String? Function(String? accountId) bankOf,
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
    for (final record in records) {
      final link = DinzoLink.fromJsonString(record.dinzoSnapshot);
      final companion = companionFor(record, bankOf(link?.source.accountId));
      if (companion == null) continue;
      wanted.add(companion.dinzoId!);
      final line =
          '${companion.title} ${companion.value!.toStringAsFixed(2)} '
          '(${record.title}, registro ${record.id})';
      final id = existing[companion.dinzoId];
      if (id == null) {
        await SqliteDatabase.ensureCategory(sqlite, companion.category!);
        await db.addRecord(companion);
        lines.add('+ $line');
        continue;
      }
      final current = await db.getRecordById(id);
      if (current != null &&
          (current.value! - companion.value!).abs() < 0.005 &&
          current.walletId == companion.walletId &&
          current.utcDateTime == companion.utcDateTime &&
          current.title == companion.title) {
        continue;
      }
      await SqliteDatabase.ensureCategory(sqlite, companion.category!);
      companion.id = id;
      await db.updateRecordById(id, companion);
      lines.add('~ $line');
    }
    final orphans = [
      for (final e in existing.entries)
        if (!wanted.contains(e.key)) e.value,
    ];
    if (orphans.isNotEmpty) {
      await db.deleteRecordsInBatch(orphans);
      lines.add('− ${orphans.length} resgate(s)/aporte(s) sem pagamento');
    }
    return lines;
  }
}
