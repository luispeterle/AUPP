import 'package:flutter/material.dart';
import 'package:aupp/desktop/asset-workspaces.dart';
import 'package:aupp/desktop/compare-page.dart';
import 'package:aupp/desktop/fii-compare-page.dart';
import 'package:aupp/investments/asset-sheet.dart';
import 'package:aupp/investments/asset-sheet-page.dart';
import 'package:aupp/investments/investments-page.dart';
import 'package:aupp/investments/stock-catalog.dart';
import 'package:url_launcher/url_launcher.dart';

/// The asset open on the computer: its workspace, with the Ficha and the sites.
/// The search is in Investimentos. Every workspace stays mounted, so that one in standby keeps its Ficha as it
/// was (what was typed in the simulator, the scroll position).
class AssetsArea extends StatefulWidget {
  const AssetsArea({super.key, required this.visible});

  /// Whether the Ativos tab is on screen. The pages are native views above
  /// Flutter, so nothing else would hide them.
  final bool visible;

  @override
  State<AssetsArea> createState() => _AssetsAreaState();
}

class _AssetsAreaState extends State<AssetsArea> {
  final _workspaces = AssetWorkspaces.instance;

  @override
  void dispose() {
    // The window was narrowed: nothing reserves the area for the page now.
    _workspaces.hideAssetPages();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _workspaces,
      builder: (context, _) {
        final current = _workspaces.current;
        if (!widget.visible || current?.active == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _workspaces.hideAssetPages());
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            for (final workspace in _workspaces.workspaces)
              Offstage(
                key: ValueKey(workspace.ticker),
                offstage: workspace != current,
                child: _WorkspaceView(
                  workspace: workspace,
                  visible: widget.visible && workspace == current,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A site, or the page that lists them, in the bar on top. All the same size.
class SiteChip extends StatelessWidget {
  const SiteChip({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.onSecondaryTap,
    this.loading = false,
    this.inStandby = false,
  });

  final String label;
  final Widget icon;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onSecondaryTap;
  final bool loading;

  /// Its page is alive, off screen.
  final bool inStandby;

  static const double _width = 158;
  static const double _height = 40;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = Row(
      children: [
        icon,
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? scheme.onSecondaryContainer : scheme.onSurface,
            ),
          ),
        ),
        if (inStandby) ...[
          const SizedBox(width: 4),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: scheme.primary,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: SizedBox(
        width: _width,
        height: _height,
        child: Tooltip(
          message: label,
          waitDuration: const Duration(milliseconds: 500),
          child: Material(
            color: selected
                ? scheme.secondaryContainer
                : scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              onSecondaryTap: onSecondaryTap,
              child: Stack(
                // Fills the chip, so that the row centers icon and text in it.
                fit: StackFit.expand,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: content,
                  ),
                  if (loading)
                    const Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What is done to the page on screen.
class SitePageActions extends StatelessWidget {
  const SitePageActions({super.key, required this.tab, this.onClose});

  final SiteTab tab;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final workspaces = AssetWorkspaces.instance;
    final dark = workspaces.darkPages;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Página anterior',
          icon: const Icon(Icons.chevron_left),
          onPressed: tab.canBack ? () => workspaces.pageBack(tab) : null,
        ),
        IconButton(
          tooltip: 'Próxima página',
          icon: const Icon(Icons.chevron_right),
          onPressed: tab.canForward ? () => workspaces.pageForward(tab) : null,
        ),
        IconButton(
          tooltip: 'Recarregar',
          icon: const Icon(Icons.refresh),
          onPressed: () => workspaces.pageReload(tab),
        ),
        IconButton(
          tooltip: dark ? 'Desligar modo escuro' : 'Ligar modo escuro',
          icon: Icon(dark ? Icons.dark_mode : Icons.dark_mode_outlined),
          onPressed: workspaces.toggleDarkPages,
        ),
        IconButton(
          tooltip: 'Abrir no navegador',
          icon: const Icon(Icons.open_in_new),
          onPressed: () => launchUrl(
            Uri.parse(tab.url),
            mode: LaunchMode.externalApplication,
          ),
        ),
        if (onClose != null)
          IconButton(
            tooltip: 'Fechar esta página',
            icon: const Icon(Icons.close),
            onPressed: onClose,
          ),
      ],
    );
  }
}

class _WorkspaceView extends StatefulWidget {
  const _WorkspaceView({required this.workspace, required this.visible});

  final AssetWorkspace workspace;
  final bool visible;

  @override
  State<_WorkspaceView> createState() => _WorkspaceViewState();
}

class _WorkspaceViewState extends State<_WorkspaceView> {
  final _pageArea = GlobalKey();
  final _workspaces = AssetWorkspaces.instance;

  /// After the frame, when the area has its final size and position.
  void _placePage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.visible) return;
      final tab = widget.workspace.active;
      final box = _pageArea.currentContext?.findRenderObject() as RenderBox?;
      if (tab == null || box == null || !box.hasSize) return;
      _workspaces.show(tab, box.localToGlobal(Offset.zero) & box.size);
    });
  }

  Widget _buildBar() {
    final workspace = widget.workspace;
    final active = workspace.active;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            IconButton(
              tooltip: 'Voltar para Investimentos',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => _workspaces.leave(widget.workspace),
            ),
            // A stock's page is its analysis; the others keep the Ficha.
            SiteChip(
              label:
                  '${workspace.hasAnalysis ? 'Análise' : 'Ficha'} · '
                  '${workspace.ticker}',
              selected: workspace.activeSite == null,
              onTap: () => _workspaces.showFicha(workspace),
              icon: InstitutionLogo(
                institution: StockCompany.badgeOf(workspace.ticker),
                size: 20,
              ),
            ),
            if (workspace.hasCompare)
              SiteChip(
                label: 'Comparar',
                selected: workspace.activeSite == AssetWorkspace.comparePage,
                onTap: () =>
                    _workspaces.showSite(workspace, AssetWorkspace.comparePage),
                icon: const Icon(Icons.table_chart_outlined, size: 18),
              ),
            if (_workspaces.supported)
              Expanded(
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    for (final tab in workspace.tabs)
                      SiteChip(
                        label: tab.label,
                        icon: SiteIcon(tab.label),
                        selected: tab == active,
                        loading: tab.loading,
                        onTap: () => _workspaces.showSite(workspace, tab.id),
                      ),
                  ],
                ),
              )
            else
              const Spacer(),
            if (active != null) SitePageActions(tab: active),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  /// The app's own pages opened so far: they stay mounted, like the sites.
  final _opened = <String>{};

