import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:aupp/budget_plan/budget-plan.dart';
import 'package:aupp/helpers/records-utility-functions.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/models/wallet.dart';
import 'package:aupp/services/database/sqlite-database.dart';
import 'package:aupp/services/service-config.dart';

/// A purchase paid partly with a caixinha (fork-only, 2026-10-13). The
/// purchase stays one record, linked to Dinzo, in its wallet; the caixinha's
/// part is a transfer caixinha → that wallet on the same day, keyed
/// `livre:split:<dinzo_id>` ([Record.splitPrefix]). Balances come out right
/// (the caixinha pays its part) and the budget counts the part in the
/// purchase's group as not spent from this month's income
/// ([BudgetPlanUsage.compute]). Deleting the purchase deletes the part.
class SplitPayment {
  static String keyFor(String dinzoId) => '${Record.splitPrefix}$dinzoId';

  /// Purchases that can have a part paid with a caixinha.
  static bool supports(Record? r) =>
      r != null &&
      r.id != null &&
      r.dinzoId != null &&
      !r.dinzoId!.startsWith('livre:') &&
      r.transferWalletId == null &&
      (r.value ?? 0) < 0;

  static Future<Record?> partOf(Record purchase) async {
    final db = (await SqliteDatabase.instance.database)!;
    final rows = await db.query(
      'records',
      columns: ['id'],
      where: 'dinzo_id = ?',
      whereArgs: [keyFor(purchase.dinzoId!)],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ServiceConfig.database.getRecordById(rows.first['id'] as int);
  }

  /// Caixinhas that can pay: every other wallet in the purchase's currency.
  static Future<List<Wallet>> payers(Record purchase) async {
    final db = ServiceConfig.database;
    final wallets = await db.getAllWallets();
    final defaultId = (await db.getDefaultWallet())?.id;
    final own = wallets.where((w) => w.id == purchase.walletId).firstOrNull;
    return [
      for (final w in wallets)
        if (!w.isArchived &&
            w.id != purchase.walletId &&
            !BudgetPlan.isBaseWallet(w, defaultId) &&
            (w.currency ?? 'BRL') == (own?.currency ?? 'BRL'))
          w,
    ];
  }

  static Future<void> save(Record purchase, Wallet from, double amount) async {
    final existing = await partOf(purchase);
    final part = Record(
      -amount,
      '${purchase.title} · ${from.name}',
      null,
      purchase.utcDateTime,
      timeZoneName: purchase.timeZoneName,
      description: 'Parte paga com a caixinha',
      walletId: from.id,
      transferWalletId: purchase.walletId,
      transferValue: amount,
      dinzoId: keyFor(purchase.dinzoId!),
      tags: {'Virtual'},
    );
    if (existing == null) {
      await ServiceConfig.database.addRecord(part);
    } else {
      part.id = existing.id;
      await ServiceConfig.database.updateRecordById(existing.id, part);
    }
  }

  static Future<void> remove(Record purchase) async {
    final existing = await partOf(purchase);
    if (existing != null) {
      await ServiceConfig.database.deleteRecordById(existing.id);
    }
  }
}

/// "Pago com caixinha" row of an existing purchase (edit record page).
class SplitPaymentTile extends StatefulWidget {
  final Record purchase;

  const SplitPaymentTile({super.key, required this.purchase});

  @override
  State<SplitPaymentTile> createState() => _SplitPaymentTileState();
}

class _SplitPaymentTileState extends State<SplitPaymentTile> {
  Record? _part;
  List<Wallet> _payers = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final part = await SplitPayment.partOf(widget.purchase);
    final payers = await SplitPayment.payers(widget.purchase);
    if (!mounted) return;
    setState(() {
      _part = part;
      _payers = payers;
      _loaded = true;
    });
  }

  String? get _payerName =>
      _payers.where((w) => w.id == _part?.walletId).firstOrNull?.name;

  @override
  Widget build(BuildContext context) {
    if (!_loaded || (_payers.isEmpty && _part == null)) {
      return const SizedBox.shrink();
    }
    final part = _part;
    return ListTile(
      leading: const Icon(Icons.savings_outlined),
      title: const Text('Pago com caixinha'),
      subtitle: Text(
        part == null
            ? 'Toque se parte desta compra saiu de uma caixinha'
            : '${getCurrencyValueString(part.transferValue ?? 0)} de '
                  '${_payerName ?? 'outra carteira'} · só o resto conta '
                  'no orçamento',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: _edit,
    );
  }

  Future<void> _edit() async {
    final purchaseTotal = (widget.purchase.value ?? 0).abs();
    var wallet =
        _payers.where((w) => w.id == _part?.walletId).firstOrNull ??
        _payers.firstOrNull;
    final controller = TextEditingController(
      text: _part == null
          ? ''
          : (_part!.transferValue ?? 0).toStringAsFixed(2).replaceAll('.', ','),
    );
    String? error;
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            0,
            24,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Parte paga com caixinha',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Compra de ${getCurrencyValueString(purchaseTotal)}. A parte '
                'da caixinha sai dela e não conta no orçamento do mês.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: wallet?.id,
                decoration: const InputDecoration(labelText: 'Caixinha'),
                items: [
                  for (final w in _payers)
                    DropdownMenuItem(value: w.id, child: Text(w.name)),
                ],
                onChanged: (id) => setSheet(
                  () => wallet = _payers.firstWhere((w) => w.id == id),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: _part == null,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: InputDecoration(
                  labelText: 'Valor da caixinha',
                  errorText: error,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  if (_part != null)
                    TextButton(
                      onPressed: () => Navigator.pop(context, 'remove'),
                      child: const Text('Tirar'),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      final amount = _parse(controller.text);
                      if (wallet == null) {
                        setSheet(() => error = 'Escolha a caixinha');
                      } else if (amount == null || amount <= 0) {
                        setSheet(() => error = 'Valor inválido');
                      } else if (amount > purchaseTotal) {
                        setSheet(
                          () => error =
                              'Maior que a compra '
                              '(${getCurrencyValueString(purchaseTotal)})',
                        );
                      } else {
                        Navigator.pop(context, 'save');
                      }
                    },
                    child: const Text('Salvar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (result == 'save') {
      await SplitPayment.save(
        widget.purchase,
        wallet!,
        _parse(controller.text)!,
      );
    } else if (result == 'remove') {
      await SplitPayment.remove(widget.purchase);
    }
    controller.dispose();
    await _load();
  }

  static double? _parse(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;
    // "1.234,56" → 1234.56; "600,5" → 600.5; "600.50" → 600.50
    final normalized = t.contains(',')
        ? t.replaceAll('.', '').replaceAll(',', '.')
        : t;
    return double.tryParse(normalized);
  }
}
