import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:aupp/components/known-tags.dart';
import 'package:aupp/dinzo/dinzo-sync-service.dart';
import 'package:aupp/helpers/records-utility-functions.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/models/recurrent-record-pattern.dart';
import 'package:aupp/records/edit-record-page.dart';
import 'package:aupp/services/database/database-interface.dart';
import 'package:aupp/services/recurrent-record-service.dart';
import 'package:aupp/services/service-config.dart';
import 'package:aupp/services/transfer-icon-service.dart';

import '../components/category_icon_circle.dart';
import '../models/recurrent-period.dart';
import 'patterns-table.dart';

/// Groups patterns by their effective recurrence: the RecurrentPeriod, plus
/// the custom interval value/unit when the period is [RecurrentPeriod.Custom]
/// (patterns with different custom intervals are shown in separate groups).
class _GroupKey {
  final RecurrentPeriod period;
  final int? customIntervalValue;
  final CustomIntervalUnit? customIntervalUnit;

  const _GroupKey(
    this.period,
    this.customIntervalValue,
    this.customIntervalUnit,
  );

  @override
  bool operator ==(Object other) =>
      other is _GroupKey &&
      other.period == period &&
      other.customIntervalValue == customIntervalValue &&
      other.customIntervalUnit == customIntervalUnit;

  @override
  int get hashCode =>
      Object.hash(period, customIntervalValue, customIntervalUnit);
}

enum _RecurrenceUnitBucket { day, week, month, year }

enum _Filter { all, recurrent, estimates, billing }

/// Classifies a pattern's recurrence into the calendar unit that should drive
/// its subtitle/sort order (e.g. a custom "every 2 weeks" pattern behaves
/// like [RecurrentPeriod.EveryTwoWeeks] for display purposes).
_RecurrenceUnitBucket _unitBucketFor(
  RecurrentPeriod? period,
  CustomIntervalUnit? customUnit,
) {
  switch (period) {
    case RecurrentPeriod.EveryDay:
      return _RecurrenceUnitBucket.day;
    case RecurrentPeriod.EveryWeek:
    case RecurrentPeriod.EveryTwoWeeks:
    case RecurrentPeriod.EveryFourWeeks:
      return _RecurrenceUnitBucket.week;
    case RecurrentPeriod.EveryYear:
      return _RecurrenceUnitBucket.year;
    case RecurrentPeriod.Custom:
      switch (customUnit) {
        case CustomIntervalUnit.day:
          return _RecurrenceUnitBucket.day;
        case CustomIntervalUnit.week:
          return _RecurrenceUnitBucket.week;
        case CustomIntervalUnit.year:
          return _RecurrenceUnitBucket.year;
        case CustomIntervalUnit.month:
        case null:
          return _RecurrenceUnitBucket.month;
      }
    default: // EveryMonth, EveryThreeMonths, EveryFourMonths, null
      return _RecurrenceUnitBucket.month;
  }
}

class PatternsPageView extends StatefulWidget {
  @override
  PatternsPageViewState createState() => PatternsPageViewState();
}

class PatternsPageViewState extends State<PatternsPageView> {
  List<RecurrentRecordPattern>? _recurrentRecordPatterns;
  DatabaseInterface database = ServiceConfig.database;
  _Filter _filter = _Filter.all;

  /// Next occurrence (today or later) of each pattern, by id.
  Map<String, Record> _next = {};

  @override
  void initState() {
    super.initState();
    fetchRecurrentRecordPatternsFromDatabase();
  }

  fetchRecurrentRecordPatternsFromDatabase() async {
    var patterns = await database.getRecurrentRecordPatterns();
    if (!mounted) return;
    setState(() {
      _recurrentRecordPatterns = patterns;
      _next = _nextOccurrences(patterns);
    });
  }

  /// Only computed (nothing is stored): a year ahead covers every period.
  static Map<String, Record> _nextOccurrences(
    List<RecurrentRecordPattern> patterns,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final until = today.add(const Duration(days: 400)).toUtc();
    final service = RecurrentRecordService();
    final next = <String, Record>{};
    for (final p in patterns) {
      if (p.id == null) continue;
      try {
        for (final r in service.generateRecurrentRecordsFromDateTime(
          p,
          until,
        )) {
          final d = r.localDateTime;
          if (!DateTime(d.year, d.month, d.day).isBefore(today)) {
            next[p.id!] = r;
            break;
          }
        }
      } catch (_) {}
    }
    return next;
  }

