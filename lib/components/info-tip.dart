import 'package:flutter/material.dart';

/// An explanation behind an icon: on hover on the computer, on a tap on the
/// phone.
class InfoTip extends StatelessWidget {
  const InfoTip(this.message, {super.key, this.size = 16});

  final String message;
  final double size;

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
      size: size,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

/// A tile title followed by its [InfoTip].
class InfoTitle extends StatelessWidget {
  const InfoTitle(this.title, this.info, {super.key});

  final String title;
  final String info;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Flexible(child: Text(title)),
      const SizedBox(width: 6),
      InfoTip(info),
    ],
  );
}
