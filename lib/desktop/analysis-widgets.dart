import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:aupp/investments/fundamentals.dart';

/// Pieces shared by Análise and Comparar: dense text, numbers in columns, and
/// charts by year.

final _ratio = NumberFormat('#,##0.00', 'pt_BR');
final _one = NumberFormat('#,##0.0', 'pt_BR');
final _whole = NumberFormat('#,##0', 'pt_BR');

/// The sign of a currency: "R$", "US$", "€"; the code for the others.
String currencySymbol(String currency) => switch (currency) {
  'BRL' => 'R\$',
  'USD' => 'US\$',
  'EUR' => '€',
  'GBP' => '£',
  'JPY' => '¥',
  'CHF' => 'CHF',
  'TWD' => 'NT\$',
  'HKD' => 'HK\$',
  'CAD' => 'C\$',
  'AUD' => 'A\$',
  _ => currency,
};

/// Without the currency, for the columns of a statement: "548,5 bi".
String amountShort(double value) {
  final sign = value < 0 ? '-' : '';
  final abs = value.abs();
  if (abs >= 1e12) return '$sign${_ratio.format(abs / 1e12)} tri';
  if (abs >= 1e9) return '$sign${_one.format(abs / 1e9)} bi';
  if (abs >= 1e6) return '$sign${_one.format(abs / 1e6)} mi';
  if (abs >= 1e3) return '$sign${_one.format(abs / 1e3)} mil';
  return '$sign${_whole.format(abs)}';
}

/// "R$ 548,5 bi", "US$ 12,3 mi", "-R$ 2,6 bi".
String moneyShort(double value, {String currency = 'BRL'}) {
  final amount = amountShort(value);
  final sign = amount.startsWith('-') ? '-' : '';
  return '$sign${currencySymbol(currency)} ${amount.replaceFirst('-', '')}';
}

/// "R$ 10,38", "€ 211,25".
String pricePerShare(double value, {String currency = 'BRL'}) =>
    '${currencySymbol(currency)} ${_ratio.format(value)}';

String percent(double value) => '${_one.format(value * 100)}%';

String ratio(double value) => _ratio.format(value);

String formatIndicator(
  Indicator indicator,
  double? value, {
  String currency = 'BRL',
}) {
  if (value == null || !value.isFinite) return '—';
  return switch (indicator.format) {
    IndicatorFormat.percent => percent(value),
    IndicatorFormat.ratio => ratio(value),
    IndicatorFormat.money => moneyShort(value, currency: currency),
    IndicatorFormat.perShare => pricePerShare(value, currency: currency),
  };
}

/// Numbers that line up in a column.
const tabular = [FontFeature.tabularFigures()];

TextStyle denseStyle(BuildContext context, {double size = 12.5}) =>
    Theme.of(context).textTheme.bodyMedium!.copyWith(
      fontSize: size,
      height: 1.2,
      fontFeatures: tabular,
    );

TextStyle mutedStyle(BuildContext context, {double size = 11.5}) =>
    denseStyle(context, size: size).copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );

/// A section title with a thin rule, instead of a card.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 30,
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: denseStyle(context, size: 13).copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
                letterSpacing: 0.1,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Width of the right column of the analysis on a wide screen: the thesis on
/// top and the grade below line up in it.
double analysisSideWidth(double width) => (width * 0.4).clamp(460.0, 760.0);

/// A group of the analysis on a soft surface with round corners.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: child,
    );
  }
}

/// A row of label and value that lights up under the mouse.
class HoverRow extends StatefulWidget {
  const HoverRow({super.key, required this.child, this.height = 24});

  final Widget child;
  final double height;

  @override
  State<HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<HoverRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: widget.height,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: _hover
              ? scheme.onSurface.withValues(alpha: 0.06)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: widget.child,
      ),
    );
  }
}

/// A label, quieter than its value.
TextStyle labelStyle(BuildContext context) => denseStyle(
  context,
).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);

/// A value, firmer than its label.
TextStyle valueStyle(BuildContext context) =>
    denseStyle(context).copyWith(fontWeight: FontWeight.w600);

/// A headline number: label above, value below.
class StatCell extends StatelessWidget {
  const StatCell(this.label, this.value, {super.key, this.tooltip});

  final String label;
  final String value;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final cell = Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 18, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: mutedStyle(context, size: 11)),
          Text(
            value,
            style: denseStyle(
              context,
              size: 15,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
    return tooltip == null
        ? cell
        : Tooltip(
            message: tooltip,
            waitDuration: const Duration(milliseconds: 400),
            child: cell,
          );
  }
}

/// Categorical colors in a fixed order (validated for color blindness on
/// adjacent pairs), light and dark steps of the same hues.
const _seriesLight = [
  Color(0xFF2A78D6),
  Color(0xFFEB6834),
  Color(0xFF1BAF7A),
  Color(0xFFEDA100),
  Color(0xFFE87BA4),
  Color(0xFF008300),
  Color(0xFF6250D6),
  Color(0xFFE34948),
];
const _seriesDark = [
  Color(0xFF3987E5),
  Color(0xFFD95926),
  Color(0xFF199E70),
  Color(0xFFC98500),
  Color(0xFFD55181),
  Color(0xFF008300),
  Color(0xFF9085E9),
  Color(0xFFE66767),
];

