import 'package:aupp/calculators/calculators-page.dart';
import 'package:aupp/dashboard/dashboard-page.dart';
import 'package:aupp/demo/demo-mode.dart';
import 'package:aupp/desktop/desktop-layout.dart';
import 'package:aupp/desktop/asset-workspace-view.dart';
import 'package:aupp/desktop/asset-workspaces.dart';
import 'package:aupp/investments/asset-sheet-page.dart';
import 'package:aupp/dinzo/dinzo-auto-sync.dart';
import 'package:aupp/dinzo/welcome-page.dart';
import 'package:aupp/dinzo/dinzo-sync-service.dart';
import 'package:aupp/hybrid_sync/hybrid-sync-page.dart';
import 'package:aupp/hybrid_sync/hybrid-sync.dart';
import 'package:aupp/investments/investments-cache.dart';
import 'package:aupp/services/sync-notifications.dart';
import 'package:aupp/services/sync-extensions.dart';
import 'package:aupp/investments/investments-page.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:aupp/desktop/calculators-area.dart';
import 'package:flutter/services.dart';
import 'package:aupp/disguise/calculator-gate.dart';
import 'package:aupp/records/records-page.dart';
import 'package:aupp/services/service-config.dart';
import 'package:aupp/settings/settings-page.dart';
import 'package:aupp/style.dart';
import 'package:aupp/categories/categories-tab-page-view.dart';
import 'package:aupp/services/crypto-quote-service.dart';

class Shell extends StatefulWidget {
  @override
  ShellState createState() => ShellState();
}

class ShellState extends State<Shell> {
  static const MethodChannel _widgetActionChannel =
      MethodChannel('aupp/widget_action');

  /// Singleton-like access for external refresh calls (e.g., quick actions).
  static ShellState? _instance;

  /// Returns the current ShellState instance, if mounted.
  static ShellState? get instance => _instance;

  int _currentIndex = 0;
  late final Future<void> _unlocked;

  /// Ensures the startup announcement dialog is checked only once per app run,
  /// after authentication has succeeded and the main UI is on screen.

  /// Fork: quick Dinzo sync after unlocking and on every return to the app
  /// (rate limited in [DinzoAutoSync]).
  bool _dinzoAutoSyncStarted = false;
  AppLifecycleListener? _lifecycleListener;
  String? _hybridConflictShown;

  final GlobalKey<TabRecordsState> _tabRecordsKey = GlobalKey();
  final GlobalKey<DashboardPageState> _dashboardKey = GlobalKey();
  final GlobalKey<InvestmentsPageState> _investmentsKey = GlobalKey();

  final GlobalKey<NavigatorState> _homeNavigatorKey =
      GlobalKey<NavigatorState>();
  final GlobalKey<NavigatorState> _categoriesNavigatorKey =
      GlobalKey<NavigatorState>();
  final GlobalKey<NavigatorState> _recordsNavigatorKey =
      GlobalKey<NavigatorState>();
  final GlobalKey<NavigatorState> _settingsNavigatorKey =
      GlobalKey<NavigatorState>();
  final GlobalKey<NavigatorState> _calculatorsNavigatorKey =
      GlobalKey<NavigatorState>();

  /// Fork: logical tabs that exist only in the computer's side rail.
  static const int _assetsTab = 6;
  bool _railLayout = false;

  @override
  void initState() {
    super.initState();
    _instance = this;
    // Fork: nothing of the real app (syncs) starts while the disguise
    // calculator is showing.
    _unlocked = CalculatorGate.firstUnlock;
    _lifecycleListener = AppLifecycleListener(
      onResume: () => CalculatorGate.whenUnlocked(() {
        if (_dinzoAutoSyncStarted && !DemoMode.active) {
          HybridSync.check();
          DinzoAutoSync.run();
          SyncExtensions.runAll();
          InvestmentsCache.resumePending();
        }
        CryptoQuoteService.refresh();
      }),
      onHide: HybridSync.flush,
    );
    HybridSync.conflict.addListener(_showHybridConflict);
    HybridSync.incoming.addListener(_showHybridIncoming);
    HybridSync.readOnly.addListener(_readOnlyChanged);
    HybridSync.dataArrived.addListener(_onHybridDataArrived);
    AssetSheetPage.openInTab = _openAssetTab;
    AssetWorkspaces.instance.addListener(_workspacesChanged);
    // A site opened from the Ficha, or an asset coming back from standby.
    AssetWorkspaces.instance.addListener(_onWorkspacesChanged);
  }

