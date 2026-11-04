import 'dart:convert';

import 'package:aupp/models/category-type.dart';

/// Where a merchant's transactions should go, learned from the merge screen.
class DinzoMerchantRule {
  final String? categoryName;
  final int? walletId;

  const DinzoMerchantRule({this.categoryName, this.walletId});

  Map<String, dynamic> toJson() => {'c': categoryName, 'w': walletId};

  factory DinzoMerchantRule.fromJson(Map<String, dynamic> json) =>
      DinzoMerchantRule(
        categoryName: json['c'] as String?,
        walletId: json['w'] as int?,
      );
}

/// User decisions that drive the Dinzo sync. Everything here is portable
/// (goes into backups) except the API key, which lives elsewhere.
class DinzoConfig {
  /// Transactions dated before this day are never imported. Not a setting
  /// any more: a full sync brings everything Dinzo has ([historyStart]);
  /// only tests pass another day.
  DateTime startDate;

  /// Earlier than anything Dinzo can hold (Open Finance keeps ~12 months
  /// before the connection; Dinzo keeps what it saw since).
  static final DateTime historyStart = DateTime(2020, 1, 1);

  /// Names/documents that identify the user, so transfers between their own
  /// accounts (e.g. PJ to PF) are recognised as internal.
  List<String> selfIdentifiers;

  /// "<dinzo category id>|<expense|income>" → AUPP category name.
  Map<String, String> categoryMap;

  /// [DinzoSyncEngine.merchantKey] → rule. Wins over [categoryMap].
  Map<String, DinzoMerchantRule> merchantRules;

  /// Dinzo transaction ids the user chose to never integrate.
  Set<String> ignoredIds;

  DinzoConfig({
    DateTime? startDate,
    List<String>? selfIdentifiers,
    Map<String, String>? categoryMap,
    Map<String, DinzoMerchantRule>? merchantRules,
    Set<String>? ignoredIds,
  }) : startDate = startDate ?? historyStart,
       selfIdentifiers = selfIdentifiers ?? [],
       categoryMap = categoryMap ?? {},
       merchantRules = merchantRules ?? {},
       ignoredIds = ignoredIds ?? {};

  static String categoryKey(String dinzoCategoryId, CategoryType type) =>
      '$dinzoCategoryId|${type == CategoryType.income ? 'income' : 'expense'}';

  String toJsonString() => jsonEncode({
    'selfIdentifiers': selfIdentifiers,
    'categoryMap': categoryMap,
    'merchantRules': merchantRules.map((k, v) => MapEntry(k, v.toJson())),
    'ignoredIds': ignoredIds.toList()..sort(),
  });

  factory DinzoConfig.fromJsonString(String? raw) {
    if (raw == null || raw.isEmpty) return DinzoConfig();
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return DinzoConfig(
      // An old "startDate" in saved configs/backups is ignored on purpose.
      selfIdentifiers: (json['selfIdentifiers'] as List?)
          ?.cast<String>()
          .toList(),
      categoryMap: (json['categoryMap'] as Map?)?.cast<String, String>(),
      merchantRules: (json['merchantRules'] as Map?)?.map(
        (k, v) => MapEntry(
          k as String,
          DinzoMerchantRule.fromJson(Map<String, dynamic>.from(v as Map)),
        ),
      ),
      ignoredIds: (json['ignoredIds'] as List?)?.cast<String>().toSet(),
    );
  }

}
