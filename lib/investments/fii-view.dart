import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:aupp/components/time-chart.dart';
import 'package:aupp/desktop/analysis-widgets.dart';
import 'package:aupp/investments/b3-market.dart';
import 'package:aupp/investments/fii-data.dart';
import 'package:aupp/investments/fii-store.dart';

final _whole = NumberFormat('#,##0', 'pt_BR');
final _monthYear = DateFormat('MM/yyyy');

String monthLabel(DateTime date) => _monthYear.format(date);

/// A fund with its price and what was traded today, from brapi's list.
class FiiQuote {
  final String ticker;
  final FiiFund fund;
  final double? price;

  /// In reais: brapi's volume times the price.
  final double? traded;

  const FiiQuote(this.ticker, this.fund, {this.price, this.traded});

  /// The fund of [ticker] with brapi's price, or [price] when given.
  static FiiQuote? of(String ticker, {double? price}) {
    final fund = FiiStore.instance.byTicker(ticker);
    if (fund == null) return null;
    final row = B3Market.funds[ticker];
    final at = price ?? row?.price;
    return FiiQuote(
      ticker,
      fund,
      price: at,
      traded: row == null || at == null ? null : row.volume * at,
    );
  }
}

/// The numbers of a fund, in the Ficha and in Comparar. [better] is 1 when
/// higher is better, -1 when lower is, 0 when neither.
enum FiiIndicator {
  pvp('P/VP', -1, 'Preço sobre o valor patrimonial da cota. Perto de 1 é o preço justo pelos imóveis; abaixo, desconto.'),
  dy('DY 12 meses', 1, 'Rendimentos dos últimos 12 meses sobre o preço de hoje.'),
  lastDividend('Último rendimento', 0, 'Pago por cota no último mês informado.'),
  paid('Meses com pagamento', 1, 'Dos últimos 24 meses informados. Constância importa mais que o valor.'),
  swing('Variação do rendimento', -1, 'Desvio-padrão sobre a média dos últimos 12 meses. Baixo é estável.'),
  price('Preço', 0, null),
  book('Valor patrimonial/cota', 0, null),
  marketCap('Valor de mercado', 0, null),
  equity('Patrimônio', 1, null),
  traded('Negociado hoje', 1, 'Liquidez: quanto foi negociado hoje na bolsa.'),
  holders('Cotistas', 1, null),
  vacancy('Vacância física', -1, 'Por área, nos imóveis prontos para renda, no último informe trimestral.'),
  properties('Imóveis', 1, 'Prontos para renda. Monoativo é risco.'),
  adminFee('Taxa de administração', -1, 'Despesa com a taxa nos últimos 12 meses, sobre o patrimônio.');

  const FiiIndicator(this.label, this.better, this.help);
  final String label;
  final int better;
  final String? help;

  double? value(FiiQuote q) {
    final f = q.fund;
    final price = q.price;
    return switch (this) {
      pvp => price == null ? null : f.pvp(price),
      dy => price == null ? null : f.dividendYield(price),
      lastDividend => f.lastDividend,
      paid => switch (f.paidMonths(24)) {
        (_, 0) => null,
        (final paid, final of) => paid / of,
      },
      swing => f.dividendSwing(12),
      FiiIndicator.price => price,
      book => f.bookPerShare,
      marketCap => price == null ? null : f.marketCap(price),
      equity => f.last?.equity,
      traded => q.traded,
      holders => f.last?.holders?.toDouble(),
      vacancy => f.vacancy,
      FiiIndicator.properties =>
        f.properties.isEmpty ? null : f.rentedCount.toDouble(),
      adminFee => f.adminFee12m,
    };
  }

  String format(FiiQuote q) {
    final v = value(q);
    if (v == null || !v.isFinite) return '—';
    return switch (this) {
      pvp => ratio(v),
      dy || swing || vacancy || adminFee => percent(v),
      lastDividend || FiiIndicator.price || book => pricePerShare(v),
      marketCap || equity || traded => moneyShort(v),
      holders || FiiIndicator.properties => _whole.format(v),
      paid => switch (q.fund.paidMonths(24)) {
        (final paid, final of) => '$paid de $of',
      },
    };
  }
}

/// While the reports are downloaded, or why they could not be.
class FiiLoading extends StatelessWidget {
  const FiiLoading({super.key});

