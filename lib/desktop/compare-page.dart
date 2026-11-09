import 'package:flutter/material.dart';
import 'package:aupp/components/source-mark.dart';
import 'package:aupp/desktop/analysis-page.dart';
import 'package:aupp/desktop/analysis-widgets.dart';
import 'package:aupp/investments/analysis-source.dart';
import 'package:aupp/investments/asset-sheet.dart';
import 'package:aupp/investments/b3-market.dart';
import 'package:aupp/investments/cvm-statements.dart';
import 'package:aupp/investments/cvm-store.dart';
import 'package:aupp/investments/fundamentals.dart';
import 'package:aupp/investments/investments-page.dart';
import 'package:aupp/investments/sec-data.dart';
import 'package:aupp/investments/stock-catalog.dart';

/// The most traded ticker of each company among [rows], in their order,
/// leaving out [except]'s company.
List<String> companyTickers(
  Iterable<MarketRow> rows,
  CvmStore store, {
  String? except,
}) {
  final skip = except == null ? null : store.byTicker(except)?.code;
  final seen = <String>{?skip};
  return [
    for (final row in rows)
      if (store.byTicker(row.ticker) case final company?)
        if (seen.add(company.code)) row.ticker,
  ];
}

/// Companies side by side, as the comparator of research sites: indicators in
/// rows with the best and the worst marked, a history chart, and the whole
/// sector below to pick from. Everything is computed here, so comparing costs
/// no request.
class ComparePage extends StatefulWidget {
  const ComparePage({super.key, required this.ticker});

  final String ticker;

  @override
  State<ComparePage> createState() => _ComparePageState();
}

class _ComparePageState extends State<ComparePage> {
  final _store = CvmStore.instance;
  final _market = B3Market.instance;
  List<String>? _tickers;
  String _metric = 'netIncome';
  int _span = 10;
  String _sortBy = 'marketCap';
  bool _sortDown = true;

  static const _metrics = <String, String>{
    'netIncome': 'Lucro líquido',
    'revenue': 'Receita líquida',
    'ebitda': 'EBITDA',
    'netMargin': 'Margem líquida',
    'roe': 'ROE',
    'roic': 'ROIC',
    'netDebtEbitda': 'Dív. líq./EBITDA',
    'dividendsPaid': 'Proventos pagos',
  };

  static const _sectorColumns = [
    'marketCap',
    'pl',
    'pvp',
    'dy',
    'evEbit',
    'roe',
    'roic',
    'netMargin',
    'netDebtEbitda',
    'cagrIncome',
  ];

  late final bool _b3 = isB3Ticker(widget.ticker);

  @override
  void initState() {
    super.initState();
    if (_b3) {
      _store.ensure();
      _market.ensure();
    } else {
      SecCatalog.instance.ensure();
    }
  }

  /// The ticker and up to four of the most traded in its subsector. Abroad
  /// there is no sector list: the ticker alone, and the user adds the rest.
  List<String> _defaults() {
    if (!_b3) return [widget.ticker];
    final peers = companyTickers(
      _market.peersOf(widget.ticker),
      _store,
      except: widget.ticker,
    );
    if (peers.isEmpty) {
      // Without brapi's sector, the CVM's.
      final company = _store.byTicker(widget.ticker);
      final rows = [
        for (final c in _store.companies)
          if (c.sector != null && c.sector == company?.sector)
            for (final t in c.tickers.keys) ?_market[t],
      ]..sort((a, b) => b.volume.compareTo(a.volume));
      peers.addAll(companyTickers(rows, _store, except: widget.ticker));
    }
    return [widget.ticker, ...peers.take(4)];
  }

  void _add(String ticker) {
    final tickers = _tickers ??= [widget.ticker];
    if (tickers.contains(ticker) || tickers.length >= maxSeries) return;
    if (isB3Ticker(ticker)) {
      _store.ensure();
      _market.ensure();
    }
    setState(() => tickers.add(ticker));
  }

