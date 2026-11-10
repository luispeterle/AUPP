import 'package:aupp/models/record.dart';
import 'package:aupp/statistics/statistics-models.dart';
import 'package:aupp/statistics/statistics-utils.dart';

/// Filters of records shared by the statistics widgets.
class RecordFilters {
  RecordFilters._(); // Private constructor to prevent instantiation

  /// Filters records by a specific date.
  ///
  /// Only records matching the truncated date (based on aggregation method)
  /// are included in the result.
  static List<Record?> byDate(
    List<Record?> records,
    DateTime? date,
    AggregationMethod? method,
  ) {
    if (date == null || method == null) {
      return List.from(records);
    }

    // Truncate the target date to ensure consistent comparison
    final targetDate = truncateDateTime(date, method);

    return records.where((r) {
      if (r == null) return false;
      return truncateDateTime(r.dateTime, method) == targetDate;
    }).toList();
  }

  /// Filters records by category name.
  ///
  /// If [category] is null, returns all records.
  /// If [category] is "Others" and [topCategories] is provided,
  /// returns records for categories NOT in topCategories.
  static List<Record?> byCategory(
    List<Record?> records,
    String? category,
    List<String>? topCategories,
  ) {
    if (category == null) {
      return List.from(records);
    }

    final isOthers = category == 'Outros';

    if (isOthers) {
      // If "Others" but no topCategories provided, return all records
      if (topCategories == null || topCategories.isEmpty) {
        return List.from(records);
      }
      return records.where((r) {
        if (r?.category?.name == null) return false;
        return !topCategories.contains(r!.category!.name);
      }).toList();
    } else {
      return records.where((r) {
        return r?.category?.name == category;
      }).toList();
    }
  }

  /// Filters records by tag.
  ///
  /// If [tag] is null, returns all records.
  /// If [tag] is "Others" and [topCategories] is provided,
  /// returns records having tags NOT in topCategories.
  static List<Record?> byTag(
    List<Record?> records,
    String? tag,
    List<String>? topCategories,
  ) {
    if (tag == null) {
      return List.from(records);
    }

    final isOthers = tag == 'Outros';

    if (isOthers) {
      // If "Others" but no topCategories provided, return records with any tag
      if (topCategories == null || topCategories.isEmpty) {
        return records.where((r) => r?.tags.isNotEmpty ?? false).toList();
      }
      return records.where((r) {
        if (r?.tags.isEmpty ?? true) return false;
        return r!.tags.any((t) => !topCategories.contains(t));
      }).toList();
    } else {
      return records.where((r) {
        return r?.tags.contains(tag) ?? false;
      }).toList();
    }
  }

  /// Filters records by wallet.
  ///
  /// If [walletId] is null, returns all records.
  /// If [walletId] is "Others" and [topWallets] is provided,
  /// returns records whose wallet is NOT in topWallets.
  static List<Record?> byWallet(
    List<Record?> records,
    String? walletId,
    List<String>? topWallets,
  ) {
    if (walletId == null) {
      return List.from(records);
    }

    final isOthers = walletId == 'Outros';

    if (isOthers) {
      // If "Others" but no topWallets provided, return records with a wallet
      if (topWallets == null || topWallets.isEmpty) {
        return records.where((r) => r?.walletId != null).toList();
      }
      return records.where((r) {
        if (r?.walletId == null) return false;
        return !topWallets.contains(r!.walletId.toString());
      }).toList();
    } else {
      return records.where((r) {
        return r?.walletId?.toString() == walletId;
      }).toList();
    }
  }

  /// Filters records by multiple criteria at once.
  ///
  /// This is a convenience method that applies filters in sequence:
  /// 1. Date filter (if date and method provided)
  /// 2. Category filter (if category provided)
  /// 3. Tag filter (if tag provided)
  /// 4. Wallet filter (if walletId provided)
  static List<Record?> byMultipleCriteria(
    List<Record?> records, {
    DateTime? date,
    AggregationMethod? aggregationMethod,
    String? category,
    String? tag,
    String? walletId,
    List<String>? topCategories,
  }) {
    var result = List<Record?>.from(records);

    if (date != null && aggregationMethod != null) {
      result = byDate(result, date, aggregationMethod);
    }

    if (category != null) {
      result = byCategory(result, category, topCategories);
    }

    if (tag != null) {
      result = byTag(result, tag, topCategories);
    }

    if (walletId != null) {
      result = byWallet(result, walletId, topCategories);
    }

    return result;
  }

  /// Filters records for tag aggregation, considering "Others" logic.
  ///
  /// This is a specialized filter used when aggregating tag data.
  /// It excludes tags that are in topCategories when showing "Others".
  static List<Record?> forTagAggregation(
    List<Record?> records,
    DateTime? date,
    AggregationMethod? method,
    String? selectedTag,
    List<String>? topCategories,
  ) {
    var result = List<Record?>.from(records);

    if (date != null && method != null) {
      result = byDate(result, date, method);
    }

    if (selectedTag != null) {
      result = byTag(result, selectedTag, topCategories);
    }

    return result;
  }

  /// Filters records for wallet aggregation, considering "Others" logic.
  ///
  /// This is a specialized filter used when aggregating wallet data.
  /// It excludes records whose wallet is in topWallets when showing "Others".
  static List<Record?> forWalletAggregation(
    List<Record?> records,
    DateTime? date,
    AggregationMethod? method,
    String? selectedWallet,
    List<String>? topWallets,
  ) {
    var result = List<Record?>.from(records);

    if (date != null && method != null) {
      result = byDate(result, date, method);
    }

    if (selectedWallet != null) {
      result = byWallet(result, selectedWallet, topWallets);
    }

    return result;
  }
}