  @override
  Widget build(BuildContext context) {
    final workspace = widget.workspace;
    final onSite = workspace.active != null;
    final page = workspace.activeSite;
    if (page == AssetWorkspace.comparePage) _opened.add(page!);
    return Scaffold(
      body: Column(
        children: [
          _buildBar(),
          const Divider(height: 1),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Also follows a resized window.
                if (onSite) _placePage();
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Offstage(
                      offstage: page != null,
                      child: AssetSheetPage(
                        ticker: workspace.ticker,
                        embedded: true,
                      ),
                    ),
                    if (_opened.contains(AssetWorkspace.comparePage))
                      Offstage(
                        offstage: page != AssetWorkspace.comparePage,
                        child: workspace.kind == AssetKind.fii
                            ? FiiComparePage(ticker: workspace.ticker)
                            : ComparePage(ticker: workspace.ticker),
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
  }
}

/// An asset in standby, below Ajustes in the side rail. Right click also closes.
class StandbyRailItem extends StatefulWidget {
  const StandbyRailItem({
    super.key,
    required this.workspace,
    required this.selected,
    required this.onTap,
  });

  final AssetWorkspace workspace;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<StandbyRailItem> createState() => _StandbyRailItemState();
}

class _StandbyRailItemState extends State<StandbyRailItem> {
  bool _hover = false;

  void _close() => AssetWorkspaces.instance.close(widget.workspace);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final workspace = widget.workspace;
    final sites = workspace.tabs.length;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Tooltip(
        message:
            '${StockCompany.titleOf(workspace.ticker)} · '
            '$sites ${sites == 1 ? 'site' : 'sites'} em standby',
        waitDuration: const Duration(milliseconds: 500),
        child: InkWell(
          onTap: widget.onTap,
          onSecondaryTap: _close,
          // Centered like the rail's own items, with the same pill and label.
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 56,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: widget.selected
                            ? theme.colorScheme.secondaryContainer
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: InstitutionLogo(
                        institution: StockCompany.badgeOf(workspace.ticker),
                        size: 24,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      workspace.ticker,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: widget.selected
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (_hover)
                Positioned(
                  top: 0,
                  right: 0,
                  child: InkWell(
                    onTap: _close,
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(Icons.close, size: 14),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
