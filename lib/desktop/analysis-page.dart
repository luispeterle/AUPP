import 'package:flutter/material.dart';
import 'package:aupp/components/info-tip.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:aupp/desktop/analysis-sections.dart';
import 'package:aupp/desktop/analysis-widgets.dart';
import 'package:aupp/investments/analysis-source.dart';
import 'package:aupp/investments/asset-sheet.dart';
import 'package:aupp/investments/b3-market.dart';
import 'package:aupp/investments/cvm-statements.dart';
import 'package:aupp/investments/cvm-store.dart';
import 'package:aupp/investments/diagram.dart';
import 'package:aupp/investments/fundamentals.dart';
import 'package:aupp/investments/investments-page.dart';
import 'package:aupp/investments/sec-data.dart';
import 'package:aupp/investments/stock-catalog.dart';

/// A stock's numbers, computed here from its statements and prices:
/// indicators with their history, the criteria of the questionnaire that the
/// numbers answer, and the statements of ten years. The B3's come from the
/// CVM and brapi's list; the rest from the SEC, priced at the home exchange.
class AnalysisPage extends StatefulWidget {
  const AnalysisPage({
    super.key,
    required this.ticker,
    this.top,
    this.held = true,
  });

  final String ticker;

  /// Above everything, under the name: the price chart and the thesis.
  final Widget? top;

  /// Whether it is in the portfolio. A grade given to what is not puts it in
  /// Carteira e aporte to study.
  final bool held;

  @override
  State<AnalysisPage> createState() => _AnalysisPageState();
}

class _AnalysisPageState extends State<AnalysisPage> {
  final _store = CvmStore.instance;
  final _market = B3Market.instance;
  late final bool _b3 = isB3Ticker(widget.ticker);
  Future<ForeignAnalysis?>? _foreign;
  Future<AssetQuote?>? _quote;

  @override
  void initState() {
    super.initState();
    if (_b3) {
      _store.ensure();
      _market.ensure();
    } else {
      _loadForeign();
    }
  }