const maxSeries = 8;

Color seriesColor(BuildContext context, int index) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return (dark ? _seriesDark : _seriesLight)[index % maxSeries];
}

/// A tiny line of a yearly history, no axes.
class Sparkline extends StatelessWidget {
  const Sparkline(this.values, {super.key, this.width = 64, this.height = 16});

  final List<double> values;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: values.length < 2
        ? null
        : CustomPaint(
            painter: _SparkPainter(
              values,
              Theme.of(context).colorScheme.primary,
              Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
  );
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color, this.zero);

  final List<double> values;
  final Color color;
  final Color zero;

  @override
  void paint(Canvas canvas, Size size) {
    final low = math.min(values.reduce(math.min), 0.0);
    final high = math.max(values.reduce(math.max), 0.0);
    final range = high == low ? 1.0 : high - low;
    double x(int i) => i / (values.length - 1) * size.width;
    double y(double v) => 1 + (high - v) / range * (size.height - 2);
    if (low < 0) {
      canvas.drawLine(
        Offset(0, y(0)),
        Offset(size.width, y(0)),
        Paint()
          ..color = zero
          ..strokeWidth = 1,
      );
    }
    final path = Path()..moveTo(x(0), y(values.first));
    for (var i = 1; i < values.length; i++) {
      path.lineTo(x(i), y(values[i]));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(Offset(x(values.length - 1), y(values.last)), 2, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.values != values || old.color != color;
}

/// One series of [YearChart].
class YearSeries {
  final String label;
  final Map<int, double> values;

  const YearSeries(this.label, this.values);
}

/// Values by year: bars side by side, or lines. Hovering a year shows all its
/// values. A legend comes with two series or more.
class YearChart extends StatefulWidget {
  const YearChart({
    super.key,
    required this.series,
    required this.format,
    this.bars = true,
    this.height = 150,
  });

  final List<YearSeries> series;
  final String Function(double value) format;
  final bool bars;
  final double height;

  @override
  State<YearChart> createState() => _YearChartState();
}

class _YearChartState extends State<YearChart> {
  int? _year;

  List<int> get _years {
    final years = <int>{
      for (final s in widget.series) ...s.values.keys,
    }.toList()..sort();
    return years;
  }

  @override
  Widget build(BuildContext context) {
    final years = _years;
    if (years.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: Center(child: Text('Sem dados', style: mutedStyle(context))),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final colors = [
      for (var i = 0; i < widget.series.length; i++) seriesColor(context, i),
    ];
    final chart = LayoutBuilder(
      builder: (context, constraints) {
        final layout = _ChartLayout(years, constraints.maxWidth);
        void hover(Offset at) {
          final year = layout.yearAt(at.dx);
          if (year != _year) setState(() => _year = year);
        }

        return MouseRegion(
          onHover: (event) => hover(event.localPosition),
          onExit: (_) => setState(() => _year = null),
          child: CustomPaint(
            size: Size(constraints.maxWidth, widget.height),
            painter: _YearChartPainter(
              series: widget.series,
              colors: colors,
              layout: layout,
              bars: widget.bars,
              format: widget.format,
              selected: _year,
              surface: scheme.surface,
              grid: scheme.outlineVariant,
              text: mutedStyle(context, size: 10.5),
              tipBackground: scheme.inverseSurface,
              tipText: denseStyle(
                context,
                size: 11.5,
              ).copyWith(color: scheme.onInverseSurface),
            ),
          ),
        );
      },
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.series.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Wrap(
              spacing: 12,
              runSpacing: 2,
              children: [
                for (final (i, s) in widget.series.indexed)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: widget.bars ? 10 : 2,
                        decoration: BoxDecoration(
                          color: colors[i],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(s.label, style: mutedStyle(context)),
                    ],
                  ),
              ],
            ),
          ),
        SizedBox(height: widget.height, child: chart),
      ],
    );
  }
}

class _ChartLayout {
  _ChartLayout(this.years, this.width);

  static const axisWidth = 58.0;
  final List<int> years;
  final double width;

  double get plotWidth => math.max(0, width - axisWidth);
  double get slot => plotWidth / years.length;
  double center(int index) => (index + 0.5) * slot;

  int? yearAt(double x) {
    if (x < 0 || x > plotWidth || years.isEmpty) return null;
    return years[(x / slot).floor().clamp(0, years.length - 1)];
  }
}

class _YearChartPainter extends CustomPainter {
  _YearChartPainter({
    required this.series,
    required this.colors,
    required this.layout,
    required this.bars,
    required this.format,
    required this.selected,
    required this.surface,
    required this.grid,
    required this.text,
    required this.tipBackground,
    required this.tipText,
  });

  final List<YearSeries> series;
  final List<Color> colors;
  final _ChartLayout layout;
  final bool bars;
  final String Function(double) format;
  final int? selected;
  final Color surface;
  final Color grid;
  final TextStyle text;
  final Color tipBackground;
  final TextStyle tipText;

  static const _bottom = 16.0;

