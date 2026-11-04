import 'package:flutter/material.dart';
import 'package:aupp/components/info-tip.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:aupp/desktop/analysis-widgets.dart';
import 'package:aupp/investments/analysis-source.dart';
import 'package:aupp/investments/asset-sheet.dart';
import 'package:aupp/investments/b3-market.dart';
import 'package:aupp/investments/bank-capital.dart';
import 'package:aupp/investments/cvm-statements.dart';
import 'package:aupp/investments/fundamentals.dart';
import 'package:url_launcher/url_launcher.dart';

/// Sections of Análise beyond the indicators: the company's register, fair
/// prices, a bank's capital, the history of the indicators, its notices and
/// what it does.

/// Label and value in rows, as the indicator groups.
class FactsTable extends StatelessWidget {
  const FactsTable({
    super.key,
    required this.facts,
    this.title = 'Dados da empresa',
  });

  final List<(String, String)> facts;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(title),
        for (final (label, value) in facts)
          HoverRow(
            child: Row(
              children: [
                Text(label, style: labelStyle(context)),
                const SizedBox(width: 12),
                Expanded(
                  child: Tooltip(
                    message: value,
                    waitDuration: const Duration(milliseconds: 500),
                    child: Text(
                      value,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: valueStyle(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Register facts of a company of the B3.
class CompanyFacts extends StatelessWidget {
  const CompanyFacts({
    super.key,
    required this.fundamentals,
    this.market,
    this.lead = const [],
  });

  final Fundamentals fundamentals;
  final MarketRow? market;

  /// Shown first: the price and the date of the statements.
  final List<(String, String)> lead;

  @override
  Widget build(BuildContext context) {
    final company = fundamentals.company;
    final date = DateFormat('dd/MM/yyyy');
    final shares = company.shares;
    final row = market;
    final facts = <(String, String)>[
      ...lead,
      if (company.cnpj != null) ('CNPJ', company.cnpj!),
      if (shares != null)
        ('Ações', '${NumberFormat('#,##0.00', 'pt_BR').format(shares / 1e9)} bi'),
      if (company.freeFloat != null)
        ('Free float', percent(company.freeFloat!)),
      if (tagAlongOf(company.segment) case final tag?) ('Tag along', tag),
      if (company.segment != null) ('Segmento', company.segment!),
      if (company.listed != null) ('Na bolsa desde', date.format(company.listed!)),
      if (company.founded != null) ('Fundada em', date.format(company.founded!)),
      if (company.control != null) ('Controle', company.control!),
      if (company.sector != null) ('Setor (CVM)', company.sector!),
      if (row?.sector != null)
        (
          'Setor (brapi)',
          [?sectorLabel(row!.sector), ?row.subsector].join(' · '),
        ),
      if (row != null && row.volume > 0)
        ('Negociado hoje', moneyShort(row.volume * row.price)),
    ];
    return FactsTable(facts: facts);
  }
}

/// The register of a company abroad: where its numbers and price come from.
class ForeignFacts extends StatelessWidget {
  const ForeignFacts({super.key, required this.analysis, this.lead = const []});

  final ForeignAnalysis analysis;

  /// Shown first: the price and the date of the statements.
  final List<(String, String)> lead;

  @override
  Widget build(BuildContext context) {
    final f = analysis.fundamentals;
    final company = f.company;
    final price = analysis.price;
    final shares = company.shares;
    final ratio = price?.adrShares;
    final facts = <(String, String)>[
      ...lead,
      ('Balanços', company.foreignIssuer ? 'SEC (20-F, anual)' : 'SEC (10-K e 10-Q)'),
      ('Moeda dos balanços', company.currency),
      if (company.segment != null) ('Bolsa', company.segment!),
      if (shares != null)
        ('Ações', '${NumberFormat('#,##0.00', 'pt_BR').format(shares / 1e9)} bi'),
      if (price != null)
        (
          'Preço usado',
          '${price.symbol} ${pricePerShare(price.price, currency: price.currency)}',
        ),
      if (ratio != null && company.foreignIssuer)
        (
          'ADR',
          '1 ADR ≈ ${NumberFormat('#,##0.##', 'pt_BR').format(ratio)} '
              '${ratio < 1.5 ? 'ação' : 'ações'} (pelas duas cotações)',
        ),
      if (analysis.brlPerUnit != null && company.currency != 'BRL')
        (
          'Câmbio (PTAX)',
          '1 ${company.currency} = R\$ ${NumberFormat('#,##0.0000', 'pt_BR').format(analysis.brlPerUnit)}',
        ),
    ];
    return FactsTable(facts: facts);
  }
}

/// Graham and Bazin: the fair price and the upside with its band, in rows
/// like the indicator groups.
class FairPricePanel extends StatelessWidget {
  const FairPricePanel({super.key, required this.fundamentals});

  final Fundamentals fundamentals;

  @override
  Widget build(BuildContext context) {
    final currency = fundamentals.company.currency;
    Widget row(String label, String value) => HoverRow(
      child: Row(
        children: [
          Expanded(child: Text(label, style: labelStyle(context))),
          Text(value, style: valueStyle(context)),
        ],
      ),
    );
    List<Widget> rows(String name, FairPrice? fair) => [
      row(name, fair == null ? '—' : pricePerShare(fair.fair, currency: currency)),
      row(
        'Upside $name',
        fair == null
            ? '—'
            : '${fair.upside >= 0 ? '+' : ''}${percent(fair.upside)} · '
                  '${fair.band.label.toLowerCase()}',
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle(
          'Preço justo',
          trailing: InfoTip(
            'Graham: √(22,5 × LPA × VPA), exige lucro e patrimônio positivos. '
            'Bazin: proventos por ação, média de 5 anos ÷ 6%.\n\n'
            'Upside = preço justo ÷ preço − 1. Faixas: abaixo de −30% muito caro, '
            'até −10% caro, até +10% próximo, até +30% abaixo do justo, acima '
            'disso muito barato. Serve para filtrar, não para decidir sozinho.',
          ),
        ),
        ...rows('Graham', fundamentals.graham),
        ...rows('Bazin', fundamentals.bazin),
      ],
    );
  }
}

/// A bank's Basel and fixed-asset ratios against the Banco Central's limits.
class BankCapitalPanel extends StatefulWidget {
  const BankCapitalPanel({super.key, required this.cnpj});

  final String cnpj;

  @override
  State<BankCapitalPanel> createState() => _BankCapitalPanelState();
}

class _BankCapitalPanelState extends State<BankCapitalPanel> {
  late final Future<BankCapital?> _capital = BankCapital.fetch(widget.cnpj);

  Widget _ratio(
    String label,
    double value,
    String rule,
    (String, Color) Function(double) judge,
  ) {
    final (verdict, color) = judge(value);
    return Expanded(
      child: Tooltip(
        message: rule,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: mutedStyle(context)),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: percent(value),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text: '  $verdict',
                    style: TextStyle(color: color, fontSize: 12),
                  ),
                ],
              ),
              style: denseStyle(context, size: 15),
            ),
            const SizedBox(height: 3),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: (value * 2).clamp(0.0, 1.0),
                minHeight: 5,
                color: color,
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final good = Colors.green.shade600;
    final warn = Colors.orange.shade700;
    return FutureBuilder<BankCapital?>(
      future: _capital,
      builder: (context, snapshot) {
        final capital = snapshot.data;
        if (snapshot.connectionState != ConnectionState.done) {
          return const SectionTitle('Basileia e imobilização · buscando');
        }
        if (capital == null) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionTitle(
              'Basileia e imobilização · Banco Central, '
              '${DateFormat('MM/yyyy').format(capital.at)}',
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                _ratio(
                  'Índice de Basileia',
                  capital.basel,
                  'Capital próprio ÷ ativos ponderados pelo risco. Mínimo do Banco '
                      'Central: 11%. Bom acima de 14%.',
                  (v) => v > 0.14
                      ? ('Bom', good)
                      : v >= 0.11
                      ? ('Atenção', warn)
                      : ('Abaixo do mínimo', scheme.error),
                ),
                const SizedBox(width: 16),
                if (capital.fixedAssets != null)
                  _ratio(
                    'Índice de imobilização',
                    capital.fixedAssets!,
                    'Patrimônio aplicado em imóveis, equipamentos e afins. Máximo '
                        'do Banco Central: 50%. Bom abaixo de 30%.',
                    (v) => v < 0.3
                        ? ('Bom', good)
                        : v <= 0.5
                        ? ('Atenção', warn)
                        : ('Acima do limite', scheme.error),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Every indicator without a price, year by year.
class IndicatorHistoryTable extends StatefulWidget {
  const IndicatorHistoryTable({super.key, required this.fundamentals});

  final Fundamentals fundamentals;

  @override
  State<IndicatorHistoryTable> createState() => _IndicatorHistoryTableState();
}

class _IndicatorHistoryTableState extends State<IndicatorHistoryTable> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final f = widget.fundamentals;
    final years = f.company.sortedYears.reversed.toList();
    final scheme = Theme.of(context).colorScheme;
    final style = denseStyle(context, size: 12);
    const labelWidth = 170.0;
    const columnWidth = 76.0;
    final toggle = TextButton(
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        textStyle: const TextStyle(fontSize: 12),
      ),
      onPressed: () => setState(() => _open = !_open),
      child: Text(_open ? 'Recolher' : 'Mostrar'),
    );
    if (!_open) return SectionTitle('Histórico de indicadores', trailing: toggle);
    final rows = <Widget>[
      SizedBox(
        height: 22,
        child: Row(
          children: [
            const SizedBox(width: labelWidth),
            for (final y in years)
              SizedBox(
                width: columnWidth,
                child: Text(
                  '$y',
                  textAlign: TextAlign.right,
                  style: style.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ),
      ),
    ];
    for (final group in IndicatorGroup.values) {
      final indicators = [
        for (final i in Indicator.all)
          if (i.group == group && !i.usesPrice) i,
      ];
      if (indicators.isEmpty) continue;
      rows.add(
        Container(
          height: 20,
          width: labelWidth + years.length * columnWidth,
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
      for (final indicator in indicators) {
        final history = f.history(indicator);
        if (history.isEmpty) continue;
        rows.add(
          SizedBox(
            height: 20,
            child: Row(
              children: [
                SizedBox(
                  width: labelWidth,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(indicator.label, style: style),
                  ),
                ),
                for (final y in years)
                  SizedBox(
                    width: columnWidth,
                    child: Text(
                      formatIndicator(indicator, history[y]),
                      textAlign: TextAlign.right,
                      style: style,
                    ),
                  ),
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
          'Histórico de indicadores (os de preço ficam de fora: não há cotação '
          'antiga de graça)',
          trailing: toggle,
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

/// The last year's material facts and notices, opened in the browser.
class NoticesList extends StatefulWidget {
  const NoticesList({super.key, required this.notices, this.source = 'CVM'});

  final List<CvmNotice> notices;

  /// Where they were filed: "CVM" or "SEC".
  final String source;

  @override
  State<NoticesList> createState() => _NoticesListState();
}

class _NoticesListState extends State<NoticesList> {
  String? _category;
  bool _all = false;

  static const _short = {
    'Fato Relevante': 'Fato relevante',
    'Comunicado ao Mercado': 'Comunicado',
    'Aviso aos Acionistas': 'Aviso aos acionistas',
    'Relatório Proventos': 'Proventos',
  };

  static bool _important(CvmNotice n) =>
      n.category == 'Fato Relevante' || n.category == 'Resultados';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = [
      for (final n in widget.notices)
        if (_category == null || n.category == _category) n,
    ];
    final visible = _all ? shown : shown.take(15).toList();
    final style = denseStyle(context, size: 12);
    final date = DateFormat('dd/MM/yy');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          'Comunicados e fatos relevantes · ${widget.source}, últimos 12 meses',
          trailing: Wrap(
            spacing: 4,
            children: [
              for (final category in [
                null,
                ...{for (final n in widget.notices) n.category},
              ])
                ChoiceChip(
                  label: Text(
                    category == null ? 'Todos' : _short[category] ?? category,
                    style: const TextStyle(fontSize: 11),
                  ),
                  visualDensity: const VisualDensity(
                    horizontal: -4,
                    vertical: -4,
                  ),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  selected: _category == category,
                  onSelected: (_) => setState(() => _category = category),
                ),
            ],
          ),
        ),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text('Nada nos últimos 12 meses.', style: mutedStyle(context)),
          ),
        for (final n in visible)
          InkWell(
            onTap: () => launchUrl(
              Uri.parse(n.url),
              mode: LaunchMode.externalApplication,
            ),
            child: SizedBox(
              height: 21,
              child: Row(
                children: [
                  SizedBox(
                    width: 62,
                    child: Text(date.format(n.date), style: mutedStyle(context)),
                  ),
                  SizedBox(
                    width: 132,
                    child: Text(
                      _short[n.category] ?? n.category,
                      style: style.copyWith(
                        color: _important(n)
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                        fontWeight: _important(n) ? FontWeight.w600 : null,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      n.subject,
                      style: style,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(Icons.open_in_new, size: 12, color: scheme.outline),
                ],
              ),
            ),
          ),
        if (shown.length > 15)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontSize: 12),
              ),
              onPressed: () => setState(() => _all = !_all),
              child: Text(_all ? 'Mostrar menos' : 'Mostrar os ${shown.length}'),
            ),
          ),
      ],
    );
  }
}

/// What the company does, from brapi's profile.
class AboutCompany extends StatefulWidget {
  const AboutCompany({super.key, required this.ticker});

  final String ticker;

  @override
  State<AboutCompany> createState() => _AboutCompanyState();
}

class _AboutCompanyState extends State<AboutCompany> {
  late final Future<AssetProfile?> _profile = AssetProfile.fetch(widget.ticker);
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AssetProfile?>(
      future: _profile,
      builder: (context, snapshot) {
        final summary = snapshot.data?.summary;
        if (summary == null) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionTitle('Sobre a empresa'),
            const SizedBox(height: 4),
            InkWell(
              onTap: () => setState(() => _open = !_open),
              child: Text(
                summary,
                maxLines: _open ? null : 3,
                overflow: _open ? null : TextOverflow.ellipsis,
                style: denseStyle(context, size: 12.5).copyWith(height: 1.4),
              ),
            ),
          ],
        );
      },
    );
  }
}
