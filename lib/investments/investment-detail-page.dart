import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:aupp/helpers/records-utility-functions.dart';

import 'asset-sheet-page.dart';
import 'investments-analytics.dart';
import 'investments-page.dart';
import 'stock-catalog.dart';

/// One investment position: what it is, how it is doing and every movement.
class InvestmentDetailPage extends StatefulWidget {
  final Position position;

  const InvestmentDetailPage({Key? key, required this.position})
    : super(key: key);

  @override
  State<InvestmentDetailPage> createState() => _InvestmentDetailPageState();
}

class _InvestmentDetailPageState extends State<InvestmentDetailPage> {
  String _money(double v) => getCurrencyValueString(v);

  String _pct(double v) => '${v.toStringAsFixed(1).replaceAll('.', ',')}%';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = widget.position;
    final dateFormat = DateFormat('dd/MM/yyyy');
    String? fmtDate(String? d) {
      final parsed = d == null ? null : DateTime.tryParse(d);
      return parsed == null ? null : dateFormat.format(parsed);
    }

    final ticker = StockCompany.tickerOf(p.inv);
    final quantity = (p.inv.raw['quantity'] as num?)?.toDouble();
    final price = (p.inv.raw['value'] as num?)?.toDouble();
    final facts = <(String, String)>[
      ('Instituição', p.institution.name),
      if (ticker != null && quantity != null)
        (
          'Quantidade',
          NumberFormat('#,##0.########', 'pt_BR').format(quantity),
        ),
      if (ticker != null && price != null) ('Cotação', _money(price)),
      if (p.inv.issuer != null) ('Emissor', p.inv.issuer!),
      ('Produto', p.product),
      if (p.rateLabel != null) ('Rentabilidade', p.rateLabel!),
      if (fmtDate(p.inv.purchaseDate) != null)
        ('Aplicado em', fmtDate(p.inv.purchaseDate)!),
      if (fmtDate(p.inv.dueDate) != null)
        ('Vencimento', fmtDate(p.inv.dueDate)!),
      ('Saldo líquido (já sem IR)', _money(p.balance)),
      if (p.tax.cost != null) ('Aplicado (restante)', _money(p.tax.cost!)),
      if (p.tax.profit != null)
        (
          'Lucro líquido',
          '${_money(p.tax.profit!)}${p.profitPct == null ? '' : ' (${_pct(p.profitPct!)})'}',
        ),
      if (p.tax.rate > 0) ('Alíquota de IR hoje', _pct(p.tax.rate * 100)),
      if (p.daysToNextBracket != null)
        (
          'Próxima faixa',
          '${_pct(p.nextRate! * 100)} em ${p.daysToNextBracket} dias'
              '${p.savingIfWait >= 0.01 ? ' (economia de ${_money(p.savingIfWait)})' : ''}',
        ),
      if (p.tax.cost != null) ...[
        ('IR já descontado do saldo', _money(p.tax.tax)),
        ('Saldo bruto (antes do IR)', _money(p.balance + p.tax.tax)),
      ],
    ];
    final movements = [...p.inv.movements]
      ..sort((a, b) => b.date.compareTo(a.date));

    return Scaffold(
      appBar: AppBar(
        title: Text(p.product),
        actions: [
          if (ticker != null)
            TextButton.icon(
              icon: const Icon(Icons.manage_search),
              label: const Text('Ficha'),
              onPressed: () => AssetSheetPage.open(context, ticker),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          ListTile(
            leading: InstitutionLogo(
              institution: ticker == null
                  ? p.institution
                  : StockCompany.badgeOf(ticker),
              size: 44,
            ),
            title: Text(
              ticker == null ? p.inv.name : StockCompany.titleOf(ticker),
            ),
            subtitle: Text(
              ticker == null
                  ? p.institution.name
                  : '${p.institution.name} · abrir a página de $ticker',
            ),
            trailing: ticker == null ? null : const Icon(Icons.chevron_right),
            onTap: ticker == null
                ? null
                : () => AssetSheetPage.open(context, ticker),
          ),
          const Divider(),
          for (final (label, value) in facts)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Flexible(
                    child: Text(
                      value,
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('Movimentos', style: theme.textTheme.titleMedium),
          ),
          if (movements.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'A instituição não informa os movimentos desta posição.',
              ),
            ),
          for (final m in movements)
            ListTile(
              dense: true,
              leading: Icon(
                m.type == 'BUY'
                    ? Icons.arrow_downward
                    : m.type == 'SELL'
                    ? Icons.arrow_upward
                    : Icons.receipt_long,
                color: m.type == 'BUY'
                    ? Colors.green
                    : m.type == 'SELL'
                    ? Colors.orange
                    : Colors.red,
              ),
              title: Text(switch (m.type) {
                'BUY' => 'Aporte',
                'SELL' => 'Resgate',
                'TAX' => 'Come-cotas',
                _ => m.type,
              }),
              subtitle: Text(
                [
                  fmtDate(m.date) ?? m.date,
                  if (m.type == 'SELL' &&
                      m.amount != null &&
                      m.netAmount != null &&
                      m.amount! - m.netAmount! >= 0.01)
                    'IR ${_money(m.amount! - m.netAmount!)} · líquido ${_money(m.netAmount!)}',
                ].join(' · '),
              ),
              trailing: Text(m.amount == null ? '—' : _money(m.amount!)),
            ),
        ],
      ),
    );
  }
}
