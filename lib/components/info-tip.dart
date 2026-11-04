import 'package:flutter/material.dart';

/// An explanation behind an icon: on hover on the computer, on a tap on the
/// phone.
class InfoTip extends StatelessWidget {
  const InfoTip(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: message,
    triggerMode: TooltipTriggerMode.tap,
    showDuration: const Duration(seconds: 8),
    waitDuration: const Duration(milliseconds: 200),
    constraints: const BoxConstraints(maxWidth: 360),
    padding: const EdgeInsets.all(10),
    child: Icon(
      Icons.info_outline,
      size: 16,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}