  /// Sector and subsector: brapi's for the B3 (written in two ways, so made
  /// plain), the SEC's industry abroad.
  (String?, String?) _sectorOf(String ticker) {
    String? plain(String? text) => text
        ?.toLowerCase()
        .replaceAll('.', ',')
        .replaceAll(RegExp(r'\s+'), ' ');
    if (isB3Ticker(ticker)) {
      final row = _market[ticker];
      return (row?.sector, plain(row?.subsector));
    }
    return (AnalysisSource.now(ticker)?.company.sector, null);
  }

  /// Tickers that are not in the same sector and subsector as the one
  /// studied, with why.
  List<String> _outOfSector(List<String> tickers) {
    final (sector, subsector) = _sectorOf(widget.ticker);
    final out = <String>[];
    for (final t in tickers) {
      if (t == widget.ticker || !AnalysisSource.loaded(t)) continue;
      if (isB3Ticker(t) != _b3) {
        out.add('$t é de outra bolsa, com outra classificação de setor');
        continue;
      }
      final (otherSector, otherSubsector) = _sectorOf(t);
      if (sector == null || otherSector == null) continue;
      if (sector != otherSector ||
          (subsector != null &&
              otherSubsector != null &&
              subsector != otherSubsector)) {
        out.add(
          '$t: ${[?sectorLabel(otherSector), ?otherSubsector].join(' · ')}',
        );
      }
    }
    return out;
  }

  /// The companies to compare: the B3's at once, those abroad as they arrive.
  List<Fundamentals> _resolve(List<String> tickers) {
    final out = <Fundamentals>[];
    for (final t in tickers) {
      if (!AnalysisSource.loaded(t)) {
        AnalysisSource.foreign(t).then((_) {
          if (mounted) setState(() {});
        });
        continue;
      }
      final f = AnalysisSource.now(t);
      if (f != null) out.add(f);
    }
    return out;
  }

