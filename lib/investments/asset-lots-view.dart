import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:aupp/helpers/records-utility-functions.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/services/service-config.dart';

import 'aportes.dart';
import 'asset-lots.dart';
import 'benchmark.dart';
import 'selic-comparison.dart';

/// The purchases of one asset, in crypto or abroad alike: each with its own
/// quantity and date, tied or not to an entry of the statement (it can be tied
/// later). What changes is only how the quantity is shown.
class AssetLotsPage extends StatefulWidget {
  const AssetLotsPage({
    super.key,
    required this.asset,
    required this.title,
    required this.priceOn,
    this.afterChange,
  });

  final String asset;
  final String title;

  /// Price in reais on a day, to estimate what was paid.
  final double? Function(DateTime) priceOn;

  /// After any change, for what depends on the total held.
  final Future<void> Function()? afterChange;

  @override
  State<AssetLotsPage> createState() => _AssetLotsPageState();
}

class _AssetLotsPageState extends State<AssetLotsPage> {
  late List<AssetLot> _lots = AssetLots.of(widget.asset);

  static final _date = DateFormat('dd/MM/yyyy');
  static final _quantity = NumberFormat('#,##0.########', 'pt_BR');

  String _money(double value) => getCurrencyValueString(value);

  Future<void> _store(List<AssetLot> lots) async {
    await AssetLots.save(widget.asset, lots);
    await widget.afterChange?.call();
    if (mounted) setState(() => _lots = AssetLots.of(widget.asset));
  }

  Future<void> _edit([AssetLot? lot]) async {
    final result = await showDialog<_LotResult>(
      context: context,
      builder: (_) => _LotDialog(
        title: widget.title,
        lot: lot,
        estimateOn: widget.priceOn,
      ),
    );
    if (result == null) return;
    final others = [
      for (final other in _lots)
        if (other.id != lot?.id) other,
    ];
    // An entry made here by older versions goes with its purchase. What
    // left the wallets comes from the Dinzo: link the purchase to it.
    if (result.lot == null && lot != null) await Aportes.delete('lot:${lot.id}');
    await _store([...others, ?result.lot]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lots = _lots.reversed.toList();
    final costs = _lots.map((lot) => AssetLots.costOf(lot, widget.priceOn));
    final invested = costs.fold<double>(0, (sum, cost) => sum + (cost ?? 0));
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Adicionar compra',
        onPressed: () => _edit(),
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          ListTile(
            title: Text(
              '${_quantity.format(AssetLots.quantityOf(_lots))} no total',
            ),
            subtitle: Text(
              '${_money(invested)} investidos'
              '${_lots.any((lot) => lot.cost == null) ? ' (parte estimada pelo preço do dia)' : ''}',
            ),
          ),
          const Divider(height: 1),
          if (lots.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'Nenhuma compra ainda. Adicione cada uma com a quantidade e a '
                'data; se quiser, vincule a um lançamento do extrato.',
                textAlign: TextAlign.center,
              ),
            ),
          for (final lot in lots)
            ListTile(
              leading: Icon(
                lot.record == null ? Icons.edit_note : Icons.link,
                color: lot.record == null
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.primary,
              ),
              title: Text(
                '${lot.quantity < 0 ? 'Venda: ' : ''}'
                '${_quantity.format(lot.quantity.abs())} · '
                '${_date.format(lot.day)}',
              ),
              subtitle: Text(
                [
                  () {
                    final cost = AssetLots.costOf(lot, widget.priceOn);
                    if (cost == null) return 'Custo desconhecido';
                    return '${_money(cost.abs())}'
                        '${lot.cost == null ? ' (estimado)' : ''}';
                  }(),
                  ?lot.record?.title,
                  ?lot.note,
                ].join(' · '),
              ),
              onTap: () => _edit(lot),
            ),
        ],
      ),
    );
  }
}

/// The dialog's answer: the lot to keep, or null to delete it.
class _LotResult {
  final AssetLot? lot;

  const _LotResult(this.lot);
}

class _LotDialog extends StatefulWidget {
  const _LotDialog({
    required this.title,
    required this.lot,
    required this.estimateOn,
  });

  final String title;
  final AssetLot? lot;
  final double? Function(DateTime) estimateOn;

  @override
  State<_LotDialog> createState() => _LotDialogState();
}

class _LotDialogState extends State<_LotDialog> {
  late DateTime _day = widget.lot?.day ?? DateTime.now();
  late LotRecord? _record = widget.lot?.record;
  late final _quantity = TextEditingController(
    text: widget.lot == null ? '' : _number(widget.lot!.quantity),
  );
  late final _cost = TextEditingController(
    text: widget.lot?.cost == null ? '' : _number(widget.lot!.cost!),
  );
  String? _error;

  static String _number(double value) =>
      NumberFormat('0.########', 'pt_BR').format(value);

  static double? _parse(String text) {
    final clean = text.trim();
    return double.tryParse(
      clean.contains(',')
          ? clean.replaceAll('.', '').replaceAll(',', '.')
          : clean,
    );
  }

