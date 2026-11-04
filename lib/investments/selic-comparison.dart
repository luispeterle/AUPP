import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:aupp/components/info-tip.dart';
import 'package:aupp/components/time-chart.dart';

import 'benchmark.dart';
import 'performance.dart';

/// The card every chart of the investments sits in.
class InvestmentCard extends StatelessWidget {
  const InvestmentCard({
    super.key,
    required this.title,
    this.subtitle,
    this.info,
    this.leading,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final String? info;
  final Widget? leading;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 8)],
                Flexible(child: Text(title, style: theme.textTheme.titleMedium)),
                if (info != null) ...[
                  const SizedBox(width: 6),
                  InfoTip(info!),
                ],
              ],
            ),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// "Rendimento × Selic", the same in Nacional, Internacional and Cripto: the
/// return of the portfolio and of the Selic over the period, both from 0%,
/// without counting what went in as gain, and what was left over inflation.
class SelicComparison extends StatelessWidget {
  const SelicComparison({
    super.key,
    required this.points,
    required this.rates,
    this.sinceStart,
    this.onSinceStart,
    this.footer,
  });

  static const title = 'Rendimento × Selic';
  static const portfolioColor = Color(0xFF1E88E5);
  static const selicColor = Color(0xFFFB8C00);

  final List<PerformancePoint> points;
  final BenchmarkRates rates;

  /// With [onSinceStart], shows the choice of period. Null when the page has
  /// its own.
  final bool? sinceStart;
  final ValueChanged<bool>? onSinceStart;
  final Widget? footer;

  static String _pct(double v) =>
      '${v >= 0 ? '+' : ''}${(v * 100).toStringAsFixed(2).replaceAll('.', ',')}%';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (points.length < 2) {
      return const SizedBox(
        height: 120,
        child: Center(child: Text('Sem histórico no período')),
      );
    }
    final portfolio = points.last.portfolio;
    final span = points.last.date.difference(points.first.date).inDays;
    Widget figure(String label, double value, Color color) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          Text(
            _pct(value),
            style: theme.textTheme.titleLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
    final inflation = rates.ipca.isEmpty
        ? null
        : BenchmarkRates.inflationBetween(
            rates.ipca,
            points.first.date,
            points.last.date,
          );
    final real = inflation == null ? null : (1 + portfolio) / (1 + inflation) - 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (sinceStart != null && onSinceStart != null) ...[
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('12 meses')),
              ButtonSegment(value: true, label: Text('Desde o início')),
            ],
            selected: {sinceStart!},
            showSelectedIcon: false,
            onSelectionChanged: (s) => onSinceStart!(s.first),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            figure('Sua carteira', portfolio, portfolioColor),
            figure('Selic', points.last.selic, selicColor),
          ],
        ),
        const SizedBox(height: 8),
        TimeChart(
          series: [
            TimeSeries('Sua carteira', portfolioColor, [
              for (final p in points) (p.date, p.portfolio * 100),
            ]),
            TimeSeries('Selic', selicColor, [
              for (final p in points) (p.date, p.selic * 100),
            ]),
          ],
          format: (v) => '${v.toStringAsFixed(1).replaceAll('.', ',')}%',
          dateLabel: DateFormat('dd/MM/yyyy').format,
          axisLabel: DateFormat(span <= 92 ? 'dd/MM' : 'MM/yy').format,
        ),
        if (real != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text.rich(
              TextSpan(
                style: theme.textTheme.bodyMedium,
                children: [
                  const TextSpan(text: 'Ganho real, acima da inflação: '),
                  TextSpan(
                    text: _pct(real),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: real >= 0 ? Colors.green : theme.colorScheme.error,
                    ),
                  ),
                  TextSpan(
                    text: ' (IPCA do período ${_pct(inflation!)})',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        if (footer != null) ...[const SizedBox(height: 8), footer!],
      ],
    );
  }
}
