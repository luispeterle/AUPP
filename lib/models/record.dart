import 'package:aupp/models/category-type.dart';
import 'package:aupp/models/category.dart';
import 'package:aupp/models/model.dart';
import 'package:aupp/services/service-config.dart';
import 'package:timezone/timezone.dart' as tz;

import '../helpers/datetime-utility-functions.dart';

class Record extends Model {
  int? id;
  double? value;
  String? title;
  String? description;
  Category? category;
  Set<String> tags = {};

  DateTime utcDateTime;
  String? timeZoneName;

  String? recurrencePatternId;
  int? walletId;
  int? transferWalletId;

  /// Dinzo transaction id this record was imported from.
  String? dinzoId;

  /// JSON snapshot of the fields as last written by the Dinzo sync. Lets the
  /// sync tell a local edit (local wins) from a change made in Dinzo.
  String? dinzoSnapshot;

  /// Estimate occurrence this real record was linked to (JSON, see
  /// EstimateLink). Linking consumes the occurrence.
  String? estimateLink;

  /// A refund and the expense it undoes, linked by the user (JSON on
  /// both, see RefundLink). All of it came back: neither counts. Part of it
  /// (a partial refund): the refund is in the expense's category and takes
  /// that part off it.
  String? refundLink;

  /// Transient: on an income that looks like a refund, an expense of
  /// the same amount it may undo ([RefundLink.markSuggestions]).
  Record? refundSuggestion;
  int aggregatedValues =
      1; // internal variables - used to identified an aggregated records (statistics)

  // Flag to indicate if this is a future record (not persisted to database)
  bool isFutureRecord = false;

  /// Transient: on an aporte from the Dinzo, what the wallet to invest
  /// did not have, so it came from the Conta corrente ([AporteShortfall]).
  double? investShortfall;

  /// Transient: on an estimate occurrence, the real record of the same
  /// day and amount ([EstimateLink.markMatches]). Then only the real one counts.
  Record? estimateMatch;

  /// Transient: the payment code (Pix or boleto) of an estimate
  /// occurrence, from [RecurrentRecordPattern.paymentCodes].
  String? paymentCode;

  /// Tags that mark a recurrence as paid by boleto or Pix: each occurrence
  /// then expects its own code ([RecurrentRecordPattern.paymentCodes]).
  static const billingTags = ['Boleto', 'Pix'];

  /// "Boleto" or "Pix" when the tags say it is paid that way.
  static String? billingKindOf(Set<String> tags) {
    for (final t in billingTags) {
      if (tags.contains(t)) return t;
    }
    return null;
  }

  /// Transient: on a generated occurrence, its date on the recurrence
  /// (before a due date moved it, see [RecurrentRecordPattern.dueDateFor]).
  /// What identifies the occurrence: codes, marks and estimate links.
  DateTime? occurrenceUtc;

  DateTime get occurrenceIdUtc => occurrenceUtc ?? utcDateTime;

  /// Transient: its code came without a due date, so the day was not
  /// checked ([RecurrentRecordPattern.dueDateMissing]): a small calendar.
  bool dueDateUnknown = false;

  /// Transient: the occurrence was marked "Já paguei"
  /// ([RecurrentRecordPattern.isMarkedPaid]).
  bool markedPaid = false;

  /// Upcoming occurrence of a boleto / Pix recurrence still without its code
  /// (and not already paid or matched to the real record).
  /// Real, and nobody chose what it was (the bank sent only "Pix"): the
  /// Extrato asks for a category.
  bool get needsCategory =>
      !isFutureRecord && category?.name == Category.uncategorizedName;

  bool get needsPaymentCode =>
      isFutureRecord &&
      recurrencePatternId != null &&
      paymentCode == null &&
      estimateMatch == null &&
      !markedPaid &&
      billingKindOf(tags) != null;

  /// "Pix", "Boleto" or "Código", for the tag shown in the Extrato.
  static String paymentCodeKind(String code) {
    final c = code.trim();
    if (c.startsWith('000201')) return 'Pix';
    final digits = c.replaceAll(RegExp(r'[\s.\-]'), '');
    if (RegExp(r'^\d{44,48}$').hasMatch(digits)) return 'Boleto';
    return 'Código';
  }

