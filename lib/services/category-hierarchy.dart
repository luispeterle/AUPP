import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:aupp/models/category-type.dart';
import 'package:aupp/models/category.dart';
import 'package:aupp/services/database/sqlite-database.dart';
import 'package:aupp/services/logger.dart';
import 'package:aupp/services/service-config.dart';
import 'package:aupp/settings/constants/preferences-keys.dart';

/// In-memory view of category parents (subcategories), so budgets
/// and statistics can roll a subcategory up into its parent without changing
/// the queries that load records. Kept fresh on every database write.
class CategoryHierarchy {
  static final _logger = Logger.withClass(CategoryHierarchy);
  static final Map<String, Category> _byKey = {};
  static bool _listening = false;

  static String _key(String? name, CategoryType? type) =>
      '$name|${type?.index}';

  static Future<void> refresh() async {
    try {
      load((await ServiceConfig.database.getAllCategories()).nonNulls);
    } catch (e, st) {
      _logger.handle(e, st, 'Failed to load category hierarchy');
    }
  }

  @visibleForTesting
  static void load(Iterable<Category> all) => _byKey
    ..clear()
    ..addAll({for (final c in all) _key(c.name, c.categoryType): c});

  /// Loads the hierarchy and reloads it after every database write.
  static Future<void> init() async {
    await refresh();
    if (_listening) return;
    _listening = true;
    SqliteDatabase.dataChangeNotifier.addListener(refresh);
  }

  /// The parent of [category], or null for a top-level category.
  static Category? parentOf(Category? category) {
    if (category == null) return null;
    final parentName =
        _byKey[_key(category.name, category.categoryType)]?.parentName;
    if (parentName == null) return null;
    return _byKey[_key(parentName, category.categoryType)];
  }

  /// The category whose look a record shows: the parent of a subcategory,
  /// else [category] itself (also when the parent is gone).
  static Category? topOf(Category? category) =>
      parentOf(category) ?? category;

  /// The category whose icon a record shows in the Extrato: its own, or
  /// its parent's when the user chose so ([PreferencesKeys.extratoParentIcon]).
  static Category? iconOf(Category? category) =>
      ServiceConfig.sharedPreferences?.getBool(
                PreferencesKeys.extratoParentIcon,
              ) ??
              false
          ? topOf(category)
          : category;

}
