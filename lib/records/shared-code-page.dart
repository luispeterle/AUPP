import 'package:aupp/components/missing-payment-code-icon.dart';
import 'package:aupp/components/payment-code-file.dart';
import 'package:aupp/components/payment-code-sheet.dart';
import 'package:aupp/dinzo/dinzo-sync-service.dart';
import 'package:aupp/dinzo/estimate-link.dart';
import 'package:aupp/dinzo/pix-charge.dart';
import 'package:aupp/helpers/records-utility-functions.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/services/payment-code-reader.dart';
import 'package:aupp/services/recurrent-record-service.dart';
import 'package:aupp/services/service-config.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// A PDF or picture shared from another app (a bill by e-mail, a boleto from
/// the bank): finds its Pix / boleto and saves it on an upcoming bill. Shows
/// one month at a time, starting with this one: a later month's bill is only
/// reached by going to that month, so the code never lands there by mistake.
class SharedCodePage extends StatefulWidget {
  final String path;

  const SharedCodePage({super.key, required this.path});

  @override
  State<SharedCodePage> createState() => _SharedCodePageState();
}

class _SharedCodePageState extends State<SharedCodePage> {
  List<String>? _codes;
  String? _code;
  late DateTime _month;
  late final DateTime _firstMonth;
  List<Record>? _bills;
  bool _saving = false;

