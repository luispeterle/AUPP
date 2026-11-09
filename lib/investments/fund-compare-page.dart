import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:aupp/desktop/analysis-widgets.dart';
import 'package:aupp/investments/asset-sheet.dart';
import 'package:aupp/investments/b3-instruments.dart';
import 'package:aupp/investments/cvm-funds.dart';
import 'package:aupp/investments/fund-view.dart';
import 'package:aupp/investments/sec-fund.dart';

final _whole = NumberFormat('#,##0', 'pt_BR');

String _signed(double v) => '${v >= 0 ? '+' : ''}${percent(v)}';

/// A column of the comparison: its title and how a row shows and sorts.
class _Column<T> {
  final String title;
  final String Function(T row) show;
  final double? Function(T row)? sortKey;

  const _Column(this.title, this.show, [this.sortKey]);
}

/// The kinds compared together: a fund is compared with its peers.
Set<B3Type> peersOf(B3Type type) => switch (type) {
  B3Type.etf || B3Type.etfAbroad => {B3Type.etf, B3Type.etfAbroad},
  B3Type.infra ||
  B3Type.fidc ||
  B3Type.fund => {B3Type.infra, B3Type.fidc, B3Type.fund},
  _ => {type},
};

/// Every listed fund of these kinds that has a CNPJ (or a SEC series).
List<(String, B3Instrument)> listedOf(Set<B3Type> types) => [
  for (final ticker in b3Instruments.keys)
    if (B3Instrument.of(ticker) case final b3?
        when types.contains(b3.type) && b3.id != null)
      (ticker, b3),
];

/// Comparar of a fund that is not a FII: its peers side by side, with what
/// the CVM has of them; a BDR of an ETF with the ETFs abroad already opened,
/// or added here by ticker (each needs its report at the SEC).
class FundComparePage extends StatefulWidget {
  const FundComparePage({super.key, required this.ticker});

  final String ticker;

  @override
  State<FundComparePage> createState() => _FundComparePageState();
}

class _FundComparePageState extends State<FundComparePage> {
  final _store = CvmFundStore.instance;
  late final B3Instrument? _self = B3Instrument.of(widget.ticker);
  int _sortColumn = 1;
  bool _ascending = false;

  // BDRs of ETFs: the ones shown, and the one being added.
  final _etfs = <String>{};
  final _adding = TextEditingController();
  String? _addError;
  bool _loadingEtf = false;

  @override
  void initState() {
    super.initState();
    final self = _self;
    if (self == null) return;
    if (self.type == B3Type.bdrEtf) {
      _etfs.add(widget.ticker);
      _loadEtfs();
      return;
    }
    _store.ensure(FundReports.register);
    final reports = reportsOf(self.type);
    if (reports != null && reports != FundReports.register) {
      _store.ensure(reports);
    }
  }

  @override
  void dispose() {
    _adding.dispose();
    super.dispose();
  }

  /// This one and every ETF abroad already opened on this device.
  Future<void> _loadEtfs() async {
    final saved = await SecFundStore.instance.saved();
    for (final (ticker, b3) in listedOf({B3Type.bdrEtf})) {
      if (saved.contains(b3.secSeries)) _etfs.add(ticker);
    }
    for (final ticker in _etfs.toList()) {
      await SecFundStore.instance.load(B3Instrument.of(ticker)!.secSeries!);
      if (mounted) setState(() {});
    }
  }

