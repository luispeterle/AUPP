import 'package:flutter/material.dart';
import 'package:aupp/components/missing-payment-code-icon.dart';
import 'package:aupp/helpers/records-utility-functions.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/services/service-config.dart';

import 'aporte-shortfall.dart';

/// On an aporte from the Dinzo: says when the wallet to invest did not have
/// all of it, and records, once the user confirms, that the rest came from
/// the default wallet ([AporteShortfall]).
class AporteShortfallTile extends StatefulWidget {
  final Record aporte;

  const AporteShortfallTile({super.key, required this.aporte});

  @override
  State<AporteShortfallTile> createState() => _AporteShortfallTileState();
}

class _AporteShortfallTileState extends State<AporteShortfallTile> {
  double? _missing;
  Record? _cover;
  String _from = 'Conta corrente';
  String _to = 'Investir';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final aporte = widget.aporte;
    await AporteShortfall.mark([aporte]);
    final cover = await AporteShortfall.coverOf(aporte);
    final db = ServiceConfig.database;
    final from = await db.getDefaultWallet();
    final to = aporte.walletId == null
        ? null
        : await db.getWalletById(aporte.walletId!);
    if (!mounted) return;
    setState(() {
      _missing = aporte.investShortfall;
      _cover = cover;
      if (from != null) _from = from.name;
      if (to != null) _to = to.name;
    });
  }

  Future<void> _confirm() async {
    final missing = _missing;
    if (missing == null) return;
    setState(() => _saving = true);
    await AporteShortfall.cover(widget.aporte, missing);
    if (!mounted) return;
    setState(() => _saving = false);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final missing = _missing;
    final covered = _cover?.transferValue;
    if (missing == null && covered == null) return const SizedBox.shrink();
    if (missing == null) {
      return ListTile(
        leading: const Icon(Icons.check_circle_outline, color: Colors.green),
        title: Text('Parte saiu da $_from'),
        subtitle: Text(
          '${getCurrencyValueString(covered!)} deste aporte saíram da $_from, '
          'porque o $_to não tinha tudo. Está registrado como transferência '
          'da $_from para o $_to neste dia.',
        ),
      );
    }
    final amount = getCurrencyValueString(missing);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BlinkingAlertIcon(
            Icons.priority_high,
            message: 'O Investir não tinha todo o dinheiro do aporte',
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Faltou dinheiro no $_to',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'O $_to não tinha $amount deste aporte, então esse valor '
                  'saiu da $_from. Se estiver certo, confirme: entra uma '
                  'transferência de $amount da $_from para o $_to neste dia, '
                  'e o aporte conta como dinheiro investido da $_from.',
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _saving ? null : _confirm,
                  icon: const Icon(Icons.check),
                  label: const Text('Está certo'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
