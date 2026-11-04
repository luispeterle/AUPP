import 'package:aupp/components/code-scanner-page.dart';
import 'package:aupp/components/known-tags.dart';
import 'package:aupp/desktop/desktop-layout.dart';
import 'package:aupp/dinzo/pix-charge.dart';
import 'package:aupp/dinzo/pix-code.dart';
import 'package:aupp/helpers/records-utility-functions.dart';
import 'package:aupp/models/record.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Bottom sheet to scan, paste or remove the Pix / boleto of one occurrence.
/// Shows what the code is and the amount it carries. Pops with the code,
/// '' to remove it, or null when cancelled.
class PaymentCodeSheet extends StatefulWidget {
  /// What it is for, e.g. "Água · qua, 05/11".
  final String subtitle;
  final String? initial;

  /// The occurrence's amount (positive), to tell when the code changes it.
  final double? amount;

  const PaymentCodeSheet({
    super.key,
    required this.subtitle,
    this.initial,
    this.amount,
  });

  static Future<String?> show(
    BuildContext context, {
    required String subtitle,
    String? initial,
    double? amount,
  }) => showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) =>
        PaymentCodeSheet(subtitle: subtitle, initial: initial, amount: amount),
  );

  @override
  State<PaymentCodeSheet> createState() => _PaymentCodeSheetState();
}

class _PaymentCodeSheetState extends State<PaymentCodeSheet> {
  late final _controller = TextEditingController(text: widget.initial ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final code = await CodeScannerPage.scan(context);
    if (code != null) setState(() => _controller.text = code);
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) {
      setState(() => _controller.text = text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = _controller.text.trim();
    final kind = code.isEmpty ? null : Record.paymentCodeKind(code);
    return SheetBody(
      icon: kind == null ? Icons.qr_code_2 : codeKindIcon(kind),
      iconColor: kind == null ? null : codeKindColor(kind),
      title: 'Pix ou boleto',
      subtitle: widget.subtitle,
      children: [
        CodeSourceButtons(onScan: _scan, onPaste: _paste),
        const SizedBox(height: 16),
        TextField(
          controller: _controller,
          minLines: 2,
          maxLines: 5,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          decoration: InputDecoration(
            labelText: 'Código',
            hintText: 'Pix copia-e-cola ou linha digitável do boleto',
            border: const OutlineInputBorder(),
            suffixIcon: code.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Limpar',
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => _controller.clear()),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        if (kind != null && PixCharge.urlOf(code) != null)
          FutureBuilder<PixCharge?>(
            // Cached per address: typing elsewhere does not ask again.
            future: PixCharge.fetch(code),
            builder: (context, snap) =>
                _buildRecognized(theme, code, kind, charge: snap),
          )
        else if (kind != null)
          _buildRecognized(theme, code, kind),
      ],
      actions: [
        if (widget.initial != null)
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, ''),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Remover'),
          ),
        const Spacer(),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: code.isEmpty || code == widget.initial?.trim()
              ? null
              : () => Navigator.pop(context, code),
          child: const Text('Salvar'),
        ),
      ],
    );
  }

  /// "Boleto reconhecido · R$ 87,40", and what that does to the amount.
  /// With [charge], a Pix charge: its amount comes from the receiver's bank.
  Widget _buildRecognized(
    ThemeData theme,
    String code,
    String kind, {
    AsyncSnapshot<PixCharge?>? charge,
  }) {
    final known = kind != 'Código';
    final loading =
        charge != null && charge.connectionState != ConnectionState.done;
    final found = charge?.data;
    final amount = found?.amount ?? PixCode.amountOf(code);
    final current = widget.amount;
    final changes =
        amount != null && current != null && (amount - current).abs() >= 0.005;
    final color = known ? codeKindColor(kind) : theme.colorScheme.error;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(known ? Icons.check_circle : Icons.help_outline, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  !known
                      ? 'Não parece um Pix nem um boleto'
                      : charge != null
                      ? 'Pix de cobrança'
                      : '$kind reconhecido',
                  style: theme.textTheme.titleSmall,
                ),
                if (loading)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Consultando o valor no banco…',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  )
                else if (charge != null && found == null)
                  Text(
                    'O banco não respondeu: fica o valor da conta. O app do '
                    'banco mostra o valor ao pagar.',
                    style: theme.textTheme.bodyMedium,
                  )
                else if (found != null)
                  Text(
                    [
                      if (found.receiver != null) found.receiver!,
                      if (found.dueDate != null)
                        'vence ${DateFormat('dd/MM').format(found.dueDate!)}',
                      getCurrencyValueString(found.amount),
                      if (!found.isOpen) 'já paga',
                    ].join(' · '),
                    style: theme.textTheme.bodyMedium,
                  )
                else if (known)
                  Text(
                    [
                      amount == null
                          ? 'Sem valor no código: fica o valor da conta'
                          : 'Valor no código: ${getCurrencyValueString(amount)}',
                      if (PixCode.dueDateOf(code) case final due?)
                        'vence ${DateFormat('dd/MM').format(due)}',
                    ].join(' · '),
                    style: theme.textTheme.bodyMedium,
                  ),
                if ((found?.dueDate ?? PixCode.dueDateOf(code)) case final due?)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'A conta passa para o dia do vencimento '
                      '(${DateFormat('dd/MM').format(due)}).',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                if (changes)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Só esta conta passa de '
                      '${getCurrencyValueString(current)} para '
                      '${getCurrencyValueString(amount)}. O recorrente '
                      'continua com ${getCurrencyValueString(current)}.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The same Pix every month: a person's key (each occurrence gets its own
/// amount) or a fixed copia-e-cola. Pops with (key or code, name), ('', '')
/// to remove it, or null.
class DefaultPixSheet extends StatefulWidget {
  final String? initialKey;
  final String? initialName;

  const DefaultPixSheet({super.key, this.initialKey, this.initialName});

  static Future<(String, String)?> show(
    BuildContext context, {
    String? initialKey,
    String? initialName,
  }) => showModalBottomSheet<(String, String)>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) =>
        DefaultPixSheet(initialKey: initialKey, initialName: initialName),
  );

  @override
  State<DefaultPixSheet> createState() => _DefaultPixSheetState();
}