  Future<void> _addEtf() async {
    final ticker = _adding.text.trim().toUpperCase();
    final b3 = B3Instrument.of(ticker);
    if (b3?.type != B3Type.bdrEtf) {
      setState(() => _addError = '$ticker não é um BDR de ETF.');
      return;
    }
    if (b3!.secSeries == null) {
      setState(() => _addError = '$ticker não tem carteira na SEC.');
      return;
    }
    setState(() {
      _addError = null;
      _loadingEtf = true;
    });
    final report = await SecFundStore.instance.load(b3.secSeries!);
    if (!mounted) return;
    setState(() {
      _loadingEtf = false;
      if (report == null) {
        _addError = 'A SEC não devolveu a carteira de $ticker agora.';
      } else {
        _etfs.add(ticker);
        _adding.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final self = _self;
    if (self == null) {
      return Center(child: Text('Nada a comparar para ${widget.ticker}.'));
    }
    if (self.type == B3Type.bdrEtf) return _etfAbroad(context);
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final reports = reportsOf(self.type)!;
        if (!_store.has(reports) || !_store.has(FundReports.register)) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _store.errorOf(reports) ??
                      _store.errorOf(FundReports.register) ??
                      _store.progress ??
                      'Preparando',
                ),
                const SizedBox(height: 8),
                if (_store.errorOf(reports) == null &&
                    _store.errorOf(FundReports.register) == null)
                  const LinearProgressIndicator(minHeight: 2),
              ],
            ),
          );
        }
        final rows = <(String, B3Instrument, CvmFund)>[
          for (final (ticker, b3) in listedOf(peersOf(self.type)))
            if (_store.fund(b3.cnpj!) case final fund?) (ticker, b3, fund),
        ];
        return _table(context, rows, _columnsFor(self.type), (r) => r.$1);
      },
    );
  }

  List<_Column<(String, B3Instrument, CvmFund)>> _columnsFor(B3Type type) {
    _Column<(String, B3Instrument, CvmFund)> col(
      String title,
      String Function(CvmFund f) show, [
      double? Function(CvmFund f)? key,
    ]) => _Column(
      title,
      (r) => show(r.$3),
      key == null ? null : (r) => key(r.$3),
    );
    String or(double? v, String Function(double) f) => v == null ? '—' : f(v);
    double? equity(CvmFund f) =>
        f.lastDay?.equity ?? f.months.lastOrNull?.equity ?? f.equity;
    double? holders(CvmFund f) =>
        (f.lastDay?.holders ?? f.months.lastOrNull?.holders)?.toDouble();
    return [
      _Column('Ticker', (r) => r.$1),
      col('Patrimônio', (f) => or(equity(f), moneyShort), equity),
      if (type == B3Type.fiagro) ...[
        col('Cotistas', (f) => or(holders(f), _whole.format), holders),
        col(
          'VP/cota',
          (f) => or(f.months.lastOrNull?.bookPerShare, pricePerShare),
          (f) => f.months.lastOrNull?.bookPerShare,
        ),
        col(
          'Rendimento 12 meses',
          (f) => or(f.yearYield, percent),
          (f) => f.yearYield,
        ),
        col(
          'Rendimento do mês',
          (f) => or(f.months.lastOrNull?.dividendYield, percent),
          (f) => f.months.lastOrNull?.dividendYield,
        ),
      ] else if (type == B3Type.etf || type == B3Type.etfAbroad) ...[
        _Column('Tipo', (r) => r.$2.type.label),
        col('Gestora', (f) => f.manager ?? '—'),
        col(
          'Desde',
          (f) => f.since?.year.toString() ?? '—',
          (f) => f.since?.year.toDouble(),
        ),
      ] else ...[
        _Column('Tipo', (r) => r.$2.type.label),
        col('Cotistas', (f) => or(holders(f), _whole.format), holders),
        col(
          'Cota em 6 meses',
          (f) => or(f.quotaChange(182), _signed),
          (f) => f.quotaChange(182),
        ),
        col(
          'Captação em 6 meses',
          (f) => or(f.flowOver(182), moneyShort),
          (f) => f.flowOver(182),
        ),
      ],
    ];
  }

  Widget _etfAbroad(BuildContext context) {
    final rows = <(String, EtfReport)>[
      for (final ticker in _etfs)
        if (SecFundStore.instance.cached(B3Instrument.of(ticker)!.secSeries!)
            case final report?)
          (ticker, report),
    ];
    _Column<(String, EtfReport)> col(
      String title,
      String Function(EtfReport r) show, [
      double? Function(EtfReport r)? key,
    ]) => _Column(
      title,
      (r) => show(r.$2),
      key == null ? null : (r) => key(r.$2),
    );
    String or(double? v, String Function(double) f) => v == null ? '—' : f(v);
    final columns = [
      _Column<(String, EtfReport)>('Ticker', (r) => r.$1),
      col(
        'Patrimônio',
        (r) => moneyShort(r.netAssets, currency: 'USD'),
        (r) => r.netAssets,
      ),
      col(
        'Posições',
        (r) => _whole.format(r.positions),
        (r) => r.positions.toDouble(),
      ),
      col('10 maiores', (r) => percent(r.topTen), (r) => r.topTen),
      col(
        '3 meses',
        (r) => or(r.returnOver(3), _signed),
        (r) => r.returnOver(3),
      ),
      col(
        '12 meses',
        (r) => or(r.returnOver(12), _signed),
        (r) => r.returnOver(12),
      ),
      col('Maior posição', (r) => r.top.firstOrNull?.name ?? '—'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 220,
                child: TextField(
                  controller: _adding,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'Comparar com (BDR de ETF)',
                    hintText: 'BAGG39',
                    errorText: _addError,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _addEtf(),
                ),
              ),
              const SizedBox(width: 8),
              _loadingEtf
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : OutlinedButton(
                      onPressed: _addEtf,
                      child: const Text('Adicionar'),
                    ),
            ],
          ),
        ),
        Expanded(child: _table(context, rows, columns, (r) => r.$1)),
      ],
    );
  }

  Widget _table<T>(
    BuildContext context,
    List<T> rows,
    List<_Column<T>> columns,
    String Function(T) tickerOf,
  ) {
    final column = _sortColumn < columns.length ? columns[_sortColumn] : null;
    final key = column?.sortKey;
    if (key != null) {
      rows.sort((a, b) {
        final x = key(a);
        final y = key(b);
        if (x == null) return y == null ? 0 : 1;
        if (y == null) return -1;
        return _ascending ? x.compareTo(y) : y.compareTo(x);
      });
    }
    final highlight = Theme.of(context).colorScheme.primaryContainer;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              sortColumnIndex: key == null ? null : _sortColumn,
              sortAscending: _ascending,
              headingTextStyle: denseStyle(context)
                  .copyWith(fontWeight: FontWeight.w600),
              dataTextStyle: denseStyle(context),
              columns: [
                for (final (i, c) in columns.indexed)
                  DataColumn(
                    label: Text(c.title),
                    numeric: c.sortKey != null,
                    onSort: c.sortKey == null
                        ? null
                        : (_, ascending) => setState(() {
                            _sortColumn = i;
                            _ascending = ascending;
                          }),
                  ),
              ],
              rows: [
                for (final row in rows)
                  DataRow(
                    color: tickerOf(row) == widget.ticker
                        ? WidgetStatePropertyAll(highlight)
                        : null,
                    cells: [
                      for (final c in columns) DataCell(Text(c.show(row))),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _self?.type == B3Type.bdrEtf
                ? 'Carteira e retornos do N-PORT de cada ETF (SEC), em dólar.'
                : 'Dados da CVM: só os fundos cujo CNPJ o app liga com '
                      'segurança ao ticker. A variação da cota não é a '
                      'rentabilidade de quem recebe os rendimentos.',
            style: mutedStyle(context, size: 11),
          ),
        ],
      ),
    );
  }
}