  @override
  Widget build(BuildContext context) {
    final store = FiiStore.instance;
    if (store.error != null && !store.busy) {
      return Row(
        children: [
          Expanded(
            child: Text(store.error!, style: denseStyle(context, size: 13)),
          ),
          OutlinedButton(
            onPressed: () => store.ensure(force: true),
            child: const Text('Tentar de novo'),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          store.progress ?? 'Preparando',
          style: denseStyle(context, size: 13),
        ),
        const SizedBox(height: 6),
        const LinearProgressIndicator(minHeight: 2),
        const SizedBox(height: 8),
        Text(
          'Na primeira vez o app baixa da CVM os informes de todos os FIIs, '
          'cerca de 10 MB. Depois, só o que a CVM mudar.',
          style: mutedStyle(context),
        ),
      ],
    );
  }
}

/// Shares as bars: label, bar and percentage.
class ShareBars extends StatelessWidget {
  const ShareBars(this.shares, {super.key, this.color});

  final List<(String, double)> shares;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final top = shares.fold<double>(0, (m, s) => s.$2 > m ? s.$2 : m);
    return Column(
      children: [
        for (final (label, share) in shares)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Text(
                    label,
                    style: labelStyle(context),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: top <= 0 ? 0 : (share / top).clamp(0.0, 1.0),
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: color ?? scheme.primary,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    percent(share),
                    textAlign: TextAlign.right,
                    style: valueStyle(context),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The fund in the Ficha: its numbers, payments, book value, what it holds and
/// its properties, from its reports to the CVM.
class FiiPanel extends StatefulWidget {
  const FiiPanel({
    super.key,
    required this.ticker,
    this.price,
    this.history = const [],
  });

  final String ticker;
  final double? price;

  /// Closes of the price, to set beside the book value.
  final List<(DateTime, double)> history;

  @override
  State<FiiPanel> createState() => _FiiPanelState();
}

class _FiiPanelState extends State<FiiPanel> {
  bool _allProperties = false;

  @override
  void initState() {
    super.initState();
    FiiStore.instance.ensure();
    B3Market.funds.ensure();
  }

  Widget _card(String title, Widget child, {Widget? trailing}) => Card(
    margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final store = FiiStore.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([store, B3Market.funds]),
      builder: (context, _) {
        if (!store.ready) {
          return _card('Dados do fundo', const FiiLoading());
        }
        final q = FiiQuote.of(widget.ticker, price: widget.price);
        if (q == null) {
          return _card(
            'Dados do fundo',
            Text(
              'Não achei os informes de ${widget.ticker} na CVM.',
              style: denseStyle(context, size: 13),
            ),
          );
        }
        final wide = MediaQuery.sizeOf(context).width >= 1100;
        final dividends = _dividends(q);
        final book = _book(q);
        final holdings = _holdings(q.fund);
        final properties = _properties(q.fund);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _indicators(q),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: dividends),
                  Expanded(child: book),
                ],
              )
            else ...[
              dividends,
              book,
            ],
            if (wide && properties != null)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: properties),
                  Expanded(flex: 2, child: holdings),
                ],
              )
            else ...[
              holdings,
              ?properties,
            ],
          ],
        );
      },
    );
  }

  Widget _indicators(FiiQuote q) {
    final f = q.fund;
    final facts = [
      ?f.kind?.label,
      ?f.segment,
      if (f.since != null) 'desde ${f.since!.year}',
      if (f.management != null) 'gestão ${f.management!.toLowerCase()}',
      ?f.administrator,
    ];
    return _card(
      'Dados do fundo',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(facts.join(' · '), style: mutedStyle(context, size: 12)),
          const SizedBox(height: 8),
          Wrap(
            children: [
              for (final indicator in FiiIndicator.values)
                if (indicator != FiiIndicator.price &&
                    indicator.value(q) != null)
                  StatCell(
                    indicator.label,
                    indicator.format(q),
                    tooltip: indicator.help,
                  ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Informe mensal de ${monthLabel(f.last!.date)}'
            '${f.quarter == null ? '' : ', trimestral de ${monthLabel(f.quarter!)}'}'
            ' (CVM). Preço da brapi.dev.',
            style: mutedStyle(context, size: 11),
          ),
        ],
      ),
    );
  }

  Widget _dividends(FiiQuote q) {
    final f = q.fund;
    final color = seriesColor(context, 2);
    final (paid, of) = f.paidMonths(24);
    final swing = f.dividendSwing(12);
    return _card(
      'Rendimentos por cota',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TimeChart(
            bars: true,
            height: 180,
            series: [
              TimeSeries('Rendimento', color, [
                for (final m in f.months)
                  if (m.dividendPerShare case final v?) (m.date, v),
              ]),
            ],
            format: pricePerShare,
            dateLabel: monthLabel,
            axisLabel: monthLabel,
          ),
          const SizedBox(height: 6),
          Text(
            [
              'Pagou em $paid de $of meses',
              if (swing != null) 'variação de ${percent(swing)} no último ano',
            ].join(' · '),
            style: denseStyle(context),
          ),
          Text(
            'Calculado do informe mensal: dividend yield do mês sobre o '
            'patrimônio × valor patrimonial da cota.',
            style: mutedStyle(context, size: 11),
          ),
        ],
      ),
    );
  }

  Widget _book(FiiQuote q) {
    final f = q.fund;
    final start = f.months.firstOrNull?.date;
    // A close a month, the last of each, from the same start.
    final closes = <DateTime, (DateTime, double)>{};
    for (final (date, close) in widget.history) {
      if (start != null && date.isBefore(start)) continue;
      closes[DateTime(date.year, date.month)] = (date, close);
    }
    return _card(
      'Preço e valor patrimonial',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TimeChart(
            height: 180,
            series: [
              TimeSeries('Valor patrimonial/cota', seriesColor(context, 0), [
                for (final m in f.months)
                  if (m.bookPerShare case final v?) (m.date, v),
              ]),
              if (closes.isNotEmpty)
                TimeSeries('Preço', seriesColor(context, 1), [
                  for (final c in closes.values) c,
                ]),
            ],
            format: pricePerShare,
            dateLabel: (d) => DateFormat('dd/MM/yyyy').format(d),
            axisLabel: monthLabel,
          ),
          const SizedBox(height: 6),
          Text(
            'O preço abaixo do valor patrimonial é desconto sobre os ativos; '
            'acima, ágio.',
            style: mutedStyle(context, size: 11),
          ),
        ],
      ),
    );
  }

  Widget _holdings(FiiFund f) {
    final mix = f.mix;
    final tenants = f.tenants.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topTenants = [
      for (final e in tenants.take(6)) (e.key, e.value),
      if (tenants.length > 6)
        ('Outros', tenants.skip(6).fold<double>(0, (s, e) => s + e.value)),
    ];
    Widget title(String text) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(
        text,
        style: denseStyle(context).copyWith(fontWeight: FontWeight.w700),
      ),
    );
    return _card(
      'O que o fundo tem',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (mix != null)
            ShareBars([
              for (final part in mix.parts)
                if (part.$2 >= 0.005) part,
            ])
          else
            Text('Sem a composição no informe.', style: mutedStyle(context)),
          if (topTenants.isNotEmpty) ...[
            title('Inquilinos por setor (da receita)'),
            ShareBars(topTenants, color: seriesColor(context, 1)),
          ],
          if (f.leases.isNotEmpty) ...[
            title('Fim dos contratos (da receita)'),
            ShareBars(f.leases, color: seriesColor(context, 3)),
          ],
          if (f.indexes.isNotEmpty) ...[
            title('Reajuste dos aluguéis'),
            ShareBars([
              for (final e in f.indexes.entries) (e.key, e.value),
            ], color: seriesColor(context, 6)),
          ],
        ],
      ),
    );
  }

  Widget? _properties(FiiFund f) {
    if (f.properties.isEmpty) return null;
    final style = denseStyle(context, size: 12);
    final head = style.copyWith(fontWeight: FontWeight.w700);
    final shown = _allProperties ? f.properties : f.properties.take(12);
    final scheme = Theme.of(context).colorScheme;
    String share(double? v) => v == null ? '—' : percent(v);
    return _card(
      'Imóveis (${f.properties.length})',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Imóvel', style: head)),
              SizedBox(
                width: 84,
                child: Text('Área m²', textAlign: TextAlign.right, style: head),
              ),
              SizedBox(
                width: 72,
                child: Text('Vacância', textAlign: TextAlign.right, style: head),
              ),
              SizedBox(
                width: 72,
                child: Text('Receita', textAlign: TextAlign.right, style: head),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final (i, p) in shown.indexed)
            Container(
              color: i.isOdd ? scheme.onSurface.withValues(alpha: 0.035) : null,
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Tooltip(
                      message: p.kind ?? '',
                      child: Text(
                        p.name,
                        style: style.copyWith(
                          color: p.rented ? null : scheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 84,
                    child: Text(
                      p.area == null ? '—' : _whole.format(p.area),
                      textAlign: TextAlign.right,
                      style: style,
                    ),
                  ),
                  SizedBox(
                    width: 72,
                    child: Text(
                      share(p.vacancy),
                      textAlign: TextAlign.right,
                      style: style.copyWith(
                        color: (p.vacancy ?? 0) >= 0.2 ? scheme.error : null,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 72,
                    child: Text(
                      share(p.revenue),
                      textAlign: TextAlign.right,
                      style: style,
                    ),
                  ),
                ],
              ),
            ),
          if (f.properties.length > 12)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () =>
                    setState(() => _allProperties = !_allProperties),
                child: Text(
                  _allProperties
                      ? 'Mostrar menos'
                      : 'Mostrar os ${f.properties.length}',
                ),
              ),
            ),
          Text(
            'Receita: parte da receita do fundo. Em cinza, os que não estão '
            'prontos para renda.',
            style: mutedStyle(context, size: 11),
          ),
        ],
      ),
    );
  }
}
