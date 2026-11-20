import 'package:flutter/material.dart';
import 'package:aupp/helpers/records-utility-functions.dart';

/// "R$ 608 a caminho": money that left an account and the Dinzo does not
/// show yet. Only a hint, beside a total; it counts in none.
class OnTheWayChip extends StatelessWidget {
  const OnTheWayChip(this.amount, {super.key});

  final double amount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule, size: 14, color: scheme.onTertiaryContainer),
          const SizedBox(width: 4),
          Text(
            '${getCurrencyValueString(amount)} a caminho',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: scheme.onTertiaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}