  @override
  void paint(Canvas canvas, Size size) {
    final all = [for (final s in series) ...s.values.values];
    if (all.isEmpty) return;
    var low = math.min(all.reduce(math.min), 0.0);
    var high = math.max(all.reduce(math.max), 0.0);
    if (high == low) high = low + 1;
    final plotHeight = size.height - _bottom - 4;
    double y(double v) => 4 + (high - v) / (high - low) * plotHeight;

    TextPainter label(String value, TextStyle style) => TextPainter(
      text: TextSpan(text: value, style: style),
      textDirection: TextDirection.ltr,
    )..layout();

    // Recessive grid: zero, top and bottom, labeled on the right.
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final v in {high, 0.0, low}) {
      canvas.drawLine(
        Offset(0, y(v)),
        Offset(layout.plotWidth, y(v)),
        gridPaint..color = v == 0 ? grid : grid.withValues(alpha: 0.45),
      );
      final painter = label(format(v), text);
      painter.paint(
        canvas,
        Offset(layout.plotWidth + 6, y(v) - painter.height / 2),
      );
    }

    final years = layout.years;
    final step = math.max(1, (years.length / (layout.plotWidth / 36)).ceil());
    for (final (i, year) in years.indexed) {
      if (i % step != 0 && i != years.length - 1) continue;
      final painter = label('$year', text);
      painter.paint(
        canvas,
        Offset(
          layout.center(i) - painter.width / 2,
          size.height - painter.height,
        ),
      );
    }

    if (selected != null) {
      final i = years.indexOf(selected!);
      canvas.drawRect(
        Rect.fromLTWH(i * layout.slot, 0, layout.slot, size.height - _bottom),
        Paint()..color = grid.withValues(alpha: 0.25),
      );
    }

    if (bars) {
      final group = layout.slot * 0.72;
      final width = math.max(2.0, (group - (series.length - 1) * 2) / series.length);
      for (final (si, s) in series.indexed) {
        final paint = Paint()..color = colors[si];
        for (final (i, year) in years.indexed) {
          final v = s.values[year];
          if (v == null) continue;
          final left = layout.center(i) - group / 2 + si * (width + 2);
          final top = math.min(y(v), y(0));
          final bottom = math.max(y(v), y(0));
          // Rounded at the data end, square at the baseline.
          final radius = Radius.circular(math.min(4, width / 2));
          canvas.drawRRect(
            RRect.fromRectAndCorners(
              Rect.fromLTRB(left, top, left + width, math.max(bottom, top + 1)),
              topLeft: v >= 0 ? radius : Radius.zero,
              topRight: v >= 0 ? radius : Radius.zero,
              bottomLeft: v < 0 ? radius : Radius.zero,
              bottomRight: v < 0 ? radius : Radius.zero,
            ),
            paint,
          );
        }
      }
    } else {
      for (final (si, s) in series.indexed) {
        final paint = Paint()
          ..color = colors[si]
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round;
        Path? path;
        for (final (i, year) in years.indexed) {
          final v = s.values[year];
          if (v == null) {
            if (path != null) canvas.drawPath(path, paint);
            path = null;
            continue;
          }
          final point = Offset(layout.center(i), y(v));
          path == null ? path = (Path()..moveTo(point.dx, point.dy)) : path.lineTo(point.dx, point.dy);
        }
        if (path != null) canvas.drawPath(path, paint);
        if (selected != null) {
          final i = years.indexOf(selected!);
          final v = s.values[selected];
          if (v != null) {
            final point = Offset(layout.center(i), y(v));
            canvas.drawCircle(point, 5, Paint()..color = surface);
            canvas.drawCircle(point, 4, Paint()..color = colors[si]);
          }
        }
      }
    }

    if (selected != null) _paintTip(canvas, size, years.indexOf(selected!));
  }

  void _paintTip(Canvas canvas, Size size, int index) {
    final year = layout.years[index];
    final spans = <InlineSpan>[
      TextSpan(
        text: '$year',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ];
    for (final (si, s) in series.indexed) {
      final v = s.values[year];
      spans.add(
        TextSpan(
          children: [
            TextSpan(
              text: '\n■ ',
              style: TextStyle(color: colors[si]),
            ),
            TextSpan(text: '${s.label}  ${v == null ? '—' : format(v)}'),
          ],
        ),
      );
    }
    final tip = TextPainter(
      text: TextSpan(style: tipText, children: spans),
      textDirection: TextDirection.ltr,
    )..layout();
    const padding = 7.0;
    final width = tip.width + padding * 2;
    final height = tip.height + padding * 2;
    final x = layout.center(index);
    final left = x + 14 + width <= layout.plotWidth ? x + 14 : x - 14 - width;
    const top = 2.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(math.max(0.0, left), top, width, height),
        const Radius.circular(6),
      ),
      Paint()..color = tipBackground,
    );
    tip.paint(canvas, Offset(math.max(0.0, left) + padding, top + padding));
  }

  @override
  bool shouldRepaint(_YearChartPainter old) =>
      old.series != series ||
      old.selected != selected ||
      old.bars != bars ||
      old.colors.first != colors.first;
}
