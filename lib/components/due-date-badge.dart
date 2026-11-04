import 'package:flutter/material.dart';

/// Small calendar on the corner of a Pix / boleto icon: the code was pasted
/// but brought no due date, so the occurrence's day was not checked
/// ([Record.dueDateUnknown]).
class DueDateBadge extends StatelessWidget {
  final bool show;
  final Widget child;

  const DueDateBadge({super.key, required this.show, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!show) return child;
    final theme = Theme.of(context);
    return Tooltip(
      message: 'O código não trouxe o vencimento: confira a data',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          Positioned(
            top: -5,
            right: -5,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.event,
                size: 13,
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
