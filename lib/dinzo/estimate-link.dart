import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:aupp/dinzo/dinzo-sync-service.dart';
import 'package:aupp/helpers/datetime-utility-functions.dart';
import 'package:aupp/helpers/records-utility-functions.dart';
import 'package:aupp/models/category-type.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/models/recurrent-record-pattern.dart';
import 'package:aupp/services/logger.dart';
import 'package:aupp/services/recurrent-record-service.dart';
import 'package:aupp/services/service-config.dart';

/// A real record linked to an estimate occurrence, kept in
/// [Record.estimateLink]. Estimates no longer vanish when their day comes:
/// an occurrence stays in the Extrato until it is linked to the real record
/// it forecast. Linking consumes the occurrence (it stops showing, and the
/// estimate is deleted once it ends with nothing left) and renames the real
/// record after the estimate, in Dinzo too.
class EstimateLink {
  static final _logger = Logger.withClass(EstimateLink);

  final String patternId;

  /// The occurrence's date, as generated from the pattern.
  final DateTime utcDateTime;
  final String? title;
  final double? value;

  EstimateLink({
    required this.patternId,
    required this.utcDateTime,
    this.title,
    this.value,
  });

  String encode() => jsonEncode({
        'pattern': patternId,
        'at': utcDateTime.millisecondsSinceEpoch,
        'title': title,
        'value': value,
      });

  static EstimateLink? decode(String? json) {
    if (json == null) return null;
    try {
      final m = jsonDecode(json) as Map<String, dynamic>;
      return EstimateLink(
        patternId: m['pattern'] as String,
        utcDateTime: DateTime.fromMillisecondsSinceEpoch(
          m['at'] as int,
          isUtc: true,
        ),
        title: m['title'] as String?,
        value: (m['value'] as num?)?.toDouble(),
      );
    } catch (_) {
      return null;
    }
  }

  /// An occurrence of an estimate shown in a list (never stored).
  static bool isOccurrence(Record r) =>
      r.isFutureRecord &&
      r.id == null &&
      r.recurrencePatternId != null &&
      r.tags.contains(DinzoSyncService.estimateTag);

  /// Whether [a] and [b] are the same estimate occurrence.
  static bool sameOccurrence(Record? a, Record? b) =>
      a != null &&
      b != null &&
      a.recurrencePatternId == b.recurrencePatternId &&
      a.occurrenceIdUtc.isAtSameMomentAs(b.occurrenceIdUtc);

  /// Whether [r] can be what an estimate forecast. A record made by the app,
  /// like the food allowance, counts; what only moves money does not.
  static bool canBeLinked(Record r) =>
      !r.isFutureRecord &&
      r.id != null &&
      !r.isSplitPart &&
      r.category?.categoryType != CategoryType.investment;

  /// Pairs each estimate occurrence in [records] with a real record of the
  /// same day and the same amount, one to one ([Record.estimateMatch]). The
  /// pair is the same money: only the real record counts, and the user is
  /// offered to link them.
  static void markMatches(Iterable<Record?> records) {
    final real = <String, List<Record>>{};
    final occurrences = <Record>[];
    String key(Record r) {
      final d = r.dateTime;
      return '${d.year}-${d.month}-${d.day}|${(r.value ?? 0).toStringAsFixed(2)}';
    }

    for (final r in records.whereType<Record>()) {
      if (isOccurrence(r)) {
        r.estimateMatch = null;
        if (!r.isTransfer) occurrences.add(r);
      } else if (canBeLinked(r) && !r.isTransfer && r.estimateLink == null) {
        (real[key(r)] ??= []).add(r);
      }
    }
    for (final occurrence in occurrences) {
      final candidates = real[key(occurrence)];
      if (candidates == null || candidates.isEmpty) continue;
      occurrence.estimateMatch = candidates.removeAt(0);
    }
  }

  /// Occurrence dates (UTC millis) already linked, per pattern id.
  static Future<Map<String, Set<int>>> linkedOccurrences() async {
    final linked = <String, Set<int>>{};
    for (final json in await ServiceConfig.database.getEstimateLinks()) {
      final link = decode(json);
      if (link == null) continue;
      (linked[link.patternId] ??= {})
          .add(link.utcDateTime.millisecondsSinceEpoch);
    }
    return linked;
  }

