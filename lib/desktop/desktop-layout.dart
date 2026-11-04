import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

/// From this window width on, the app uses the computer layout: side rail,
/// limited content width and the Extrato in two columns. Phones stay below it.
const double wideLayoutMinWidth = 840;

bool isWideLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= wideLayoutMinWidth;

/// Running on a computer. The tests run on one too, but exercise the phone's
/// behavior (in-app keyboard, payment button).
bool get isComputer =>
    (Platform.isLinux || Platform.isWindows || Platform.isMacOS) &&
    !Platform.environment.containsKey('FLUTTER_TEST');

/// Two columns of cards when there is room, otherwise one, in [narrow] order.
class AdaptiveColumns extends StatelessWidget {
  const AdaptiveColumns({
    super.key,
    required this.left,
    required this.right,
    required this.narrow,
  });

  /// Below this width the cards would get too tight side by side.
  static const double minTwoColumnWidth = 980;

  final List<Widget> left;
  final List<Widget> right;
  final List<Widget> narrow;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < minTwoColumnWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: narrow,
          );
        }
        Widget column(List<Widget> children) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [column(left), column(right)],
        );
      },
    );
  }
}

/// Lists also drag with the mouse, so pull to refresh works on the computer.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    ...super.dragDevices,
    PointerDeviceKind.mouse,
  };
}
