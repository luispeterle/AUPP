import 'package:aupp/components/payment-code-sheet.dart';
import 'package:aupp/dinzo/pix-charge.dart';
import 'package:aupp/dinzo/pix-code.dart';
import 'package:aupp/helpers/records-utility-functions.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/services/payment-code-reader.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// A Pix / boleto taken from a PDF or a picture: the file picker, and the
/// choice when the file has both (a boleto with a Pix QR code).
class PaymentCodeFile {
  /// Picks a PDF or picture; its path, or null when cancelled.
  static Future<String?> pick() async {
    List<PlatformFile> files;
    try {
      files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: PaymentCodeReader.extensions,
      );
    } catch (_) {
      // Some Androids refuse the filter.
      files = await FilePicker.pickFiles();
    }
    return files.isEmpty ? null : files.single.path;
  }

  /// Picks a file and reads it. The code (the one chosen, when there are
  /// several), or null with [onProblem] told why. [onReading] brackets the
  /// reading, for a progress sign. With [pixOnly], boletos are left out.
  static Future<String?> pickAndRead(
    BuildContext context, {
    required void Function(bool reading) onReading,
    required void Function(String? problem) onProblem,
    bool pixOnly = false,
  }) async {
    onProblem(null);
    final path = await pick();
    if (path == null) return null;
    onReading(true);
    List<String> codes;
    try {
      codes = await PaymentCodeReader.readFile(path);
    } catch (_) {
      codes = const [];
    } finally {
      onReading(false);
    }
    if (pixOnly) {
      codes = codes.where((c) => Record.paymentCodeKind(c) == 'Pix').toList();
    }
    if (codes.isEmpty) {
      onProblem(
        pixOnly
            ? 'Nenhum QR code de Pix neste arquivo.'
            : 'Nenhum QR code de Pix nem código de barras de boleto neste '
                  'arquivo.',
      );
      return null;
    }
    if (codes.length == 1 || !context.mounted) return codes.first;
    return choose(context, codes);
  }

  /// Asks which of [codes] to use.
  static Future<String?> choose(BuildContext context, List<String> codes) =>
      showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Qual código usar?'),
          contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
          children: [
            for (final code in codes)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FoundCodeTile(
                  code: code,
                  onTap: () => Navigator.pop(context, code),
                ),
              ),
          ],
        ),
      );

  /// Amount and due date written in [code] (no network).
  static CodeFacts localFacts(String code) => CodeFacts(
    amount: PixCode.amountOf(code),
    due: PixCode.dueDateOf(code),
  );

  /// Amount and due date of [code]; a Pix charge asks its bank.
  static Future<CodeFacts> facts(String code) async {
    if (PixCharge.urlOf(code) == null) return localFacts(code);
    final charge = await PixCharge.fetch(code);
    if (charge == null) {
      return CodeFacts(amount: PixCode.amountOf(code), charge: true);
    }
    return CodeFacts(
      amount: charge.amount,
      due: charge.dueDate,
      receiver: charge.receiver,
      charge: true,
      paid: !charge.isOpen,
    );
  }
}

/// What a code says about the bill: amount, due date, who receives.
class CodeFacts {
  final double? amount;
  final DateTime? due;
  final String? receiver;

  /// A Pix charge (its data comes from the bank).
  final bool charge;

  /// The bank says the charge is already paid.
  final bool paid;

  /// Still asking the bank.
  final bool loading;

  const CodeFacts({
    this.amount,
    this.due,
    this.receiver,
    this.charge = false,
    this.paid = false,
    this.loading = false,
  });
}

/// One code found in a file: its kind, amount and due date in evidence, and
/// the start of the code itself. [selected] outlines it.
class FoundCodeTile extends StatelessWidget {
  final String code;
  final bool selected;
  final VoidCallback onTap;

  /// Amount and due date; read from the code itself when null.
  final CodeFacts? facts;

  const FoundCodeTile({
    super.key,
    required this.code,
    required this.onTap,
    this.selected = false,
    this.facts,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kind = Record.paymentCodeKind(code);
    final color = codeKindColor(kind);
    final f = facts ?? PaymentCodeFile.localFacts(code);
    Widget fact(IconData icon, String text, {bool strong = false}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: strong
              ? theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                )
              : theme.textTheme.bodyMedium,
        ),
      ],
    );
    return Material(
      color: color.withValues(alpha: selected ? 0.16 : 0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? color : color.withValues(alpha: 0.3),
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: color.withValues(alpha: 0.18),
                child: Icon(codeKindIcon(kind), color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        f.charge ? 'Pix de cobrança' : kind,
                        if (f.receiver != null) f.receiver!,
                      ].join(' · '),
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    if (f.loading)
                      Text(
                        'Consultando valor e vencimento no banco…',
                        style: theme.textTheme.bodySmall,
                      )
                    else
                      Wrap(
                        spacing: 16,
                        runSpacing: 4,
                        children: [
                          fact(
                            Icons.payments_outlined,
                            f.amount == null
                                ? 'sem valor no código'
                                : getCurrencyValueString(f.amount),
                            strong: f.amount != null,
                          ),
                          fact(
                            Icons.event,
                            f.due == null
                                ? 'sem vencimento no código'
                                : 'vence '
                                      '${DateFormat('EEE, dd/MM/yyyy', 'pt_BR').format(f.due!)}',
                            strong: f.due != null,
                          ),
                          if (f.paid)
                            fact(Icons.check_circle_outline, 'já paga'),
                        ],
                      ),
                    const SizedBox(height: 6),
                    Text(
                      code,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                Icon(Icons.check_circle, color: color),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
