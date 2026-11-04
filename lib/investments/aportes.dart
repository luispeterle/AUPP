import 'package:aupp/dinzo/dinzo-sync-service.dart';
import 'package:aupp/services/database/sqlite-database.dart';
import 'package:aupp/services/service-config.dart';

/// Entries of money that left the wallets to be invested, made by older
/// versions (by hand, or from a purchase). Nothing makes them anymore: what
/// leaves the banks comes from the Dinzo. They go with their purchase.
class Aportes {
  static const prefix = '${DinzoSyncService.syntheticPrefix}inv:';

  /// Every entry of a movement.
  static Future<void> delete(String key) async {
    final sqlite = (await SqliteDatabase.instance.database)!;
    final rows = await sqlite.rawQuery(
      'SELECT id FROM records WHERE dinzo_id LIKE ?',
      ['$prefix$key#%'],
    );
    for (final row in rows) {
      await ServiceConfig.database.deleteRecordById(row['id'] as int);
    }
  }
}
