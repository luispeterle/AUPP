import 'package:flutter/material.dart';
import 'package:aupp/calculators/calculators-page.dart';
import 'package:aupp/desktop/asset-workspace-view.dart';
import 'package:aupp/desktop/asset-workspaces.dart';

/// The Calculadoras tab on the computer: a browser of those sites. A page only
/// loads when clicked and then stays in standby until closed.
class CalculatorsArea extends StatefulWidget {
  const CalculatorsArea({super.key, required this.visible});

  /// The pages are native views above Flutter, so nothing else would hide them.
  final bool visible;

  @override
  State<CalculatorsArea> createState() => _CalculatorsAreaState();
}

class _CalculatorsAreaState extends State<CalculatorsArea> {
  final _pageArea = GlobalKey();
  final _workspaces = AssetWorkspaces.instance;

  @override
  void initState() {
    super.initState();
    _workspaces.setCalculators([
      for (final c in CalculatorsPage.calculators)
        (label: c.name, url: c.uri.toString()),
    ]);
  }

  @override
  void dispose() {
    // The window was narrowed: nothing reserves the area for the page now.
    _workspaces.hideCalculatorPages();
    super.dispose();
  }

  SiteTab _tabOf(Calculator calculator) => _workspaces.calculators.tabs
      .firstWhere((tab) => tab.label == calculator.name);

  /// After the frame, when the area has its final size and position.
  void _syncPage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final tab = _workspaces.calculators.active;
      final box = _pageArea.currentContext?.findRenderObject() as RenderBox?;
      if (!widget.visible || tab == null) {
        _workspaces.hideCalculatorPages();
      } else if (box != null && box.hasSize) {
        _workspaces.show(tab, box.localToGlobal(Offset.zero) & box.size);
      }
    });
  }

  Widget _buildBar(SiteTab? active) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            const SizedBox(width: 8),
            SiteChip(
              label: 'Calculadoras',
              icon: const Icon(Icons.apps, size: 20),
              selected: active == null,
              onTap: () => _workspaces.showCalculator(null),
            ),
            Expanded(
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (final calculator in CalculatorsPage.calculators)
                    _chip(calculator, active),
                ],
              ),
            ),
            if (active != null)
              SitePageActions(
                tab: active,
                onClose: () => _workspaces.closeCalculator(active),
              ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  Widget _chip(Calculator calculator, SiteTab? active) {
    final tab = _tabOf(calculator);
    return SiteChip(
      label: calculator.name,
      icon: Icon(calculator.icon, size: 20, color: calculator.color),
      selected: tab == active,
      loading: tab.loading,
      inStandby: tab.opened && tab != active,
      onTap: () => _workspaces.showCalculator(tab),
      onSecondaryTap: tab.opened ? () => _workspaces.closeCalculator(tab) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _workspaces,
      builder: (context, _) {
        final active = _workspaces.calculators.active;
        _syncPage();
        return Scaffold(
          body: Column(
            children: [
              _buildBar(active),
              const Divider(height: 1),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Also follows a resized window.
                    if (active != null) _syncPage();
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        Offstage(
                          offstage: active != null,
                          child: CalculatorsPage(
                            onOpen: (calculator) => _workspaces.showCalculator(
                              _tabOf(calculator),
                            ),
                          ),
                        ),
                        SizedBox(key: _pageArea),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
