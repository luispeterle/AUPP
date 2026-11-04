import 'package:flutter/material.dart';

import 'fiscal-store.dart';
import 'fiscal-ui.dart';

/// The Fator R now, and the pró-labore that puts an activity depending on
/// it in Anexo III in each coming month.
class FatorRPage extends StatefulWidget {
  final String companyName;

  const FatorRPage({super.key, required this.companyName});

  @override
  State<FatorRPage> createState() => _FatorRPageState();
}

class _FatorRPageState extends State<FatorRPage> {
  FiscalSession? _session;

  @override
  void initState() {
    super.initState();
    FiscalSession.load(widget.companyName).then((s) {
      if (mounted) setState(() => _session = s);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    return Scaffold(
      appBar: AppBar(title: const Text('Fator R e pró-labore')),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : _body(s),
    );
  }

  Widget _body(FiscalSession s) {
    final engine = s.engine;
    final now = FiscalStore.currentMonth;
    final (from, to) = engine.fatorRWindow(now);
    final (r, fs, revenue) = engine.fatorR(now);
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        FiscalCard('Como funciona', [
          const Text(
            'Fator R = folha (pró-labore) ÷ faturamento, nos 12 meses da '
            'janela. Com 28% ou mais, as atividades que dependem dele pagam '
            'Anexo III (6% na primeira faixa); abaixo, Anexo V (15,5%). Meses '
            'de MEI entram com folha zero. Desde 2027 a janela pula o mês '
            'anterior: um aumento de pró-labore demora dois meses para '
            'contar.',
          ),
          const SizedBox(height: 8),
          FiscalNote(
            engine.usesFatorR
                ? 'A empresa tem atividade que depende do Fator R.'
                : 'Nenhuma atividade da empresa depende do Fator R hoje: '
                      'isto só importa se passar a emitir numa que dependa '
                      '(desenvolvimento, suporte de TI…).',
            icon: engine.usesFatorR ? Icons.warning_amber_rounded : Icons.check,
            color: engine.usesFatorR ? Colors.orange : Colors.green,
          ),
        ]),
        FiscalCard('Hoje: ${now.label}', [
          FiscalRow('Janela', '${from.label} a ${to.label}'),
          FiscalRow('Folha na janela', money(fs)),
          FiscalRow('Faturamento na janela', money(revenue)),
          FiscalRow(
            'Fator R',
            percent(r),
            bold: true,
            color: r >= 0.28 ? Colors.green : Theme.of(context).colorScheme.error,
          ),
        ]),
        FiscalCard('Para estar no Anexo III em…', [
          Text(
            'Pró-labore a pagar todo mês a partir de ${now.label}. Usa o '
            'faturamento real e o previsto.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          for (var i = 1; i <= 14; i++)
            () {
              final plan = engine.planFatorR(now.add(i), now);
              return FiscalRow(
                plan.target.label,
                plan.proLabore == null ? 'não dá mais' : money(plan.proLabore!),
              );
            }(),
        ]),
      ],
    );
  }
}

/// The person's yearly income tax with the company's money (estimate).
class IncomeTaxPage extends StatefulWidget {
  final String companyName;

  const IncomeTaxPage({super.key, required this.companyName});

  @override
  State<IncomeTaxPage> createState() => _IncomeTaxPageState();
}

class _IncomeTaxPageState extends State<IncomeTaxPage> {
  FiscalSession? _session;
  int _year = DateTime.now().year;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await FiscalSession.load(widget.companyName);
    if (mounted) setState(() => _session = s);
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    return Scaffold(
      appBar: AppBar(title: const Text('IR anual')),
      body: s == null || !s.data.isSetUp
          ? const Center(child: CircularProgressIndicator())
          : _body(s),
    );
  }

  Widget _body(FiscalSession s) {
    final theme = Theme.of(context);
    final first = s.data.firstMonth!.year;
    final years = [for (var y = first; y <= DateTime.now().year + 1; y++) y];
    if (!years.contains(_year)) _year = years.last;
    final ir = s.engine.incomeTax(_year);
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SegmentedButton<int>(
            segments: [
              for (final y in years)
                ButtonSegment(value: y, label: Text('$y')),
            ],
            selected: {_year},
            onSelectionChanged: (v) => setState(() => _year = v.first),
          ),
        ),
        FiscalCard('Como é calculado', [
          const Text(
            'O IR retido do pró-labore é adiantamento. Na declaração entram '
            'o pró-labore e a parte do lucro distribuído que passa do '
            'isento: sem escrituração completa, só 32% do faturamento é '
            'isento.',
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('O contador faz escrituração completa'),
            subtitle: const Text('Aí todo o lucro distribuído é isento'),
            value: s.data.fullBookkeeping,
            onChanged: (v) async {
              s.data.fullBookkeeping = v;
              await s.save();
              await _load();
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Outras despesas da empresa em $_year'),
            subtitle: const Text('Sistemas, taxas… (impostos, pró-labore e '
                'contador já entram)'),
            trailing: Text(money(ir.otherExpenses)),
            onTap: () async {
              final v = await askMoney(context, 'Outras despesas de $_year',
                  initial: ir.otherExpenses);
              if (v == null) return;
              s.data.otherExpenses[_year] = v;
              await s.save();
              await _load();
            },
          ),
        ]),
        FiscalCard('Lucro da empresa em $_year', [
          FiscalRow('Faturamento', money(ir.revenue)),
          FiscalRow('DAS', '− ${money(ir.das)}'),
          FiscalRow('Pró-labore', '− ${money(ir.proLabore)}'),
          FiscalRow('Contador', '− ${money(ir.accountantFees)}'),
          FiscalRow('Outros pagamentos', '− ${money(ir.otherPayments)}'),
          FiscalRow('Outras despesas', '− ${money(ir.otherExpenses)}'),
          FiscalRow('Lucro', money(ir.profit), bold: true),
          FiscalRow(
            s.data.fullBookkeeping ? 'Isento (escrituração)' : 'Isento (32%)',
            money(ir.exemptProfit),
          ),
          FiscalRow('Lucro tributável', money(ir.taxableProfit), bold: true),
        ]),
        FiscalCard('Declaração de ${_year + 1}', [
          FiscalRow('Renda tributável', money(ir.taxableIncome),
              hint: 'Pró-labore + lucro tributável'),
          FiscalRow('Desconto', '− ${money(ir.discount)}',
              hint: 'O maior: INSS pago ou simplificado (20%)'),
          FiscalRow('Imposto pela tabela', money(ir.tax)),
          FiscalRow('Redutor da Lei 15.270', '− ${money(ir.reduction)}'),
          FiscalRow('Imposto do ano', money(ir.due)),
          FiscalRow('IRRF já retido', '− ${money(ir.irrfWithheld)}'),
          const Divider(),
          FiscalRow(
            ir.adjustment >= 0 ? 'A pagar' : 'A restituir',
            money(ir.adjustment.abs()),
            bold: true,
            color: ir.adjustment > 0.005 ? theme.colorScheme.error : Colors.green,
          ),
          const SizedBox(height: 6),
          Text(
            'Estimativa só com a renda da empresa (sem salário de outro '
            'lugar, aluguel ou dependentes). Meses à frente usam o '
            'faturamento previsto.',
            style: theme.textTheme.bodySmall,
          ),
        ]),
      ],
    );
  }
}
