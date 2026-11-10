import 'dart:convert';

import 'package:aupp/accounts/money-accounts.dart';
import 'package:aupp/models/category-type.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/services/logger.dart';
import 'package:aupp/services/service-config.dart';

/// Points at a record across devices: its Dinzo id when it has one (record
/// ids change when the devices merge), else its date, amount and title.
class RefundRef {
  final String? dinzoId;
  final int atMillis;
  final double value;
  final String? title;

  RefundRef({
    this.dinzoId,
    required this.atMillis,
    required this.value,
    this.title,
  });

  RefundRef.of(Record r)
    : dinzoId = r.dinzoId,
      atMillis = r.utcDateTime.millisecondsSinceEpoch,
      value = r.value ?? 0,
      title = r.title;

  DateTime get utc =>
      DateTime.fromMillisecondsSinceEpoch(atMillis, isUtc: true);

  Map<String, dynamic> toJson() => {
    'dinzo': dinzoId,
    'at': atMillis,
    'value': value,
    'title': title,
  };

  static RefundRef fromJson(Map<String, dynamic> m) => RefundRef(
    dinzoId: m['dinzo'] as String?,
    atMillis: m['at'] as int,
    value: (m['value'] as num).toDouble(),
    title: m['title'] as String?,
  );

  bool matches(Record r) =>
      dinzoId != null
          ? r.dinzoId == dinzoId
          : (r.value ?? 0) == value &&
                r.utcDateTime.millisecondsSinceEpoch == atMillis &&
                r.title == title;
}

/// Refunds and the expense they undo, linked by the user ([Record.refundLink]
/// on each). One refund of all of it: neither counts in income, expenses,
/// the budget or the statistics ([Record.isRefundPair]). Part of it (one or
/// more refunds, never more than the expense): each refund moves to the
/// expense's category, positive, so everything counts what is left
/// (1.220 − 100 = 1.120); unlinking gives it its own category back. All of
/// them still move the wallet's balance. The app only suggests a match
/// ([markSuggestions]).
class RefundLink {
  static final _logger = Logger.withClass(RefundLink);

  /// Whether this side is a refund (money in) or the expense.
  final bool isRefund;

  /// Refunds that do not undo all of the expense at once.
  final bool isPartial;

  /// On a refund: the expense it undoes.
  final RefundRef? expense;

  /// On the expense: its refunds.
  final List<RefundRef> refunds;

  /// On a partial refund: its own category, given back on unlinking.
  final String? ownCategoryName;
  final int? ownCategoryType;

  RefundLink.refund({
    required RefundRef this.expense,
    required this.isPartial,
    this.ownCategoryName,
    this.ownCategoryType,
  }) : isRefund = true,
       refunds = const [];

  RefundLink.expense({required this.refunds, required this.isPartial})
    : isRefund = false,
      expense = null,
      ownCategoryName = null,
      ownCategoryType = null;

  /// What came back of the expense, on its side.
  double get refunded => refunds.fold(0.0, (sum, r) => sum + r.value);

  String encode() => jsonEncode({
    'role': isRefund ? 'refund' : 'expense',
    // Read by [Record.isRefundPair] as text.
    if (isPartial) 'partial': true,
    if (expense != null) 'expense': expense!.toJson(),
    if (!isRefund) 'refunds': [for (final r in refunds) r.toJson()],
    if (ownCategoryName != null) 'category': ownCategoryName,
    if (ownCategoryType != null) 'type': ownCategoryType,
  });

  static RefundLink? decode(String? json) {
    if (json == null) return null;
    try {
      final m = jsonDecode(json) as Map<String, dynamic>;
      final partial = m['partial'] == true;
      if (m['role'] == 'refund') {
        return RefundLink.refund(
          expense: RefundRef.fromJson(m['expense'] as Map<String, dynamic>),
          isPartial: partial,
          ownCategoryName: m['category'] as String?,
          ownCategoryType: m['type'] as int?,
        );
      }
      return RefundLink.expense(
        refunds: [
          for (final r in m['refunds'] as List)
            RefundRef.fromJson(r as Map<String, dynamic>),
        ],
        isPartial: partial,
      );
    } catch (_) {
      return null;
    }
  }

