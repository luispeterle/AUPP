import 'package:flutter/material.dart';

import 'known-tags.dart';

/// Red, blinking boleto / Pix icon: an upcoming occurrence of a recurrence
/// paid that way still without its code ([Record.needsPaymentCode]).
class MissingPaymentCodeIcon extends StatelessWidget {
  /// "Boleto" or "Pix" ([Record.billingKindOf]).
  final String kind;
  final double size;

  const MissingPaymentCodeIcon(this.kind, {super.key, this.size = 34});

  @override
  Widget build(BuildContext context) => BlinkingAlertIcon(
    KnownTag.of(kind)?.icon ?? Icons.qr_code_2,
    message: 'Falta o código do $kind',
    size: size,
  );
}

/// Red, blinking round icon left of an amount: something on the record
/// waits for the user.
class BlinkingAlertIcon extends StatefulWidget {
  final IconData icon;
  final String message;
  final double size;

  const BlinkingAlertIcon(
    this.icon, {
    super.key,
    required this.message,
    this.size = 34,
  });

  @override
  State<BlinkingAlertIcon> createState() => _BlinkingAlertIconState();
}

class _BlinkingAlertIconState extends State<BlinkingAlertIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
    lowerBound: 0.25,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return Tooltip(
      message: widget.message,
      child: FadeTransition(
        opacity: _blink,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: error, width: 1.5),
          ),
          child: Icon(widget.icon, size: widget.size / 2, color: error),
        ),
      ),
    );
  }
}
