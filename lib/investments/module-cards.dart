import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:aupp/components/time-chart.dart';
import 'package:aupp/helpers/records-utility-functions.dart';

import 'selic-comparison.dart';

// The cards Nacional, Internacional and Cripto share, so that the three tabs
// open alike: total, Rendimento × Selic, Evolução, Divisão, then what is only
// theirs.

String _money(double value) => getCurrencyValueString(value);

String _pct(double value) => '${NumberFormat('0.0', 'pt_BR').format(value)}%';

/// What the module holds over time, in reais.
class EvolutionCard extends StatelessWidget {
  const EvolutionCard({super.key, required this.points, this.info});

  /// Already cut to the period shown, oldest first.
  final List<(DateTime, double)> points;
  final String? info;

  static const color = SelicComparison.portfolioColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final span = points.length < 2
        ? 0
        : points.last.$1.difference(points.first.$1).inDays;
    // The day only fits while the period spans a few months.
    final axis = span <= 92 ? DateFormat('dd/MM') : DateFormat('MM/yy');
    final day = DateFormat('dd/MM/yy');
    return InvestmentCard(
      title: 'Evolução',
      info: info,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (points.isNotEmpty)
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: _money(points.last.$2),
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextSpan(
                    text: '  ${day.format(points.last.$1)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          points.length < 2
              ? const SizedBox(
                  height: 220,
                  child: Center(child: Text('Sem saldo registrado no período')),
                )
              : TimeChart(
                  series: [TimeSeries('Saldo', color, points)],
                  format: _money,
                  dateLabel: day.format,
                  axisLabel: axis.format,
                ),
        ],
      ),
    );
  }
}

/// One part of [DivisionCard].
class DivisionSlice {
  final String key;
  final String label;
  final double value;

  const DivisionSlice(this.key, this.label, this.value);
}

/// One class of the portfolio in a [DivisionCard]: its parts and its target.
class DivisionGroup {
  final String label;
  final List<DivisionSlice> slices;

  /// Percent of the portfolio this class should have; 0 when not set.
  final double target;

  const DivisionGroup(this.label, this.slices, this.target);

  double get total => slices.fold(0.0, (sum, s) => sum + s.value);
}

/// How the module is split, class by class: one colour per asset, and beside
/// each class its share of the portfolio and its target (Carteira e aporte →
/// Metas), just the numbers. Classes are never added together.
class DivisionCard extends StatelessWidget {
  const DivisionCard({super.key, required this.groups, required this.portfolio});

  /// Classes with nothing held and no target are left out.
  final List<DivisionGroup> groups;

  /// The whole portfolio of Carteira e aporte, in reais.
  final double portfolio;

  static const palette = [
    Color(0xFF76B900),
    Color(0xFF00A4EF),
    Color(0xFFE5A000),
    Color(0xFFD94F70),
    Color(0xFF8E6CEF),
    Color(0xFF26A69A),
    Color(0xFFEF6C00),
    Color(0xFF5C6BC0),
  ];

