import 'package:flutter/material.dart';
import 'package:aupp/components/source-mark.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:aupp/components/time-chart.dart';
import 'package:aupp/desktop/analysis-widgets.dart';
import 'package:aupp/investments/asset-sheet.dart';
import 'package:aupp/investments/cvm-funds.dart';
import 'package:aupp/investments/fii-view.dart';
import 'package:aupp/investments/sec-fund.dart';
import 'package:aupp/investments/yahoo-chart.dart';
import 'package:aupp/investments/price-history.dart';
import 'package:http/http.dart' as http;

final _whole = NumberFormat('#,##0', 'pt_BR');
final _day = DateFormat('dd/MM/yyyy');

/// [unofficial]: where its figures come from when not an official source.
Widget _card(
  BuildContext context,
  String title,
  Widget child, {
  String? unofficial,
}) => Card(
  margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (unofficial != null) SourceMark(unofficial),
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  ),
);

/// Two cards side by side on a wide screen, one under the other on a narrow
/// one.
Widget _pair(BuildContext context, Widget left, Widget right) =>
    MediaQuery.sizeOf(context).width >= 1100
    ? Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: left),
          Expanded(child: right),
        ],
      )
    : Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [left, right],
      );

const _priceWithCvm =
    'A cota e o valor patrimonial são da CVM; o preço é de fonte não oficial '
    '(Yahoo Finance ou brapi.dev).';

Widget _note(BuildContext context, String text) =>
    Text(text, style: mutedStyle(context, size: 11));

String _signed(double v) => '${v >= 0 ? '+' : ''}${percent(v)}';

/// Which report of the CVM a kind of fund has.
FundReports? reportsOf(B3Type type) => switch (type) {
  B3Type.etf || B3Type.etfAbroad => FundReports.register,
  B3Type.fiagro => FundReports.fiagro,
  B3Type.infra || B3Type.fidc || B3Type.fund => FundReports.daily,
  _ => null,
};

/// A listed fund that is not a FII, in the Ficha: what the CVM has of it.
/// ETFs only have their register (net assets, manager); the funds with a
/// daily report their quota, holders and flows; Fiagros their monthly report.
class FundPanel extends StatefulWidget {
  const FundPanel({
    super.key,
    required this.instrument,
    this.price,
    this.history = const [],
  });

  final B3Instrument instrument;
  final double? price;
  final List<(DateTime, double)> history;

  @override
  State<FundPanel> createState() => _FundPanelState();
}

class _FundPanelState extends State<FundPanel> {
  final _store = CvmFundStore.instance;

