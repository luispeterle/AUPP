/// Plain data classes for the Dinzo REST API (https://dinzo.com.br/docs).
/// Only the fields the sync uses are parsed.

class DinzoTransaction {
  final String id;
  final bool projected;

  /// Calendar day "YYYY-MM-DD" (BRT).
  final String date;

  /// `DEBIT` (money out) or `CREDIT` (money in).
  final String type;

  /// `PENDING` or `POSTED`.
  final String status;

  /// Always positive.
  final double amount;
  final String description;
  final String? originalDescription;
  final String? notes;
  final String accountId;
  final String? categoryId;
  final int? installmentCurrent;
  final int? installmentTotal;
  final bool hidden;

  DinzoTransaction({
    required this.id,
    required this.date,
    required this.type,
    required this.amount,
    required this.description,
    required this.accountId,
    this.projected = false,
    this.status = 'POSTED',
    this.originalDescription,
    this.notes,
    this.categoryId,
    this.installmentCurrent,
    this.installmentTotal,
    this.hidden = false,
  });

  bool get isDebit => type == 'DEBIT';

  bool get isInstallment =>
      installmentCurrent != null && installmentTotal != null;

  factory DinzoTransaction.fromJson(Map<String, dynamic> json) {
    final installment = json['installment'] as Map<String, dynamic>?;
    return DinzoTransaction(
      id: json['id'] as String,
      projected: json['projected'] as bool? ?? false,
      date: json['date'] as String,
      type: json['type'] as String,
      status: json['status'] as String? ?? 'POSTED',
      amount: (json['amount'] as num).toDouble(),
      description: json['description'] as String? ?? '',
      originalDescription: json['original_description'] as String?,
      notes: json['notes'] as String?,
      accountId: json['account_id'] as String,
      categoryId: json['category_id'] as String?,
      installmentCurrent: installment?['current'] as int?,
      installmentTotal: installment?['total'] as int?,
      hidden: json['hide_from_results'] as bool? ?? false,
    );
  }
}

class DinzoAccount {
  final String id;

  /// `BANK` or `CREDIT`.
  final String type;
  final String? subType;
  final String title;

  /// Bank accounts: balance. Credit cards: used limit (open bill plus future
  /// installments). Null when the API does not compute it.
  final double? balance;
  final bool archived;
  final bool excludeFromTotals;
  final String? connectorName;

  /// Credit cards: the card's limit.
  final double? creditLimit;

  DinzoAccount({
    required this.id,
    required this.type,
    required this.title,
    this.subType,
    this.balance,
    this.archived = false,
    this.excludeFromTotals = false,
    this.connectorName,
    this.creditLimit,
  });

  bool get isCreditCard => type == 'CREDIT';

  factory DinzoAccount.fromJson(Map<String, dynamic> json) {
    final openFinance = json['open_finance'] as Map<String, dynamic>?;
    return DinzoAccount(
      id: json['id'] as String,
      type: json['type'] as String,
      subType: json['sub_type'] as String?,
      title: (json['title'] as String? ?? '').trim(),
      balance: (json['balance'] as num?)?.toDouble(),
      archived: json['archived'] as bool? ?? false,
      excludeFromTotals: json['exclude_from_totals'] as bool? ?? false,
      connectorName: openFinance?['connector_name'] as String?,
      creditLimit: ((json['credit'] as Map<String, dynamic>?)?['limit'] as num?)
          ?.toDouble(),
    );
  }
}

class DinzoCategory {
  final String id;
  final String title;
  final String? parentId;

  /// "#RRGGBB", or null.
  final String? colorHex;

  DinzoCategory({
    required this.id,
    required this.title,
    this.parentId,
    this.colorHex,
  });

  factory DinzoCategory.fromJson(Map<String, dynamic> json) => DinzoCategory(
    id: json['id'] as String,
    title: json['title'] as String,
    parentId: json['parent_id'] as String?,
    colorHex: json['color_hex'] as String?,
  );
}
