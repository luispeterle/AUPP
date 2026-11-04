import 'package:aupp/models/category.dart';
import 'package:aupp/services/database/exceptions.dart';
import 'package:aupp/services/database/sqlite-migration-service.dart';
import 'package:aupp/services/logger.dart';
import 'package:aupp/services/service-config.dart';

import 'dinzo-default-categories.dart';

/// Fork-only first-run setup. A brand-new database comes with the upstream
/// defaults (four categories, "Default Wallet"); this copy replaces them with
/// the Dinzo category tree and names the default wallet "Conta corrente", so
/// a fresh install (or a debug build) is ready before any backup is restored.
/// Runs once; a database that already has data is left untouched.
class ForkDefaults {
  static final _logger = Logger.withClass(ForkDefaults);
  static const _appliedKey = 'forkDefaultsApplied';
  static const defaultWalletName = 'Conta corrente';

  static Future<void> applyIfFresh() async {
    final prefs = ServiceConfig.sharedPreferences;
    if (prefs == null || prefs.getBool(_appliedKey) == true) return;
    try {
      final db = ServiceConfig.database;
      final categories = (await db.getAllCategories())
          .whereType<Category>()
          .toList();
      String key(Category c) => '${c.name}|${c.categoryType?.index}';
      final upstream = SqliteMigrationService.getDefaultCategories()
          .map(key)
          .toSet();
      final fresh =
          await db.getCountRecords() == 0 &&
          categories.every((c) => upstream.contains(key(c)));
      if (fresh) {
        for (final c in categories) {
          await db.deleteCategory(c.name, c.categoryType);
        }
        for (final c in dinzoDefaultCategories()) {
          try {
            await db.addCategory(c);
          } on ElementAlreadyExists {
            // Already there: keep it.
          }
        }
        final wallet = await db.getDefaultWallet();
        if (wallet != null &&
            {'Default Wallet', 'Carteira padrão'}.contains(wallet.name)) {
          wallet.name = defaultWalletName;
          await db.updateWallet(wallet.id!, wallet);
        }
        _logger.info('Fresh database: Dinzo categories installed');
      }
      await prefs.setBool(_appliedKey, true);
    } catch (e, st) {
      _logger.handle(e, st, 'Failed to apply fork defaults');
    }
  }
}