  static bool _isEstimate(RecurrentRecordPattern p) =>
      p.tags.contains(DinzoSyncService.estimateTag);

  bool _passesFilter(RecurrentRecordPattern p) => _matches(p, _filter);

  static bool _matches(RecurrentRecordPattern p, _Filter filter) {
    switch (filter) {
      case _Filter.all:
        return true;
      case _Filter.recurrent:
        return !_isEstimate(p);
      case _Filter.estimates:
        return _isEstimate(p);
      case _Filter.billing:
        return Record.billingKindOf(p.tags) != null;
    }
  }

  static const _weekdays = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];

  String _dateLabel(DateTime d) =>
      '${_weekdays[d.weekday - 1]}, ${DateFormat('dd/MM/yy').format(d)}';

  String _nextLabel(DateTime d) {
    final now = DateTime.now();
    final days = DateTime(
      d.year,
      d.month,
      d.day,
    ).difference(DateTime(now.year, now.month, now.day)).inDays;
    final when = days == 0
        ? 'hoje'
        : days == 1
        ? 'amanhã'
        : 'em $days dias';
    return 'Próxima: ${_dateLabel(d)} ($when)';
  }

  Color? _amountColor(RecurrentRecordPattern pattern) =>
      getAmountColor(pattern.value ?? 0.0, Theme.of(context).brightness);

  Widget _buildPatternAmountWidget(RecurrentRecordPattern pattern) {
    final color = _amountColor(pattern);
    final style = color != null
        ? _biggerFont.copyWith(color: color)
        : _biggerFont;
    return Text(formatMoney(pattern.value ?? 0.0), style: style);
  }

  final _biggerFont = const TextStyle(fontSize: 18.0);
  final _subtitleFontSize = const TextStyle(fontSize: 14.0);

  String _recurrenceSubtitle(RecurrentRecordPattern pattern) {
    final dt = pattern.localDateTime;
    switch (_unitBucketFor(
      pattern.recurrentPeriod,
      pattern.customIntervalUnit,
    )) {
      case _RecurrenceUnitBucket.day:
        return '';
      case _RecurrenceUnitBucket.week:
        return DateFormat.EEEE().format(DateTime(dt.year, dt.month, dt.day));
      case _RecurrenceUnitBucket.year:
        return DateFormat.MMMd().format(DateTime(dt.year, dt.month, dt.day));
      case _RecurrenceUnitBucket.month:
        return "${'Dia'} ${dt.day}";
    }
  }

  /// Small outlined pill under the title.
  Widget _pill(String text, Color color, {IconData? icon}) {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 0.8),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(text, style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }

  /// When it happens (next date, period, end) and what kind of item it is.
  Widget _buildPatternDetails(RecurrentRecordPattern pattern) {
    final theme = Theme.of(context);
    final dim = theme.textTheme.bodySmall?.color;
    final nextRecord = pattern.id == null ? null : _next[pattern.id];
    final next = nextRecord?.localDateTime;
    final start = pattern.localDateTime;
    final end = pattern.localEndDate;
    final once =
        end != null &&
        !DateTime(
          end.year,
          end.month,
          end.day,
        ).isAfter(DateTime(start.year, start.month, start.day));
    final period = once
        ? 'Uma vez'
        : [
            recurrentPeriodDisplayString(
              pattern.recurrentPeriod,
              customIntervalValue: pattern.customIntervalValue,
              customIntervalUnit: pattern.customIntervalUnit,
            ),
            if (_recurrenceSubtitle(pattern).isNotEmpty)
              _recurrenceSubtitle(pattern).toLowerCase(),
          ].join(', ');
    final lines = [
      next != null
          ? _nextLabel(next)
          : end != null
          ? 'Encerrada em ${_dateLabel(end)}'
          : 'Sem próximas ocorrências',
      [
        period,
        if (!once) 'desde ${DateFormat('dd/MM/yy').format(start)}',
        if (!once && end != null) 'até ${DateFormat('dd/MM/yy').format(end)}',
      ].join(' · '),
    ];

    final billing = Record.billingKindOf(pattern.tags);
    final nextCode = nextRecord == null
        ? null
        : pattern.paymentCodeFor(pattern.occurrenceDayOf(nextRecord));
    final pills = <Widget>[
      if (_isEstimate(pattern))
        _pill('Estimativa', const Color(0xFFF9A825), icon: Icons.query_stats),
      if (billing != null)
        next != null && nextCode == null
            ? _pill(
                '$billing sem código',
                theme.colorScheme.error,
                icon: KnownTag.of(billing)?.icon,
              )
            : _pill(
                billing,
                KnownTag.of(billing)?.color ?? dim!,
                icon: KnownTag.of(billing)?.icon,
              ),
      if (pattern.defaultPix != null && billing == 'Pix')
        _pill('Pix padrão', dim!, icon: Icons.push_pin_outlined),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final l in lines)
          Text(l, style: _subtitleFontSize.copyWith(color: dim)),
        if (pills.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(spacing: 6, runSpacing: 4, children: pills),
          ),
      ],
    );
  }

  Widget _buildRecurrentPatternRow(RecurrentRecordPattern pattern) {
    /// Returns a ListTile rendering the single movement row
    final isTransfer = pattern.transferWalletId != null;
    final isUncategorizedTransfer = isTransfer && pattern.category == null;
    final transferEmoji = TransferIconService.iconEmoji;
    return Container(
      margin: EdgeInsets.only(top: 4, bottom: 4),
      child: ListTile(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  EditRecordPage(passedRecurrentRecordPattern: pattern),
            ),
          );
          await fetchRecurrentRecordPatternsFromDatabase();
        },
        title: Text(
          pattern.title == null || pattern.title!.trim().isEmpty
              ? pattern.category?.name ?? 'Transferência'
              : pattern.title!,
          style: _biggerFont,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: _buildPatternDetails(pattern),
        trailing: _buildPatternAmountWidget(pattern),
        leading: CategoryIconCircle(
          iconEmoji: isUncategorizedTransfer
              ? transferEmoji
              : pattern.category?.iconEmoji,
          iconDataFromDefaultIconSet: isUncategorizedTransfer
              ? TransferIconService.icon
              : pattern.category?.icon ?? Icons.swap_horiz,
          backgroundColor: isUncategorizedTransfer
              ? TransferIconService.color
              : pattern.category?.color,
          topOverlayIcon:
              isTransfer && pattern.category != null && transferEmoji == null
              ? TransferIconService.icon
              : null,
          topOverlayEmoji: isTransfer && pattern.category != null
              ? transferEmoji
              : null,
          topOverlayBackgroundColor: isTransfer && pattern.category != null
              ? TransferIconService.color
              : null,
        ),
      ),
    );
  }

  Map<_GroupKey, List<RecurrentRecordPattern>> _groupPatternsByPeriod() {
    Map<_GroupKey, List<RecurrentRecordPattern>> grouped = {};

    for (var pattern in _recurrentRecordPatterns!.where(_passesFilter)) {
      if (pattern.recurrentPeriod != null) {
        final key = _GroupKey(
          pattern.recurrentPeriod!,
          pattern.customIntervalValue,
          pattern.customIntervalUnit,
        );
        grouped.putIfAbsent(key, () => []).add(pattern);
      }
    }

    for (var entry in grouped.entries) {
      final bucket = _unitBucketFor(
        entry.key.period,
        entry.key.customIntervalUnit,
      );
      entry.value.sort((a, b) {
        final aDate = a.localDateTime;
        final bDate = b.localDateTime;
        switch (bucket) {
          case _RecurrenceUnitBucket.week:
            return aDate.weekday.compareTo(bDate.weekday);
          case _RecurrenceUnitBucket.year:
            final cmp = aDate.month.compareTo(bDate.month);
            return cmp != 0 ? cmp : aDate.day.compareTo(bDate.day);
          case _RecurrenceUnitBucket.day:
          case _RecurrenceUnitBucket.month:
            return aDate.day.compareTo(bDate.day);
        }
      });
    }

    return grouped;
  }

  String _formatGroupSum(List<RecurrentRecordPattern> patterns) => formatMoney(
    patterns.fold<double>(0.0, (sum, p) => sum + (p.value ?? 0.0)),
  );

  Widget _buildGroupHeader(_GroupKey groupKey, String formattedSum) {
    final label = recurrentPeriodDisplayString(
      groupKey.period,
      customIntervalValue: groupKey.customIntervalValue,
      customIntervalUnit: groupKey.customIntervalUnit,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 8, 15, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          Text(
            formattedSum,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.normal),
          ),
        ],
      ),
    );
  }

  /// Recurrent / estimates / boleto or Pix, with how many of each.
  Widget _buildFilters(bool nothingShown) {
    final all = _recurrentRecordPatterns!;
    int count(_Filter f) => all.where((p) => _matches(p, f)).length;

    const labels = {
      _Filter.all: 'Todos',
      _Filter.recurrent: 'Recorrentes',
      _Filter.estimates: 'Estimativas',
      _Filter.billing: 'Boleto / Pix',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(9, 4, 9, 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final f in _Filter.values)
                ChoiceChip(
                  label: Text('${labels[f]} (${count(f)})'),
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
                ),
            ],
          ),
        ),
        if (nothingShown)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('Nenhum item neste filtro.')),
          ),
      ],
    );
  }

  Widget buildRecurrentRecordPatternsList() {
    return _recurrentRecordPatterns != null
        ? new Container(
            margin: EdgeInsets.all(5),
            child: _recurrentRecordPatterns!.length == 0
                ? new Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: new Column(
                          children: <Widget>[
                            Image.asset(
                              'assets/images/no_entry_2.png',
                              width: 200,
                            ),
                            Container(
                              child: Text(
                                'Nenhum Item recorrente ainda.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 22.0),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(6.0),
                    itemCount: _groupPatternsByPeriod().length + 1,
                    itemBuilder: (context, index) {
                      var groupedPatterns = _groupPatternsByPeriod();
                      if (index == 0) {
                        return _buildFilters(groupedPatterns.isEmpty);
                      }
                      var period = groupedPatterns.keys.elementAt(index - 1);
                      var patterns = groupedPatterns[period]!;

                      return Container(
                        margin: const EdgeInsets.fromLTRB(0, 5, 0, 5),
                        child: Column(
                          children: [
                            _buildGroupHeader(
                              period,
                              _formatGroupSum(patterns),
                            ),
                            Divider(thickness: 0.5),
                            ListView.separated(
                              physics: const NeverScrollableScrollPhysics(),
                              shrinkWrap: true,
                              separatorBuilder: (context, index) => Divider(),
                              itemCount: patterns.length,
                              itemBuilder: (context, i) {
                                return _buildRecurrentPatternRow(patterns[i]);
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          )
        : new Container();
  }

  static const _tableViewKey = 'recurrentPatternsTableView';

  /// Spreadsheet (default) or the list with the details of each item.
  bool get _tableView =>
      ServiceConfig.sharedPreferences?.getBool(_tableViewKey) ?? true;

  Future<void> _openPattern(RecurrentRecordPattern pattern) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            EditRecordPage(passedRecurrentRecordPattern: pattern),
      ),
    );
    await fetchRecurrentRecordPatternsFromDatabase();
  }

  @override
  Widget build(BuildContext context) {
    final patterns = _recurrentRecordPatterns;
    final table = _tableView;
    return Scaffold(
      appBar: AppBar(
        title: Text('Itens Recorrentes'),
        actions: [
          IconButton(
            tooltip: table ? 'Ver em lista' : 'Ver em tabela',
            icon: Icon(table ? Icons.view_agenda_outlined : Icons.table_rows),
            onPressed: () async {
              await ServiceConfig.sharedPreferences?.setBool(
                _tableViewKey,
                !table,
              );
              setState(() {});
            },
          ),
        ],
      ),
      body: table && patterns != null && patterns.isNotEmpty
          ? PatternsTable(
              patterns: patterns
                  .where((p) => p.recurrentPeriod != null && _passesFilter(p))
                  .toList(),
              next: _next,
              onOpen: _openPattern,
              top: _buildFilters(false),
            )
          : buildRecurrentRecordPatternsList(),
    );
  }
}