  /// The colour of each part, biggest first, the same in the positions below
  /// the card.
  static Map<String, Color> colorsOf(Iterable<DivisionSlice> slices) {
    final sorted = [
      for (final s in slices)
        if (s.value > 0) s,
    ]..sort((a, b) => b.value.compareTo(a.value));
    return {
      for (final (i, s) in sorted.indexed) s.key: palette[i % palette.length],
    };
  }

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final g in groups)
        if (g.total > 0 || g.target > 0) g,
    ];
    if (shown.every((g) => g.total <= 0)) return const SizedBox.shrink();
    final colors = colorsOf([for (final g in shown) ...g.slices]);
    return InvestmentCard(
      title: 'Divisão',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, g) in shown.indexed) ...[
            if (i > 0) const Divider(height: 28),
            _group(context, g, colors, titled: shown.length > 1),
          ],
        ],
      ),
    );
  }

  Widget _group(
    BuildContext context,
    DivisionGroup group,
    Map<String, Color> colors, {
    required bool titled,
  }) {
    final theme = Theme.of(context);
    final parts = [
      for (final s in group.slices)
        if (s.value > 0) s,
    ]..sort((a, b) => b.value.compareTo(a.value));
    final total = group.total;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    // "23% · meta 30%": where the class is and where it should be.
    final share = group.target > 0 && portfolio > 0
        ? Text(
            '${_pct(total / portfolio * 100)} · meta ${_number(group.target)}%',
            style: muted,
          )
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (titled) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  group.label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (share != null) ...[share, const SizedBox(width: 10)],
              Text(_money(total), style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
        ] else if (share != null) ...[
          Align(alignment: Alignment.centerRight, child: share),
          const SizedBox(height: 6),
        ],
        // One asset fills the bar by itself: the legend says it all.
        if (parts.length > 1) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  for (final s in parts)
                    Expanded(
                      flex: math.max(1, (s.value / total * 1000).round()),
                      child: Container(color: colors[s.key]),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (parts.isNotEmpty)
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              for (final s in parts)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: colors[s.key],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      parts.length > 1
                          ? '${s.label} ${_pct(s.value / total * 100)}'
                          : s.label,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
            ],
          ),
      ],
    );
  }

  static String _number(double v) =>
      NumberFormat('0.#', 'pt_BR').format(v);
}

/// One position, the same in the three tabs: what it is, its quote, and the
/// figures below (quantity, value, result, share).
class PositionCard extends StatelessWidget {
  const PositionCard({
    super.key,
    required this.color,
    required this.logo,
    required this.title,
    this.subtitle,
    this.badge,
    required this.price,
    this.changePct,
    required this.figures,
    this.onTap,
    this.action,
    this.warning,
  });

  /// The asset's colour in the Divisão.
  final Color color;
  final Widget logo;
  final String title;
  final String? subtitle;

  /// Next to the title, e.g. the class when it is not the tab's main one.
  final Widget? badge;
  final String price;

  /// Today's change, when known.
  final double? changePct;
  final List<(String, Widget)> figures;
  final VoidCallback? onTap;

  /// At the end of the figures, e.g. remove.
  final Widget? action;
  final String? warning;

  /// A figure in bold, the way the cards show them.
  static Widget bold(String text, {Color? color}) => Text(
    text,
    style: TextStyle(fontWeight: FontWeight.w700, color: color),
  );

  /// A result in percent: green up, red down; "—" when unknown.
  static Widget result(BuildContext context, double? pct, {String? note}) {
    if (pct == null) return const Text('—');
    return bold(
      '${pct >= 0 ? '+' : ''}${_pct(pct)}${note ?? ''}',
      color: pct >= 0
          ? const Color(0xFF43A047)
          : Theme.of(context).colorScheme.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: color, width: 4)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  logo,
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                title,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            if (badge != null) ...[
                              const SizedBox(width: 6),
                              badge!,
                            ],
                          ],
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      bold(price),
                      ?_change(context, changePct),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (final (label, value) in figures)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label, style: theme.textTheme.bodySmall),
                          const SizedBox(height: 2),
                          value,
                        ],
                      ),
                    ),
                  ?action,
                ],
              ),
              if (warning != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    warning!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget? _change(BuildContext context, double? pct) {
    if (pct == null) return null;
    final up = pct >= 0;
    final color = up
        ? const Color(0xFF43A047)
        : Theme.of(context).colorScheme.error;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          up ? Icons.arrow_drop_up : Icons.arrow_drop_down,
          color: color,
          size: 20,
        ),
        Text(
          _pct(pct.abs()),
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// The positions of a tab: a title, an optional button, and the cards, two
/// side by side on a wide screen.
class PositionsSection extends StatelessWidget {
  const PositionsSection({
    super.key,
    required this.cards,
    this.title = 'Posições',
    this.action,
    this.empty,
  });

  final List<Widget> cards;
  final String title;
  final Widget? action;

  /// Shown when there are no cards.
  final Widget? empty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final width = wide
              ? (constraints.maxWidth - 12) / 2
              : constraints.maxWidth;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
                  ?action,
                ],
              ),
              const SizedBox(height: 8),
              if (cards.isEmpty)
                ?empty
              else
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final card in cards) SizedBox(width: width, child: card),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}
