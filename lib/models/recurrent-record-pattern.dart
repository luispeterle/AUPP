import 'dart:convert';

import 'package:aupp/dinzo/pix-code.dart';
import 'package:aupp/models/category.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/services/service-config.dart';
import 'package:timezone/timezone.dart' as tz;

import '../helpers/datetime-utility-functions.dart';
import 'recurrent-period.dart';

class RecurrentRecordPattern {
  String? id;
  double? value;
  String? title;
  String? description;
  Category? category;
  DateTime utcDateTime;
  DateTime? utcEndDate;
  String? timeZoneName;
  RecurrentPeriod? recurrentPeriod;
  DateTime? utcLastUpdate;
  Set<String> tags = {};

  /// Fork: payment code (Pix copia-e-cola or boleto digitable line) of each
  /// estimate occurrence, by its local date ([occurrenceKey]): this month's
  /// boleto is not next month's. Column `payment_codes` (JSON), in backups.
  Map<String, String> paymentCodes = {};

  /// Entries of [paymentCodes] that are not dates: the recurrence's default
  /// Pix (a key, or a whole copia-e-cola) and the name for a key's code. An
  /// older app only looks up dates, so it ignores them.
  static const defaultPixKey = 'pix:padrao';
  static const pixNameKey = 'pix:nome';

  String? get defaultPix => paymentCodes[defaultPixKey];

  /// "Já paguei" on one occurrence, while its real record has not come from
  /// the Dinzo yet: no more alerts. Linking it later works as always.
  static String paidKey(DateTime local) => 'pago:${occurrenceKey(local)}';

  bool isMarkedPaid(DateTime local) => paymentCodes.containsKey(paidKey(local));

  void setMarkedPaid(DateTime local, bool paid) {
    if (paid) {
      paymentCodes[paidKey(local)] = '1';
    } else {
      paymentCodes.remove(paidKey(local));
    }
  }

  /// Happens on one day only (a one-off estimate, or an occurrence edited
  /// into an item of its own): it ends on the day it starts.
  bool get happensOnce {
    final end = localEndDate;
    if (end == null) return false;
    final start = localDateTime;
    return !DateTime(end.year, end.month, end.day)
        .isAfter(DateTime(start.year, start.month, start.day));
  }

  /// One occurrence taken out of the recurrence: edited by hand, it became an
  /// item of its own ([RecurrentRecordService.saveOccurrence]), or it was
  /// deleted alone. Keyed by the recurrence's day, like codes and marks.
  static String skipKey(DateTime local) => 'pular:${occurrenceKey(local)}';

  bool isSkipped(DateTime local) => paymentCodes.containsKey(skipKey(local));

  void skip(DateTime local) => paymentCodes[skipKey(local)] = '1';

  /// Moves what belongs to the occurrence on [from] (its code, "Já paguei"
  /// mark and Pix charge amount) to [to] on the item [target] made from it.
  /// Its day is now set by hand, so a code there counts as checked.
  void moveOccurrenceTo(
      RecurrentRecordPattern target, DateTime from, DateTime to) {
    final code = paymentCodes.remove(occurrenceKey(from));
    final paid = paymentCodes.remove(paidKey(from));
    final charge = paymentCodes.remove(chargeValueKey(from));
    paymentCodes.remove(dueKey(from));
    if (code != null) {
      target.paymentCodes[occurrenceKey(to)] = code;
      target.setDueDate(to, to);
    }
    if (paid != null) target.paymentCodes[paidKey(to)] = paid;
    if (charge != null) target.paymentCodes[chargeValueKey(to)] = charge;
  }

  /// The code of the occurrence on [local]: its own, else the default Pix
  /// (a key becomes a copia-e-cola with the occurrence's amount).
  String? paymentCodeFor(DateTime local) {
    final own = paymentCodes[occurrenceKey(local)];
    if (own != null) return own;
    final pix = defaultPix;
    if (pix == null || pix.trim().isEmpty) return null;
    if (PixCode.isPayload(pix)) return pix.trim();
    return PixCode.build(
      key: pix,
      name: paymentCodes[pixNameKey],
      amount: value?.abs(),
    );
  }

