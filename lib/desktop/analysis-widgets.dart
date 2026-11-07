import 'dart:async';
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
    Theme.of(context).textTheme.bodyMedium!
        .copyWith(fontSize: size, height: 1.2, fontFeatures: tabular);

TextStyle mutedStyle(BuildContext context, {double size = 11.5}) => denseStyle(
  context,
  size: size,
).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);

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
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
        ),
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
TextStyle labelStyle(BuildContext context) =>
    denseStyle(context)
        .copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);

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
    canvas.drawCircle(
      Offset(x(values.length - 1), y(values.last)),
      2,
      Paint()..color = color,
    );
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
    this.barValues = false,
  });

  final List<YearSeries> series;
  final String Function(double value) format;
  final bool bars;
  final double height;

  /// Each bar's value written along it, inside when it fits.
  final bool barValues;

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
              barValues: widget.barValues,
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

/// Round values from below [low] to above [high], about six of them,
/// 1, 2, 2.5 or 5 times a power of ten apart; zero among them when the range
/// crosses it.
List<double> niceTicks(double low, double high, {int count = 6}) {
  if (high <= low) high = low + 1;
  final rough = (high - low) / (count - 1);
  final magnitude = math
      .pow(10, (math.log(rough) / math.ln10).floor())
      .toDouble();
  final step =
      magnitude *
      switch (rough / magnitude) {
        <= 1 => 1.0,
        <= 2 => 2.0,
        <= 2.5 => 2.5,
        <= 5 => 5.0,
        _ => 10.0,
      };
  final first = (low / step).floor();
  final last = (high / step).ceil();
  return [for (var i = first; i <= last; i++) i * step];
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
    required this.barValues,
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
  final bool barValues;
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
    final ticks = niceTicks(
      math.min(all.reduce(math.min), 0.0),
      math.max(all.reduce(math.max), 0.0),
    );
    final low = ticks.first;
    final high = ticks.last;
    final plotHeight = size.height - _bottom - 4;
    double y(double v) => 4 + (high - v) / (high - low) * plotHeight;

    TextPainter label(String value, TextStyle style) => TextPainter(
      text: TextSpan(text: value, style: style),
      textDirection: TextDirection.ltr,
    )..layout();

    // Recessive grid at round values, labeled on the right; zero firmer.
    final gridPaint = Paint()..strokeWidth = 1;
    for (final v in ticks) {
      canvas.drawLine(
        Offset(0, y(v)),
        Offset(layout.plotWidth, y(v)),
        gridPaint..color = v == 0 ? grid : grid.withValues(alpha: 0.35),
      );
      final painter = label(format(v), text);
      painter.paint(
        canvas,
        Offset(layout.plotWidth + 6, y(v) - painter.height / 2),
      );
    }

    final years = layout.years;
    // A faint line between years, to find one along the axis.
    final yearLine = Paint()
      ..color = grid.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    for (var i = 1; i < years.length; i++) {
      final x = i * layout.slot;
      canvas.drawLine(Offset(x, 4), Offset(x, 4 + plotHeight), yearLine);
    }
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
      final width = math.max(
        2.0,
        (group - (series.length - 1) * 2) / series.length,
      );
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
          if (barValues) {
            _barValue(canvas, v, left + width / 2, top, bottom, colors[si]);
          }
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
          path == null
              ? path = (Path()..moveTo(point.dx, point.dy))
              : path.lineTo(point.dx, point.dy);
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

  /// [value] written upwards along its bar: inside it in white when it fits,
  /// otherwise just past its end.
  void _barValue(
    Canvas canvas,
    double value,
    double center,
    double top,
    double bottom,
    Color bar,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: format(value),
        style: text.copyWith(fontSize: 9.5, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final length = painter.width;
    final inside = bottom - top >= length + 6;
    final white = text.copyWith(
      fontSize: 9.5,
      fontWeight: FontWeight.w600,
      color: bar.computeLuminance() > 0.5 ? Colors.black87 : Colors.white,
    );
    final drawn = inside
        ? (TextPainter(
            text: TextSpan(text: format(value), style: white),
            textDirection: TextDirection.ltr,
          )..layout())
        : painter;
    // Where the text starts, reading upwards: near the data end inside, past
    // it outside.
    final double start;
    if (inside) {
      start = value >= 0 ? top + 3 + length : bottom - 3;
    } else {
      start = value >= 0 ? top - 3 : bottom + 3 + length;
    }
    canvas.save();
    canvas.translate(center - drawn.height / 2, start);
    canvas.rotate(-math.pi / 2);
    drawn.paint(canvas, Offset.zero);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_YearChartPainter old) =>
      old.series != series ||
      old.selected != selected ||
      old.bars != bars ||
      old.barValues != barValues ||
      old.colors.first != colors.first;
}

/// Shows [popup] by [child] while the mouse rests on it, or on a tap (a
/// phone has no mouse); a tap on it or elsewhere closes it. Below the child,
/// or above when the screen ends first, and always inside the screen.
class HoverPopup extends StatefulWidget {
  const HoverPopup({
    super.key,
    required this.child,
    required this.popup,
    this.width = 380,
  });

  final Widget child;
  final WidgetBuilder popup;
  final double width;

  @override
  State<HoverPopup> createState() => _HoverPopupState();
}

class _HoverPopupState extends State<HoverPopup> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  Timer? _wait;
  bool _above = false;
  double _dx = 0;
  double _width = 0;

  void _show() {
    _wait?.cancel();
    if (!mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final screen = MediaQuery.sizeOf(context);
    final topLeft = box.localToGlobal(Offset.zero);
    _width = math.min(widget.width, screen.width - 16);
    _above =
        topLeft.dy + box.size.height + 320 > screen.height && topLeft.dy > 320;
    // From the child's left edge, pushed back inside the screen.
    _dx =
        topLeft.dx.clamp(8.0, math.max(8.0, screen.width - _width - 8)) -
        topLeft.dx;
    setState(() {});
    _portal.show();
  }

  void _hide() {
    _wait?.cancel();
    if (_portal.isShowing) _portal.hide();
  }

  @override
  void dispose() {
    _wait?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => Align(
          alignment: Alignment.topLeft,
          child: CompositedTransformFollower(
            link: _link,
            targetAnchor: _above ? Alignment.topLeft : Alignment.bottomLeft,
            followerAnchor: _above ? Alignment.bottomLeft : Alignment.topLeft,
            offset: Offset(_dx, _above ? -4 : 4),
            // The pointer stays on the child: the popup never takes it.
            child: IgnorePointer(
              child: Material(
                elevation: 6,
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: _width,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: widget.popup(context),
                ),
              ),
            ),
          ),
        ),
        child: TapRegion(
          onTapOutside: (_) => _hide(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _portal.isShowing ? _hide() : _show(),
            child: MouseRegion(
              onEnter: (_) {
                _wait?.cancel();
                _wait = Timer(const Duration(milliseconds: 300), _show);
              },
              onExit: (_) => _hide(),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// An indicator's history for [HoverPopup]: what it is, a chart and the
/// numbers by year, of one company or several ([currencies] goes with
/// [series], one per company).
class IndicatorHistory extends StatelessWidget {
  const IndicatorHistory({
    super.key,
    required this.indicator,
    required this.series,
    required this.currencies,
  });

  final Indicator indicator;
  final List<YearSeries> series;
  final List<String> currencies;

  /// Years in the table of several companies; one company shows them all.
  static const tableYears = 5;

  @override
  Widget build(BuildContext context) {
    final years = <int>{for (final s in series) ...s.values.keys}.toList()
      ..sort();
    String format(double v, int i) =>
        formatIndicator(indicator, v, currency: currencies[i]);
    final value = denseStyle(context, size: 11.5);
    final muted = mutedStyle(context, size: 11);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          indicator.label,
          style: denseStyle(
            context,
            size: 13,
          ).copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(indicator.formula, style: muted),
        if (years.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Sem histórico por ano.', style: muted),
          )
        else ...[
          const SizedBox(height: 10),
          // One company: its values in the bars. Several: lines, and the
          // numbers in a table below.
          YearChart(
            series: series,
            bars: series.length == 1,
            barValues: series.length == 1,
            height: series.length == 1 ? 150 : 120,
            format: (v) => format(v, 0),
          ),
          if (series.length > 1) ...[
            const SizedBox(height: 8),
            Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              children: [
                TableRow(
                  children: [
                    const SizedBox.shrink(),
                    for (final y in years.skip(
                      math.max(0, years.length - tableYears),
                    ))
                      Padding(
                        padding: const EdgeInsets.only(left: 10),
                        child: Text(
                          '$y',
                          style: muted,
                          textAlign: TextAlign.right,
                        ),
                      ),
                  ],
                ),
                for (final (i, s) in series.indexed)
                  TableRow(
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: seriesColor(context, i),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(s.label, style: value),
                        ],
                      ),
                      for (final y in years.skip(
                        math.max(0, years.length - tableYears),
                      ))
                        Padding(
                          padding: const EdgeInsets.only(left: 10),
                          child: Text(
                            s.values[y] == null ? '—' : format(s.values[y]!, i),
                            style: value,
                            textAlign: TextAlign.right,
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ],
        ],
      ],
    );
  }
}
