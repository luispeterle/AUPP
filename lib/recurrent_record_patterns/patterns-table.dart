import 'package:aupp/components/category_icon_circle.dart';
import 'package:aupp/components/known-tags.dart';
import 'package:aupp/desktop/desktop-layout.dart';
import 'package:aupp/helpers/records-utility-functions.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/models/recurrent-period.dart';
import 'package:aupp/models/recurrent-record-pattern.dart';
import 'package:aupp/services/transfer-icon-service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

enum _Column { item, next, period, value }

/// The recurrent items as a spreadsheet: one line each, a fixed header that
/// sorts by its column, and the monthly totals at the bottom. On the
/// computer it also shows when each one starts and ends.
class PatternsTable extends StatefulWidget {
  final List<RecurrentRecordPattern> patterns;

  /// Next occurrence (today or later) of each pattern, by id.
  final Map<String, Record> next;
  final void Function(RecurrentRecordPattern) onOpen;

  /// Above the header (the filters).
  final Widget? top;

  const PatternsTable({
    super.key,
    required this.patterns,
    required this.next,
    required this.onOpen,
    this.top,
  });

  @override
  State<PatternsTable> createState() => _PatternsTableState();
}

class _PatternsTableState extends State<PatternsTable> {
  _Column _sort = _Column.next;
  bool _ascending = true;

  static final _day = DateFormat('dd/MM');
  static final _date = DateFormat('dd/MM/yy');

  /// How many times a month it happens, to compare and add up periods.
  static double perMonth(RecurrentRecordPattern p) {
    switch (p.recurrentPeriod) {
      case RecurrentPeriod.EveryDay:
        return 365.25 / 12;
      case RecurrentPeriod.EveryWeek:
        return 365.25 / 12 / 7;
      case RecurrentPeriod.EveryTwoWeeks:
        return 365.25 / 12 / 14;
      case RecurrentPeriod.EveryFourWeeks:
        return 365.25 / 12 / 28;
      case RecurrentPeriod.EveryMonth:
        return 1;
      case RecurrentPeriod.EveryThreeMonths:
        return 1 / 3;
      case RecurrentPeriod.EveryFourMonths:
        return 1 / 4;
      case RecurrentPeriod.EveryYear:
        return 1 / 12;
      case RecurrentPeriod.Custom:
        final n = p.customIntervalValue ?? 0;
        if (n <= 0) return 0;
        switch (p.customIntervalUnit) {
          case CustomIntervalUnit.day:
            return 365.25 / 12 / n;
          case CustomIntervalUnit.week:
            return 365.25 / 12 / 7 / n;
          case CustomIntervalUnit.month:
            return 1 / n;
          case CustomIntervalUnit.year:
            return 1 / 12 / n;
          case null:
            return 0;
        }
      case null:
        return 0;
    }
  }

  /// "Mensal", "Semanal", "A cada 3 meses"…
  static String shortPeriod(RecurrentRecordPattern p) {
    switch (p.recurrentPeriod) {
      case RecurrentPeriod.EveryDay:
        return 'Diário';
      case RecurrentPeriod.EveryWeek:
        return 'Semanal';
      case RecurrentPeriod.EveryTwoWeeks:
        return 'Quinzenal';
      case RecurrentPeriod.EveryFourWeeks:
        return '4 semanas';
      case RecurrentPeriod.EveryMonth:
        return 'Mensal';
      case RecurrentPeriod.EveryThreeMonths:
        return 'Trimestral';
      case RecurrentPeriod.EveryFourMonths:
        return 'Quadrimestral';
      case RecurrentPeriod.EveryYear:
        return 'Anual';
      default:
        return recurrentPeriodDisplayString(
          p.recurrentPeriod,
          customIntervalValue: p.customIntervalValue,
          customIntervalUnit: p.customIntervalUnit,
        );
    }
  }

  static bool _once(RecurrentRecordPattern p) {
    final end = p.localEndDate;
    return end != null &&
        !DateUtils.dateOnly(end).isAfter(DateUtils.dateOnly(p.localDateTime));
  }

  static String _title(RecurrentRecordPattern p) =>
      p.title == null || p.title!.trim().isEmpty
      ? p.category?.name ?? 'Transferência'
      : p.title!;

