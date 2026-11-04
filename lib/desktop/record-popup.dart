import 'package:flutter/material.dart';
import 'package:aupp/desktop/desktop-layout.dart';

/// Opens a record: in a popup on the computer, on top of the page on the phone.
/// Completes when it is closed, like Navigator.push.
Future<void> openRecord(BuildContext context, WidgetBuilder builder) {
  if (!isWideLayout(context)) {
    return Navigator.push(context, MaterialPageRoute(builder: builder));
  }
  return showDialog<void>(
    context: context,
    builder: (_) => _RecordPopup(builder: builder),
  );
}

/// The popup has its own navigator, so the edit page and whatever it opens
/// (category picker, tags) work inside without changes. An empty first route
/// is what lets the page pop itself: when it does, the popup closes.
class _RecordPopup extends StatefulWidget {
  const _RecordPopup({required this.builder});

  final WidgetBuilder builder;

  @override
  State<_RecordPopup> createState() => _RecordPopupState();
}

class _RecordPopupState extends State<_RecordPopup> {
  late final Route<void> _page = PageRouteBuilder<void>(
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (context, _, _) => widget.builder(context),
  );

  @override
  void initState() {
    super.initState();
    _page.popped.then((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.all(32),
      child: SizedBox(
        width: 720,
        height: size.height - 64 < 860 ? size.height - 64 : 860,
        child: Navigator(
          onGenerateInitialRoutes: (_, _) => [
            PageRouteBuilder<void>(
              pageBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
            _page,
          ],
        ),
      ),
    );
  }
}
