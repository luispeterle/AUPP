import 'dart:convert';

import 'dart:math' as math;

import 'package:aupp/components/category_icon_circle.dart';
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
/// [Record.estimateLink]. An estimate occurrence stays in the Extrato until it is linked to the real record
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
    builder: (dialogContext) => _EstimateLinkDialog(
      estimate: estimate,
      target: target,
      newName: renames ? name : null,
      inDinzo: inDinzo,
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

const _amber = Color(0xFFF9A825);

/// The two records joined like in the Extrato (icon - link - icon), and
/// what linking does, one line each.
class _EstimateLinkDialog extends StatelessWidget {
  final Record estimate;
  final Record target;

  /// The name the record takes, when linking renames it.
  final String? newName;
  final bool inDinzo;

  const _EstimateLinkDialog({
    required this.estimate,
    required this.target,
    required this.newName,
    required this.inDinzo,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const _LinkBadge(size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Vincular estimativa?', style: text.titleLarge),
                        Text(
                          'É o mesmo dinheiro',
                          style: text.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _RecordCard(estimate, label: 'Estimativa', isEstimate: true),
              // Chain: icon center of the cards is 12 (padding) + 18.
              Padding(
                padding: const EdgeInsets.only(left: 30 - 13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _chainLine(),
                    const _LinkBadge(size: 26),
                    _chainLine(),
                  ],
                ),
              ),
              _RecordCard(target, label: 'Lançamento', newName: newName),
              const SizedBox(height: 18),
              _Effect(Icons.visibility_off_outlined,
                  'A estimativa some do Extrato'),
              if (newName != null)
                _Effect(
                  Icons.drive_file_rename_outline,
                  'O lançamento passa a se chamar "$newName"'
                  '${inDinzo ? ', na Dinzo também' : ''}',
                ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _amber,
                      foregroundColor: Colors.black87,
                    ),
                    onPressed: () => Navigator.pop(context, true),
                    icon: Transform.rotate(
                      angle: math.pi / 2,
                      child: const Icon(Icons.link, size: 18),
                    ),
                    label: const Text('Vincular'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chainLine() => Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Container(width: 2, height: 6, color: _amber),
      );
}

class _LinkBadge extends StatelessWidget {
  final double size;
  const _LinkBadge({required this.size});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration:
            const BoxDecoration(color: _amber, shape: BoxShape.circle),
        child: Transform.rotate(
          angle: math.pi / 2,
          child: Icon(Icons.link, size: size * 0.6, color: Colors.black87),
        ),
      );
}

/// One record as a small card: icon, what it is, name, date and amount.
/// With [newName], the current name shows crossed out above the new one.
class _RecordCard extends StatelessWidget {
  final Record record;
  final String label;
  final bool isEstimate;
  final String? newName;

  const _RecordCard(
    this.record, {
    required this.label,
    this.isEstimate = false,
    this.newName,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final name = record.title?.trim().isNotEmpty == true
        ? record.title!.trim()
        : record.category?.name ?? 'Transferência';
    final category = record.category;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isEstimate
              ? _amber.withValues(alpha: 0.45)
              : scheme.outlineVariant,
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          CategoryIconCircle(
            circleSize: 36,
            mainIconSize: 18,
            overlayIconSize: 13,
            iconEmoji: category?.iconEmoji,
            iconDataFromDefaultIconSet: category?.icon ?? Icons.swap_horiz,
            backgroundColor: category?.color,
            badgeIcon: isEstimate ? Icons.query_stats : null,
            badgeColor: isEstimate ? _amber : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w600,
                    color: isEstimate ? _amber : muted,
                  ),
                ),
                if (newName != null)
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: muted,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                Text(
                  newName ?? name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15),
                ),
                Text(
                  getDateStr(record.dateTime),
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatMoney(record.value ?? 0),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: getRecordAmountColor(
                  record, Theme.of(context).brightness),
            ),
          ),
        ],
      ),
    );
  }
}

/// One thing linking does: an icon and a line of text.
class _Effect extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Effect(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 13.5, color: muted)),
          ),
        ],
      ),
    );
  }
}
