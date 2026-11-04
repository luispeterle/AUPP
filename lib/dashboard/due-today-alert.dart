import 'package:aupp/helpers/records-utility-functions.dart';
import 'package:aupp/models/record.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Red, blinking card on the home screen: boletos and Pix due today (or
/// overdue) and not paid yet. Each one can be paid or marked "Já paguei"
/// while its real record has not come from the Dinzo.
class DueTodayAlert extends StatefulWidget {
  final List<Record> due;
  final void Function(Record) onPay;
  final void Function(Record) onMarkPaid;
  final void Function(Record) onOpen;

  const DueTodayAlert({
    super.key,
    required this.due,
    required this.onPay,
    required this.onMarkPaid,
    required this.onOpen,
  });

  @override
  State<DueTodayAlert> createState() => _DueTodayAlertState();
}

class _DueTodayAlertState extends State<DueTodayAlert>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  static bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = theme.colorScheme.error;
    final overdue = widget.due.any((r) => !_isToday(r.dateTime));
    final total = widget.due.fold<double>(
      0,
      (sum, r) => sum + (r.value ?? 0).abs(),
    );
    return AnimatedBuilder(
      animation: _blink,
      builder: (context, child) => Container(
        decoration: BoxDecoration(
          color: error.withValues(alpha: 0.06 + 0.08 * _blink.value),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: error.withValues(alpha: 0.35 + 0.65 * _blink.value),
            width: 2,
          ),
        ),
        child: child,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                FadeTransition(
                  opacity: Tween(begin: 0.3, end: 1.0).animate(_blink),
                  child: Icon(Icons.notification_important, color: error),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    overdue ? 'Pagamentos vencendo' : 'Vence hoje',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    getCurrencyValueString(total),
                    style: theme.textTheme.titleMedium?.copyWith(color: error),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (final r in widget.due) _buildRow(theme, r),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(ThemeData theme, Record r) {
    final title = r.title == null || r.title!.trim().isEmpty
        ? r.category?.name ?? 'Conta'
        : r.title!;
    final code = r.paymentCode;
    final kind = code != null
        ? Record.paymentCodeKind(code)
        : Record.billingKindOf(r.tags) ?? 'Conta';
    final when = _isToday(r.dateTime)
        ? 'hoje'
        : 'venceu ${DateFormat('dd/MM').format(r.dateTime)}';
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => widget.onOpen(r),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge,
                  ),
                  Text(
                    '${getCurrencyValueString((r.value ?? 0).abs())} · $kind'
                    '${code == null ? ' sem código' : ''} · $when',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (code != null)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: const Color(0xFFF9A825),
                    foregroundColor: Colors.black87,
                  ),
                  onPressed: () => widget.onPay(r),
                  child: const Text('Pagar'),
                ),
              ),
            TextButton.icon(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () => widget.onMarkPaid(r),
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Já paguei'),
            ),
          ],
        ),
      ),
    );
  }
}
