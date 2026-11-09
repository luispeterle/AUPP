import 'package:flutter/material.dart';
import 'package:aupp/components/source-mark.dart';
import 'package:aupp/components/time-chart.dart';
import 'package:aupp/desktop/analysis-widgets.dart';
import 'package:aupp/investments/b3-market.dart';
import 'package:aupp/investments/fii-data.dart';
import 'package:aupp/investments/fii-store.dart';
import 'package:aupp/investments/fii-view.dart';
import 'package:aupp/investments/investments-page.dart';
import 'package:aupp/investments/stock-catalog.dart';

/// Real estate funds side by side: their numbers in rows with the best and the
/// worst marked, a chart of the months, and the funds of the same kind below
/// to pick from. All from the CVM's reports and brapi's list, so comparing
/// costs no request.
class FiiComparePage extends StatefulWidget {
  const FiiComparePage({super.key, required this.ticker});

  final String ticker;

  @override
  State<FiiComparePage> createState() => _FiiComparePageState();
}

enum _Chart {
  dividend('Rendimento por cota'),
  yieldOnBook('Rendimento sobre VP'),
  book('Valor patrimonial'),
  holders('Cotistas');

  const _Chart(this.label);
  final String label;
}

class _FiiComparePageState extends State<FiiComparePage> {
  final _store = FiiStore.instance;
  final _market = B3Market.funds;
  List<String>? _tickers;
  _Chart _chart = _Chart.dividend;
  FiiIndicator _sortBy = FiiIndicator.traded;
  bool _sortDown = true;

  static const _listColumns = [
    FiiIndicator.price,
    FiiIndicator.pvp,
    FiiIndicator.dy,
    FiiIndicator.traded,
    FiiIndicator.equity,
    FiiIndicator.vacancy,
    FiiIndicator.adminFee,
  ];

  @override
  void initState() {
    super.initState();
    _store.ensure();
    _market.ensure();
  }

  /// Every listed fund with its reports, most traded first.
  List<FiiQuote> _all() => [
    for (final row in _market.rows.toList()
      ..sort((a, b) => (b.volume * b.price).compareTo(a.volume * a.price)))
      ?FiiQuote.of(row.ticker),
  ];

  /// Same kind and, when the CVM says something about it, the same segment.
  List<FiiQuote> _peers(FiiFund fund) => [
    for (final q in _all())
      if (q.fund.cnpj != fund.cnpj &&
          q.fund.kind == fund.kind &&
          (fund.plainSegment == null ||
              q.fund.plainSegment == fund.plainSegment))
        q,
  ];

  List<String> _defaults() {
    final fund = _store.byTicker(widget.ticker);
    if (fund == null) return [widget.ticker];
    return [
      widget.ticker,
      for (final q in _peers(fund).take(4)) q.ticker,
    ];
  }

  void _add(String ticker) {
    final tickers = _tickers ??= [widget.ticker];
    if (tickers.contains(ticker) || tickers.length >= maxSeries) return;
    setState(() => tickers.add(ticker));
  }