  /// Amount and due date of each code (a Pix charge's from its bank).
  final _facts = <String, CodeFacts>{};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _firstMonth = DateTime(now.year, now.month);
    _month = _firstMonth;
    _read();
    _load();
  }

  Future<void> _read() async {
    List<String> codes;
    try {
      codes = await PaymentCodeReader.readFile(widget.path);
    } catch (_) {
      codes = const [];
    }
    if (!mounted) return;
    setState(() {
      _codes = codes;
      // With a Pix and a boleto, the person picks one.
      _code = codes.length == 1 ? codes.single : null;
      for (final code in codes) {
        _facts[code] = PixCharge.urlOf(code) == null
            ? PaymentCodeFile.localFacts(code)
            : const CodeFacts(charge: true, loading: true);
      }
    });
    for (final code in codes) {
      if (PixCharge.urlOf(code) == null) continue;
      PaymentCodeFile.facts(code).then((facts) {
        if (mounted) setState(() => _facts[code] = facts);
      });
    }
  }

  /// Bills whose code can be saved: upcoming occurrences of a boleto / Pix
  /// recurrence or of an estimate, as in the record's page. Not the ones
  /// already paid or matched to the real record.
  static bool _takesCode(Record r) =>
      r.isFutureRecord &&
      r.recurrencePatternId != null &&
      !r.isTransfer &&
      (r.value ?? 0) < 0 &&
      r.estimateMatch == null &&
      !r.markedPaid &&
      (Record.billingKindOf(r.tags) != null ||
          r.tags.contains(DinzoSyncService.estimateTag));

  Future<void> _load() async {
    final month = _month;
    setState(() => _bills = null);
    final end = DateTime(month.year, month.month + 1);
    List<Record> bills;
    try {
      final upcoming = await RecurrentRecordService().updateRecurrentRecords(
        end.toUtc(),
      );
      // The real records of the month, so a bill already paid drops out.
      final real = await ServiceConfig.database.getAllRecordsInInterval(
        DateTime(month.year, month.month - 1),
        end,
      );
      EstimateLink.markMatches([...real, ...upcoming]);
      bills = upcoming.where((r) {
        if (!_takesCode(r) || !r.dateTime.isBefore(end)) return false;
        // This month also lists what is late, from before it.
        if (month == _firstMonth) return true;
        return !r.dateTime.isBefore(month);
      }).toList()..sort((a, b) => a.dateTime.compareTo(b.dateTime));
    } catch (_) {
      bills = const [];
    }
    if (mounted && month == _month) setState(() => _bills = bills);
  }

  /// The chosen code is due in another month than the one shown: says so,
  /// without going there (the person goes, so it is never by mistake).
  Widget? _dueMonthHint() {
    final code = _code;
    final due = code == null ? null : _facts[code]?.due;
    if (due == null) return null;
    final dueMonth = DateTime(due.year, due.month);
    if (dueMonth == _month) return null;
    // Late codes belong to this month's list.
    if (dueMonth.isBefore(_firstMonth) && _month == _firstMonth) return null;
    final theme = Theme.of(context);
    final later = dueMonth.isAfter(_month);
    final month = DateFormat('MMMM', 'pt_BR').format(due);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: theme.colorScheme.onTertiaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'O código vence em ${DateFormat('dd/MM/yyyy').format(due)}, '
              'em $month. ${later ? 'Passe para o próximo mês' : 'Volte o mês'} '
              'se a conta for de lá.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _goTo(int months) {
    setState(() => _month = DateTime(_month.year, _month.month + months));
    _load();
  }

  static String _name(Record r) => r.title == null || r.title!.trim().isEmpty
      ? r.category?.name ?? 'Conta'
      : r.title!;

  Future<void> _save(Record bill) async {
    final code = _code;
    if (code == null || _saving) return;
    final name = _name(bill);
    final day = DateFormat('dd/MM').format(bill.dateTime);
    if (bill.paymentCode != null) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Trocar o código?'),
          content: Text(
            '$name, $day, já tem um '
            '${Record.paymentCodeKind(bill.paymentCode!)}. Fica o novo.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Trocar'),
            ),
          ],
        ),
      );
      if (replace != true || !mounted) return;
    }
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final saved = await RecurrentRecordService.savePaymentCode(bill, code);
      if (!mounted) return;
      if (saved == null) {
        setState(() => _saving = false);
        messenger.showSnackBar(
          const SnackBar(content: Text('Essa conta não existe mais.')),
        );
        _load();
        return;
      }
      Navigator.pop(context, true);
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text('$name, $day: ${saved.message(code, bill.value)}'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Não deu para salvar o código: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final codes = _codes;
    return Scaffold(
      appBar: AppBar(title: const Text('Pix ou boleto')),
      body: codes == null
          ? const _Reading()
          : codes.isEmpty
          ? const _NothingFound()
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    ..._buildCodes(codes),
                    const SizedBox(height: 24),
                    _buildMonthBar(),
                    const SizedBox(height: 8),
                    ..._buildBills(),
                  ],
                ),
              ),
            ),
    );
  }

  List<Widget> _buildCodes(List<String> codes) {
    final theme = Theme.of(context);
    return [
      Text(
        codes.length == 1 ? 'Código no arquivo' : 'Qual código guardar?',
        style: theme.textTheme.titleMedium,
      ),
      if (codes.length > 1)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'O arquivo tem ${codes.length} códigos. Os dois pagam a mesma '
            'conta quando é um boleto com Pix.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      for (final code in codes)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: FoundCodeTile(
            code: code,
            facts: _facts[code],
            selected: code == _code,
            onTap: () => setState(() => _code = code),
          ),
        ),
    ];
  }

  Widget _buildMonthBar() {
    final theme = Theme.of(context);
    final label = DateFormat('MMMM y', 'pt_BR').format(_month);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Em qual conta?', style: theme.textTheme.titleMedium),
              Text(
                '${label[0].toUpperCase()}${label.substring(1)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Mês anterior',
          onPressed: _month.isAfter(_firstMonth) ? () => _goTo(-1) : null,
          icon: const Icon(Icons.chevron_left),
        ),
        IconButton.filledTonal(
          tooltip: 'Próximo mês',
          onPressed: () => _goTo(1),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }

  List<Widget> _buildBills() {
    final theme = Theme.of(context);
    final bills = _bills;
    if (bills == null) {
      return const [
        Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    final dueHint = _dueMonthHint();
    if (bills.isEmpty) {
      return [
        ?dueHint,
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            'Nenhuma conta de boleto, Pix ou estimativa a pagar neste mês. '
            'Passe para o próximo mês se a conta for de lá.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ];
    }
    final code = _code;
    final facts = code == null ? null : _facts[code];
    final amount = facts?.amount;
    final due = facts?.due;
    return [
      ?dueHint,
      if (code == null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Escolha o código acima para guardar numa conta.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
      for (final r in bills)
        _BillTile(
          bill: r,
          name: _name(r),
          sameAmount:
              amount != null &&
              r.value != null &&
              (r.value!.abs() - amount).abs() < 0.005,
          sameDay: due != null && DateUtils.isSameDay(due, r.dateTime),
          onTap: code == null || _saving ? null : () => _save(r),
        ),
    ];
  }
}

class _BillTile extends StatelessWidget {
  final Record bill;
  final String name;
  final bool sameAmount;
  final bool sameDay;
  final VoidCallback? onTap;

  const _BillTile({
    required this.bill,
    required this.name,
    required this.sameAmount,
    required this.sameDay,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = bill.paymentCode;
    final kind = code != null
        ? Record.paymentCodeKind(code)
        : Record.billingKindOf(bill.tags);
    final date = DateFormat('EEE, dd/MM', 'pt_BR').format(bill.dateTime);
    final today = DateUtils.dateOnly(DateTime.now());
    final late = bill.dateTime.isBefore(today);
    final match = sameAmount || sameDay;
    final primary = theme.colorScheme.primary;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      color: match ? theme.colorScheme.primaryContainer : null,
      shape: match
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: primary, width: 2),
            )
          : null,
      child: ListTile(
        enabled: onTap != null,
        onTap: onTap,
        leading: kind == null
            ? const CircleAvatar(child: Icon(Icons.event_note))
            : code == null
            ? MissingPaymentCodeIcon(kind, size: 36)
            : CircleAvatar(
                backgroundColor: codeKindColor(kind),
                child: Icon(codeKindIcon(kind), color: Colors.white, size: 20),
              ),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [
                late ? 'atrasada · $date' : date,
                code == null ? 'sem código' : 'já tem $kind: trocar',
              ].join(' · '),
            ),
            if (match)
              Text(
                [
                  if (sameAmount) 'mesmo valor',
                  if (sameDay) 'mesmo dia',
                ].join(' e ') + ' do código',
                style: TextStyle(color: primary, fontWeight: FontWeight.w600),
              ),
          ],
        ),
        trailing: Text(
          getCurrencyValueString(bill.value?.abs()),
          style: theme.textTheme.titleMedium,
        ),
      ),
    );
  }
}

class _Reading extends StatelessWidget {
  const _Reading();

  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 16),
        Text('Procurando Pix e boleto no arquivo…'),
      ],
    ),
  );
}

class _NothingFound extends StatelessWidget {
  const _NothingFound();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.qr_code_scanner,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Nenhum QR code de Pix nem código de barras de boleto neste '
              'arquivo.',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Se o código estiver escrito, copie a linha digitável ou o Pix '
              'copia-e-cola e cole na conta.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
          ],
        ),
      ),
    );
  }
}