  /// Amount computed elsewhere for an occurrence (the company's taxes of
  /// the month before), without sign; null when there is none. Set once at
  /// startup by FiscalEstimates.
  static double? Function(RecurrentRecordPattern pattern, DateTime local)?
      computedValue;

  /// The amount of the occurrence on [local]: what its own code asks for
  /// (the water bill's boleto), else a computed one ([computedValue]), else
  /// the recurrence's average. Only that occurrence changes; the recurrence
  /// keeps its value.
  double? valueFor(DateTime local) {
    final own = paymentCodes[occurrenceKey(local)];
    if (own == null && transferWalletId == null) {
      final computed = computedValue?.call(this, local);
      if (computed != null) {
        return (value ?? -1) < 0 ? -computed : computed;
      }
    }
    final amount = own == null
        ? null
        : PixCode.amountOf(own) ??
              double.tryParse(paymentCodes[chargeValueKey(local)] ?? '');
    if (amount == null || value == null || transferWalletId != null) {
      return value;
    }
    return value! < 0 ? -amount : amount;
  }

  /// Amount of a Pix charge pasted on one occurrence, read from the
  /// receiver's bank when it was pasted ([PixCharge]): the code itself has
  /// none, and the bank may not answer later.
  static String chargeValueKey(DateTime local) =>
      'valor:${occurrenceKey(local)}';

  /// Due date of one occurrence, from its Pix charge or boleto, when it is
  /// not the recurrence's day: the occurrence shows on that day. It keeps
  /// its key ([occurrenceKey] of the recurrence's day) for codes and marks.
  static String dueKey(DateTime local) => 'data:${occurrenceKey(local)}';

  DateTime? dueDateFor(DateTime local) {
    final due = paymentCodes[dueKey(local)];
    return due == null ? null : DateTime.tryParse(due);
  }

  /// Kept even on the recurrence's own day: it says the date was checked.
  void setDueDate(DateTime local, DateTime? due) {
    if (due == null) {
      paymentCodes.remove(dueKey(local));
    } else {
      paymentCodes[dueKey(local)] = occurrenceKey(due);
    }
  }

  /// The occurrence got its own code, but no due date came with it (nor was
  /// one set by hand): its day may still be the recurrence's average one.
  bool dueDateMissing(DateTime local) =>
      paymentCodes.containsKey(occurrenceKey(local)) &&
      !paymentCodes.containsKey(dueKey(local));

  /// The recurrence's day of [r] (what keys its codes and marks): the
  /// generated date, else the day a due date moved it from, else its date.
  DateTime occurrenceDayOf(Record r) {
    if (r.occurrenceUtc != null) {
      return createTzDateTime(r.occurrenceUtc!, timeZoneName!);
    }
    final shown = occurrenceKey(r.localDateTime);
    for (final e in paymentCodes.entries) {
      if (e.key.startsWith('data:') && e.value == shown) {
        final day = DateTime.tryParse(e.key.substring(5));
        if (day != null) return day;
      }
    }
    return r.localDateTime;
  }

  static String occurrenceKey(DateTime local) =>
      '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
  int? walletId;
  int? transferWalletId;
  double? transferValue;
  // Only meaningful when recurrentPeriod == RecurrentPeriod.Custom.
  int? customIntervalValue;
  CustomIntervalUnit? customIntervalUnit;

  RecurrentRecordPattern(this.value, this.title, this.category,
      this.utcDateTime, this.recurrentPeriod,
      {this.id,
      this.description,
      this.utcEndDate,
      this.utcLastUpdate,
      this.timeZoneName,
      this.walletId,
      this.transferWalletId,
      this.transferValue,
      this.customIntervalValue,
      this.customIntervalUnit,
      Set<String>? tags}) {
    if (timeZoneName == null) {
      timeZoneName = ServiceConfig.localTimezone;
    }
    if (tags != null) {
      this.tags = tags;
    }
  }