  // Transient: true when this copy represents the destination wallet's view of
  // a transfer (value = received amount, walletId = destination). Not persisted.
  bool isDestinationTransferView = false;

  // Transient: true when a transfer record is shown in a wallet-filtered
  // view that includes only one of its two wallets (source or destination),
  // not both. In that case the amount should be colored by sign like a
  // normal record (value is already signed for that side's perspective)
  // instead of the neutral color transfers get when both sides - or no
  // wallet filter at all - are visible. Not persisted.
  bool isSingleSideTransferView = false;

  Record(
    this.value,
    this.title,
    this.category,
    this.utcDateTime, {
    this.id,
    this.description,
    this.recurrencePatternId,
    this.timeZoneName,
    this.walletId,
    this.transferWalletId,
    Set<String>? tags,
    this.isFutureRecord = false,
    this.dinzoId,
    this.dinzoSnapshot,
    this.estimateLink,
    this.refundLink,
  }) {
    if (timeZoneName == null) {
      timeZoneName = ServiceConfig.localTimezone;
    }
    if (tags != null) {
      this.tags = tags;
    }
  }

  /// Deserialize from database
  static Record fromMap(Map<String, dynamic> map) {
    final int? utcMillis = map['datetime'];
    final utcDateTime =
        DateTime.fromMillisecondsSinceEpoch(utcMillis!, isUtc: true);

    String? timezone = map['timezone'];
    if (timezone == null) {
      timezone = ServiceConfig.localTimezone;
    }

    return Record(
      map['value'],
      map['title'],
      map['category'],
      utcDateTime,
      timeZoneName: timezone,
      id: map['id'],
      description: map['description'],
      recurrencePatternId: map['recurrence_id'],
      walletId: map['wallet_id'] as int?,
      transferWalletId: map['transfer_wallet_id'] as int?,
      dinzoId: map['dinzo_id'] as String?,
      dinzoSnapshot: map['dinzo_snapshot'] as String?,
      estimateLink: map['estimate_link'] as String?,
      refundLink: map['refund_link'] as String?,
      tags:
          map['tags'] != null ? (map['tags'] as String).split(',').toSet() : {},
    );
  }