  void _remove(String ticker) => setState(() => _tickers!.remove(ticker));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_store, _market, SecCatalog.instance]),
      builder: (context, _) {
        if (_b3 && !_store.ready) return StatementsLoading(store: _store);
        if (_tickers == null && (!_b3 || _market.rows.isNotEmpty)) {
          _tickers = _defaults();
        }
        final tickers = _tickers ?? [widget.ticker];
        final companies = _resolve(tickers);
        final waiting = tickers.length - companies.length;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
          children: [
            _picker(tickers),
            for (final warning in _outOfSector(tickers))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber,
                      size: 15,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Fora do setor de ${widget.ticker}: $warning',
                        style: denseStyle(context, size: 12),
                      ),
                    ),
                  ],
                ),
              ),
            if (waiting > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  [
                    for (final t in tickers)
                      if (!AnalysisSource.loaded(t))
                        '$t: buscando na SEC'
                      else if (AnalysisSource.now(t) == null)
                        '$t: sem balanços abertos',
                  ].join(' · '),
                  style: mutedStyle(context),
                ),
              ),
            const SizedBox(height: 10),
            Panel(child: _table(companies)),
            const SizedBox(height: 16),
            Panel(child: _history(companies)),
            const SizedBox(height: 16),
            if (_b3) Panel(child: _sector(tickers)),
          ],
        );
      },
    );
  }

  Widget _picker(List<String> tickers) {
    final scheme = Theme.of(context).colorScheme;
    final options = [
      for (final c in _store.companies)
        for (final t in c.tickers.keys)
          if (_market[t] != null) (t, StockCompany.of(t)?.name ?? c.name),
    ]..sort((a, b) => (_market[b.$1]!.volume).compareTo(_market[a.$1]!.volume));
    final secReady = SecCatalog.instance.ready;
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
                  style: denseStyle(context)
                      .copyWith(fontWeight: FontWeight.w700),
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
                final b3 = options
                    .where(
                      (o) =>
                          !tickers.contains(o.$1) &&
                          (o.$1.startsWith(query) ||
                              o.$2.toUpperCase().contains(query)),
                    )
                    .take(8);
                final abroad = secReady
                    ? [
                        for (final l in SecCatalog.instance.search(
                          query,
                          limit: 8,
                        ))
                          if (!tickers.contains(l.ticker)) (l.ticker, l.name),
                      ]
                    : const <(String, String)>[];
                return [...b3, ...abroad];
              },
              onSelected: (o) => _add(o.$1),
              fieldViewBuilder: (context, controller, focus, submit) =>
                  TextField(
                    controller: controller,
                    focusNode: focus,
                    style: denseStyle(context),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Adicionar ticker ou empresa (B3 ou EUA)',
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
          child: const Text('Pares do setor'),
        ),
      ],
    );
  }

  Widget _table(List<Fundamentals> companies) {
    const labelWidth = 170.0;
    const columnWidth = 118.0;
    final scheme = Theme.of(context).colorScheme;
    final good = Colors.green.withValues(alpha: 0.16);
    final bad = scheme.error.withValues(alpha: 0.13);
    final style = denseStyle(context, size: 12);
    final rows = <Widget>[
      SizedBox(
        height: 40,
        child: Row(
          children: [
            const SizedBox(width: labelWidth),
            for (final f in companies)
              SizedBox(
                width: columnWidth,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    InstitutionLogo(
                      institution: StockCompany.badgeOf(f.ticker),
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            f.ticker,
                            style: style.copyWith(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            StockCompany.of(f.ticker)?.name ?? f.company.name,
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
    ];
    for (final group in IndicatorGroup.values) {
      rows.add(
        Container(
          height: 22,
          width: labelWidth + companies.length * columnWidth,
          color: scheme.onSurface.withValues(alpha: 0.05),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            group.label,
            style: style.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      );
      for (final indicator in Indicator.all.where((i) => i.group == group)) {
        final values = [for (final f in companies) f.value(indicator)];
        final marks = bestAndWorst(indicator, values);
        YearSeries seriesOf(Fundamentals f) =>
            YearSeries(f.ticker, f.history(indicator));
        rows.add(
          SizedBox(
            width: labelWidth + companies.length * columnWidth + 12,
            child: HoverRow(
              child: Row(
                children: [
                  // The name shows every company; a value, only its own.
                  SizedBox(
                    width: labelWidth,
                    child: HoverPopup(
                      width: 440,
                      popup: (_) => IndicatorHistory(
                        indicator: indicator,
                        series: [for (final f in companies) seriesOf(f)],
                        currencies: [
                          for (final f in companies) f.company.currency,
                        ],
                      ),
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              indicator.label,
                              style: labelStyle(context).copyWith(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (indicator.usesPrice)
                            const SourceMark(Unofficial.brapiPrice, size: 12),
                          // Has a history to chart: hover or tap shows it.
                          if (companies.any(
                            (f) => f.history(indicator).isNotEmpty,
                          )) ...[
                            const SizedBox(width: 4),
                            Icon(
                              Icons.show_chart,
                              size: 13,
                              color: scheme.onSurfaceVariant,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  for (final (i, v) in values.indexed)
                    SizedBox(
                      width: columnWidth,
                      child: HoverPopup(
                        popup: (_) => IndicatorHistory(
                          indicator: indicator,
                          series: [seriesOf(companies[i])],
                          currencies: [companies[i].company.currency],
                        ),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: marks == null || v == null
                                  ? null
                                  : v == marks.$1
                                  ? good
                                  : v == marks.$2
                                  ? bad
                                  : null,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              formatIndicator(
                                indicator,
                                v,
                                currency: companies[i].company.currency,
                              ),
                              style: valueStyle(context).copyWith(fontSize: 12),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          'Indicadores',
          trailing: Text(
            'Verde: o melhor da linha · vermelho: o pior',
            style: mutedStyle(context, size: 11),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: rows,
          ),
        ),
      ],
    );
  }

  Widget _history(List<Fundamentals> companies) {
    final isFigure = switch (_metric) {
      'netIncome' || 'revenue' || 'ebitda' || 'dividendsPaid' => true,
      _ => false,
    };
    final currencies = {for (final f in companies) f.company.currency};
    final mixed = currencies.length > 1;
    Map<int, double> values(Fundamentals f) {
      // Different currencies on one axis would mislead: into reais at today's
      // PTAX, or left out when there is no rate.
      final toBrl = !isFigure || !mixed
          ? 1.0
          : f.company.currency == 'BRL'
          ? 1.0
          : AnalysisSource.cached(f.ticker)?.brlPerUnit;
      if (toBrl == null) return const {};
      final years = f.company.sortedYears.where(
        (y) => y > (f.year ?? DateTime.now().year) - _span - 1,
      );
      if (!isFigure) {
        final history = f.history(Indicator.byId(_metric));
        return {
          for (final y in years)
            if (history[y] case final v?) y: v,
        };
      }
      return {
        for (final y in years)
          if (switch (_metric) {
                'ebitda' => f.company.years[y]!.ebitda,
                _ => f.company.years[y]![Figure.values.byName(_metric)],
              }
              case final v?)
            y: v * toBrl,
      };
    }

    final format = isFigure
        ? amountShort
        : Indicator.byId(_metric).format == IndicatorFormat.percent
        ? percent
        : ratio;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          isFigure
              ? 'Histórico (${mixed ? 'em R\$, câmbio PTAX de hoje' : currencySymbol(currencies.firstOrNull ?? 'BRL')})'
              : 'Histórico',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<String>(
                value: _metric,
                isDense: true,
                underline: const SizedBox.shrink(),
                style: denseStyle(context),
                items: [
                  for (final e in _metrics.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _metric = v!),
              ),
              const SizedBox(width: 10),
              SegmentedButton<int>(
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity(horizontal: -4, vertical: -4),
                  textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 11)),
                ),
                segments: const [
                  ButtonSegment(value: 5, label: Text('5 anos')),
                  ButtonSegment(value: 10, label: Text('10 anos')),
                ],
                selected: {_span},
                onSelectionChanged: (v) => setState(() => _span = v.single),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        YearChart(
          bars: false,
          height: 190,
          format: format,
          series: [for (final f in companies) YearSeries(f.ticker, values(f))],
        ),
      ],
    );
  }

  Widget _sector(List<String> selected) {
    final row = _market[widget.ticker];
    final peers = companyTickers(_market.peersOf(widget.ticker), _store);
    if (peers.isEmpty) return const SizedBox.shrink();
    final prices = _market.prices;
    final list = [
      for (final t in peers) Fundamentals(_store.byTicker(t)!, t, prices),
    ];
    final values = {
      for (final f in list)
        f.ticker: {
          for (final id in _sectorColumns) id: f.value(Indicator.byId(id)),
        },
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
    const columnWidth = 92.0;
    Widget header(String id) {
      final active = id == _sortBy;
      return InkWell(
        onTap: () => setState(() {
          if (active) {
            _sortDown = !_sortDown;
          } else {
            _sortBy = id;
            _sortDown = true;
          }
        }),
        child: SizedBox(
          width: columnWidth,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (Indicator.byId(id).usesPrice)
                const SourceMark(Unofficial.brapiPrice, size: 11),
              Flexible(
                child: Text(
                  '${Indicator.byId(id).label}${active ? (_sortDown ? ' ↓' : ' ↑') : ''}',
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: style.copyWith(
                    fontWeight: FontWeight.w700,
                    color: active ? scheme.primary : null,
                  ),
                ),
              ),
            ],
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
              width: 220,
              child: Text(
                'Empresa',
                style: style.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            for (final id in _sectorColumns) header(id),
          ],
        ),
      ),
      for (final (i, f) in list.indexed)
        Container(
          height: 22,
          color: i.isOdd ? scheme.onSurface.withValues(alpha: 0.035) : null,
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: selected.contains(f.ticker)
                    ? Icon(Icons.check, size: 14, color: scheme.primary)
                    : selected.length < maxSeries
                    ? InkWell(
                        onTap: () => _add(f.ticker),
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
                width: 220,
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: f.ticker,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(
                        text:
                            '  ${StockCompany.of(f.ticker)?.name ?? f.company.name}',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  style: style,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              for (final id in _sectorColumns)
                SizedBox(
                  width: columnWidth,
                  child: Text(
                    formatIndicator(Indicator.byId(id), values[f.ticker]![id]),
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
            'Setor',
            ?sectorLabel(row?.sector),
            ?row?.subsector,
            '${list.length} ${list.length == 1 ? 'empresa' : 'empresas'}',
          ].join(' · '),
          trailing: Text(
            'Clique no título da coluna para ordenar',
            style: mutedStyle(context, size: 11),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: rows,
          ),
        ),
      ],
    );
  }
}