  static String _tagsKey(RecurrentRecordPattern p) =>
      (p.tags.map((t) => t.toLowerCase()).toList()..sort()).join(',');

  /// A boleto / Pix item whose next occurrence has no code yet.
  bool _missingCode(RecurrentRecordPattern p) {
    final next = p.id == null ? null : widget.next[p.id];
    return Record.billingKindOf(p.tags) != null &&
        next != null &&
        p.paymentCodeFor(p.occurrenceDayOf(next)) == null;
  }

  DateTime? _nextOf(RecurrentRecordPattern p) =>
      p.id == null ? null : widget.next[p.id]?.localDateTime;

  List<RecurrentRecordPattern> get _sorted {
    int compare(RecurrentRecordPattern a, RecurrentRecordPattern b) {
      switch (_sort) {
        case _Column.item:
          // Same tags together (no tags last), then by name.
          final x = _tagsKey(a), y = _tagsKey(b);
          if (x != y) {
            if (x.isEmpty || y.isEmpty) return x.isEmpty ? 1 : -1;
            return x.compareTo(y);
          }
          // Within the same tags, the ones still without a code first.
          final m = (_missingCode(a) ? 0 : 1) - (_missingCode(b) ? 0 : 1);
          if (m != 0) return m;
          return _title(a).toLowerCase().compareTo(_title(b).toLowerCase());
        case _Column.next:
          final x = _nextOf(a), y = _nextOf(b);
          // Ended ones at the bottom either way.
          if (x == null || y == null) {
            return (x == null ? 1 : 0) - (y == null ? 1 : 0);
          }
          return x.compareTo(y);
        case _Column.period:
          return perMonth(b).compareTo(perMonth(a));
        case _Column.value:
          return (a.value ?? 0).abs().compareTo((b.value ?? 0).abs());
      }
    }

    final list = [...widget.patterns];
    list.sort((a, b) => _ascending ? compare(a, b) : compare(b, a));
    return list;
  }

  void _sortBy(_Column column) => setState(() {
    if (_sort == column) {
      _ascending = !_ascending;
    } else {
      _sort = column;
      _ascending = true;
    }
  });