  /// "Estorno Aluguel", "Reembolso Shopee", "Devolução de compra"...
  static final _refundWords = RegExp(
    r'^(estorno|reembolso|devolu[cç][aã]o|refund|cancelamento)\b',
    caseSensitive: false,
  );

  /// How far back the expense of a suggested match may be.
  static const suggestionDays = 60;

  /// The Conta corrente (default wallet): refunds and expenses are only
  /// its records. Loaded by [loadAccount].
  static int? _accountId;

  static Future<void> loadAccount() async {
    _accountId = (await ServiceConfig.database.getDefaultWallet())?.id;
  }

  /// A stored record of the Conta corrente, money that really came from
  /// outside or went to someone (not a Pix between the user's accounts).
  static bool _stored(Record r) =>
      _accountId != null &&
      r.walletId == _accountId &&
      !r.isFutureRecord &&
      r.id != null &&
      !r.isTransfer &&
      !r.tags.contains(MoneyAccounts.transferTag);

  /// Money that came in, not linked yet: it may be a refund.
  static bool canBeRefund(Record r) =>
      _stored(r) &&
      r.refundLink == null &&
      r.category?.categoryType == CategoryType.income &&
      (r.value ?? 0) > 0;

  /// Money that went out and may have come back, in full or in part (not
  /// a recurrence's, not all of it back yet).
  static bool canBeUndone(Record r) =>
      _stored(r) &&
      r.recurrencePatternId == null &&
      r.category?.categoryType == CategoryType.expense &&
      (r.value ?? 0) < 0 &&
      leftOf(r) > 0.005;

  static bool looksLikeRefund(Record r) =>
      _refundWords.hasMatch((r.title ?? '').trim());

  /// What of [expense] has not come back yet.
  static double leftOf(Record expense) {
    if (expense.refundLink == null) return -(expense.value ?? 0);
    final link = decode(expense.refundLink);
    if (link == null || link.isRefund || !link.isPartial) return 0;
    return -(expense.value ?? 0) - link.refunded;
  }

  static bool sameAmount(Record refund, Record expense) =>
      ((refund.value ?? 0) + (expense.value ?? 0)).abs() < 0.005;

  /// [refund] fits in what has not come back of [expense].
  static bool fits(Record refund, Record expense) =>
      (refund.value ?? 0) <= leftOf(expense) + 0.005;

  static int _days(Record a, Record b) =>
      a.utcDateTime.difference(b.utcDateTime).inDays;

  /// Marks each income named like a refund with an expense of the same
  /// amount up to [suggestionDays] before it ([Record.refundSuggestion]),
  /// the closest, one to one. Only a suggestion: nothing changes until the
  /// user links them.
  static void markSuggestions(Iterable<Record?> records) {
    final all = records.whereType<Record>().toList();
    for (final r in all) {
      r.refundSuggestion = null;
    }
    final taken = <Record>{};
    final refunds = all
        .where((r) => canBeRefund(r) && looksLikeRefund(r))
        .toList()
      ..sort((a, b) => a.utcDateTime.compareTo(b.utcDateTime));
    for (final refund in refunds) {
      Record? best;
      for (final expense in all) {
        if (taken.contains(expense) || expense.refundLink != null) continue;
        if (!canBeUndone(expense) || !sameAmount(refund, expense)) continue;
        final days = _days(refund, expense);
        if (days < 0 || days > suggestionDays) continue;
        if (best == null || days < _days(refund, best)) best = expense;
      }
      if (best == null) continue;
      taken.add(best);
      refund.refundSuggestion = best;
    }
  }

  /// The expenses [refund] fits in: the same amount first, then the
  /// closest; up to [suggestionDays] after it too (a bank can post the
  /// refund first).
  static Future<List<Record>> candidates(Record refund) async {
    await loadAccount();
    final records = await ServiceConfig.database.getAllRecordsInInterval(
      refund.utcDateTime.subtract(const Duration(days: 400)),
      refund.utcDateTime.add(const Duration(days: suggestionDays)),
    );
    final expenses = records
        .whereType<Record>()
        .where((r) => canBeUndone(r) && fits(refund, r))
        .toList();
    expenses.sort((a, b) {
      final same =
          (sameAmount(refund, a) ? 0 : 1) - (sameAmount(refund, b) ? 0 : 1);
      if (same != 0) return same;
      return _days(refund, a).abs().compareTo(_days(refund, b).abs());
    });
    return expenses;
  }