  @override
  void initState() {
    super.initState();
    if (widget.instrument.cnpj == null) return;
    _store.ensure(FundReports.register);
    final reports = reportsOf(widget.instrument.type);
    if (reports != null && reports != FundReports.register) {
      _store.ensure(reports);
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.instrument.type;
    final cnpj = widget.instrument.cnpj;
    if (cnpj == null) {
      return _card(
        context,
        'Dados do fundo',
        Text(
          'Não achei com segurança o CNPJ deste fundo na CVM, e é por ele que '
          'a CVM publica os informes. Fica o preço acima e os sites.',
          style: denseStyle(context, size: 13),
        ),
      );
    }
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final reports = reportsOf(type)!;
        final fund = _store.fund(cnpj);
        if (fund == null || !_store.has(reports)) {
          return _card(context, 'Dados do fundo', _loading(context, reports));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _facts(context, fund),
            if (fund.days.length >= 2) _quotaChart(context, fund),
            if (fund.months.isNotEmpty) _fiagroCharts(context, fund),
          ],
        );
      },
    );
  }

  Widget _loading(BuildContext context, FundReports reports) {
    final error =
        _store.errorOf(reports) ?? _store.errorOf(FundReports.register);
    if (error != null && !_store.busy) {
      return Row(
        children: [
          Expanded(child: Text(error, style: denseStyle(context, size: 13))),
          OutlinedButton(
            onPressed: () {
              _store.ensure(FundReports.register, force: true);
              _store.ensure(reports, force: true);
            },
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
          _store.progress ?? 'Preparando',
          style: denseStyle(context, size: 13),
        ),
        const SizedBox(height: 6),
        const LinearProgressIndicator(minHeight: 2),
      ],
    );
  }

  Widget _facts(BuildContext context, CvmFund fund) {
    final type = widget.instrument.type;
    final day = fund.lastDay;
    final month = fund.months.lastOrNull;
    final price = widget.price;
    final equity = day?.equity ?? month?.equity ?? fund.equity;
    final holders = day?.holders ?? month?.holders;
    final cells = <Widget>[
      if (equity != null) StatCell('Patrimônio', moneyShort(equity)),
      if (holders != null && holders > 0)
        StatCell('Cotistas', _whole.format(holders)),
      if (day != null) ...[
        StatCell('Cota', pricePerShare(day.quota)),
        if (price != null && day.quota > 0)
          StatCell(
            price >= day.quota ? 'Ágio' : 'Deságio',
            percent((price / day.quota - 1).abs()),
            tooltip:
                'Preço na B3 sobre o valor da cota. Com ágio, paga-se mais '
                'que os ativos valem.',
            unofficial: Unofficial.brapiPrice,
          ),
        if (fund.quotaChange(182) case final r?)
          StatCell(
            'Variação da cota em 6 meses',
            _signed(r),
            tooltip:
                'Não é a rentabilidade: o fundo que distribui rendimentos (os '
                'de infraestrutura listados, quase todos) tira cada pagamento '
                'da cota.',
          ),
        if (fund.flowOver(182) case final f? when f != 0)
          StatCell(
            'Captação em 6 meses',
            moneyShort(f),
            tooltip: 'Aplicações menos resgates.',
          ),
      ],
      if (month != null) ...[
        if (month.bookPerShare case final book?) ...[
          StatCell('Valor patrimonial/cota', pricePerShare(book)),
          if (price != null && book > 0)
            StatCell(
              'P/VP',
              ratio(price / book),
              tooltip: 'Preço sobre o valor patrimonial da cota.',
              unofficial: Unofficial.brapiPrice,
            ),
        ],
        if (month.dividendPerShare case final paid?)
          StatCell(
            'Rendimento do mês',
            '${pricePerShare(paid)}'
                '${month.dividendYield == null ? '' : ' (${percent(month.dividendYield!)})'}',
            tooltip:
                'Rendimentos a distribuir do informe mensal sobre as cotas '
                'emitidas; entre parênteses, sobre o valor patrimonial.',
          ),
        if (fund.yearYield case final y?)
          StatCell(
            'Rendimento em 12 meses',
            percent(y),
            tooltip:
                'Soma do rendimento de cada mês sobre o valor patrimonial.',
          ),
      ],
    ];
    final facts = [
      type.label,
      if (fund.manager case final m?) 'gestão ${m.toLowerCase()}',
      ?fund.administrator,
      if (fund.since != null) 'desde ${fund.since!.year}',
    ];
    final source = day != null
        ? 'Informe diário de ${_day.format(day.date)} (CVM).'
        : month != null
        ? 'Informe mensal de ${monthLabel(month.date)} (CVM).'
        : fund.equityDate != null
        ? 'Cadastro da CVM, patrimônio de ${_day.format(fund.equityDate!)}.'
        : 'Cadastro da CVM.';
    return _card(
      context,
      'Dados do fundo',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(facts.join(' · '), style: mutedStyle(context, size: 12)),
          const SizedBox(height: 8),
          Wrap(children: cells),
          const SizedBox(height: 8),
          _note(
            context,
            [
              source,
              if (type == B3Type.etf || type == B3Type.etfAbroad)
                'ETF não entrega informe diário nem carteira à CVM: o '
                    'desempenho está no preço acima.',
            ].join(' '),
          ),
        ],
      ),
    );
  }

  Widget _quotaChart(BuildContext context, CvmFund fund) {
    final start = fund.days.first.date;
    final closes = [
      for (final (date, close) in widget.history)
        if (!date.isBefore(start)) (date, close),
    ];
    return _card(
      context,
      'Cota e preço',
      unofficial: closes.isEmpty ? null : _priceWithCvm,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TimeChart(
            height: 200,
            series: [
              TimeSeries('Cota', seriesColor(context, 0), [
                for (final d in fund.days) (d.date, d.quota),
              ]),
              if (closes.isNotEmpty)
                TimeSeries('Preço', seriesColor(context, 1), closes),
            ],
            format: pricePerShare,
            dateLabel: _day.format,
            axisLabel: monthLabel,
          ),
          const SizedBox(height: 6),
          _note(
            context,
            'A cota é o que os ativos do fundo valem por cota, dia a dia; o '
            'preço é o da B3. A distância entre as duas é o ágio ou deságio.',
          ),
        ],
      ),
    );
  }

  Widget _fiagroCharts(BuildContext context, CvmFund fund) {
    final start = fund.months.first.date;
    final closes = <DateTime, (DateTime, double)>{};
    for (final (date, close) in widget.history) {
      if (date.isBefore(start)) continue;
      closes[DateTime(date.year, date.month)] = (date, close);
    }
    return _pair(
      context,
      _card(
        context,
        'Rendimento por cota',
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TimeChart(
              bars: true,
              height: 180,
              series: [
                TimeSeries('Rendimento', seriesColor(context, 2), [
                  for (final m in fund.months)
                    if (m.dividendPerShare case final v?) (m.date, v),
                ]),
              ],
              format: pricePerShare,
              dateLabel: monthLabel,
              axisLabel: monthLabel,
            ),
            const SizedBox(height: 6),
            _note(
              context,
              'Rendimentos a distribuir de cada informe mensal sobre as cotas '
              'emitidas. O dividend yield que cada fundo informa não é usado: '
              'vem em unidades diferentes de um fundo para outro.',
            ),
          ],
        ),
      ),
      _card(
        context,
        'Preço e valor patrimonial',
        unofficial: closes.isEmpty ? null : _priceWithCvm,
        TimeChart(
          height: 180,
          series: [
            TimeSeries('Valor patrimonial/cota', seriesColor(context, 0), [
              for (final m in fund.months)
                if (m.bookPerShare case final v?) (m.date, v),
            ]),
            if (closes.isNotEmpty)
              TimeSeries('Preço', seriesColor(context, 1), [
                for (final c in closes.values) c,
              ]),
          ],
          format: pricePerShare,
          dateLabel: _day.format,
          axisLabel: monthLabel,
        ),
      ),
    );
  }
}

