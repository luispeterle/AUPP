import 'package:flutter/material.dart';
import 'package:aupp/components/info-tip.dart';

/// The label over the big total of each investments tab (Nacional,
/// Internacional, Cripto): the same look in all of them.
class TotalLabel extends StatelessWidget {
  const TotalLabel(this.text, {super.key, this.info});

  final String text;

  /// An explanation behind an (i) by the label.
  final String? info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        if (info != null) ...[const SizedBox(width: 4), InfoTip(info!)],
      ],
    );
  }
}

/// The big total under [TotalLabel].
class TotalValue extends StatelessWidget {
  const TotalValue(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(
      context,
    ).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold),
  );
}