  static List<Record> withoutLinked(
    Iterable<Record> occurrences,
    Map<String, Set<int>> linked,
  ) =>
      occurrences
          .where((r) => !(linked[r.recurrencePatternId]
                  ?.contains(r.occurrenceIdUtc.millisecondsSinceEpoch) ??
              false))
          .toList();

  /// Deletes [pattern] when it has an end and all its occurrences up to it
  /// are linked (or were consumed before links existed). True if deleted.
  static Future<bool> deleteIfDone(
    RecurrentRecordPattern pattern,
    Map<String, Set<int>> linked,
  ) async {
    final end = pattern.utcEndDate;
    if (end == null) return false;
    final left = withoutLinked(
      RecurrentRecordService()
          .generateRecurrentRecordsFromDateTime(pattern, end),
      linked,
    );
    if (left.isNotEmpty) return false;
    await ServiceConfig.database.deleteRecurrentRecordPatternById(pattern.id);
    _logger.info('Estimate "${pattern.title}" done, deleted');
    return true;
  }

  /// Links the [estimate] occurrence to the real record [recordId]: stores
  /// the link, renames the record after the estimate (Dinzo too) and deletes
  /// the estimate when nothing is left of it. False when the rename didn't
  /// reach Dinzo (the link itself is saved).
  static Future<bool> link(Record estimate, int recordId) async {
    final db = ServiceConfig.database;
    final target = await db.getRecordById(recordId);
    if (target == null) return true;
    target.estimateLink = EstimateLink(
      patternId: estimate.recurrencePatternId!,
      utcDateTime: estimate.occurrenceIdUtc,
      title: estimate.title,
      value: estimate.value,
    ).encode();
    final title = estimate.title?.trim();
    final rename = title != null && title.isNotEmpty && title != target.title;
    if (rename) target.title = title;
    await db.updateRecordById(target.id, target);
    _logger.info(
      'Estimate "${estimate.title}" (${estimate.utcDateTime}) linked to '
      'record $recordId',
    );

    final pattern =
        await db.getRecurrentRecordPattern(estimate.recurrencePatternId);
    if (pattern != null) await deleteIfDone(pattern, await linkedOccurrences());

    if (rename &&
        target.dinzoId != null &&
        !DinzoSyncService.isSynthetic(target.dinzoId)) {
      try {
        await DinzoSyncService.pushTitle(target);
      } catch (e, st) {
        _logger.handle(e, st, 'Failed to rename record $recordId in Dinzo');
        return false;
      }
    }
    return true;
  }
}

/// Asks before linking [estimate] to the real record [target], and links.
/// True when it was linked.
Future<bool> confirmEstimateLink(
  BuildContext context,
  Record estimate,
  Record target,
) async {
  final name = estimate.title?.trim().isNotEmpty == true
      ? estimate.title!.trim()
      : null;
  final renames = name != null && name != target.title;
  final inDinzo =
      target.dinzoId != null && !DinzoSyncService.isSynthetic(target.dinzoId);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Vincular estimativa?'),
      content: Text(
        'Estimativa: ${estimate.title ?? estimate.category?.name ?? ''}, '
        '${getDateStr(estimate.dateTime)}, '
        '${getCurrencyValueString(estimate.value)}\n'
        'Lançamento: ${target.title ?? target.category?.name ?? ''}, '
        '${getDateStr(target.dateTime)}, '
        '${getCurrencyValueString(target.value)}\n\n'
        'A estimativa some do Extrato'
        '${renames ? ' e o lançamento passa a se chamar "$name"${inDinzo ? ' (na Dinzo também)' : ''}' : ''}.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Vincular'),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;
  final dinzoOk = await EstimateLink.link(estimate, target.id!);
  messenger?.showSnackBar(
    SnackBar(
      content: Text(
        dinzoOk
            ? 'Estimativa vinculada'
            : 'Estimativa vinculada; não foi renomeado na Dinzo',
      ),
    ),
  );
  return true;
}