/// An ETF of the United States (itself, or behind a BDR of an ETF), in the
/// Ficha: its last N-PORT at the SEC.
class EtfAbroadPanel extends StatefulWidget {
  const EtfAbroadPanel({super.key, required this.ticker});

  /// A BDR of an ETF ("BIVB39") or the ETF itself ("IVV").
  final String ticker;

  @override
  State<EtfAbroadPanel> createState() => _EtfAbroadPanelState();
}

class _EtfAbroadPanelState extends State<EtfAbroadPanel> {
  late final B3Instrument? _bdr = B3Instrument.of(widget.ticker);

  String? get _usTicker => _bdr == null ? widget.ticker : _bdr.abroadTicker;

  late Future<EtfReport?> _report = _load();

  Future<EtfReport?> _load() async {
    final series =
        _bdr?.secSeries ??
        (_bdr == null
            ? await SecFundStore.instance.seriesOf(widget.ticker)
            : null);
    return series == null ? null : SecFundStore.instance.load(series);
  }

  @override
  Widget build(BuildContext context) {
    if (_bdr != null && _bdr.secSeries == null) {
      return _card(
        context,
        'Dados do ETF',
        Text(
          'Este ETF não tem série na SEC: é europeu (UCITS), de cripto ou de '
          'fora dos EUA, e não entrega a carteira (N-PORT). Fica o preço do '
          'BDR acima e os sites.',
          style: denseStyle(context, size: 13),
        ),
      );
    }
    return FutureBuilder<EtfReport?>(
      future: _report,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _card(
            context,
            'Dados do ETF',
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Buscando a carteira na SEC',
                  style: denseStyle(context, size: 13),
                ),
                const SizedBox(height: 6),
                const LinearProgressIndicator(minHeight: 2),
              ],
            ),
          );
        }
        final r = snapshot.data;
        if (r == null) {
          return _card(
            context,
            'Dados do ETF',
            Row(
              children: [
                Expanded(
                  child: Text(
                    _bdr == null
                        ? 'Não achei a carteira (N-PORT) deste ETF na SEC: '
                              'pode não ser um fundo registrado lá (ETF de '
                              'cripto ou de commodity é um trust e não entrega '
                              'N-PORT), ou a SEC não respondeu agora.'
                        : 'A SEC não devolveu a carteira (N-PORT) deste ETF '
                              'agora.',
                    style: denseStyle(context, size: 13),
                  ),
                ),
                OutlinedButton(
                  onPressed: () => setState(() => _report = _load()),
                  child: const Text('Tentar de novo'),
                ),
              ],
            ),
          );
        }
        return _view(context, r);
      },
    );
  }

  /// The ETF itself in the United States, for a BDR of it: years of price
  /// in dollars (Yahoo has a single day of most of these BDRs).
  late final Future<List<(DateTime, double)>> _usHistory = () async {
    final ticker = _usTicker;
    if (_bdr == null || ticker == null) return const <(DateTime, double)>[];
    final client = http.Client();
    try {
      return (await YahooChart.fetch(ticker, client))?.closes ??
          const <(DateTime, double)>[];
    } finally {
      client.close();
    }
  }();

  PriceRange _range = PriceRange.y5;

  Widget _usChart(BuildContext context) => FutureBuilder(
    future: _usHistory,
    builder: (context, snapshot) {
      final all = snapshot.data ?? const <(DateTime, double)>[];
      if (all.length < 30) return const SizedBox.shrink();
      final history = inRange(all, _range);
      final change = history.last.$2 / history.first.$2 - 1;
      String price(double v) => pricePerShare(v, currency: 'USD');
      return _card(
        context,
        '$_usTicker nos EUA',
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${price(history.last.$2)} · ${_signed(change)} no período, em '
              'dólar, sem os dividendos. O BDR acompanha este preço mais o '
              'câmbio.',
              style: mutedStyle(context, size: 12),
            ),
            const SizedBox(height: 6),
            PriceRangeBar(
              history: all,
              selected: _range,
              onChanged: (range) => setState(() => _range = range),
              source: Unofficial.yahoo,
            ),
            const SizedBox(height: 8),
            TimeChart(
              area: true,
              height: 180,
              series: [TimeSeries('Preço', seriesColor(context, 0), history)],
              format: price,
              dateLabel: _day.format,
              axisLabel: monthLabel,
            ),
          ],
        ),
        unofficial: Unofficial.yahoo,
      );
    },
  );

  Widget _view(BuildContext context, EtfReport r) {
    final returns = r.months.isEmpty
        ? null
        : _card(
            context,
            'Retorno por mês',
            TimeChart(
              bars: true,
              height: 220,
              series: [
                TimeSeries('Retorno', seriesColor(context, 0), r.months),
              ],
              format: _signed,
              dateLabel: monthLabel,
              axisLabel: monthLabel,
            ),
          );
    final top = _card(
      context,
      'Maiores posições',
      ShareBars([for (final h in r.top.take(10)) (h.name, h.share)]),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(
          context,
          'Dados do ETF',
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${r.name}${_usTicker == null ? '' : ' · $_usTicker nos EUA'}',
                style: mutedStyle(context, size: 12),
              ),
              const SizedBox(height: 8),
              Wrap(
                children: [
                  StatCell(
                    'Patrimônio',
                    moneyShort(r.netAssets, currency: 'USD'),
                  ),
                  StatCell('Posições', _whole.format(r.positions)),
                  StatCell(
                    '10 maiores',
                    percent(r.topTen),
                    tooltip:
                        'Quanto do patrimônio está nas dez maiores posições.',
                  ),
                  if (r.returnOver(3) case final v?)
                    StatCell('Retorno em 3 meses', _signed(v)),
                  if (r.returnOver(12) case final v?)
                    StatCell('Retorno em 12 meses', _signed(v)),
                ],
              ),
              const SizedBox(height: 8),
              _note(
                context,
                'Carteira de ${monthLabel(r.date)} (N-PORT, SEC; a SEC publica '
                'cerca de dois meses depois).'
                '${r.classes > 1 ? ' O patrimônio é do fundo inteiro: o ETF é uma das ${r.classes} classes dele.' : ''}'
                ' Retorno total do ETF nos EUA, em '
                'dólar${_bdr == null ? '' : ': o BDR ainda varia com o câmbio'}.',
              ),
            ],
          ),
        ),
        if (returns == null) top else _pair(context, returns, top),
        _pair(
          context,
          _card(context, 'Tipo de ativo', ShareBars(r.byKind)),
          _card(context, 'País', ShareBars(r.byCountry)),
        ),
        _usChart(context),
      ],
    );
  }
}
