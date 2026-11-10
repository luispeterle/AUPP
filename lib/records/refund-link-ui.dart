import 'package:aupp/components/category_icon_circle.dart';
import 'package:aupp/components/info-tip.dart';
import 'package:aupp/helpers/datetime-utility-functions.dart';
import 'package:aupp/helpers/records-utility-functions.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/records/refund-link.dart';
import 'package:flutter/material.dart';

const _green = Color(0xFF43A047);

/// The record's screen: on money that came in, "Vincular como estorno"
/// (choose the expense it undoes); on a linked refund, that expense and
/// "Desvincular". Linking or unlinking closes the screen, so the list shows
/// the record with its new category.
class RefundLinkTile extends StatefulWidget {
  final Record record;

  const RefundLinkTile({super.key, required this.record});

  static bool shows(Record? record) =>
      record != null &&
      (record.refundLink != null || RefundLink.canBeRefund(record));

  @override
  State<RefundLinkTile> createState() => _RefundLinkTileState();
}

class _RefundLinkTileState extends State<RefundLinkTile> {
  /// The other side(s): the expense of a refund, the refunds of an expense.
  List<Record>? _others;

  @override
  void initState() {
    super.initState();
    final link = RefundLink.decode(widget.record.refundLink);
    if (link == null) return;
    (link.isRefund
            ? RefundLink.expenseOf(widget.record).then((e) => [?e])
            : RefundLink.refundsOf(widget.record))
        .then((others) {
          if (mounted) setState(() => _others = others);
        });
  }

  @override
  Widget build(BuildContext context) {
    final link = RefundLink.decode(widget.record.refundLink);
    if (link == null) {
      return ListTile(
        leading: const Icon(Icons.undo),
        title: const Text('Vincular como estorno'),
        trailing: const Icon(Icons.chevron_right),
        onTap: _pick,
      );
    }
    final String title;
    final String subtitle;
    if (link.isRefund) {
      final expense = link.expense!;
      final name = _others?.firstOrNull?.title ?? expense.title ?? '';
      title = link.isPartial
          ? 'Reembolso parcial de "$name"'
          : 'Estorno de "$name"';
      subtitle =
          '${getDateStr(expense.utc.toLocal())} · '
          '${formatMoney(expense.value)}'
          '${_others != null && _others!.isEmpty ? ' (não encontrado)' : ''}';
    } else if (!link.isPartial) {
      final refund = link.refunds.first;
      title = 'Estornado por "${refund.title ?? ''}"';
      subtitle =
          '${getDateStr(refund.utc.toLocal())} · ${formatMoney(refund.value)}';
    } else {
      title = 'Reembolso parcial de ${formatMoney(link.refunded)}';
      subtitle = [
        for (final r in link.refunds)
          '${r.title ?? ''} (${formatMoney(r.value)})',
      ].join(' · ');
    }
    return ListTile(
      leading: const Icon(Icons.undo, color: _green),
      title: InfoTitle(
        title,
        link.isPartial
            ? 'O gasto conta só o que sobrou.'
            : 'Os dois não contam em receita, gasto, orçamento nem '
                  'estatísticas.',
      ),
      subtitle: Text(subtitle),
      trailing: TextButton(
        onPressed: _unlink,
        child: const Text('Desvincular'),
      ),
    );
  }

  Future<void> _pick() async {
    if (await linkRefund(context, widget.record) && mounted) {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _unlink() async {
    await RefundLink.unlink(widget.record);
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('Estorno desvinculado')),
    );
    Navigator.of(context).maybePop();
  }
}

