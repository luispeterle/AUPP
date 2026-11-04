import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:aupp/disguise/calc-engine.dart';
import 'package:aupp/disguise/calculator-page.dart';

/// "Racha conta": total, 10% service, quick 2–5 people and drinks split only
/// among those who drank.
class SplitBillPage extends StatefulWidget {
  final double? initialTotal;

  const SplitBillPage({super.key, this.initialTotal});

  @override
  State<SplitBillPage> createState() => _SplitBillPageState();
}

class _SplitBillPageState extends State<SplitBillPage> {
  late final TextEditingController _total;
  final _drinks = TextEditingController();
  bool _service = true;
  int _people = 2;
  bool _splitDrinks = false;
  int _drinkers = 1;

  @override
  void initState() {
    super.initState();
    final t = widget.initialTotal;
    _total = TextEditingController(
        text: t == null ? '' : CalcEngine.format(double.parse(t.toStringAsFixed(2))));
  }

  @override
  void dispose() {
    _total.dispose();
    _drinks.dispose();
    super.dispose();
  }

  /// Accepts "1.250,50", "1250,5" and "1250.50".
  static double _parse(String s) {
    var v = s.trim().replaceAll(' ', '');
    if (v.isEmpty) return 0;
    if (v.contains(',')) {
      v = v.replaceAll('.', '').replaceAll(',', '.');
    } else if (RegExp(r'^\d+\.\d{1,2}$').hasMatch(v)) {
      // decimal point
    } else {
      v = v.replaceAll('.', '');
    }
    return double.tryParse(v) ?? 0;
  }

  static final _currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  static String _money(double v) => _currency.format(v);

  SplitBill get _bill => SplitBill(
        total: _parse(_total.text),
        servicePercent: _service ? 10 : 0,
        people: _people,
        drinks: _splitDrinks ? _parse(_drinks.text) : 0,
        drinkers: _splitDrinks ? _drinkers : 0,
      );

  void _setPeople(int n) {
    HapticFeedback.selectionClick();
    setState(() {
      _people = n.clamp(1, 99);
      if (_drinkers >= _people) _drinkers = (_people - 1).clamp(1, 99);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bill = _bill;
    return Theme(
      data: CalcColors.theme(context),
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Racha conta',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            _card(
              children: [
                _label('Total da conta'),
                _moneyField(_total, autofocus: widget.initialTotal == null),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeTrackColor: CalcColors.ink,
                  activeThumbColor: CalcColors.background,
                  title: const Text('Serviço (10%)'),
                  value: _service,
                  onChanged: (v) => setState(() => _service = v),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _card(
              children: [
                _label('Quantas pessoas'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final n in [2, 3, 4, 5])
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _chip('$n', _people == n, () => _setPeople(n)),
                        ),
                      ),
                    _stepper(
                      value: _people,
                      onMinus: _people > 1 ? () => _setPeople(_people - 1) : null,
                      onPlus: () => _setPeople(_people + 1),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            _card(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeTrackColor: CalcColors.ink,
                  activeThumbColor: CalcColors.background,
                  title: const Text('Nem todo mundo bebeu'),
                  subtitle: const Text(
                    'As bebidas são divididas só entre quem bebeu',
                    style: TextStyle(color: CalcColors.muted),
                  ),
                  value: _splitDrinks,
                  onChanged: _people > 1
                      ? (v) => setState(() => _splitDrinks = v)
                      : null,
                ),
                if (_splitDrinks) ...[
                  _label('Valor das bebidas'),
                  _moneyField(_drinks, autofocus: true),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Expanded(child: Text('Quantos beberam')),
                      _stepper(
                        value: _drinkers,
                        onMinus: _drinkers > 1
                            ? () => setState(() => _drinkers--)
                            : null,
                        onPlus: _drinkers < _people - 1
                            ? () => setState(() => _drinkers++)
                            : null,
                      ),
                    ],
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            _result(bill),
          ],
        ),
      ),
    );
  }

  Widget _result(SplitBill bill) {
    final empty = bill.total <= 0;
    const tabular = [FontFeature.tabularFigures()];
    Widget line(String label, double v, {bool big = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: CalcColors.operatorText.withValues(alpha: 0.8),
                    fontSize: big ? 16 : 14,
                  ),
                ),
              ),
              Text(
                _money(v),
                style: TextStyle(
                  color: CalcColors.operatorText,
                  fontSize: big ? 28 : 16,
                  fontWeight: FontWeight.w700,
                  fontFeatures: tabular,
                ),
              ),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: CalcColors.ink,
        borderRadius: BorderRadius.circular(20),
      ),
      child: empty
          ? const Text(
              'Digite o total da conta',
              style: TextStyle(color: CalcColors.operatorText),
            )
          : Column(
              children: [
                if (bill.splitsDrinks) ...[
                  line('Quem bebeu (${bill.drinkers})', bill.perDrinker, big: true),
                  line('Quem não bebeu (${bill.people - bill.drinkers})',
                      bill.perPerson, big: true),
                ] else
                  line('Cada um paga', bill.perPerson, big: true),
                const Divider(color: Color(0x55FFD65B), height: 24),
                if (_service) line('Serviço', bill.totalWithService - bill.total),
                line('Total', bill.totalWithService),
              ],
            ),
    );
  }

  Widget _card({required List<Widget> children}) => Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        decoration: BoxDecoration(
          color: CalcColors.paper,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      );

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: CalcColors.muted,
        ),
      );

  Widget _moneyField(TextEditingController c, {bool autofocus = false}) =>
      TextField(
        controller: c,
        autofocus: autofocus,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        onChanged: (_) => setState(() {}),
        cursorColor: CalcColors.ink,
        style: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
        decoration: const InputDecoration(
          prefixText: 'R\$ ',
          hintText: '0,00',
          border: InputBorder.none,
          isDense: true,
        ),
      );

  Widget _chip(String text, bool selected, VoidCallback onTap) => Material(
        color: selected ? CalcColors.ink : CalcColors.digitKey,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: SizedBox(
            height: 48,
            child: Center(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: selected ? CalcColors.operatorText : CalcColors.ink,
                ),
              ),
            ),
          ),
        ),
      );

  Widget _stepper({
    required int value,
    VoidCallback? onMinus,
    VoidCallback? onPlus,
  }) =>
      Container(
        decoration: BoxDecoration(
          color: CalcColors.digitKey,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.remove),
              color: CalcColors.ink,
              onPressed: onMinus,
            ),
            Text(
              '$value',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            IconButton(
              icon: const Icon(Icons.add),
              color: CalcColors.ink,
              onPressed: onPlus,
            ),
          ],
        ),
      );
}
