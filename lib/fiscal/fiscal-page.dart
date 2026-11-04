import 'package:aupp/services/service-config.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'fiscal-data.dart';
import 'fiscal-engine.dart';
import 'fiscal-setup-page.dart';
import 'fiscal-store.dart';
import 'fiscal-tables.dart';
import 'fiscal-tools.dart';
import 'fiscal-ui.dart';

/// A company's taxes as a spreadsheet: one row per month with its invoices,
/// pró-labore, accountant, Fator R and taxes. The pró-labore and the
/// accountant are typed in their cells; a month opens below with its
/// payments, whether each had an invoice and in which activity.
class FiscalPage extends StatefulWidget {
  final String companyName;

  const FiscalPage({super.key, required this.companyName});

  @override
  State<FiscalPage> createState() => _FiscalPageState();
}

enum _C {
  month,
  revenue,
  activity,
  proLabore,
  fatorR,
  annex,
  das,
  dctfweb,
  fee,
  total,
  others,
}

class _FiscalPageState extends State<FiscalPage> {
  FiscalSession? _session;
  bool _loaded = false;
  final Set<YearMonth> _open = {};
  final _list = ScrollController();
  bool _scrolled = false;

  /// The cell being typed in: (column, month).
  (_C, YearMonth)? _editing;
  final _editor = TextEditingController();
  final _editorFocus = FocusNode();

  static const _rowHeight = 40.0;

  static const _widths = {
    _C.month: 96.0,
    _C.revenue: 104.0,
    _C.activity: 168.0,
    _C.proLabore: 104.0,
    _C.fee: 96.0,
    _C.fatorR: 76.0,
    _C.annex: 64.0,
    _C.das: 92.0,
    _C.dctfweb: 104.0,
    _C.total: 104.0,
    _C.others: 260.0,
  };

  static const _titles = {
    _C.month: 'Mês',
    _C.revenue: 'Notas',
    _C.activity: 'Atividade',
    _C.proLabore: 'Pró-labore',
    _C.fee: 'Contador',
    _C.fatorR: 'Fator R',
    _C.annex: 'Anexo',
    _C.das: 'DAS',
    _C.dctfweb: 'INSS+IRRF',
    _C.total: 'Total',
    _C.others: 'Outros pagamentos',
  };

  double get _width => _widths.values.fold<double>(0, (s, w) => s + w) + 24;

  @override
  void initState() {
    super.initState();
    _editorFocus.addListener(() {
      if (!_editorFocus.hasFocus) _commit();
    });
    _load();
  }

