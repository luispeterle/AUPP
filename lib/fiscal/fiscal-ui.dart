import 'package:aupp/accounts/money-accounts.dart';
import 'package:aupp/helpers/records-utility-functions.dart';
import 'package:aupp/models/recurrent-record-pattern.dart';
import 'package:aupp/services/service-config.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'fiscal-data.dart';
import 'fiscal-engine.dart';
import 'fiscal-estimates.dart';
import 'fiscal-store.dart';
import 'fiscal-tables.dart';

/// One company's taxes loaded for the screens, and how to save changes.
class FiscalSession {
  final List<Company> companies;
  final Company company;
  final CompanyTaxes taxes;
  final List<RecurrentRecordPattern> patterns;

  FiscalSession(this.companies, this.company, this.taxes, this.patterns);

  FiscalData get data => company.fiscal;
  FiscalEngine get engine => taxes.engine;

  List<CompanyPayment> get pending =>
      [for (final p in taxes.payments) if (p.pending) p];

  static Future<FiscalSession?> load(String companyName) async {
    final companies = MoneyAccounts.companies();
    for (final c in companies) {
      if (c.name != companyName) continue;
      final taxes = await FiscalStore.load(c);
      final patterns =
          await ServiceConfig.database.getRecurrentRecordPatterns();
      return FiscalSession(companies, c, taxes, patterns);
    }
    return null;
  }

  Future<void> save() async {
    _compact(data.proLabore);
    _compact(data.accountantFee);
    await MoneyAccounts.saveCompanies(companies);
    await FiscalEstimates.refresh();
  }

  /// Keeps only the months where the amount changes.
  static void _compact(List<MonthlyValue> series) {
    series.sort((a, b) => a.since.compareTo(b.since));
    double? last;
    series.removeWhere((c) {
      final same = last != null && (c.value - last!).abs() < 0.005;
      last = c.value;
      return same;
    });
  }

  String activityLabel(String code) {
    final a = data.activityOf(code);
    return a == null ? code : '$code · ${a.name}';
  }
}

final dayFormat = DateFormat('dd/MM/yyyy');
final shortDay = DateFormat('dd/MM');

String money(double v) => formatMoney(v);

String percent(double v) =>
    '${(v * 100).toStringAsFixed(2).replaceAll('.', ',')}%';

String regimeShort(RegimeKind? kind) => switch (kind) {
  RegimeKind.mei => 'MEI',
  RegimeKind.simples => 'ME',
  null => '—',
};

class FiscalCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final Widget? action;
  final Color? color;

  const FiscalCard(
    this.title,
    this.children, {
    super.key,
    this.action,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: color,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                ?action,
              ],
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class FiscalRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final Color? color;
  final String? hint;

  const FiscalRow(
    this.label,
    this.value, {
    super.key,
    this.bold = false,
    this.color,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.bold : null,
      color: color,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(label, style: style)),
              const SizedBox(width: 12),
              Text(value, style: style),
            ],
          ),
          if (hint != null)
            Text(hint!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class FiscalNote extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color? color;

  const FiscalNote(
    this.text, {
    super.key,
    this.icon = Icons.info_outline,
    this.color,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

Future<double?> askMoney(
  BuildContext context,
  String title, {
  double? initial,
  String? help,
}) async {
  final controller = TextEditingController(
    text: initial == null
        ? ''
        : initial.toStringAsFixed(2).replaceAll('.', ','),
  );
  final text = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (help != null) ...[Text(help), const SizedBox(height: 8)],
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(prefixText: 'R\$ '),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('OK'),
        ),
      ],
    ),
  );
  if (text == null || text.trim().isEmpty) return null;
  return tryParseCurrencyString(text) ??
      double.tryParse(text.replaceAll('.', '').replaceAll(',', '.'));
}

Future<YearMonth?> askMonth(
  BuildContext context,
  String title, {
  YearMonth? initial,
  YearMonth? first,
}) {
  final now = FiscalStore.currentMonth;
  final from = first ?? now.add(-36);
  final to = now.add(36);
  final months = [for (var m = to; !m.isBefore(from); m = m.add(-1)) m];
  final start = initial ?? now;
  final index = months.indexOf(start).clamp(0, months.length - 1);
  return showDialog<YearMonth>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(title),
      children: [
        SizedBox(
          width: 320,
          height: 380,
          child: ListView.builder(
            controller: ScrollController(
              initialScrollOffset: (index * 48.0 - 160).clamp(
                0,
                double.infinity,
              ),
            ),
            itemExtent: 48,
            itemCount: months.length,
            itemBuilder: (_, i) => ListTile(
              title: Text(months[i].label),
              selected: months[i] == start,
              onTap: () => Navigator.pop(context, months[i]),
            ),
          ),
        ),
      ],
    ),
  );
}

Future<DateTime?> askDate(BuildContext context, DateTime? initial) =>
    showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