  void _loadForeign() {
    _foreign = AnalysisSource.foreign(widget.ticker);
    _quote = AssetQuote.fetch(widget.ticker, withHistory: false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_b3) return _buildForeign();
    return ListenableBuilder(
      listenable: Listenable.merge([_store, _market, DiagramState.revision]),
      builder: (context, _) {
        if (!_store.ready) return StatementsLoading(store: _store);
        final company = _store.byTicker(widget.ticker);
        if (company == null) {
          return _message(
            'A CVM não tem balanços de ${widget.ticker}: não é ação de empresa '
            'brasileira (FII, ETF ou BDR). Veja na aba da AUVP Analítica.',
          );
        }
        final f = Fundamentals(company, widget.ticker, _market.prices);
        final row = _market[widget.ticker];
        return _body(
          f,
          notices: _store.noticesOf(company),
          facts: CompanyFacts(
            fundamentals: f,
            market: row,
            lead: _quoteFacts(
              f,
              price: f.price,
              currency: 'BRL',
              change: row?.changePct,
              others: [
                for (final ticker in company.tickers.keys)
                  if (ticker != widget.ticker && _market[ticker] != null)
                    (ticker, pricePerShare(_market[ticker]!.price)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _message(String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(text, style: mutedStyle(context, size: 13)),
    ),
  );

  Widget _buildForeign() {
    if (secContact.isEmpty) {
      return _message(
        'Falta o contato que a SEC exige (SEC_CONTACT no private/build.env). '
        'Sem ele não dá para buscar os balanços de fora.',
      );
    }
    return ListenableBuilder(
      listenable: DiagramState.revision,
      builder: (context, _) => FutureBuilder<ForeignAnalysis?>(
        future: _foreign,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: SizedBox(
                width: 280,
                child: LinearProgressIndicator(minHeight: 2),
              ),
            );
          }
          final found = snapshot.data;
          if (found == null) {
            return _message(
              'Sem balanços abertos de ${widget.ticker}. A análise cobre as ações '
              'da B3 (CVM) e as empresas que entregam balanço à SEC: as listadas '
              'nos EUA, inclusive ADRs de estrangeiras. Para ETFs e ações só de '
              'outras bolsas, use a aba da AUVP Analítica ou da Ficha.',
            );
          }
          final f = found.fundamentals;
          final price = found.price;
          return FutureBuilder<AssetQuote?>(
            future: _quote,
            builder: (context, quote) {
              final us = quote.data;
              return _body(
                f,
                notices: found.notices,
                brlPerUnit: found.brlPerUnit,
                warning: _staleWarning(found.newerAnnualReport),
                facts: ForeignFacts(
                  analysis: found,
                  lead: _quoteFacts(
                    f,
                    price: us?.price ?? f.price,
                    currency: us?.currency ?? f.company.currency,
                    change: us?.changePct,
                    others: [
                      if (price != null && price.symbol != widget.ticker)
                        (
                          price.symbol,
                          pricePerShare(price.price, currency: price.currency),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// The price and the date of the statements, first in "Dados da empresa".
  static List<(String, String)> _quoteFacts(
    Fundamentals f, {
    required double? price,
    required String currency,
    required double? change,
    List<(String, String)> others = const [],
  }) => [
    (
      'Preço',
      price == null
          ? '—'
          : '${pricePerShare(price, currency: currency)}'
                '${change == null ? '' : '  ${change >= 0 ? '+' : ''}${ratio(change)}% hoje'}',
    ),
    ...others,
    if (f.company.ttmEnd != null)
      ('Balanço até', DateFormat('dd/MM/yyyy').format(f.company.ttmEnd!)),
  ];

  static String? _staleWarning(DateTime? newer) => newer == null
      ? null
      : 'A SEC recebeu em ${DateFormat('dd/MM/yyyy').format(newer)} um '
            'relatório anual mais novo que estes números, que ainda não chegou '
            'aos dados estruturados dela. P/L, P/VP e os outros indicadores de '
            'preço comparam o preço de hoje com o balanço antigo: confira na '
            'aba SEC ou na AUVP Analítica.';

  Widget _body(
    Fundamentals f, {
    required List<CvmNotice> notices,
    double? brlPerUnit = 1,
    String? warning,
    required Widget facts,
  }) {
    final company = f.company;
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
      children: [
        if (warning != null)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.errorContainer,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber,
                  size: 16,
                  color: scheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    warning,
                    style: denseStyle(
                      context,
                      size: 12,
                    ).copyWith(color: scheme.onErrorContainer),
                  ),
                ),
              ],
            ),
          ),
        _header(f),
        if (widget.top != null) ...[const SizedBox(height: 10), widget.top!],
        const SizedBox(height: 6),
        ..._notes(f),
        _layout(
          first: [
            facts,
            if (company.financial && company.cnpj != null)
              BankCapitalPanel(cnpj: company.cnpj!),
            _group(f, IndicatorGroup.valuation),
            FairPricePanel(fundamentals: f),
          ],
          second: [
            _group(f, IndicatorGroup.efficiency),
            _group(f, IndicatorGroup.growth),
            _group(f, IndicatorGroup.debt),
            _group(f, IndicatorGroup.returns),
          ],
          criteria: _CriteriaPanel(
            fundamentals: f,
            brlPerUnit: brlPerUnit,
            held: widget.held,
          ),
        ),
        const SizedBox(height: 14),
        _charts(f),
        const SizedBox(height: 14),
        Panel(child: IndicatorHistoryTable(fundamentals: f)),
        const SizedBox(height: 14),
        Panel(child: _StatementsTable(company: company)),
        const SizedBox(height: 14),
        Panel(
          child: NoticesList(
            notices: notices,
            source: company.fromSec ? 'SEC' : 'CVM',
          ),
        ),
        const SizedBox(height: 14),
        AboutCompany(ticker: widget.ticker),
      ],
    );
  }

  Widget _header(Fundamentals f) {
    final company = f.company;
    final scheme = Theme.of(context).colorScheme;
    final details = [
      ?company.sector,
      ?company.segment,
      if (company.control != null) 'Controle ${company.control!.toLowerCase()}',
      if (company.founded != null) 'Fundada em ${company.founded!.year}',
      if (company.listed != null) 'Na bolsa desde ${company.listed!.year}',
    ];
    return Row(
      children: [
        InstitutionLogo(
          institution: StockCompany.badgeOf(widget.ticker),
          size: 30,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: widget.ticker,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    TextSpan(
                      text: '  ${company.name}',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
                style: denseStyle(context, size: 16),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                details.join(' · '),
                style: mutedStyle(context),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Wide: the company and valuation, the other groups, and the criteria
  /// apart on the right. Narrower: the two columns over the criteria. On a
  /// phone, one under the other.
  Widget _layout({
    required List<Widget> first,
    required List<Widget> second,
    required Widget criteria,
  }) {
    Widget column(List<Widget> panels) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, panel) in panels.indexed) ...[
          if (i > 0) const SizedBox(height: 14),
          panel is Panel ? panel : Panel(child: panel),
        ],
      ],
    );
    criteria = Panel(child: criteria);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        const most = 360.0;
        if (width >= 1250) {
          final side = analysisSideWidth(width);
          final each = ((width - side - 48 - 24) / 2).clamp(0.0, most);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: each, child: column(first)),
              const SizedBox(width: 24),
              SizedBox(width: each, child: column(second)),
              const Spacer(),
              const SizedBox(width: 48),
              SizedBox(width: side, child: criteria),
            ],
          );
        }
        if (width >= 760) {
          final each = ((width - 24) / 2).clamp(0.0, most);
          return column([
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: each, child: column(first)),
                const SizedBox(width: 24),
                SizedBox(width: each, child: column(second)),
              ],
            ),
            criteria,
          ]);
        }
        return column([...first, ...second, criteria]);
      },
    );
  }

  List<Widget> _notes(Fundamentals f) => [
    if (f.company.financial)
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          'Banco ou seguradora: EBIT, margens, EV e dívida não se aplicam. '
          'Olhe ROE, P/VP, P/L e proventos.',
          style: mutedStyle(context),
        ),
      ),
    if (f.company.fromSec && f.price == null)
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          'Sem a cotação na bolsa de origem, os indicadores de preço ficam '
          'de fora. Confira na aba da AUVP Analítica.',
          style: mutedStyle(context),
        ),
      ),
  ];

  Widget _group(Fundamentals f, IndicatorGroup group) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SectionTitle(group.label),
      for (final indicator in Indicator.all.where(
        (i) => i.group == group && i.id != 'graham' && i.id != 'bazin',
      ))
        _IndicatorRow(fundamentals: f, indicator: indicator),
    ],
  );

  Widget _charts(Fundamentals f) {
    final company = f.company;
    YearSeries series(String label, double? Function(Figures) pick) =>
        YearSeries(label, {
          for (final y in company.sortedYears)
            if (pick(company.years[y]!) case final v?) y: v,
        });
    YearSeries ratioSeries(String label, String id) =>
        YearSeries(label, f.history(Indicator.byId(id)));
    final charts = [
      (
        'Receita e lucro (${currencySymbol(company.currency)})',
        YearChart(
          series: [
            series('Receita líquida', (y) => y[Figure.revenue]),
            series('Lucro líquido', (y) => y[Figure.netIncome]),
          ],
          format: amountShort,
        ),
      ),
      (
        'Margens',
        YearChart(
          bars: false,
          series: [
            if (!company.financial) ratioSeries('EBIT', 'ebitMargin'),
            if (!company.financial) ratioSeries('Líquida', 'netMargin'),
            ratioSeries('ROE', 'roe'),
          ],
          format: percent,
        ),
      ),
      (
        'Proventos por ação (pagos no ano)',
        YearChart(
          series: [YearSeries('Por ação', f.dividendsPerShare)],
          format: (v) => pricePerShare(v, currency: company.currency),
        ),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1000 ? 3 : 1;
        final width = (constraints.maxWidth - (columns - 1) * 20) / columns;
        return Wrap(
          spacing: 20,
          runSpacing: 12,
          children: [
            for (final (title, chart) in charts)
              SizedBox(
                width: width,
                child: Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SectionTitle(title),
                      const SizedBox(height: 6),
                      chart,
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// While the statements are not here yet.
class StatementsLoading extends StatelessWidget {
  const StatementsLoading({super.key, required this.store});

  final CvmStore store;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (store.error != null && !store.busy) ...[
              Text(store.error!, style: denseStyle(context, size: 13)),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  onPressed: () => store.ensure(force: true),
                  child: const Text('Tentar de novo'),
                ),
              ),
            ] else ...[
              Text(
                store.progress ?? 'Preparando',
                style: denseStyle(context, size: 13),
              ),
              const SizedBox(height: 6),
              const LinearProgressIndicator(minHeight: 2),
              const SizedBox(height: 8),
              Text(
                'Na primeira vez o app baixa os balanços de todas as empresas da '
                'bolsa na CVM, cerca de 90 MB. Depois, só o que a CVM mudar.',
                style: mutedStyle(context),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _IndicatorRow extends StatelessWidget {
  const _IndicatorRow({required this.fundamentals, required this.indicator});

  final Fundamentals fundamentals;
  final Indicator indicator;

  @override
  Widget build(BuildContext context) {
    final history = fundamentals.history(indicator);
    final value = fundamentals.value(indicator);
    final years = history.keys.toList()..sort();
    return Tooltip(
      message: [
        indicator.formula,
        if (years.isNotEmpty)
          years
              .map(
                (y) =>
                    '$y: ${formatIndicator(indicator, history[y], currency: fundamentals.company.currency)}',
              )
              .join('   '),
      ].join('\n'),
      waitDuration: const Duration(milliseconds: 400),
      child: HoverRow(
        child: Row(
          children: [
            Expanded(
              child: Text(
                indicator.label,
                style: labelStyle(context),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Sparkline([for (final y in years) history[y]!]),
            SizedBox(
              width: 92,
              child: Text(
                formatIndicator(
                  indicator,
                  value,
                  currency: fundamentals.company.currency,
                ),
                textAlign: TextAlign.right,
                style: valueStyle(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The questions of the stock questionnaire with what the numbers say, beside
/// the user's answer. Filling them in is the user's call.
/// The stock questionnaire of Carteira e aporte, with what the numbers say:
/// each question answered by hand, or with the numbers' answer ("usar").
class _CriteriaPanel extends StatelessWidget {
  const _CriteriaPanel({
    required this.fundamentals,
    this.brlPerUnit = 1,
    this.held = true,
  });

  final Fundamentals fundamentals;
  final double? brlPerUnit;
  final bool held;

  String get _key => fundamentals.ticker;

  void _save(DiagramState state) {
    state.touch(_key);
    // Not held: graded, it goes to Carteira e aporte to study.
    if (!held && !state.watched.containsKey(_key)) {
      state.watched[_key] = fundamentals.company.fromSec
          ? DiagramClass.intlStock
          : DiagramClass.nationalStock;
    }
    state.save();
  }

  void _set(DiagramState state, Map<String, String?> values) {
    final answers = state.answers.putIfAbsent(_key, () => {});
    final skipped = state.skipped.putIfAbsent(_key, () => {});
    for (final MapEntry(key: question, :value) in values.entries) {
      answers.remove(question);
      skipped.remove(question);
      if (value == 'yes') answers[question] = true;
      if (value == 'no') answers[question] = false;
      if (value == 'na') skipped.add(question);
    }
    _save(state);
  }

  @override
  Widget build(BuildContext context) {
    final state = DiagramState.load();
    final now = DateTime.now();
    final questions = state.questionsOf(QuestionSet.stock);
    final auto = fundamentals.criteria(now, brlPerUnit: brlPerUnit);
    final answers = state.answers[_key] ?? const <String, bool>{};
    final skipped = state.skipped[_key] ?? const <String>{};
    final empty = {
      for (final q in questions)
        if (auto[q] != null && !answers.containsKey(q) && !skipped.contains(q))
          q: auto[q]!.$1 ? 'yes' : 'no',
    };
    final grade = questionnaireGrade(questions, answers, skipped: skipped);
    final at = state.gradedAt[_key];
    final stale = state.isStale(_key, now);
    final scheme = Theme.of(context).colorScheme;
    final date = DateFormat('dd/MM/yyyy');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle(
          'Nota em Carteira e aporte',
          trailing: InfoTip(
            'O questionário de ações de Carteira e aporte. Sim soma 1, não tira '
            '1, N/A não conta; só nota positiva recebe aporte.\n\nÀ esquerda, o '
            'que os números dizem (✓ sim, ✕ não, – não dizem); "usar" responde '
            'com eles. Liderança, gestão e inovação ficam com você.',
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Text(
                'Nota ${grade ?? '—'}',
                style: denseStyle(
                  context,
                  size: 15,
                ).copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  [
                    if (at != null) 'Respondida em ${date.format(at)}',
                    'próxima revisão ${date.format(DiagramState.nextReview(now))}',
                  ].join(' · '),
                  style: mutedStyle(context, size: 12),
                ),
              ),
              if (empty.isNotEmpty)
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  onPressed: () => _set(state, empty),
                  child: Text('Usar os números em ${empty.length}'),
                ),
            ],
          ),
        ),
        if (at != null && stale)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.errorContainer,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Revisão de ${DateFormat('dd/MM').format(DiagramState.reviewStart(now))} '
                    'pendente: confira as respostas com os balanços novos.',
                    style: denseStyle(
                      context,
                      size: 12,
                    ).copyWith(color: scheme.onErrorContainer),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  onPressed: () => _save(state),
                  child: const Text('Revisei, continua igual'),
                ),
              ],
            ),
          ),
        for (final question in questions)
          _criterion(
            context,
            question,
            auto[question],
            skipped.contains(question)
                ? 'na'
                : switch (answers[question]) {
                    true => 'yes',
                    false => 'no',
                    null => null,
                  },
            onAnswer: (value) => _set(state, {question: value}),
          ),
      ],
    );
  }

  Widget _criterion(
    BuildContext context,
    String question,
    (bool, String)? auto,
    String? answer, {
    required void Function(String? value) onAnswer,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final good = Colors.green.shade600;
    final suggested = auto == null ? null : (auto.$1 ? 'yes' : 'no');
    final differs = suggested != null && answer != suggested;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: SizedBox(
                  width: 22,
                  child: auto == null
                      ? Icon(Icons.remove, size: 14, color: scheme.outline)
                      : Icon(
                          auto.$1 ? Icons.check_circle : Icons.cancel,
                          size: 16,
                          color: auto.$1 ? good : scheme.error,
                          semanticLabel: auto.$1 ? 'Sim' : 'Não',
                        ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      question,
                      style: denseStyle(
                        context,
                        size: 13,
                      ).copyWith(height: 1.35, fontWeight: FontWeight.w500),
                    ),
                    if (auto != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        auto.$2,
                        style: mutedStyle(
                          context,
                          size: 12,
                        ).copyWith(height: 1.35),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const SizedBox(width: 22),
              SegmentedButton<String>(
                emptySelectionAllowed: true,
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity(horizontal: -3, vertical: -3),
                  textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
                ),
                segments: const [
                  ButtonSegment(value: 'yes', label: Text('Sim')),
                  ButtonSegment(value: 'no', label: Text('Não')),
                  ButtonSegment(
                    value: 'na',
                    label: Text('N/A'),
                    tooltip: 'Não se aplica: não conta na nota',
                  ),
                ],
                selected: {?answer},
                onSelectionChanged: (value) =>
                    onAnswer(value.isEmpty ? null : value.single),
              ),
              const Spacer(),
              if (differs)
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  onPressed: () => onAnswer(suggested),
                  child: Text('usar: ${suggested == 'yes' ? 'Sim' : 'Não'}'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Ten years of statements and the last twelve months, in columns.
class _StatementsTable extends StatelessWidget {
  const _StatementsTable({required this.company});

  final CvmCompany company;

  static const _labelWidth = 190.0;
  static const _columnWidth = 82.0;

  @override
  Widget build(BuildContext context) {
    final years = company.sortedYears.reversed.toList();
    final columns = <(String, Figures)>[
      if (company.ttm != null && company.ttmEnd != null)
        ('12m ${DateFormat('MM/yy').format(company.ttmEnd!)}', company.ttm!),
      for (final y in years) ('$y', company.years[y]!),
    ];
    double? margin(Figures f) {
      final income = f[Figure.netIncome];
      final revenue = f[Figure.revenue];
      return income == null || revenue == null || revenue == 0
          ? null
          : income / revenue;
    }

    double? payout(Figures f) {
      final income = f[Figure.netIncome];
      final paid = f[Figure.dividendsPaid];
      return income == null || paid == null || income <= 0
          ? null
          : paid / income;
    }

    final sections =
        <(String, List<(String, double? Function(Figures), bool)>)>[
          (
            'Resultado',
            [
              ('Receita líquida', (f) => f[Figure.revenue], false),
              if (!company.financial) ...[
                ('Custos', (f) => f[Figure.costs], false),
                ('Lucro bruto', (f) => f[Figure.grossProfit], false),
                (
                  'Despesas operacionais',
                  (f) => f[Figure.operatingExpenses],
                  false,
                ),
                ('EBITDA', (f) => f.ebitda, false),
                (
                  'Depreciação e amortização',
                  (f) => f[Figure.depreciation],
                  false,
                ),
                ('EBIT', (f) => f[Figure.ebit], false),
              ],
              ('Imposto de renda', (f) => f[Figure.incomeTax], false),
              ('Lucro líquido', (f) => f[Figure.netIncome], false),
              if (!company.financial) ('Margem líquida', margin, true),
            ],
          ),
          (
            'Balanço',
            [
              ('Ativo total', (f) => f[Figure.assets], false),
              if (!company.financial) ...[
                ('Ativo circulante', (f) => f[Figure.currentAssets], false),
                (
                  'Ativo não circulante',
                  (f) => f[Figure.nonCurrentAssets],
                  false,
                ),
                ('Caixa e aplicações', (f) => f[Figure.cash], false),
                ('Passivo total', (f) => f.liabilities, false),
                (
                  'Passivo circulante',
                  (f) => f[Figure.currentLiabilities],
                  false,
                ),
                (
                  'Passivo não circulante',
                  (f) => f[Figure.nonCurrentLiabilities],
                  false,
                ),
                ('Dívida bruta', (f) => f[Figure.grossDebt], false),
                ('Dívida líquida', (f) => f.netDebt, false),
              ],
              ('Patrimônio líquido', (f) => f[Figure.equity], false),
            ],
          ),
          (
            'Fluxo de caixa',
            [
              ('Caixa das operações', (f) => f[Figure.cfo], false),
              ('Caixa dos investimentos', (f) => f[Figure.cfi], false),
              ('Caixa dos financiamentos', (f) => f[Figure.cff], false),
              ('Variação cambial no caixa', (f) => f[Figure.fxEffect], false),
              ('Variação do caixa', (f) => f.cashChange, false),
              ('Caixa no fim', (f) => f[Figure.cashEnd], false),
              ('Investimento (capex)', (f) => f[Figure.capex], false),
              ('Fluxo de caixa livre', (f) => f.freeCashFlow, false),
              ('Proventos pagos', (f) => f[Figure.dividendsPaid], false),
              ('Payout', payout, true),
            ],
          ),
        ];
    final scheme = Theme.of(context).colorScheme;
    final style = denseStyle(context, size: 12);
    Widget cell(String text, {bool bold = false, Color? color}) => SizedBox(
      width: _columnWidth,
      child: Text(
        text,
        textAlign: TextAlign.right,
        style: style.copyWith(
          fontWeight: bold ? FontWeight.w700 : null,
          color: color,
        ),
      ),
    );
    final rows = <Widget>[
      SizedBox(
        height: 24,
        child: Row(
          children: [
            const SizedBox(width: _labelWidth),
            for (final (title, _) in columns) cell(title, bold: true),
          ],
        ),
      ),
    ];
    for (final (title, lines) in sections) {
      rows.add(
        Container(
          height: 22,
          width: _labelWidth + columns.length * _columnWidth,
          alignment: Alignment.centerLeft,
          color: scheme.onSurface.withValues(alpha: 0.05),
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            title,
            style: style.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      );
      for (final (label, pick, isPercent) in lines) {
        rows.add(
          SizedBox(
            height: 21,
            child: Row(
              children: [
                SizedBox(
                  width: _labelWidth,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(label, style: style),
                  ),
                ),
                for (final (_, figures) in columns)
                  switch (pick(figures)) {
                    null => cell('—', color: scheme.onSurfaceVariant),
                    final v => cell(
                      isPercent ? percent(v) : amountShort(v),
                      color: v < 0 ? scheme.error : null,
                    ),
                  },
              ],
            ),
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          'Demonstrativos (consolidados, ${currencySymbol(company.currency)}'
          '${company.fromSec ? ', SEC' : ''})',
        ),
        const SizedBox(height: 2),
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