  @override
  void dispose() {
    _editor.dispose();
    _editorFocus.dispose();
    for (final c in [
      ..._newValue.values,
      ..._otherDescription.values,
      ..._otherValue.values,
      ..._otherDay.values,
    ]) {
      c.dispose();
    }
    _list.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = await FiscalSession.load(widget.companyName);
    if (!mounted) return;
    setState(() {
      _session = s;
      _loaded = true;
    });
    if (!_scrolled && s != null && s.data.isSetUp) {
      _scrolled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final first = s.data.firstMonth!;
        final now = FiscalStore.currentMonth;
        final rows = now.since(first) + now.year - first.year + 1;
        if (_list.hasClients) {
          _list.jumpTo(
            (rows * _rowHeight - 160).clamp(0, _list.position.maxScrollExtent),
          );
        }
      });
    }
  }

  Future<void> _save() async {
    await _session!.save();
    await _load();
  }

  Future<void> _push(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    await _load();
  }

  /// A typed amount: "4.500", "4500,50" or "4500.50".
  static double? _parse(String text) {
    var t = text.replaceAll(RegExp(r'[^0-9.,-]'), '');
    if (t.contains(',')) {
      t = t.replaceAll('.', '').replaceAll(',', '.');
    } else if (!RegExp(r'\.\d{1,2}$').hasMatch(t)) {
      t = t.replaceAll('.', '');
    }
    return double.tryParse(t);
  }

  /// "1.234,56", no currency (the sheet is all reais).
  static String _n(double v) {
    final fixed = v.abs().toStringAsFixed(2);
    final parts = fixed.split('.');
    final digits = parts[0];
    final groups = <String>[];
    for (var i = digits.length; i > 0; i -= 3) {
      groups.insert(0, digits.substring(i - 3 < 0 ? 0 : i - 3, i));
    }
    return '${v < 0 ? '-' : ''}${groups.join('.')},${parts[1]}';
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final s = _session;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.companyName),
        actions: [
          IconButton(
            icon: const Icon(Icons.percent),
            tooltip: 'Fator R e pró-labore',
            onPressed: () => _push(FatorRPage(companyName: widget.companyName)),
          ),
          IconButton(
            icon: const Icon(Icons.request_quote_outlined),
            tooltip: 'IR anual',
            onPressed: () =>
                _push(IncomeTaxPage(companyName: widget.companyName)),
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Cadastro da empresa',
            onPressed: () =>
                _push(FiscalSetupPage(companyName: widget.companyName)),
          ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : s == null
          ? const Center(child: Text('Empresa não encontrada'))
          : !s.data.isSetUp
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Falta dizer desde quando a empresa existe, em que '
                      'regime e a atividade.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => _push(
                        FiscalSetupPage(companyName: widget.companyName),
                      ),
                      child: const Text('Cadastrar'),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _summary(s),
                Expanded(child: _sheet(s)),
              ],
            ),
    );
  }

  /// One line above the sheet: what is due next, and what to check.
  Widget _summary(FiscalSession s) {
    final theme = Theme.of(context);
    final now = FiscalStore.currentMonth;
    final due = s.engine.month(now.add(-1));
    final current = s.data.regimeAt(now);
    final pending = s.pending.length;
    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Wrap(
          spacing: 16,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              current?.kind == RegimeKind.simples
                  ? 'ME no Simples desde ${current!.startMonth.label}'
                  : current?.kind == RegimeKind.mei
                  ? 'MEI'
                  : 'Sem regime hoje',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              'Impostos de ${due.month.label}: R\$ ${_n(due.taxes)} até '
              '${shortDay.format(due.due)}',
            ),
            if (pending > 0)
              ActionChip(
                avatar: const Icon(Icons.hourglass_empty, size: 16),
                label: Text('$pending entrada(s) sem resposta: todas com nota'),
                onPressed: () async {
                  for (final p in s.pending) {
                    s.data.adjustments[p.key] = RevenueAdjustment(
                      status: PaymentStatus.invoice,
                      activity: p.adjustment?.activity,
                      parts: p.adjustment?.parts,
                    );
                  }
                  await _save();
                },
              ),
            Text(
              'Valores em R\$ · impostos vencem no dia 20 do mês seguinte · '
              'toque num mês para ver as notas',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sheet(FiscalSession s) {
    final now = FiscalStore.currentMonth;
    final months = s.engine.months(now.add(12));
    final rows = <Widget>[];
    int? year;
    for (final m in months) {
      if (m.month.year != year) {
        year = m.month.year;
        rows.add(_yearRow(s, year));
      }
      rows.add(_monthRow(s, m));
      if (_open.contains(m.month)) rows.add(_details(s, m));
    }
    return LayoutBuilder(
      builder: (context, box) => Scrollbar(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: _width < box.maxWidth ? box.maxWidth : _width,
            height: box.maxHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(),
                Expanded(
                  child: ListView(
                    controller: _list,
                    padding: const EdgeInsets.only(bottom: 48),
                    children: rows,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cell(_C c, Widget child, {bool left = false}) => SizedBox(
    width: _widths[c],
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Align(
        alignment: left ? Alignment.centerLeft : Alignment.centerRight,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: left ? Alignment.centerLeft : Alignment.centerRight,
          child: child,
        ),
      ),
    ),
  );

  Widget _header() {
    final theme = Theme.of(context);
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          for (final c in _C.values)
            _cell(
              c,
              Text(
                _titles[c]!,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              left: c == _C.month,
            ),
        ],
      ),
    );
  }

  Widget _yearRow(FiscalSession s, int year) {
    final theme = Theme.of(context);
    var revenue = 0.0, taxes = 0.0, fees = 0.0, others = 0.0;
    YearMonth? lastMei;
    for (var m = YearMonth(year, 1); m.year == year; m = m.add(1)) {
      if (s.data.regimeAt(m) == null) continue;
      final fm = s.engine.month(m);
      revenue += fm.revenue;
      taxes += fm.taxes;
      fees += fm.accountantFee;
      others += fm.otherPayments;
      if (fm.regime == RegimeKind.mei) lastMei = m;
    }
    var mei = '';
    if (lastMei != null) {
      final (used, limit) = s.engine.meiYearUse(lastMei);
      mei = '   ·   limite do MEI: ${_n(used)} de ${_n(limit)}';
      if (used > limit * (1 + FiscalTables.meiTolerance)) {
        mei += ' (passou de 20%: exclusão)';
      } else if (used > limit) {
        mei += ' (imposto sobre o excesso)';
      }
    }
    return Container(
      height: _rowHeight,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.6),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text:
                  '$year   ·   notas ${_n(revenue)}   ·   impostos '
                  '${_n(taxes)}   ·   contador ${_n(fees)}'
                  '${others > 0 ? '   ·   outros ${_n(others)}' : ''}$mei',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            // Res. CGSN 190/2026: from 2027 the window skips the month
            // before.
            if (year >= 2027)
              TextSpan(
                text:
                    '   ·   o pró-labore de um mês só conta no Fator R dois '
                    'meses depois',
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }

  Widget _monthRow(FiscalSession s, FiscalMonth m) {
    final theme = Theme.of(context);
    final now = FiscalStore.currentMonth;
    final open = _open.contains(m.month);
    final simples = m.regime == RegimeKind.simples;
    final mei = m.regime == RegimeKind.mei;
    final pending = s.engine.revenueEntries(m.month).any((e) => e.pending);
    final soft = TextStyle(color: theme.hintColor);
    final grey = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    final r = simples ? s.engine.fatorR(m.month).$1 : null;
    Widget blank() => const SizedBox.shrink();
    return Material(
      color: m.month == now
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
          : open
          ? theme.colorScheme.surfaceContainerHigh
          : Colors.transparent,
      child: InkWell(
        onTap: () => setState(() {
          open ? _open.remove(m.month) : _open.add(m.month);
        }),
        child: Container(
          height: _rowHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: theme.dividerColor.withValues(alpha: 0.5),
              ),
            ),
          ),
          // Computed cells in grey; the typed ones (_editable) stand out.
          child: DefaultTextStyle.merge(
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            child: Row(
              children: [
                _cell(
                  _C.month,
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        open ? Icons.expand_less : Icons.expand_more,
                        size: 16,
                        color: theme.hintColor,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        m.month.label,
                        style: TextStyle(color: theme.colorScheme.onSurface),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        regimeShort(m.regime),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: mei ? Colors.teal : theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  left: true,
                ),
                _cell(
                  _C.revenue,
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (pending)
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(
                            Icons.hourglass_empty,
                            size: 13,
                            color: Colors.orange,
                          ),
                        ),
                      Text(
                        _n(m.revenue),
                        style: m.forecast
                            ? soft.copyWith(fontStyle: FontStyle.italic)
                            : grey,
                      ),
                    ],
                  ),
                ),
                _cell(
                  _C.activity,
                  Text(_activities(s, m), style: grey),
                  left: true,
                ),
                simples
                    ? _editable(s, _C.proLabore, m.month, s.data.proLabore)
                    : _cell(_C.proLabore, blank()),
                _cell(
                  _C.fatorR,
                  r == null
                      ? blank()
                      : Text(
                          percent(r),
                          style: TextStyle(
                            color: r >= FiscalTables.fatorRThreshold
                                ? Colors.green
                                : theme.hintColor,
                          ),
                        ),
                ),
                _cell(
                  _C.annex,
                  mei
                      ? Text('MEI', style: soft)
                      : !simples
                      ? blank()
                      : Text(
                          m.annexes.isEmpty
                              ? 'III'
                              : m.annexes.values
                                    .toSet()
                                    .map((a) => a == Annex.iii ? 'III' : 'V')
                                    .join('+'),
                          style: m.inAnnexV
                              ? TextStyle(
                                  color: theme.colorScheme.error,
                                  fontWeight: FontWeight.bold,
                                )
                              : null,
                        ),
                ),
                _cell(
                  _C.das,
                  m.regime == null ? blank() : Text(_n(m.das), style: grey),
                ),
                _cell(
                  _C.dctfweb,
                  simples ? Text(_n(m.dctfweb), style: grey) : blank(),
                ),
                m.regime == null
                    ? _cell(_C.fee, blank())
                    : _editable(s, _C.fee, m.month, s.data.accountantFee),
                _cell(
                  _C.total,
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (m.warnings.isNotEmpty)
                        Tooltip(
                          message: m.warnings.join('\n'),
                          child: const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(
                              Icons.warning_amber_rounded,
                              size: 15,
                              color: Colors.orange,
                            ),
                          ),
                        ),
                      Text(
                        _n(m.total),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade300,
                        ),
                      ),
                    ],
                  ),
                ),
                _otherCell(s, m.month),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The month's one-off payments, each with its day, description and
  /// value. A tap opens the month, where they are typed in.
  Widget _otherCell(FiscalSession s, YearMonth month) {
    final theme = Theme.of(context);
    final mine = [
      for (final p in s.data.otherPayments)
        if (p.month == month) p,
    ]..sort((a, b) => a.day.compareTo(b.day));
    return InkWell(
      onTap: () async {
        if (_editing != null) await _commit();
        setState(() => _open.add(month));
      },
      child: _cell(
        _C.others,
        mine.isEmpty
            ? Text('—', style: TextStyle(color: theme.hintColor))
            : Text(
                [
                  for (final p in mine)
                    '${shortDay.format(p.date)} ${p.description} ${_n(p.value)}',
                ].join('  ·  '),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
        left: true,
      ),
    );
  }

  /// The month's one-off payments with their descriptions, and a line to add
  /// one.
  List<Widget> _otherPaymentsDetail(FiscalSession s, YearMonth month) {
    final mine = [
      for (final p in s.data.otherPayments)
        if (p.month == month) p,
    ];
    final description = _otherDescription.putIfAbsent(
      month,
      () => TextEditingController(),
    );
    final value = _otherValue.putIfAbsent(month, () => TextEditingController());
    final day = _otherDay.putIfAbsent(month, () => TextEditingController());
    final lastDay = DateTime(month.year, month.month + 1, 0).day;
    Future<void> add() async {
      final v = _parse(value.text.trim());
      if (v == null || v <= 0) return;
      final d = (int.tryParse(day.text.trim()) ?? 1).clamp(1, lastDay);
      s.data.otherPayments.add(
        OtherPayment(
          const Uuid().v4(),
          month,
          v,
          description.text.trim().isEmpty
              ? 'Outro pagamento'
              : description.text.trim(),
          day: d,
        ),
      );
      description.clear();
      value.clear();
      day.clear();
      await _save();
    }

    return [
      const Divider(height: 16),
      Text(
        'Outros pagamentos de ${month.label}',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      for (final p in mine)
        _line(
          Icons.receipt_outlined,
          '${shortDay.format(p.date)} · ${p.description}',
          p.patternId == null
              ? 'fora do total'
              : 'fora do total · estimativa no Extrato',
          p.value,
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            tooltip: 'Excluir',
            onPressed: () async {
              s.data.otherPayments.remove(p);
              // Its estimate goes with it.
              if (p.patternId != null) {
                await ServiceConfig.database.deleteRecurrentRecordPatternById(
                  p.patternId,
                );
              }
              await _save();
            },
          ),
        ),
      SizedBox(
        height: 44,
        child: Row(
          children: [
            const Icon(Icons.add, size: 18),
            const SizedBox(width: 8),
            SizedBox(
              width: 48,
              child: TextField(
                controller: day,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'dia',
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 164,
              child: TextField(
                controller: description,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Descrição (multa, migração…)',
                ),
              ),
            ),
            SizedBox(
              width: 110,
              child: TextField(
                controller: value,
                textAlign: TextAlign.right,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'valor',
                ),
                onSubmitted: (_) => add(),
              ),
            ),
            TextButton(onPressed: add, child: const Text('Adicionar')),
          ],
        ),
      ),
    ];
  }

  final Map<YearMonth, TextEditingController> _otherDescription = {};
  final Map<YearMonth, TextEditingController> _otherValue = {};
  final Map<YearMonth, TextEditingController> _otherDay = {};

  /// The activities of the month's invoices, each invoice in its own.
  String _activities(FiscalSession s, FiscalMonth m) => [
    for (final code in m.revenueByActivity.keys)
      s.data.activityOf(code)?.short ?? code,
  ].join(' + ');

  /// A monthly amount of [series] (pró-labore, accountant): shown as text,
  /// typed in place after a tap. A typed value holds in the months after it
  /// until the next one (shown greyed there).
  Widget _editable(
    FiscalSession s,
    _C col,
    YearMonth month,
    List<MonthlyValue> series,
  ) {
    final theme = Theme.of(context);
    final explicit = series.any((c) => c.since == month);
    final value = FiscalData.valueAt(series, month);
    if (_editing == (col, month)) {
      return SizedBox(
        width: _widths[col],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: TextField(
            controller: _editor,
            focusNode: _editorFocus,
            autofocus: true,
            textAlign: TextAlign.right,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              border: OutlineInputBorder(),
            ),
            // Saved on Enter, on Tab and on a click anywhere else.
            onSubmitted: (_) => _commit(),
            onEditingComplete: _commit,
            onTapOutside: (_) => _commit(),
          ),
        ),
      );
    }
    return InkWell(
      onTap: () async {
        // Another cell being typed in is saved first.
        if (_editing != null) await _commit();
        _editor.text = explicit
            ? value.toStringAsFixed(2).replaceAll('.', ',')
            : '';
        if (mounted) setState(() => _editing = (col, month));
      },
      child: _cell(
        col,
        Text(
          value > 0 ? _n(value) : 'digitar',
          // Every typed cell in bold white; carried over from the month
          // before, a little dimmer.
          style: TextStyle(
            color: theme.colorScheme.onSurface.withValues(
              alpha: value <= 0 ? 0.5 : (explicit ? 1 : 0.8),
            ),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Future<void> _commit() async {
    final editing = _editing;
    final s = _session;
    if (editing == null || s == null) return;
    final text = _editor.text.trim();
    _editing = null;
    if (mounted) setState(() {});
    final (col, month) = editing;
    final series = col == _C.proLabore
        ? s.data.proLabore
        : s.data.accountantFee;
    final v = text.isEmpty ? null : _parse(text);
    if (text.isNotEmpty && v == null) return;
    final before = [
      for (final c in series)
        if (c.since == month) c.value,
    ];
    if ((before.isEmpty && v == null) ||
        (before.isNotEmpty && v != null && (before.first - v).abs() < 0.005)) {
      return;
    }
    series.removeWhere((c) => c.since == month);
    // The same as the month before: nothing to keep, it carries over.
    if (v != null && (FiscalData.valueAt(series, month) - v).abs() >= 0.005) {
      series.add(MonthlyValue(month, v));
    }
    await _save();
  }

  /// Picks the activity of one invoice among the company's (registered in
  /// Cadastro).
  Widget _activityPicker(
    FiscalSession s,
    String current,
    Future<void> Function(String code) onPick,
  ) {
    final options = <String>{...s.data.activities, current};
    if (options.length < 2) {
      return Text(s.data.activityOf(current)?.short ?? current);
    }
    return DropdownButton<String>(
      value: current,
      isDense: true,
      items: [
        for (final code in options)
          DropdownMenuItem(
            value: code,
            child: Text(s.data.activityOf(code)?.short ?? code),
          ),
      ],
      onChanged: (code) async {
        if (code == null || code == current) return;
        await onPick(code);
      },
    );
  }

  // -------------------------------------------------------------- details

  /// The month opened: its payments with what each was, the invoices typed
  /// in and the forecast.
  Widget _details(FiscalSession s, FiscalMonth m) {
    final theme = Theme.of(context);
    final arrived = [
      for (final p in s.taxes.payments)
        if (p.month == m.month) p,
    ];
    final fromOther = [
      for (final e in s.engine.revenueEntries(m.month))
        if (e.source == RevenueSource.account &&
            !arrived.any((p) => p.key == e.key))
          e,
    ];
    final manual = [
      for (final r in s.data.manualRevenues)
        if (r.month == m.month) r,
    ];
    final forecast = [
      for (final e in s.engine.revenueEntries(m.month))
        if (e.source == RevenueSource.forecast) e,
    ];
    return Container(
      color: theme.colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(32, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (arrived.isEmpty &&
              fromOther.isEmpty &&
              manual.isEmpty &&
              forecast.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('Nenhuma entrada nem nota neste mês.'),
            ),
          for (final p in arrived) _paymentLine(s, p),
          for (final e in fromOther)
            _line(
              Icons.subdirectory_arrow_right,
              '${e.title} de ${e.date == null ? '' : shortDay.format(e.date!)}',
              'nota deste mês, dinheiro de outro mês',
              e.value,
            ),
          for (final r in manual)
            _line(
              Icons.edit_note,
              r.description ?? 'Nota avulsa',
              'nota sem entrada na conta',
              r.value,
              activity: _activityPicker(
                s,
                r.activity ?? s.data.mainActivity ?? '',
                (code) async {
                  r.activity = code == s.data.mainActivity ? null : code;
                  await _save();
                },
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                tooltip: 'Excluir',
                onPressed: () async {
                  s.data.manualRevenues.remove(r);
                  await _save();
                },
              ),
            ),
          for (final e in forecast)
            _line(
              Icons.query_stats,
              e.title,
              'previsto pela estimativa · a atividade vale deste mês em '
              'diante',
              e.value,
              activity: _activityPicker(s, e.activity, (code) async {
                s.data.setForecastActivity(e.key, m.month, code);
                await _save();
              }),
            ),
          _manualAdder(s, m.month),
          ..._otherPaymentsDetail(s, m.month),
          if (m.warnings.isNotEmpty) ...[
            const SizedBox(height: 4),
            for (final w in m.warnings)
              Text('⚠ $w', style: const TextStyle(color: Colors.orange)),
          ],
        ],
      ),
    );
  }

  Widget _line(
    IconData icon,
    String title,
    String note,
    double value, {
    Widget? activity,
    Widget? trailing,
  }) => SizedBox(
    height: 40,
    child: Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        SizedBox(
          width: 220,
          child: Text(title, overflow: TextOverflow.ellipsis),
        ),
        SizedBox(
          width: 110,
          child: Text(money(value), textAlign: TextAlign.right),
        ),
        const SizedBox(width: 12),
        if (activity != null) ...[activity, const SizedBox(width: 12)],
        Expanded(
          child: Text(
            note,
            style: Theme.of(context).textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        ?trailing,
      ],
    ),
  );

  /// One payment of the month, with "teve nota?" as a dropdown (and the
  /// month of the invoice, or the part invoiced, right beside it).
  Widget _paymentLine(FiscalSession s, CompanyPayment p) {
    final total = p.record.value ?? 0;
    final adj = p.adjustment;
    final parts = adj?.parts;
    String kind;
    if (p.status == PaymentStatus.noInvoice) {
      kind = 'none';
    } else if (p.status == PaymentStatus.notRevenue) {
      kind = 'notRevenue';
    } else if (parts == null) {
      kind = p.pending ? 'pending' : 'here';
    } else if (parts.length == 1 && (parts.first.value - total).abs() < 0.005) {
      kind = 'other';
    } else if (parts.length == 2 &&
        parts.every((x) => x.month == p.month && x.activity != null)) {
      kind = 'two';
    } else {
      kind = 'partial';
    }
    Future<void> set(RevenueAdjustment a) async {
      a.activity = adj?.activity;
      if (a.isEmpty) {
        s.data.adjustments.remove(p.key);
      } else {
        s.data.adjustments[p.key] = a;
      }
      await _save();
    }

    final months = [
      for (var m = p.month.add(-3); !m.isAfter(p.month.add(6)); m = m.add(1)) m,
    ];
    Widget monthPicker(YearMonth value, void Function(YearMonth) onPick) =>
        DropdownButton<YearMonth>(
          value: months.contains(value) ? value : null,
          isDense: true,
          items: [
            for (final m in months)
              DropdownMenuItem(value: m, child: Text(m.label)),
          ],
          onChanged: (m) => m == null ? null : onPick(m),
        );

    final extra = <Widget>[];
    if (kind == 'two') {
      final first = parts!.first;
      final second = parts.last;
      void setTwo(double v, String a1, String a2) => set(
        RevenueAdjustment(
          status: PaymentStatus.invoice,
          parts: [
            RevenuePart(p.month, v, activity: a1),
            RevenuePart(p.month, total - v, activity: a2),
          ],
        ),
      );
      extra.addAll([
        const Text('nota 1: '),
        SizedBox(
          width: 100,
          child: TextFormField(
            key: ValueKey('${p.key}-two-${first.value}'),
            initialValue: first.value.toStringAsFixed(2).replaceAll('.', ','),
            textAlign: TextAlign.right,
            decoration: const InputDecoration(isDense: true),
            onFieldSubmitted: (text) {
              final v = double.tryParse(
                text.replaceAll('.', '').replaceAll(',', '.'),
              );
              if (v == null || v <= 0 || v >= total) return;
              setTwo(v, first.activity!, second.activity!);
            },
          ),
        ),
        _activityPicker(
          s,
          first.activity!,
          (code) async => setTwo(first.value, code, second.activity!),
        ),
        Text('   nota 2: ${money(second.value)} '),
        _activityPicker(
          s,
          second.activity!,
          (code) async => setTwo(first.value, first.activity!, code),
        ),
      ]);
    } else if (kind == 'other') {
      extra.add(
        monthPicker(
          parts!.first.month,
          (m) => set(
            RevenueAdjustment(
              status: PaymentStatus.invoice,
              parts: [RevenuePart(m, total)],
            ),
          ),
        ),
      );
    } else if (kind == 'partial') {
      final here = parts!
          .where((x) => x.month == p.month)
          .fold<double>(0, (t, x) => t + x.value);
      final rest = [
        for (final x in parts)
          if (x.month != p.month) x,
      ];
      extra.addAll([
        const Text('com nota aqui: '),
        SizedBox(
          width: 100,
          child: TextFormField(
            key: ValueKey('${p.key}-$here'),
            initialValue: here.toStringAsFixed(2).replaceAll('.', ','),
            textAlign: TextAlign.right,
            decoration: const InputDecoration(isDense: true),
            onFieldSubmitted: (text) {
              final v = double.tryParse(
                text.replaceAll('.', '').replaceAll(',', '.'),
              );
              if (v == null || v < 0 || v > total) return;
              set(
                RevenueAdjustment(
                  status: PaymentStatus.invoice,
                  parts: [
                    if (v > 0.004) RevenuePart(p.month, v),
                    if (rest.isNotEmpty && total - v > 0.004)
                      RevenuePart(rest.first.month, total - v),
                  ],
                ),
              );
            },
          ),
        ),
        const Text('  resto: '),
        DropdownButton<YearMonth?>(
          value: rest.isEmpty ? null : rest.first.month,
          isDense: true,
          items: [
            const DropdownMenuItem(value: null, child: Text('sem nota')),
            for (final m in months)
              if (m != p.month)
                DropdownMenuItem(value: m, child: Text('nota em ${m.label}')),
          ],
          onChanged: (m) => set(
            RevenueAdjustment(
              status: PaymentStatus.invoice,
              parts: [
                if (here > 0.004) RevenuePart(p.month, here),
                if (m != null && total - here > 0.004)
                  RevenuePart(m, total - here),
              ],
            ),
          ),
        ),
      ]);
    }

    final line = SizedBox(
      height: 44,
      child: Row(
        children: [
          Icon(
            switch (kind) {
              'pending' => Icons.hourglass_empty,
              'none' => Icons.money_off,
              'notRevenue' => Icons.block,
              _ => Icons.check_circle,
            },
            size: 18,
            color: switch (kind) {
              'pending' => Colors.orange,
              'none' || 'notRevenue' => Colors.grey,
              _ => Colors.green,
            },
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 220,
            child: Text(
              '${shortDay.format(p.record.dateTime)} · ${p.record.title ?? 'Entrada'}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 110,
            child: Text(money(total), textAlign: TextAlign.right),
          ),
          const SizedBox(width: 12),
          DropdownButton<String>(
            value: kind,
            isDense: true,
            items: [
              if (kind == 'pending')
                const DropdownMenuItem(
                  value: 'pending',
                  child: Text('a conferir'),
                ),
              DropdownMenuItem(
                value: 'here',
                child: Text('com nota de ${p.month.label}'),
              ),
              const DropdownMenuItem(
                value: 'other',
                child: Text('nota de outro mês'),
              ),
              const DropdownMenuItem(
                value: 'partial',
                child: Text('só parte com nota'),
              ),
              const DropdownMenuItem(
                value: 'two',
                child: Text('duas notas, atividades diferentes'),
              ),
              const DropdownMenuItem(value: 'none', child: Text('sem nota')),
              const DropdownMenuItem(
                value: 'notRevenue',
                child: Text('não é receita'),
              ),
            ],
            onChanged: (v) {
              switch (v) {
                case 'here':
                  set(RevenueAdjustment(status: PaymentStatus.invoice));
                case 'other':
                  set(
                    RevenueAdjustment(
                      status: PaymentStatus.invoice,
                      parts: [RevenuePart(p.month.add(1), total)],
                    ),
                  );
                case 'partial':
                  set(
                    RevenueAdjustment(
                      status: PaymentStatus.invoice,
                      parts: [RevenuePart(p.month, total / 2)],
                    ),
                  );
                case 'two':
                  final main = s.data.mainActivity ?? '';
                  final other = s.data.activities.firstWhere(
                    (c) => c != main,
                    orElse: () => '6201-5/01',
                  );
                  if (!s.data.activities.contains(other)) {
                    s.data.activities.add(other);
                  }
                  set(
                    RevenueAdjustment(
                      status: PaymentStatus.invoice,
                      parts: [
                        RevenuePart(p.month, total / 2, activity: main),
                        RevenuePart(
                          p.month,
                          total - total / 2,
                          activity: other,
                        ),
                      ],
                    ),
                  );
                case 'none':
                  set(RevenueAdjustment(status: PaymentStatus.noInvoice));
                case 'notRevenue':
                  set(RevenueAdjustment(status: PaymentStatus.notRevenue));
              }
            },
          ),
          if (p.counts && kind != 'two') ...[
            const SizedBox(width: 12),
            _activityPicker(s, adj?.activity ?? s.data.mainActivity ?? '', (
              code,
            ) async {
              final next = adj ?? RevenueAdjustment();
              next.activity = code == s.data.mainActivity ? null : code;
              if (next.isEmpty) {
                s.data.adjustments.remove(p.key);
              } else {
                s.data.adjustments[p.key] = next;
              }
              await _save();
            }),
          ],
        ],
      ),
    );
    if (extra.isEmpty) return line;
    // The month of the invoice, or the part invoiced, on a line below.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        line,
        Padding(
          padding: const EdgeInsets.only(left: 26, bottom: 6),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            runSpacing: 4,
            children: extra,
          ),
        ),
      ],
    );
  }

  /// Activity picked for the next invoice typed in, by month.
  final Map<YearMonth, String> _newActivity = {};
  final Map<YearMonth, TextEditingController> _newValue = {};

  Widget _manualAdder(FiscalSession s, YearMonth month) {
    final controller = _newValue.putIfAbsent(
      month,
      () => TextEditingController(),
    );
    final activity = _newActivity[month] ?? s.data.mainActivity ?? '';
    Future<void> add() async {
      final v = double.tryParse(
        controller.text.replaceAll('.', '').replaceAll(',', '.'),
      );
      if (v == null || v <= 0) return;
      s.data.manualRevenues.add(
        ManualRevenue(
          const Uuid().v4(),
          month,
          v,
          activity: activity == s.data.mainActivity ? null : activity,
          description: 'Nota avulsa',
        ),
      );
      controller.clear();
      await _save();
    }

    return SizedBox(
      height: 44,
      child: Row(
        children: [
          const Icon(Icons.add, size: 18),
          const SizedBox(width: 8),
          const SizedBox(width: 220, child: Text('Nota sem entrada na conta')),
          SizedBox(
            width: 110,
            child: TextField(
              controller: controller,
              textAlign: TextAlign.right,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'valor',
              ),
              onSubmitted: (_) => add(),
            ),
          ),
          const SizedBox(width: 12),
          _activityPicker(s, activity, (code) async {
            setState(() => _newActivity[month] = code);
          }),
          TextButton(onPressed: add, child: const Text('Adicionar')),
        ],
      ),
    );
  }
}