  /// Serialize to database
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'value': value,
      'datetime': utcDateTime
          .millisecondsSinceEpoch, // this will be same as the original
      'timezone': timeZoneName,
      'category_name': category?.name,
      'category_type': category?.categoryType?.index,
      'description': description,
      'recurrence_id': recurrencePatternId,
      'wallet_id': walletId,
      'transfer_wallet_id': transferWalletId,
      'dinzo_id': dinzoId,
      'dinzo_snapshot': dinzoSnapshot,
      'estimate_link': estimateLink,
      'refund_link': refundLink,
    };
  }

  bool get isTransfer => transferWalletId != null;

  /// One side of a refund that undid all of its expense
  /// ([refundLink]): neither counts.
  bool get isRefundPair =>
      refundLink != null && !refundLink!.contains('"partial":true');

  /// Tag that keeps a record out of the Extrato's list (not deleted,
  /// still counted in the totals) unless "Exibir ocultos" is on. A tag, not a
  /// column: it goes in the backup and the Dinzo sync keeps tags it didn't
  /// write.
  static const hiddenTag = 'Oculto';

  bool get isHidden => tags.contains(hiddenTag);

  /// Whether this record counts in the balance. A transfer between the
  /// user's own wallets nets to zero, so it only counts when a wallet filter
  /// shows just one of its sides ([countsAsSetAside]).
  bool get countsTowardTotals =>
      !isAdjustment &&
      estimateMatch == null &&
      !isRefundPair &&
      (!isTransfer || isSingleSideTransferView);

  /// Income and expenses are only money that came from outside or is
  /// gone, at full value (a purchase paid partly with a caixinha too). A
  /// transfer is never one of them: see [countsAsSetAside].
  bool get countsAsExpense =>
      estimateMatch == null &&
      !isRefundPair &&
      !isTransfer &&
      category?.categoryType == CategoryType.expense;

  bool get countsAsIncome =>
      estimateMatch == null &&
      !isRefundPair &&
      !isTransfer &&
      category?.categoryType == CategoryType.income;

  /// A transfer between the shown (counted) wallets and another one:
  /// negative = money set aside, positive = taken back (e.g. the caixinha's
  /// part of a purchase). Shown apart from income/expenses; it still moves
  /// the balance. Between two shown wallets, or two others, it doesn't count.
  bool get countsAsSetAside => isTransfer && isSingleSideTransferView;

  /// Money that left the wallet to become an investment: it moves the
  /// balance and shows as invested, but it was neither spent nor earned.
  bool get isInvestmentBuy =>
      !isTransfer &&
      category?.categoryType == CategoryType.investment &&
      category?.name == Category.investmentName;

  /// Money that came back from an investment: the opposite of
  /// [isInvestmentBuy]. Into the wallet to invest it already counts there;
  /// into another wallet ([BrokerPayment]) it lowers what was invested.
  bool get isInvestmentSell =>
      !isTransfer &&
      category?.categoryType == CategoryType.investment &&
      category?.name == Category.withdrawalName;

  /// [isInvestmentBuy] or [isInvestmentSell]: its value, as is, is what
  /// went to (negative) or came from (positive) the investments.
  bool get isInvestmentFlow => isInvestmentBuy || isInvestmentSell;

  /// What the wallet to invest gained or lost in a month without an entry
  /// saying why: interest, and what was not entered.
  bool get isAdjustment =>
      category?.categoryType == CategoryType.investment &&
      category?.name == Category.adjustmentName;

  /// Moves money without spending or earning, or repeats a real record: what
  /// income and expense figures leave out.
  bool get isOwnMove =>
      isTransfer ||
      estimateMatch != null ||
      isRefundPair ||
      category?.categoryType == CategoryType.investment;

  /// Part of a purchase paid with a caixinha ([SplitPayment]): a
  /// transfer caixinha → the purchase's wallet, keyed by the purchase's
  /// dinzo_id. Deleted together with the purchase (see SqliteDatabase).
  static const splitPrefix = 'livre:split:';

  bool get isSplitPart => dinzoId?.startsWith(splitPrefix) ?? false;

  /// dinzo_id of the purchase this part belongs to.
  String? get splitParentDinzoId =>
      isSplitPart ? dinzoId!.substring(splitPrefix.length) : null;

  Record copyWith({
    int? id,
    double? value,
    String? title,
    String? description,
    Category? category,
    Set<String>? tags,
    DateTime? utcDateTime,
    String? timeZoneName,
    String? recurrencePatternId,
    int? walletId,
    int? transferWalletId,
    bool? isFutureRecord,
    bool? isDestinationTransferView,
    bool? isSingleSideTransferView,
  }) {
    final copy = Record(
      value ?? this.value,
      title ?? this.title,
      category ?? this.category,
      utcDateTime ?? this.utcDateTime,
      id: id ?? this.id,
      description: description ?? this.description,
      recurrencePatternId: recurrencePatternId ?? this.recurrencePatternId,
      timeZoneName: timeZoneName ?? this.timeZoneName,
      walletId: walletId ?? this.walletId,
      transferWalletId: transferWalletId ?? this.transferWalletId,
      tags: tags ?? this.tags,
      isFutureRecord: isFutureRecord ?? this.isFutureRecord,
      dinzoId: this.dinzoId,
      dinzoSnapshot: this.dinzoSnapshot,
      estimateLink: this.estimateLink,
      refundLink: this.refundLink,
    );
    copy.refundSuggestion = refundSuggestion;
    copy.isDestinationTransferView =
        isDestinationTransferView ?? this.isDestinationTransferView;
    copy.isSingleSideTransferView =
        isSingleSideTransferView ?? this.isSingleSideTransferView;
    copy.paymentCode = paymentCode;
    copy.markedPaid = markedPaid;
    copy.occurrenceUtc = occurrenceUtc;
    copy.dueDateUnknown = dueDateUnknown;
    return copy;
  }

  tz.TZDateTime get localDateTime {
    return createTzDateTime(utcDateTime, timeZoneName!);
  }

  tz.TZDateTime get dateTime => localDateTime;

  /// YYYYMMDD string for grouping/sorting
  String get date {
    return localDateTime.year.toString().padLeft(4, '0') +
        localDateTime.month.toString().padLeft(2, '0') +
        localDateTime.day.toString().padLeft(2, '0');
  }
}