  /// Links [refund] to [expense]: all of it at once, neither counts any
  /// more; part of it, the refund moves to the expense's category.
  static Future<void> link(Record refund, Record expense) async {
    final db = ServiceConfig.database;
    await loadAccount();
    final r = await db.getRecordById(refund.id!);
    final e = await db.getRecordById(expense.id!);
    if (r == null || e == null || !canBeRefund(r) || !canBeUndone(e)) return;
    if (!fits(r, e)) return;
    final before = decode(e.refundLink);
    final partial = before != null || !sameAmount(r, e);
    r.refundLink = RefundLink.refund(
      expense: RefundRef.of(e),
      isPartial: partial,
      ownCategoryName: partial ? r.category?.name : null,
      ownCategoryType: partial ? r.category?.categoryType?.index : null,
    ).encode();
    e.refundLink = RefundLink.expense(
      refunds: [...?before?.refunds, RefundRef.of(r)],
      isPartial: partial,
    ).encode();
    if (partial) r.category = e.category;
    await db.updateRecordById(r.id, r);
    await db.updateRecordById(e.id, e);
    _logger.info('Refund ${r.id} "${r.title}" linked to ${e.id} "${e.title}"');
  }

  /// Unlinks [record]: a refund leaves its expense; an expense lets all its
  /// refunds go.
  static Future<void> unlink(Record record) async {
    final stored = await ServiceConfig.database.getRecordById(record.id!);
    if (stored == null) return;
    await forget(stored);
    await _release(stored);
    _logger.info('Refund link of ${stored.id} "${stored.title}" undone');
  }

  /// The other side(s) of [record] stop pointing at it: run before it is
  /// unlinked or deleted.
  static Future<void> forget(Record record) async {
    final db = ServiceConfig.database;
    final link = decode(record.refundLink);
    if (link == null) return;
    if (!link.isRefund) {
      for (final refund in await refundsOf(record)) {
        await _release(refund);
      }
      return;
    }
    final expense = await expenseOf(record);
    final expenseLink = decode(expense?.refundLink);
    if (expense == null || expenseLink == null) return;
    final left = [
      for (final r in expenseLink.refunds)
        if (!r.matches(record)) r,
    ];
    expense.refundLink = left.isEmpty
        ? null
        : RefundLink.expense(refunds: left, isPartial: true).encode();
    await db.updateRecordById(expense.id, expense);
  }

  /// Takes the link off [record] alone: a partial refund gets its own
  /// category back.
  static Future<void> _release(Record record) async {
    final db = ServiceConfig.database;
    final link = decode(record.refundLink);
    record.refundLink = null;
    if (link?.ownCategoryName != null && link?.ownCategoryType != null) {
      record.category =
          await db.getCategory(
            link!.ownCategoryName!,
            CategoryType.values[link.ownCategoryType!],
          ) ??
          record.category;
    }
    await db.updateRecordById(record.id, record);
  }

  static Future<Record?> _find(RefundRef ref, {int? besides}) async {
    final records = await ServiceConfig.database.getAllRecordsInInterval(
      ref.utc.subtract(const Duration(days: 1)),
      ref.utc.add(const Duration(days: 1)),
    );
    for (final r in records.whereType<Record>()) {
      if (r.id != besides && ref.matches(r)) return r;
    }
    return null;
  }

  /// The expense a refund undoes, if it is still there.
  static Future<Record?> expenseOf(Record refund) async {
    final ref = decode(refund.refundLink)?.expense;
    return ref == null ? null : _find(ref, besides: refund.id);
  }

  /// The refunds of an expense that are still there.
  static Future<List<Record>> refundsOf(Record expense) async {
    final link = decode(expense.refundLink);
    if (link == null || link.isRefund) return const [];
    return [
      for (final ref in link.refunds) ?await _find(ref, besides: expense.id),
    ];
  }
}