class _DefaultPixSheetState extends State<DefaultPixSheet> {
  late final _key = TextEditingController(text: widget.initialKey ?? '');
  late final _name = TextEditingController(text: widget.initialName ?? '');

  @override
  void dispose() {
    _key.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final code = await CodeScannerPage.scan(context);
    if (code != null) setState(() => _key.text = code);
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) setState(() => _key.text = text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final key = _key.text.trim();
    final payload = PixCode.isPayload(key);
    return SheetBody(
      icon: codeKindIcon('Pix'),
      iconColor: codeKindColor('Pix'),
      title: 'Pix padrão',
      subtitle: 'O mesmo Pix todo mês, já com o valor de cada conta',
      children: [
        CodeSourceButtons(onScan: _scan, onPaste: _paste),
        const SizedBox(height: 16),
        TextField(
          controller: _key,
          minLines: 1,
          maxLines: 4,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Chave Pix ou copia-e-cola',
            helperText:
                'Telefone com +55, CPF, CNPJ, e-mail ou chave aleatória',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.key_outlined),
            suffixIcon: key.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Limpar',
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => _key.clear()),
                  ),
          ),
        ),
        if (!payload) ...[
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nome de quem recebe (opcional)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
        ],
        if (key.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: codeKindColor('Pix').withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: codeKindColor('Pix')),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    payload
                        ? PixCode.amountOf(key) == null
                              ? 'Copia-e-cola fixo, sem valor: você digita no '
                                    'banco.'
                              : 'Copia-e-cola fixo de '
                                    '${getCurrencyValueString(PixCode.amountOf(key))}'
                                    ' todo mês.'
                        : '${PixCode.keyKind(key)} '
                              '${PixCode.normalizeKey(key)}: cada conta gera o '
                              'Pix com o valor dela.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
      actions: [
        if (widget.initialKey != null)
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, ('', '')),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Remover'),
          ),
        const Spacer(),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: key.isEmpty
              ? null
              : () => Navigator.pop(context, (key, _name.text.trim())),
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}

IconData codeKindIcon(String kind) =>
    KnownTag.of(kind)?.icon ?? Icons.qr_code_2;

Color codeKindColor(String kind) =>
    KnownTag.of(kind)?.color ?? const Color(0xFF546E7A);

/// Header (round icon, title, subtitle), content and a row of actions, above
/// the keyboard and no wider than a phone on the computer.
class SheetBody extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String subtitle;
  final List<Widget> children;
  final List<Widget> actions;

  const SheetBody({
    super.key,
    required this.icon,
    this.iconColor,
    required this.title,
    required this.subtitle,
    required this.children,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = iconColor ?? theme.colorScheme.primary;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: color.withValues(alpha: 0.15),
                      child: Icon(icon, color: color),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: theme.textTheme.titleLarge),
                          Text(
                            subtitle,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                ...children,
                const SizedBox(height: 16),
                Row(children: actions),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Escanear" (phone only) and "Colar", side by side.
class CodeSourceButtons extends StatelessWidget {
  final VoidCallback onScan;
  final VoidCallback onPaste;

  const CodeSourceButtons({
    super.key,
    required this.onScan,
    required this.onPaste,
  });

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
    return Row(
      children: [
        if (!isComputer) ...[
          Expanded(
            child: FilledButton.tonalIcon(
              style: style,
              onPressed: onScan,
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Escanear'),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: FilledButton.tonalIcon(
            style: style,
            onPressed: onPaste,
            icon: const Icon(Icons.content_paste),
            label: const Text('Colar'),
          ),
        ),
      ],
    );
  }
}