  void _onWorkspacesChanged() {
    if (mounted) setState(() {});
  }

  /// Fork: the Ficha has its own place in the rail on the computer. False on
  /// the phone, where the caller opens it on top of the page.
  bool _openAssetTab(String ticker) {
    if (!_railLayout) return false;
    setState(() => _currentIndex = _assetsTab);
    AssetWorkspaces.instance.openAsset(ticker);
    return true;
  }

  /// Fork: another device's data was joined in while the app runs.
  void _onHybridDataArrived() {
    _dashboardKey.currentState?.onTabChange();
    _tabRecordsKey.currentState?.onTabChange();
  }

  void _readOnlyChanged() {
    if (mounted) setState(() {});
  }

  /// Fork: data from a newer app on another device: this one only reads until
  /// updated, and says so above every page.
  PreferredSizeWidget? _readOnlyBar(BuildContext context) {
    final remote = HybridSync.readOnly.value;
    if (remote == null) return null;
    final scheme = Theme.of(context).colorScheme;
    final newer = remote.appVersion == null
        ? 'um app mais novo'
        : 'o app ${remote.appVersion}';
    return PreferredSize(
      preferredSize: Size.fromHeight(64 + MediaQuery.paddingOf(context).top),
      child: Material(
        color: scheme.errorContainer,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.lock_outline, color: scheme.onErrorContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Somente leitura: os dados vêm de $newer '
                    '(${HybridSync.describe(remote)}). Atualize este app '
                    '(${ServiceConfig.version}) para voltar a editar.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: scheme.onErrorContainer),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Fork: changes on both devices; asked once per conflict seen.
  void _showHybridConflict() {
    final remote = HybridSync.conflict.value;
    if (remote == null || remote.rev == _hybridConflictShown) return;
    _hybridConflictShown = remote.rev;
    CalculatorGate.whenUnlocked(() {
      if (mounted) showHybridConflictDialog(context, remote);
    });
  }

  /// Fork: newer data from another device; asked once per snapshot seen.
  void _showHybridIncoming() {
    final remote = HybridSync.incoming.value;
    if (remote == null || remote.rev == _hybridConflictShown) return;
    _hybridConflictShown = remote.rev;
    CalculatorGate.whenUnlocked(() {
      if (mounted) {
        showHybridConflictDialog(context, remote, bothChanged: false);
      }
    });
  }

  @override
  void dispose() {
    HybridSync.conflict.removeListener(_showHybridConflict);
    HybridSync.incoming.removeListener(_showHybridIncoming);
    HybridSync.readOnly.removeListener(_readOnlyChanged);
    HybridSync.dataArrived.removeListener(_onHybridDataArrived);
    AssetWorkspaces.instance.removeListener(_onWorkspacesChanged);
    AssetSheetPage.openInTab = null;
    AssetWorkspaces.instance.removeListener(_workspacesChanged);
    _lifecycleListener?.dispose();
    if (_instance == this) _instance = null;
    super.dispose();
  }

  /// Handles home screen widget quick-add taps (add expense/income). The
  /// action arrives either pushed while running or stashed for cold starts;
  /// both run only after authentication, like the announcement dialog.
  void _handleWidgetQuickAction() {
    _widgetActionChannel.setMethodCallHandler((call) async {
      if (call.method == 'openAddFlow') {
        final action = call.arguments as String?;
        CalculatorGate.whenUnlocked(() {
          if (mounted) _openAddFlow(action);
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      String? action;
      try {
        action =
            await _widgetActionChannel.invokeMethod<String>('getInitialAction');
      } catch (_) {
        return;
      }
      if (action != null && mounted) _openAddFlow(action);
    });
  }

  /// Opens the add-record flow on the expense (0) or income (1) tab.
  void _openAddFlow(String? action) {
    final tabIndex = action == 'add_income' ? 1 : 0;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CategoryTabPageView(
          goToEditMovementPage: true,
          initialTabIndex: tabIndex,
        ),
      ),
    );
  }

  /// Refreshes the home tab's records list (e.g., after a quick action added a record).
  void refreshHomeTab() {
    _tabRecordsKey.currentState?.onTabChange();
  }

  /// Returns the fixed logical indexes currently represented in the
  /// NavigationBar, preserving the indexes used by the tab navigators.
  List<int> _visibleLogicalIndexes({
    required bool walletsEnabled,
  }) {
    // Fork: 0 = Início (dashboard), 3 = Extrato (records list, formerly
    // the upstream Budgets' slot), 2 = Investimentos. The wallets (1) open
    // from the Início instead of the bar. 5 = Calculadoras. On the computer
    // the rail also has 6 = Ativos and the tools, below its separator.
    return [0, 3, 2, 5, 4];
  }

  /// Maps a logical tab index to the visual NavigationBar index.
  int _visualIndex(
    int logicalIndex,
    bool walletsEnabled,
  ) {
    final index = _visibleLogicalIndexes(
      walletsEnabled: walletsEnabled,
    ).indexOf(logicalIndex);
    return index < 0 ? 0 : index;
  }

  /// Maps a visual NavigationBar index to the logical tab index.
  int _logicalIndex(
    int visualIndex,
    bool walletsEnabled,
  ) {
    final indexes = _visibleLogicalIndexes(
      walletsEnabled: walletsEnabled,
    );
    final safeVisualIndex =
        visualIndex.clamp(0, indexes.length - 1).toInt();
    return indexes[safeVisualIndex];
  }

  List<Widget> _buildDestinations(
    bool walletsEnabled) {
    Widget navigationIcon({
      required int logicalIndex,
      required String semanticsIdentifier,
      required IconData iconData,
      required IconData selectedIconData,
      required _NavigationIconMotion motion,
    }) {
      final isSelected = _currentIndex == logicalIndex;
      return Semantics(
        identifier: isSelected
            ? '$semanticsIdentifier-selected'
            : semanticsIdentifier,
        child: _AnimatedNavigationIcon(
          key: ValueKey<String>(semanticsIdentifier),
          isSelected: isSelected,
          icon: iconData,
          selectedIcon: selectedIconData,
          motion: motion,
        ),
      );
    }

    final destinations = <Widget>[
      NavigationDestination(
        label: 'Início',
        icon: navigationIcon(
          logicalIndex: 0,
          semanticsIdentifier: 'home-tab',
          iconData: Icons.home_outlined,
          selectedIconData: Icons.home,
          motion: _NavigationIconMotion.bounce,
        ),
      ),
      NavigationDestination(
        label: 'Extrato',
        icon: navigationIcon(
          logicalIndex: 3,
          semanticsIdentifier: 'records-tab',
          iconData: Icons.receipt_long_outlined,
          selectedIconData: Icons.receipt_long,
          motion: _NavigationIconMotion.bounce,
        ),
      ),
    ];
    destinations.addAll([
      // Fork: Categories moved to Settings; this slot is Investments.
      NavigationDestination(
        label: 'Investimentos',
        icon: navigationIcon(
          logicalIndex: 2,
          semanticsIdentifier: 'investments-tab',
          iconData: Icons.trending_up_outlined,
          selectedIconData: Icons.trending_up,
          motion: _NavigationIconMotion.bounce,
        ),
      ),
      NavigationDestination(
        label: 'Calculadoras',
        icon: navigationIcon(
          logicalIndex: 5,
          semanticsIdentifier: 'calculators-tab',
          iconData: Icons.calculate_outlined,
          selectedIconData: Icons.calculate,
          motion: _NavigationIconMotion.bounce,
        ),
      ),
      NavigationDestination(
        label: 'Ajustes',
        icon: navigationIcon(
          logicalIndex: 4,
          semanticsIdentifier: 'settings-tab',
          iconData: Icons.settings_outlined,
          selectedIconData: Icons.settings,
          motion: _NavigationIconMotion.rotate,
        ),
      ),
    ]);
    return destinations;
  }

  @override
  Widget build(BuildContext context) {
    print("Shell build called");
    return FutureBuilder<void>(
      future: _unlocked,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(body: Center(child: CircularProgressIndicator()));
        } else {
          _handleWidgetQuickAction();
          if (!_dinzoAutoSyncStarted && DemoMode.active) {
            // Demo: made-up data, no syncs (public crypto quotes only).
            _dinzoAutoSyncStarted = true;
            CryptoQuoteService.refresh();
          } else if (!_dinzoAutoSyncStarted) {
            _dinzoAutoSyncStarted = true;
            SyncNotifications.attach();
            HybridSync.check();
            CryptoQuoteService.refresh();
            SyncExtensions.runAll();
            InvestmentsCache.resumePending();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              // The Dinzo is optional: without a key there is nothing to
              // sync (connecting it in Configurações → Integrações com API starts the
              // first sync there).
              if (DinzoSyncService.apiKey != null) DinzoAutoSync.run();
              WelcomePage.showOnFirstOpening(context);
            });
          }
          return _buildMainUI(context);
        }
      },
    );
  }

