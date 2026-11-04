import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A line or a set of bars over dates.
class TimeSeries {
  final String label;
  final Color color;
  final List<(DateTime, double)> points;

  const TimeSeries(this.label, this.color, this.points);
}

/// Values over dates, read by moving the mouse over it or dragging a finger
/// along it: a guide line and a box with the date and every value follow.
/// The axis keeps a few dates, so years of months stay readable.
class TimeChart extends StatefulWidget {
  const TimeChart({
    super.key,
    required this.series,
    required this.format,
    required this.dateLabel,
    required this.axisLabel,
    this.bars = false,
    this.height = 220,
    this.marks = const [],
    this.area = false,
    this.onSelect,
    this.pinned,
  });

  /// Tapping a date picks it (the same date again lets it go): the caller
  /// shows what is behind it. The picked date stays highlighted ([pinned]).
  final void Function(DateTime? date)? onSelect;
  final DateTime? pinned;

  /// The first line with a fill fading down to the axis.
  final bool area;

  final List<TimeSeries> series;

  /// Dates marked with a dashed vertical line, when inside the chart.
  final List<DateTime> marks;

  /// Bars side by side per date (months); otherwise lines over time.
  final bool bars;
  final String Function(double value) format;

  /// The date in the box ("15/10/2026", "out/2026").
  final String Function(DateTime date) dateLabel;

  /// The date under the axis, shorter.
  final String Function(DateTime date) axisLabel;
  final double height;

  @override
  State<TimeChart> createState() => _TimeChartState();
}

class _TimeChartState extends State<TimeChart> {
  int? _selected;

  List<DateTime> get _dates =>
      ({for (final s in widget.series) for (final p in s.points) p.$1}.toList()
        ..sort());

  void _pick(_Layout layout, double x) {
    final index = layout.indexAt(x);
    if (index != _selected) setState(() => _selected = index);
  }

  void _clear() {
    if (_selected != null) setState(() => _selected = null);
  }

