import 'package:aupp/models/category-type.dart';
import 'package:aupp/models/category.dart';
import 'package:aupp/services/database/sqlite-database.dart';
import 'package:aupp/services/logger.dart';
import 'package:aupp/services/service-config.dart';

/// In-memory view of category parents (fork-only subcategories), so budgets
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
      final all = await ServiceConfig.database.getAllCategories();
      _byKey
        ..clear()
        ..addAll({
          for (final c in all)
            if (c != null) _key(c.name, c.categoryType): c,
        });
    } catch (e, st) {
      _logger.handle(e, st, 'Failed to load category hierarchy');
    }
  }

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

  /// [category] itself when top-level, otherwise its parent.
  static Category? topLevelOf(Category? category) =>
      parentOf(category) ?? category;

  /// Whether a record in [category] belongs to the category named [name]:
  /// the category itself or its parent.
  static bool belongsTo(Category? category, String name) =>
      category?.name == name || parentOf(category)?.name == name;

  static List<Category> childrenOf(Category parent) => _byKey.values
      .where((c) =>
          c.parentName == parent.name && c.categoryType == parent.categoryType)
      .toList();
}