  /// Fork: on the computer the tab content has a limited width, so rows don't
  /// stretch across the whole window.
  Widget _tabContent(bool wide, double maxWidth, Widget navigator) => wide
      ? Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: navigator,
          ),
        )
      : navigator;

  /// The navigator of the tab on screen.
  NavigatorState? get _currentNavigator => switch (_currentIndex) {
    0 => _homeNavigatorKey.currentState,
    2 => _categoriesNavigatorKey.currentState,
    3 => _recordsNavigatorKey.currentState,
    4 => _settingsNavigatorKey.currentState,
    5 => _calculatorsNavigatorKey.currentState,
    _ => null,
  };

  void _goToExtrato() {
    if (_currentIndex == 3) return;
    setState(() => _currentIndex = 3);
    _tabRecordsKey.currentState?.onTabChange();
  }

  /// Fork: keyboard on the computer. Ctrl+N new record, Ctrl+F search in the
  /// Extrato, F5 sync, Esc back.
  Map<ShortcutActivator, VoidCallback> get _shortcuts => {
    const SingleActivator(LogicalKeyboardKey.keyN, control: true): () {
      _goToExtrato();
      _tabRecordsKey.currentState?.addRecordFromShortcut();
    },
    const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
      _goToExtrato();
      _tabRecordsKey.currentState?.searchFromShortcut();
    },
    const SingleActivator(LogicalKeyboardKey.f5): () {
      _goToExtrato();
      _tabRecordsKey.currentState?.refreshFromShortcut();
    },
    const SingleActivator(LogicalKeyboardKey.escape): () {
      _currentNavigator?.maybePop();
    },
  };

  Widget _buildRail() {
    final walletsEnabled = ServiceConfig.walletsEnabledNotifier.value;
    return NavigationRail(
      labelType: NavigationRailLabelType.all,
      // What is below the separator is highlighted in its own item.
      selectedIndex: _currentIndex >= _assetsTab
          ? null
          : _visualIndex(_currentIndex, walletsEnabled),
      onDestinationSelected: (visualIndex) =>
          _onDestinationSelected(visualIndex, walletsEnabled),
      // Fork: the assets in standby, below Ajustes.
      trailing: Expanded(
        child: ListenableBuilder(
          listenable: AssetWorkspaces.instance,
          builder: (context, _) {
            final workspaces = AssetWorkspaces.instance;
            return SizedBox(
              width: 88,
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  if (workspaces.inStandby.isNotEmpty)
                    const Divider(height: 16, indent: 12, endIndent: 12),
                  for (final workspace in workspaces.inStandby)
                    StandbyRailItem(
                      key: ValueKey(workspace.ticker),
                      workspace: workspace,
                      selected:
                          _currentIndex == _assetsTab &&
                          workspaces.current == workspace,
                      onTap: () => _openAssetTab(workspace.ticker),
                    ),
                ],
              ),
            );
          },
        ),
      ),
      destinations: [
        for (final destination
            in _buildDestinations(walletsEnabled)
                .cast<NavigationDestination>())
          NavigationRailDestination(
            icon: destination.icon,
            label: Text(destination.label),
          ),
      ],
    );
  }

  /// Leaving an asset goes back to Investimentos, where the search is.
  void _workspacesChanged() {
    if (_currentIndex == _assetsTab &&
        AssetWorkspaces.instance.current == null) {
      setState(() => _currentIndex = 2);
    }
  }

  Future<void> _onDestinationSelected(
    int visualIndex,
    bool walletsEnabled,
  ) async {
    setState(() {
      _currentIndex = _logicalIndex(visualIndex, walletsEnabled);
    });
    // refresh data whenever changing the tab
    if (_currentIndex == 0) {
      await _dashboardKey.currentState?.onTabChange();
    }
    if (_currentIndex == 2) {
      await _investmentsKey.currentState?.refreshInBackground();
    }
    if (_currentIndex == 3) {
      await _tabRecordsKey.currentState?.onTabChange();
    }
  }

  Widget _buildMainUI(BuildContext context) {
    ThemeData themeData = Theme.of(context);
    MaterialThemeInstance.currentTheme = themeData;
    final wide = isWideLayout(context);
    _railLayout = wide;
    // Fork: narrowed the window on a tab the phone layout does not have.
    if (!wide && _currentIndex >= _assetsTab) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _currentIndex = 0);
      });
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) {
          return;
        }

        // Get the current tab's navigator
        final currentNavigator = _currentNavigator;

        // Check if the current tab's navigator can pop.
        // Use maybePop so inner PopScopes (e.g., in-app keyboard) can intercept first.
        if (currentNavigator != null && currentNavigator.canPop()) {
          await currentNavigator.maybePop();
          return;
        }

        // At the root of the current tab's navigator.
        // Use maybePop to respect inner PopScopes (e.g., select mode in records).
        if (currentNavigator != null) {
          final bool handled = await currentNavigator.maybePop();
          if (handled) return;
        }

        if (_currentIndex != 0) {
          // If we're at the root of a non-Home tab, navigate to Home
          setState(() {
            _currentIndex = 0;
          });
        } else {
          // We're at the root of Home tab - exit the app
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        appBar: _readOnlyBar(context),
        body: SafeArea(
          // In landscape the system navigation bar (3-button mode) sits on the
          // side of the screen. Pad horizontally so body content never extends
          // behind it. The top inset is handled by each page's app bar and the
          // bottom inset by the NavigationBar below.
          top: false,
          bottom: false,
          child: CallbackShortcuts(
            bindings: wide ? _shortcuts : const {},
            child: Focus(
              autofocus: true,
              child: Row(
                children: [
                  if (wide) ...[
                    _buildRail(),
                    const VerticalDivider(width: 1, thickness: 1),
                  ],
                  Expanded(
                    child: Stack(
                      children: <Widget>[
                        Offstage(
                          offstage: _currentIndex != 0,
                          child: TickerMode(
                            enabled: _currentIndex == 0,
                            child: _tabContent(
                              wide,
                              1320,
                              Navigator(
                                key: _homeNavigatorKey,
                                onGenerateRoute: (settings) {
                                  return MaterialPageRoute(
                                    builder: (_) =>
                                        DashboardPage(key: _dashboardKey),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                        Offstage(
                          offstage: _currentIndex != 2,
                          child: TickerMode(
                            enabled: _currentIndex == 2,
                            child: _tabContent(
                              wide,
                              1320,
                              Navigator(
                                key: _categoriesNavigatorKey,
                                onGenerateRoute: (settings) {
                                  return MaterialPageRoute(
                                    builder: (_) =>
                                        InvestmentsPage(key: _investmentsKey),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                        Offstage(
                          offstage: _currentIndex != 3,
                          child: TickerMode(
                            enabled: _currentIndex == 3,
                            child: _tabContent(
                              wide,
                              1320,
                              Navigator(
                                key: _recordsNavigatorKey,
                                onGenerateRoute: (settings) {
                                  return MaterialPageRoute(
                                    builder: (_) =>
                                        TabRecords(key: _tabRecordsKey),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                        if (wide)
                          Offstage(
                            offstage: _currentIndex != _assetsTab,
                            child: TickerMode(
                              enabled: _currentIndex == _assetsTab,
                              child: AssetsArea(
                                visible: _currentIndex == _assetsTab,
                              ),
                            ),
                          ),
                        Offstage(
                          offstage: _currentIndex != 4,
                          child: TickerMode(
                            enabled: _currentIndex == 4,
                            child: _tabContent(
                              wide,
                              760,
                              Navigator(
                                key: _settingsNavigatorKey,
                                onGenerateRoute: (settings) {
                                  return MaterialPageRoute(
                                    builder: (_) => TabSettings(),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                        Offstage(
                          offstage: _currentIndex != 5,
                          child: TickerMode(
                            enabled: _currentIndex == 5,
                            child: wide && AssetWorkspaces.instance.supported
                                ? CalculatorsArea(visible: _currentIndex == 5)
                                : _tabContent(
                              wide,
                              900,
                              Navigator(
                                key: _calculatorsNavigatorKey,
                                onGenerateRoute: (settings) {
                                  return MaterialPageRoute(
                                    builder: (_) => const CalculatorsPage(),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: wide ? null : ValueListenableBuilder<bool>(
          valueListenable: ServiceConfig.walletsEnabledNotifier,
          builder: (context, walletsEnabled, _) {
            // Defensively reset to the Home tab if the currently selected
            // tab no longer exists after a feature is disabled.
            if (!walletsEnabled && _currentIndex == 1) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _currentIndex = 0);
              });
            }
            return NavigationBar(
                animationDuration: const Duration(milliseconds: 220),
                selectedIndex: _visualIndex(
                    _currentIndex, walletsEnabled),
                labelBehavior:
                    NavigationDestinationLabelBehavior.alwaysShow,
                // One point smaller than labelSmall (11sp) for extra
                // margin so longer localized labels don't wrap.
                labelTextStyle: WidgetStatePropertyAll<TextStyle?>(
                  Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                  ),
                ),
                onDestinationSelected: (int visualIndex) =>
                    _onDestinationSelected(visualIndex, walletsEnabled),
                destinations: _buildDestinations(walletsEnabled),
            );
          },
        ),
      ),
    );
  }
}

/// Defines the selection motion for a navigation icon.
enum _NavigationIconMotion { bounce, rotate, mirror, rotateAndStay }

/// Animates an outlined-to-filled icon with a per-destination transition.
class _AnimatedNavigationIcon extends StatefulWidget {
  const _AnimatedNavigationIcon({
    super.key,
    required this.isSelected,
    required this.icon,
    required this.selectedIcon,
    required this.motion,
  });

  final bool isSelected;
  final IconData icon;
  final IconData selectedIcon;
  final _NavigationIconMotion motion;

  @override
  State<_AnimatedNavigationIcon> createState() =>
      _AnimatedNavigationIconState();
}

class _AnimatedNavigationIconState extends State<_AnimatedNavigationIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 240),
      reverseDuration: const Duration(milliseconds: 170),
      value: widget.isSelected ? 1.0 : 0.0,
      vsync: this,
    );
  }

  @override
  void didUpdateWidget(covariant _AnimatedNavigationIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isSelected == widget.isSelected) return;

    if (widget.isSelected) {
      _controller.forward(from: 0.0);
    } else {
      _controller.reverse(from: 1.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _rotationTurns(double progress) {
    switch (widget.motion) {
      case _NavigationIconMotion.bounce:
        return 0.0;
      case _NavigationIconMotion.rotate:
        // Settings/Home rotate briefly and settle back to their original angle.
        return 0.09 * math.sin(progress * math.pi);
      case _NavigationIconMotion.mirror:
        return 0.0;
      case _NavigationIconMotion.rotateAndStay:
        // Categories remain at a quarter turn while selected.
        return 0.25 * progress;
    }
  }

  double _horizontalScale(double progress) {
    if (widget.motion == _NavigationIconMotion.mirror) {
      // A scaleX transition through zero creates a left-to-right mirror flip.
      return 1.0 - (2.0 * progress);
    }
    return 1.0;
  }

  @override
  Widget build(BuildContext context) {

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final progress = _controller.value;
        final selectionOpacity = Curves.easeIn.transform(progress);
        final selectedScale =
            0.88 + 0.12 * Curves.easeOutBack.transform(progress);
        final rotation = _rotationTurns(progress) * 2 * math.pi;
        final horizontalScale = _horizontalScale(progress);
        final keepsRotation =
            widget.motion == _NavigationIconMotion.rotateAndStay;
        final unselectedRotation = keepsRotation ? rotation : -rotation;

        return Stack(
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: 1.0 - selectionOpacity,
              child: Transform.rotate(
                angle: unselectedRotation,
                child: Transform.scale(
                  scaleX: horizontalScale,
                  scaleY: 1.0 - 0.06 * progress,
                  child: Icon(widget.icon),
                ),
              ),
            ),
            Opacity(
              opacity: selectionOpacity,
              child: Transform.rotate(
                angle: rotation,
                child: Transform.scale(
                  scaleX: horizontalScale,
                  scaleY: selectedScale,
                  child: Icon(widget.selectedIcon),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