  void _remove(String ticker) =>
      setState(() => _tickers = [...?_tickers]..remove(ticker));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_store, _market]),
      builder: (context, _) {
        if (!_store.ready) {
          return const Center(
            child: SizedBox(width: 420, child: FiiLoading()),
          );
        }
        if (_tickers == null && _market.rows.isNotEmpty) {
          _tickers = _defaults();
        }
        final tickers = _tickers ?? [widget.ticker];
        final quotes = [for (final t in tickers) ?FiiQuote.of(t)];
        final missing = [
          for (final t in tickers)
            if (!quotes.any((q) => q.ticker == t)) t,
        ];
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
          children: [
            _picker(tickers),
            if (missing.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${missing.join(', ')}: sem informe na CVM',
                  style: mutedStyle(context),
                ),
              ),
            const SizedBox(height: 10),
            Panel(child: _table(quotes)),
            const SizedBox(height: 16),
            Panel(child: _history(quotes)),
            const SizedBox(height: 16),
            if (_store.byTicker(widget.ticker) case final fund?)
              Panel(child: _list(fund, tickers)),
          ],
        );
      },
    );
  }

  Widget _picker(List<String> tickers) {
    final scheme = Theme.of(context).colorScheme;
    final options = [
      for (final row in _market.rows.toList()
        ..sort((a, b) => b.volume.compareTo(a.volume)))
        (row.ticker, row.name),
    ];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final (i, ticker) in tickers.indexed)
          Container(
            height: 28,
            padding: const EdgeInsets.only(left: 6),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(6),
              border: Border(
                left: BorderSide(color: seriesColor(context, i), width: 3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ticker,
                  style: denseStyle(
                    context,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
                if (ticker != widget.ticker)
                  InkWell(
                    onTap: () => _remove(ticker),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(Icons.close, size: 14),
                    ),
                  )
                else
                  const SizedBox(width: 8),
              ],
            ),
          ),
        if (tickers.length < maxSeries)
          SizedBox(
            width: 230,
            height: 30,
            child: Autocomplete<(String, String)>(
              displayStringForOption: (o) => o.$1,
              optionsBuilder: (value) {
                final query = value.text.trim().toUpperCase();
                if (query.isEmpty) return const [];
                return options
                    .where(
                      (o) =>
                          !tickers.contains(o.$1) &&
                          (o.$1.startsWith(query) ||
                              o.$2.toUpperCase().contains(query)),
                    )
                    .take(8);
              },
              onSelected: (o) => _add(o.$1),
              fieldViewBuilder: (context, controller, focus, submit) =>
                  TextField(
                    controller: controller,
                    focusNode: focus,
                    style: denseStyle(context),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Adicionar FII',
                      prefixIcon: Icon(Icons.add, size: 16),
                      prefixIconConstraints: BoxConstraints(minWidth: 28),
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                    ),
                    onSubmitted: (_) {
                      submit();
                      controller.clear();
                    },
                  ),
              optionsViewBuilder: (context, onSelected, found) => Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 320,
                    child: ListView(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      children: [
                        for (final o in found)
                          InkWell(
                            onTap: () => onSelected(o),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 5,
                              ),
                              child: Row(
                                children: [
                                  InstitutionLogo(
                                    institution: StockCompany.badgeOf(o.$1),
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  SizedBox(
                                    width: 56,
                                    child: Text(
                                      o.$1,
                                      style: denseStyle(
                                        context,
                                      ).copyWith(fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      o.$2,
                                      style: mutedStyle(context),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        TextButton(
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            textStyle: const TextStyle(fontSize: 12),
          ),
          onPressed: () => setState(() => _tickers = _defaults()),
          child: const Text('Fundos parecidos'),
        ),
      ],
    );
  }

  /// The best and the worst of a row, by its direction; none with fewer than
  /// two values.
  (int?, int?) _marks(FiiIndicator indicator, List<double?> values) {
    if (indicator.better == 0) return (null, null);
    int? best;
    int? worst;
    for (final (i, v) in values.indexed) {
      if (v == null || !v.isFinite) continue;
      final score = v * indicator.better;
      if (best == null || score > values[best]! * indicator.better) best = i;
      if (worst == null || score < values[worst]! * indicator.better) {
        worst = i;
      }
    }
    if (best == worst) return (null, null);
    return (best, worst);
  }

  Widget _table(List<FiiQuote> quotes) {
    const labelWidth = 170.0;
    const columnWidth = 118.0;
    final scheme = Theme.of(context).colorScheme;
    final good = Colors.green.withValues(alpha: 0.16);
    final bad = scheme.error.withValues(alpha: 0.13);
    final style = denseStyle(context, size: 12);
    final width = labelWidth + quotes.length * columnWidth + 12;
    Widget textRow(String label, String Function(FiiQuote q) text) => SizedBox(
      width: width,
      child: HoverRow(
        child: Row(
          children: [
            SizedBox(
              width: labelWidth,
              child: Text(label, style: labelStyle(context).copyWith(fontSize: 12)),
            ),
            for (final q in quotes)
              SizedBox(
                width: columnWidth,
                child: Text(
                  text(q),
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
          ],
        ),
      ),
    );
    final rows = <Widget>[
      SizedBox(
        height: 40,
        child: Row(
          children: [
            const SizedBox(width: labelWidth),
            for (final q in quotes)
              SizedBox(
                width: columnWidth,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    InstitutionLogo(
                      institution: StockCompany.badgeOf(q.ticker),
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            q.ticker,
                            style: style.copyWith(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            plainFundName(q.fund.name) ?? q.fund.name,
                            style: mutedStyle(context, size: 10.5),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      textRow('Tipo', (q) => q.fund.kind?.label ?? '—'),
      textRow('Segmento', (q) => q.fund.segment ?? '—'),
      for (final indicator in FiiIndicator.values)
        Builder(
          builder: (context) {
            final values = [for (final q in quotes) indicator.value(q)];
            final (best, worst) = _marks(indicator, values);
            final label = Row(
              children: [
                Flexible(
                  child: Text(
                    indicator.label,
                    style: labelStyle(context).copyWith(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (indicator.unofficial case final source?)
                  SourceMark(source, size: 12),
              ],
            );
            return SizedBox(
              width: width,
              child: HoverRow(
                child: Row(
                  children: [
                    SizedBox(
                      width: labelWidth,
                      child: indicator.help == null
                          ? label
                          : Tooltip(
                              message: indicator.help,
                              waitDuration: const Duration(milliseconds: 400),
                              child: label,
                            ),
                    ),
                    for (final (i, q) in quotes.indexed)
                      Container(
                        width: columnWidth,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        color: i == best
                            ? good
                            : i == worst
                            ? bad
                            : null,
                        child: Text(
                          indicator.format(q),
                          textAlign: TextAlign.right,
                          style: style.copyWith(
                            fontWeight: i == best ? FontWeight.w700 : null,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: rows,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Verde é o melhor da linha; vermelho, o pior. Passe o mouse no nome '
          'para ver o que é. Informes da CVM; preço e volume da brapi.dev.',
          style: mutedStyle(context, size: 11),
        ),
      ],
    );
  }

  Widget _history(List<FiiQuote> quotes) {
    double? valueOf(FiiMonth m) => switch (_chart) {
      _Chart.dividend => m.dividendPerShare,
      _Chart.yieldOnBook =>
        m.dividendPerShare == null || (m.bookPerShare ?? 0) <= 0
            ? null
            : m.dividendPerShare! / m.bookPerShare!,
      _Chart.book => m.bookPerShare,
      _Chart.holders => m.holders?.toDouble(),
    };
    final format = switch (_chart) {
      _Chart.dividend || _Chart.book => pricePerShare,
      _Chart.yieldOnBook => percent,
      _Chart.holders => amountShort,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          'Mês a mês',
          trailing: DropdownButton<_Chart>(
            value: _chart,
            isDense: true,
            underline: const SizedBox.shrink(),
            style: denseStyle(context),
            items: [
              for (final c in _Chart.values)
                DropdownMenuItem(value: c, child: Text(c.label)),
            ],
            onChanged: (v) => setState(() => _chart = v!),
          ),
        ),
        const SizedBox(height: 6),
        TimeChart(
          height: 200,
          series: [
            for (final (i, q) in quotes.indexed)
              TimeSeries(q.ticker, seriesColor(context, i), [
                for (final m in q.fund.months)
                  if (valueOf(m) case final v?) (m.date, v),
              ]),
          ],
          format: format,
          dateLabel: monthLabel,
          axisLabel: monthLabel,
        ),
      ],
    );
  }

  Widget _list(FiiFund fund, List<String> selected) {
    final list = [?FiiQuote.of(widget.ticker), ..._peers(fund)];
    final values = {
      for (final q in list)
        q.ticker: {for (final c in _listColumns) c: c.value(q)},
    };
    list.sort((a, b) {
      final va = values[a.ticker]![_sortBy];
      final vb = values[b.ticker]![_sortBy];
      if (va == null) return vb == null ? 0 : 1;
      if (vb == null) return -1;
      return _sortDown ? vb.compareTo(va) : va.compareTo(vb);
    });
    final scheme = Theme.of(context).colorScheme;
    final style = denseStyle(context, size: 12);
    const columnWidth = 104.0;
    Widget header(FiiIndicator column) {
      final active = column == _sortBy;
      return InkWell(
        onTap: () => setState(() {
          if (active) {
            _sortDown = !_sortDown;
          } else {
            _sortBy = column;
            _sortDown = column.better >= 0;
          }
        }),
        child: SizedBox(
          width: columnWidth,
          child: Text(
            '${column.label}${active ? (_sortDown ? ' ↓' : ' ↑') : ''}',
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: style.copyWith(
              fontWeight: FontWeight.w700,
              color: active ? scheme.primary : null,
            ),
          ),
        ),
      );
    }

    final rows = <Widget>[
      SizedBox(
        height: 24,
        child: Row(
          children: [
            const SizedBox(width: 28),
            SizedBox(
              width: 260,
              child: Text(
                'Fundo',
                style: style.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            for (final c in _listColumns) header(c),
          ],
        ),
      ),
      for (final (i, q) in list.indexed)
        Container(
          height: 22,
          color: i.isOdd ? scheme.onSurface.withValues(alpha: 0.035) : null,
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: selected.contains(q.ticker)
                    ? Icon(Icons.check, size: 14, color: scheme.primary)
                    : selected.length < maxSeries
                    ? InkWell(
                        onTap: () => _add(q.ticker),
                        child: Tooltip(
                          message: 'Comparar',
                          child: Icon(
                            Icons.add,
                            size: 15,
                            color: scheme.primary,
                          ),
                        ),
                      )
                    : null,
              ),
              SizedBox(
                width: 260,
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: q.ticker,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(
                        text: '  ${plainFundName(q.fund.name) ?? q.fund.name}',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  style: style,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              for (final c in _listColumns)
                SizedBox(
                  width: columnWidth,
                  child: Text(
                    c.format(q),
                    textAlign: TextAlign.right,
                    style: style,
                  ),
                ),
            ],
          ),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          [
            ?fund.kind?.label,
            ?fund.plainSegment,
            '${list.length} ${list.length == 1 ? 'fundo' : 'fundos'}',
          ].join(' · '),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: rows,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Toque no título da coluna para ordenar.',
          style: mutedStyle(context, size: 11),
        ),
      ],
    );
  }
}