  @override
  Widget build(BuildContext context) {
    final wide = isWideLayout(context);
    final rows = _sorted;
    return Column(
      children: [
        if (widget.top != null) widget.top!,
        _buildHeader(context, wide),
        const Divider(height: 1),
        Expanded(
          child: rows.isEmpty
              ? const Center(child: Text('Nenhum item neste filtro.'))
              : ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, i) =>
                      _buildRow(context, rows[i], i, wide),
                ),
        ),
        const Divider(height: 1),
        _buildTotals(context),
      ],
    );
  }

  Widget _cell(Widget child, int flex, {bool end = false}) => Expanded(
    flex: flex,
    child: Align(
      alignment: end ? Alignment.centerRight : Alignment.centerLeft,
      child: child,
    ),
  );

  Widget _buildHeader(BuildContext context, bool wide) {
    final theme = Theme.of(context);
    Widget head(String label, _Column column, int flex, {bool end = false}) {
      final active = _sort == column;
      return _cell(
        InkWell(
          onTap: () => _sortBy(column),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: active ? theme.colorScheme.primary : null,
                  ),
                ),
                if (active)
                  Icon(
                    _ascending ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
              ],
            ),
          ),
        ),
        flex,
        end: end,
      );
    }

    Widget plain(String label, int flex) => _cell(
      Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
      flex,
    );

    return Container(
      color: theme.colorScheme.surfaceContainerHigh,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          head('Item', _Column.item, wide ? 6 : 5),
          head('Próxima', _Column.next, 3),
          head('Repete', _Column.period, 3),
          if (wide) ...[plain('Início', 2), plain('Fim', 2)],
          head('Valor', _Column.value, 3, end: true),
        ],
      ),
    );
  }

  Widget _buildRow(
    BuildContext context,
    RecurrentRecordPattern p,
    int index,
    bool wide,
  ) {
    final theme = Theme.of(context);
    final dim = theme.colorScheme.onSurfaceVariant;
    final small = theme.textTheme.bodySmall?.copyWith(color: dim);
    final next = _nextOf(p);
    final missingCode = _missingCode(p);
    final isTransfer = p.transferWalletId != null;
    final amountColor = getAmountColor(p.value ?? 0, theme.brightness);

    String? days;
    if (next != null) {
      final d = DateUtils.dateOnly(next)
          .difference(DateUtils.dateOnly(DateTime.now()))
          .inDays;
      days = d == 0
          ? 'hoje'
          : d == 1
          ? 'amanhã'
          : 'em $d dias';
    }

    // Every tag, as in the Extrato: a known one (bank, card, Pix) is its
    // icon, any other a small pill. Boleto / Pix turns red without a code.
    final outline = theme.colorScheme.outlineVariant;
    final markers = <Widget>[
      for (final tag in KnownTag.sortForDisplay(p.tags))
        if (Record.billingTags.contains(tag) && missingCode)
          Tooltip(
            message: '$tag sem código',
            child: Icon(
              KnownTag.of(tag)?.icon ?? Icons.qr_code_2,
              size: 14,
              color: theme.colorScheme.error,
            ),
          )
        else if (KnownTag.of(tag) != null)
          TagLabel(tag, size: 16, textStyle: const TextStyle(fontSize: 10))
        else
          Container(
            height: 16,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: outline, width: 0.8),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(tag, style: const TextStyle(fontSize: 10)),
          ),
      if (p.defaultPix != null)
        Tooltip(
          message: 'Pix padrão',
          child: Icon(Icons.push_pin_outlined, size: 13, color: dim),
        ),
    ];

    return Material(
      color: index.isOdd
          ? theme.colorScheme.surfaceContainerLowest
          : theme.colorScheme.surfaceContainerLow,
      child: InkWell(
        onTap: () => widget.onOpen(p),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              _cell(
                Row(
                  children: [
                    CategoryIconCircle(
                      iconEmoji: isTransfer && p.category == null
                          ? TransferIconService.iconEmoji
                          : p.category?.iconEmoji,
                      iconDataFromDefaultIconSet:
                          isTransfer && p.category == null
                          ? TransferIconService.icon
                          : p.category?.icon ?? Icons.swap_horiz,
                      backgroundColor: isTransfer && p.category == null
                          ? TransferIconService.color
                          : p.category?.color,
                      circleSize: 26,
                      mainIconSize: 14,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _title(p),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                          if (markers.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Wrap(
                                spacing: 5,
                                runSpacing: 3,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: markers,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                wide ? 6 : 5,
              ),
              _cell(
                next == null
                    ? Text('—', style: small)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _day.format(next),
                            style: theme.textTheme.bodyMedium,
                          ),
                          Text(days!, style: small),
                        ],
                      ),
                3,
              ),
              _cell(
                Text(
                  _once(p) ? 'Uma vez' : shortPeriod(p),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
                3,
              ),
              if (wide) ...[
                _cell(Text(_date.format(p.localDateTime), style: small), 2),
                _cell(
                  Text(
                    p.localEndDate == null
                        ? '—'
                        : _date.format(p.localEndDate!),
                    style: small,
                  ),
                  2,
                ),
              ],
              _cell(
                Text(
                  formatMoney((p.value ?? 0).abs()),
                  maxLines: 1,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: amountColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                3,
                end: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// What the shown items add up to in a month (by how often each one
  /// happens), without the ended ones and moves between wallets.
  Widget _buildTotals(BuildContext context) {
    final theme = Theme.of(context);
    var expenses = 0.0;
    var income = 0.0;
    for (final p in widget.patterns) {
      if (p.transferWalletId != null || _nextOf(p) == null || _once(p)) {
        continue;
      }
      final monthly = (p.value ?? 0) * perMonth(p);
      if (monthly < 0) {
        expenses += -monthly;
      } else {
        income += monthly;
      }
    }
    Widget total(String label, double value, Color? color) => Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label, style: theme.textTheme.labelSmall),
        Text(
          formatMoney(value),
          style: theme.textTheme.titleSmall?.copyWith(color: color),
        ),
      ],
    );
    return Container(
      color: theme.colorScheme.surfaceContainerHigh,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Por mês, pelo que se repete',
                style: theme.textTheme.bodySmall,
              ),
            ),
            total('Receitas', income, getAmountColor(1, theme.brightness)),
            const SizedBox(width: 20),
            total('Despesas', expenses, getAmountColor(-1, theme.brightness)),
          ],
        ),
      ),
    );
  }
}