  RecurrentRecordPattern.fromRecord(
    Record record,
    this.recurrentPeriod, {
    this.id,
    this.utcEndDate,
    this.customIntervalValue,
    this.customIntervalUnit,
  })  : value = record.value,
        title = record.title,
        category = record.category,
        utcDateTime = record.utcDateTime,
        description = record.description,
        timeZoneName = record.timeZoneName,
        walletId = record.walletId,
        transferWalletId = record.transferWalletId,
        transferValue = record.transferValue,
        tags = record.tags;

  /// Serialize to database
  Map<String, dynamic> toMap() {
    final map = {
      'title': title,
      'value': value,
      'datetime': utcDateTime.millisecondsSinceEpoch,
      'timezone': timeZoneName,
      'category_name': category?.name,
      'category_type': category?.categoryType?.index,
      'description': description,
      'recurrent_period': recurrentPeriod?.index,
      'last_update': utcLastUpdate?.millisecondsSinceEpoch,
      'tags': tags.where((t) => t.trim().isNotEmpty).join(','),
      'end_date': utcEndDate?.millisecondsSinceEpoch,
      'wallet_id': walletId,
      'transfer_wallet_id': transferWalletId,
      'transfer_value': transferValue,
      'custom_interval_value': customIntervalValue,
      'custom_interval_unit': customIntervalUnit?.index,
      'payment_codes': paymentCodes.isEmpty ? null : jsonEncode(paymentCodes),
    };
    if (id != null) map['id'] = id;
    return map;
  }

  /// Deserialize from database
  static RecurrentRecordPattern fromMap(Map<String, dynamic> map) {
    final int? utcMillis = map['datetime'];
    final utcDateTime =
        DateTime.fromMillisecondsSinceEpoch(utcMillis!, isUtc: true);

    String? timezone = map['timezone'];
    if (timezone == null) {
      timezone = ServiceConfig.localTimezone;
    }

    DateTime? utcLastUpdate;
    final int? lastUpdateMillis = map['last_update'];
    if (lastUpdateMillis != null) {
      utcLastUpdate =
          DateTime.fromMillisecondsSinceEpoch(lastUpdateMillis, isUtc: true);
    }

    DateTime? utcEndDate;
    final int? endDateMillis = map['end_date'];
    if (endDateMillis != null) {
      utcEndDate =
          DateTime.fromMillisecondsSinceEpoch(endDateMillis, isUtc: true);
    }

    Set<String> tags = map['tags'] != null
        ? (map['tags'] as String)
            .split(',')
            .where((t) => t.trim().isNotEmpty)
            .toSet()
        : {};

    final int? customIntervalUnitIndex = map['custom_interval_unit'] as int?;

    return RecurrentRecordPattern(
      map['value'],
      map['title'],
      map['category'],
      utcDateTime,
      RecurrentPeriod.values[map['recurrent_period']],
      id: map['id'],
      description: map['description'],
      utcEndDate: utcEndDate,
      utcLastUpdate: utcLastUpdate,
      timeZoneName: timezone,
      walletId: map['wallet_id'] as int?,
      transferWalletId: map['transfer_wallet_id'] as int?,
      transferValue: (map['transfer_value'] as num?)?.toDouble(),
      customIntervalValue: map['custom_interval_value'] as int?,
      customIntervalUnit: customIntervalUnitIndex != null
          ? CustomIntervalUnit.values[customIntervalUnitIndex]
          : null,
      tags: tags,
    )..paymentCodes = _decodeCodes(map['payment_codes']);
  }

  static Map<String, String> _decodeCodes(Object? raw) {
    if (raw is! String || raw.isEmpty) return {};
    try {
      return {
        for (final e in (jsonDecode(raw) as Map).entries)
          if (e.value is String) e.key as String: e.value as String,
      };
    } catch (_) {
      return {};
    }
  }

  tz.TZDateTime get localDateTime {
    return createTzDateTime(utcDateTime, timeZoneName!);
  }

  tz.TZDateTime? get localEndDate {
    if (utcEndDate == null) return null;
    return createTzDateTime(utcEndDate!, timeZoneName!);
  }
}
