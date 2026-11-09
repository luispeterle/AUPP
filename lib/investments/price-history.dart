import 'package:flutter/material.dart';
import 'package:aupp/components/source-mark.dart';
import 'package:aupp/desktop/analysis-widgets.dart';

/// How far back a price chart goes.
enum PriceRange {
  m3('3M', 91),
  m6('6M', 182),
  y1('1A', 365),
  y5('5A', 1826),
  all('Máx', 0);

  final String label;

  /// 0 is the whole history.
  final int days;

  const PriceRange(this.label, this.days);
}

/// The closes of [history] within [range]; all of them when the history is
/// shorter.
List<(DateTime, double)> inRange(
  List<(DateTime, double)> history,
  PriceRange range,
) {
  if (range.days == 0 || history.isEmpty) return history;
  final start = history.last.$1.subtract(Duration(days: range.days));
  return [
    for (final point in history)
      if (!point.$1.isBefore(start)) point,
  ];
}

/// The ranges [history] covers (a range needs most of its days), the chosen
/// one selected, and the mark of where the prices came from.
class PriceRangeBar extends StatelessWidget {
  const PriceRangeBar({
    super.key,
    required this.history,
    required this.selected,
    required this.onChanged,
    required this.source,
    this.trailing,
  });

  final List<(DateTime, double)> history;
  final PriceRange selected;
  final ValueChanged<PriceRange> onChanged;

  /// [Unofficial]: every price history the app has is from one.
  final String source;
  final Widget? trailing;

  static String nameOf(String source) => source.split(':').first;

  /// The ranges [history] covers: each one needs most of its days, and Máx
  /// only shows when it holds more than the longest of them. A single range
  /// (three months of brapi) leaves no choice: no chips.
  static List<PriceRange> rangesOf(List<(DateTime, double)> history) {
    final span = history.length < 2
        ? 0
        : history.last.$1.difference(history.first.$1).inDays;
    final fixed = [
      for (final range in PriceRange.values)
        if (range.days > 0 && span >= range.days * 0.8) range,
    ];
    final longest = fixed.isEmpty ? 0 : fixed.last.days;
    return [
      ...fixed,
      if (fixed.isEmpty || span > longest * 1.2) PriceRange.all,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final ranges = rangesOf(history);
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (ranges.length > 1)
          for (final range in ranges)
            ChoiceChip(
              label: Text(range.label),
              selected:
                  range == selected ||
                  (!ranges.contains(selected) && range == PriceRange.all),
              visualDensity: VisualDensity.compact,
              labelStyle: denseStyle(context, size: 11.5),
              onSelected: (_) => onChanged(range),
            ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'preços: ${nameOf(source)}',
              style: mutedStyle(context, size: 11),
            ),
            SourceMark(source),
            ?trailing,
          ],
        ),
      ],
    );
  }
}