  @override
  void dispose() {
    _quantity.dispose();
    _cost.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2010),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _day = picked);
  }

  /// The entry says when and for how much; the quantity stays what was typed.
  Future<void> _link() async {
    final record = await showDialog<Record>(
      context: context,
      builder: (_) => const _RecordPicker(),
    );
    if (record == null || record.id == null) return;
    setState(() {
      _record = LotRecord(
        record.id!,
        record.utcDateTime.millisecondsSinceEpoch,
        record.value ?? 0,
        record.title ?? record.category?.name ?? '',
      );
      _day = record.utcDateTime.toLocal();
      _cost.text = _number((record.value ?? 0).abs());
    });
  }

  void _save() {
    final quantity = _parse(_quantity.text);
    if (quantity == null || quantity == 0) {
      setState(() => _error = 'Informe a quantidade.');
      return;
    }
    Navigator.pop(
      context,
      _LotResult(
        AssetLot(
          id: widget.lot?.id,
          day: _day,
          quantity: quantity,
          cost: _parse(_cost.text),
          record: _record,
          note: widget.lot?.note,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final record = _record;
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _quantity,
              autofocus: widget.lot == null,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: InputDecoration(
                labelText: 'Quantidade',
                helperText: 'Negativa para uma venda.',
                errorText: _error,
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: const Text('Data'),
              subtitle: Text(DateFormat('dd/MM/yyyy').format(_day)),
              onTap: _pickDay,
            ),
            TextField(
              controller: _cost,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Total pago em R\$ (opcional)',
                helperText: 'Em branco: estima pelo preço do dia.',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(record == null ? Icons.add_link : Icons.link),
              title: Text(
                record == null ? 'Vincular a um lançamento' : record.title,
              ),
              subtitle: record == null
                  ? const Text('Opcional, agora ou depois')
                  : Text(
                      DateFormat('dd/MM/yyyy').format(
                        DateTime.fromMillisecondsSinceEpoch(record.at),
                      ),
                    ),
              trailing: record == null
                  ? null
                  : IconButton(
                      tooltip: 'Desvincular',
                      icon: const Icon(Icons.link_off),
                      onPressed: () => setState(() => _record = null),
                    ),
              onTap: _link,
            ),
          ],
        ),
      ),
      actions: [
        if (widget.lot != null)
          TextButton(
            onPressed: () => Navigator.pop(context, const _LotResult(null)),
            child: const Text('Excluir'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _save, child: const Text('Salvar')),
      ],
    );
  }
}

/// Finds an entry of the statement, newest first.
class _RecordPicker extends StatefulWidget {
  const _RecordPicker();

  @override
  State<_RecordPicker> createState() => _RecordPickerState();
}

class _RecordPickerState extends State<_RecordPicker> {
  List<Record>? _all;
  String _query = '';

  @override
  void initState() {
    super.initState();
    ServiceConfig.database.getAllRecords().then((records) {
      if (!mounted) return;
      setState(() {
        _all = records.whereType<Record>().toList()
          ..sort((a, b) => b.utcDateTime.compareTo(a.utcDateTime));
      });
    });
  }

  String _text(Record record) => record.title ?? record.category?.name ?? '';

  @override
  Widget build(BuildContext context) {
    final query = _query.toLowerCase();
    final found = (_all ?? const <Record>[])
        .where(
          (record) =>
              query.isEmpty ||
              _text(record).toLowerCase().contains(query) ||
              (record.value?.abs().toStringAsFixed(2).contains(query) ?? false),
        )
        .take(100)
        .toList();
    return AlertDialog(
      title: const Text('Vincular a um lançamento'),
      contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Nome ou valor',
                ),
                onChanged: (text) => setState(() => _query = text),
              ),
            ),
            Expanded(
              child: _all == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: found.length,
                      itemBuilder: (context, index) {
                        final record = found[index];
                        return ListTile(
                          title: Text(_text(record)),
                          subtitle: Text(
                            DateFormat(
                              'dd/MM/yyyy',
                            ).format(record.utcDateTime.toLocal()),
                          ),
                          trailing: Text(
                            getCurrencyValueString(
                                    (record.value ?? 0).abs(),
                                  ),
                          ),
                          onTap: () => Navigator.pop(context, record),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}

/// [SelicComparison] for what is followed purchase by purchase, and in reais
/// what went in, what it is worth and what the same money would be at the Selic.
class LotsSelicCard extends StatefulWidget {
  const LotsSelicCard({
    super.key,
    required this.points,
    required this.rates,
    this.note,
    this.sinceStart,
  });

  final List<PortfolioPoint> points;
  final BenchmarkRates rates;

  /// When the line has limits worth saying.
  final String? note;

  /// When the page has its own choice of period.
  final bool? sinceStart;

  @override
  State<LotsSelicCard> createState() => _LotsSelicCardState();
}

class _LotsSelicCardState extends State<LotsSelicCard> {
  bool _sinceStart = false;

  String _money(double value) => getCurrencyValueString(value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final all = widget.points;
    if (all.length < 2) return const SizedBox.shrink();
    final last = all.last;
    final sinceStart = widget.sinceStart ?? _sinceStart;
    return InvestmentCard(
      title: SelicComparison.title,
      info:
          'Rendimento acumulado das suas compras, cada uma a partir da própria '
          'data, descontando aportes e resgates.',
      child: SelicComparison(
        points: AssetLots.performance(
          all,
          widget.rates,
          from: sinceStart
              ? null
              : DateTime(last.date.year - 1, last.date.month, last.date.day),
        ),
        rates: widget.rates,
        sinceStart: widget.sinceStart == null ? _sinceStart : null,
        onSinceStart: widget.sinceStart == null
            ? (value) => setState(() => _sinceStart = value)
            : null,
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Desde a primeira compra: ${_money(last.invested)} investidos '
              'valem ${_money(last.value)}. Na Selic, nas mesmas datas, seriam '
              '${_money(last.selic)}.',
              style: theme.textTheme.bodySmall,
            ),
            if (widget.note != null)
              Text(widget.note!, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