/// Lists the expenses [refund] may undo (its amount or more, the same
/// amount first) and returns the one chosen.
Future<Record?> pickRefundExpense(BuildContext context, Record refund) =>
    showModalBottomSheet<Record>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (context, scroll) => FutureBuilder<List<Record>>(
          future: RefundLink.candidates(refund),
          builder: (context, snapshot) {
            final items = snapshot.data;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: Text(
                    'De qual gasto é este estorno?',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    '${formatMoney(refund.value ?? 0)} em '
                    '${getDateStr(refund.dateTime)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: items == null
                      ? const Center(child: CircularProgressIndicator())
                      : items.isEmpty
                      ? const Center(child: Text('Nenhum gasto possível'))
                      : ListView.separated(
                          controller: scroll,
                          itemCount: items.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1, indent: 64),
                          itemBuilder: (context, i) {
                            final e = items[i];
                            final same =
                                ((e.value ?? 0) + (refund.value ?? 0)).abs() <
                                0.005;
                            return ListTile(
                              leading: _icon(e),
                              title: Text(
                                e.title ?? e.category?.name ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${getDateStr(e.dateTime)} · '
                                '${e.category?.name ?? ''}',
                              ),
                              trailing: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    formatMoney(e.value ?? 0),
                                    style: TextStyle(
                                      fontWeight: same
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                      color: getRecordAmountColor(
                                        e,
                                        Theme.of(context).brightness,
                                      ),
                                    ),
                                  ),
                                  // Already refunded in part: what came back.
                                  if (e.refundLink != null)
                                    Text(
                                      '−${formatMoney(-(e.value ?? 0) - RefundLink.leftOf(e))} '
                                      'de reembolsos',
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        color: _green,
                                      ),
                                    ),
                                ],
                              ),
                              onTap: () => Navigator.pop(context, e),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );

Widget _icon(Record r) => CategoryIconCircle(
  circleSize: 36,
  mainIconSize: 18,
  overlayIconSize: 13,
  iconEmoji: r.category?.iconEmoji,
  iconDataFromDefaultIconSet: r.category?.icon ?? Icons.swap_horiz,
  backgroundColor: r.category?.color,
);

enum _Answer { link, other }

/// Links [refund] to an expense: the [suggestion] when there is one (with
/// "Escolher outro"), else the one picked from the list; always asking
/// first. True when linked.
Future<bool> linkRefund(
  BuildContext context,
  Record refund, {
  Record? suggestion,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  var expense = suggestion;
  while (true) {
    expense ??= await pickRefundExpense(context, refund);
    if (expense == null || !context.mounted) return false;
    final answer = await showDialog<_Answer>(
      context: context,
      builder: (_) => _RefundLinkDialog(refund: refund, expense: expense!),
    );
    if (answer == _Answer.other && context.mounted) {
      expense = null;
      continue;
    }
    if (answer != _Answer.link) return false;
    break;
  }
  await RefundLink.link(refund, expense);
  messenger?.showSnackBar(
    const SnackBar(content: Text('Vinculado como estorno')),
  );
  return true;
}

class _RefundLinkDialog extends StatelessWidget {
  final Record refund;
  final Record expense;

  const _RefundLinkDialog({required this.refund, required this.expense});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final muted = scheme.onSurfaceVariant;
    // All of it at once: neither counts. Else a partial refund.
    final whole =
        expense.refundLink == null && RefundLink.sameAmount(refund, expense);
    Widget row(Record r, String label) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant, width: 0.8),
      ),
      child: Row(
        children: [
          _icon(r),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w600,
                    color: muted,
                  ),
                ),
                Text(
                  r.title ?? r.category?.name ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15),
                ),
                Text(
                  getDateStr(r.dateTime),
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatMoney(r.value ?? 0),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: getRecordAmountColor(r, Theme.of(context).brightness),
            ),
          ),
        ],
      ),
    );
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: _green,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.undo, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Vincular como estorno?',
                      style: text.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              row(expense, 'Gasto'),
              Padding(
                padding: const EdgeInsets.only(left: 18),
                child: Icon(Icons.arrow_downward, size: 18, color: muted),
              ),
              row(
                refund,
                whole
                    ? 'Estorno'
                    : 'Reembolso parcial',
              ),
              const SizedBox(height: 16),
              Text(
                whole
                    ? 'Os dois deixam de contar em receita, gasto, orçamento '
                          'e estatísticas.'
                    : 'Reembolso parcial: o gasto passa a contar '
                          '${formatMoney(-RefundLink.leftOf(expense) + (refund.value ?? 0))}.',
                style: TextStyle(fontSize: 13.5, color: muted),
              ),
              const SizedBox(height: 14),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, _Answer.other),
                    child: const Text('Escolher outro item'),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => Navigator.pop(context, _Answer.link),
                    icon: const Icon(Icons.undo, size: 18),
                    label: const Text('Vincular'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