  @override
  Widget build(BuildContext context) {
    final dates = _dates;
    if (dates.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: const Center(child: Text('Sem dados no período')),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme.bodySmall!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.series.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Wrap(
              spacing: 14,
              children: [
                for (final s in widget.series)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: widget.bars ? 10 : 3,
                        decoration: BoxDecoration(
                          color: s.color,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(s.label, style: text),
                    ],
                  ),
              ],
            ),
          ),
        SizedBox(
          height: widget.height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final layout = _Layout(dates, constraints.maxWidth, widget.bars);
              return MouseRegion(
                onHover: (e) => _pick(layout, e.localPosition.dx),
                onExit: (_) => _clear(),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => _pick(layout, d.localPosition.dx),
                  onTapUp: widget.onSelect == null
                      ? null
                      : (d) {
                          final date = dates[layout.indexAt(d.localPosition.dx)];
                          widget.onSelect!(date == widget.pinned ? null : date);
                        },
                  onHorizontalDragStart: (d) =>
                      _pick(layout, d.localPosition.dx),
                  onHorizontalDragUpdate: (d) =>
                      _pick(layout, d.localPosition.dx),
                  child: CustomPaint(
                    size: Size(constraints.maxWidth, widget.height),
                    painter: _TimeChartPainter(
                      series: widget.series,
                      layout: layout,
                      bars: widget.bars,
                      marks: widget.marks,
                      area: widget.area,
                      selected: _selected,
                      pinned: widget.pinned == null
                          ? null
                          : dates.indexOf(widget.pinned!),
                      format: widget.format,
                      dateLabel: widget.dateLabel,
                      axisLabel: widget.axisLabel,
                      grid: scheme.outlineVariant,
                      surface: scheme.surface,
                      text: text.copyWith(
                        fontSize: 10.5,
                        color: scheme.onSurfaceVariant,
                      ),
                      tipBackground: scheme.inverseSurface,
                      tipText: text.copyWith(
                        fontSize: 12,
                        color: scheme.onInverseSurface,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Layout {
  _Layout(this.dates, this.width, this.bars);

  static const axisWidth = 64.0;
  final List<DateTime> dates;
  final double width;
  final bool bars;

  double get plotWidth => math.max(1, width - axisWidth);

  /// Bars: one slot per date. Lines: in proportion to time.
  double x(int index) {
    if (bars) return (index + 0.5) * plotWidth / dates.length;
    if (dates.length < 2) return plotWidth / 2;
    final first = dates.first.millisecondsSinceEpoch;
    final span = dates.last.millisecondsSinceEpoch - first;
    return span == 0
        ? plotWidth / 2
        : (dates[index].millisecondsSinceEpoch - first) / span * plotWidth;
  }

  /// Where a date falls on a time axis; null outside it or with bars.
  double? xOf(DateTime date) {
    if (bars || dates.length < 2) return null;
    if (date.isBefore(dates.first) || date.isAfter(dates.last)) return null;
    final first = dates.first.millisecondsSinceEpoch;
    final span = dates.last.millisecondsSinceEpoch - first;
    return span == 0
        ? null
        : (date.millisecondsSinceEpoch - first) / span * plotWidth;
  }

  int indexAt(double px) {
    var best = 0;
    var distance = double.infinity;
    for (var i = 0; i < dates.length; i++) {
      final d = (x(i) - px).abs();
      if (d < distance) {
        distance = d;
        best = i;
      }
    }
    return best;
  }
}

class _TimeChartPainter extends CustomPainter {
  _TimeChartPainter({
    required this.series,
    required this.layout,
    required this.bars,
    required this.marks,
    this.area = false,
    required this.selected,
    this.pinned,
    required this.format,
    required this.dateLabel,
    required this.axisLabel,
    required this.grid,
    required this.surface,
    required this.text,
    required this.tipBackground,
    required this.tipText,
  });

  final List<TimeSeries> series;
  final _Layout layout;
  final bool bars;
  final List<DateTime> marks;
  final bool area;
  final int? selected;
  final int? pinned;
  final String Function(double) format;
  final String Function(DateTime) dateLabel;
  final String Function(DateTime) axisLabel;
  final Color grid;
  final Color surface;
  final TextStyle text;
  final Color tipBackground;
  final TextStyle tipText;

  static const _bottom = 18.0;

  TextPainter _label(String value, TextStyle style) => TextPainter(
    text: TextSpan(text: value, style: style),
    textDirection: TextDirection.ltr,
  )..layout();

  double? _valueAt(TimeSeries s, DateTime date) {
    for (final p in s.points) {
      if (p.$1 == date) return p.$2;
    }
    return null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final values = [for (final s in series) for (final p in s.points) p.$2];
    var low = values.reduce(math.min);
    var high = values.reduce(math.max);
    if (bars) {
      low = math.min(low, 0);
      high = math.max(high, 0);
    }
    if (high == low) {
      high += 1;
      low -= bars ? 0 : 1;
    }
    final plotHeight = size.height - _bottom - 6;
    double y(double v) => 6 + (high - v) / (high - low) * plotHeight;

    // Recessive grid: top, middle and bottom, labeled on the right.
    final gridPaint = Paint()
      ..color = grid.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (final v in {high, (high + low) / 2, low, if (low < 0 && high > 0) 0.0}) {
      canvas.drawLine(
        Offset(0, y(v)),
        Offset(layout.plotWidth, y(v)),
        gridPaint..color = v == 0 ? grid : grid.withValues(alpha: 0.4),
      );
      final label = _label(format(v), text);
      label.paint(
        canvas,
        Offset(layout.plotWidth + 6, y(v) - label.height / 2),
      );
    }

    // A few dates: as many as fit, evenly spread, the last always there.
    final dates = layout.dates;
    final sample = _label(axisLabel(dates.last), text).width + 16;
    final fit = math.max(2, (layout.plotWidth / sample).floor());
    final step = math.max(1, ((dates.length - 1) / (fit - 1)).ceil());
    var lastRight = -double.infinity;
    for (var i = 0; i < dates.length; i++) {
      if (i % step != 0 && i != dates.length - 1) continue;
      final label = _label(axisLabel(dates[i]), text);
      final left = (layout.x(i) - label.width / 2).clamp(
        0.0,
        layout.plotWidth - label.width,
      );
      if (left < lastRight + 6) continue;
      label.paint(canvas, Offset(left, size.height - label.height));
      lastRight = left + label.width;
    }

    for (final mark in marks) {
      final mx = layout.xOf(mark);
      if (mx == null) continue;
      final dash = Paint()
        ..color = grid
        ..strokeWidth = 1;
      for (var dy = 0.0; dy < size.height - _bottom; dy += 6) {
        canvas.drawLine(Offset(mx, dy), Offset(mx, dy + 3), dash);
      }
    }

    final picked = pinned;
    if (picked != null && picked >= 0) {
      final half = bars ? layout.plotWidth / dates.length / 2 : 6.0;
      canvas.drawRect(
        Rect.fromLTRB(layout.x(picked) - half, 0, layout.x(picked) + half,
            size.height - _bottom),
        Paint()..color = grid.withValues(alpha: 0.35),
      );
    }

    if (bars) {
      final slot = layout.plotWidth / dates.length;
      final group = slot * 0.75;
      final width = math.max(1.0, (group - (series.length - 1)) / series.length);
      for (final (si, s) in series.indexed) {
        final paint = Paint()..color = s.color;
        for (final (i, date) in dates.indexed) {
          final v = _valueAt(s, date);
          if (v == null || v == 0) continue;
          final left = layout.x(i) - group / 2 + si * (width + 1);
          final top = math.min(y(v), y(0));
          final bottom = math.max(y(v), y(0));
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTRB(left, top, left + width, math.max(bottom, top + 1)),
              Radius.circular(math.min(3, width / 2)),
            ),
            paint,
          );
        }
      }
    } else {
      for (final (si, s) in series.indexed) {
        if (s.points.isEmpty) continue;
        final path = Path();
        for (final (i, p) in s.points.indexed) {
          final point = Offset(layout.x(dates.indexOf(p.$1)), y(p.$2));
          i == 0 ? path.moveTo(point.dx, point.dy) : path.lineTo(point.dx, point.dy);
        }
        if (area && si == 0) {
          final bottom = size.height - _bottom;
          final fill = Path.from(path)
            ..lineTo(layout.x(dates.indexOf(s.points.last.$1)), bottom)
            ..lineTo(layout.x(dates.indexOf(s.points.first.$1)), bottom)
            ..close();
          canvas.drawPath(
            fill,
            Paint()
              ..shader = LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  s.color.withValues(alpha: 0.28),
                  s.color.withValues(alpha: 0.0),
                ],
              ).createShader(Rect.fromLTWH(0, 0, size.width, bottom)),
          );
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = s.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..strokeJoin = StrokeJoin.round,
        );
      }
    }

    final index = selected;
    if (index == null || index >= dates.length) return;
    final date = dates[index];
    final cx = layout.x(index);
    canvas.drawLine(
      Offset(cx, 0),
      Offset(cx, size.height - _bottom),
      Paint()
        ..color = grid
        ..strokeWidth = 1,
    );
    final lines = <InlineSpan>[
      TextSpan(
        text: dateLabel(date),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ];
    for (final s in series) {
      final v = _valueAt(s, date);
      if (v == null) continue;
      if (!bars) {
        canvas.drawCircle(Offset(cx, y(v)), 5, Paint()..color = surface);
        canvas.drawCircle(Offset(cx, y(v)), 3.5, Paint()..color = s.color);
      }
      lines.add(
        TextSpan(
          children: [
            TextSpan(text: '\n■ ', style: TextStyle(color: s.color)),
            TextSpan(text: '${s.label}  ${format(v)}'),
          ],
        ),
      );
    }
    final tip = TextPainter(
      text: TextSpan(style: tipText, children: lines),
      textDirection: TextDirection.ltr,
    )..layout();
    const padding = 8.0;
    final boxWidth = tip.width + padding * 2;
    final boxHeight = tip.height + padding * 2;
    // Beside the guide, on the side that fits.
    final left = cx + 12 + boxWidth <= size.width
        ? cx + 12
        : math.max(0.0, cx - 12 - boxWidth);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, 2, boxWidth, boxHeight),
        const Radius.circular(6),
      ),
      Paint()..color = tipBackground,
    );
    tip.paint(canvas, Offset(left + padding, 2 + padding));
  }

  @override
  bool shouldRepaint(_TimeChartPainter old) =>
      old.series != series ||
      old.selected != selected ||
      old.pinned != pinned ||
      old.bars != bars;
}
