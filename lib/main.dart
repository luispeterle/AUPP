import 'package:aupp/fiscal/fiscal-estimates.dart';
import 'package:aupp/demo/demo-mode.dart';
import 'package:aupp/desktop/desktop-layout.dart';
import 'package:aupp/desktop/asset-workspaces.dart';
import 'package:aupp/disguise/calculator-gate.dart';
import 'package:aupp/hybrid_sync/hybrid-sync.dart';
import 'package:aupp/services/automatic-writes.dart';
import 'package:aupp/services/category-hierarchy.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:aupp/categories/categories-tab-page-view.dart';
import 'package:private_extensions/private_extensions.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:aupp/services/home-widget-service.dart';
import 'package:aupp/services/locale-service.dart';
import 'package:aupp/services/logger.dart';
import 'package:aupp/services/database/sqlite-database.dart';
import 'package:aupp/services/service-config.dart';
import 'package:aupp/shell.dart';
import 'package:aupp/style.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quick_actions/quick_actions.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;


final logger = Logger.withContext("main");

Timer? _widgetRefreshDebounce;

/// Debounced home-widget refresh so rapid consecutive database writes
/// (e.g. a restore) coalesce into one update.
void _scheduleWidgetRefresh() {
  _widgetRefreshDebounce?.cancel();
  _widgetRefreshDebounce = Timer(
    const Duration(milliseconds: 600),
    () => HomeWidgetService.refreshAll(),
  );
}

/// Pending quick action that arrived before the navigator was ready.
String? _pendingQuickAction;

/// Handles a pending quick action by navigating to the appropriate screen.
/// Refreshes the home tab after the record is saved and the user returns.
void _handlePendingQuickAction() {
  final action = _pendingQuickAction;
  if (action == null) return;

  final navigator = AppCore.navigatorKey.currentState;
  if (navigator == null) return;

  _pendingQuickAction = null;

  final int tabIndex = (action == 'add_expense') ? 0 : 1;
  navigator
      .push(
        MaterialPageRoute(
          builder: (_) => CategoryTabPageView(
            goToEditMovementPage: true,
            initialTabIndex: tabIndex,
          ),
        ),
      )
      .then((_) {
        // After the record is saved and the user returns to Shell, refresh home tab
        ShellState.instance?.refreshHomeTab();
      });
}

main() async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();
  registerPrivateExtensions();

  logger.info('App initialization started');

  try {
    tz_data.initializeTimeZones();

    // Get the IANA timezone name (e.g. "Europe/Vienna").
    // DateTime.now().timeZoneName returns abbreviations like "CEST" on some
    // Linux distributions, which the timezone package cannot resolve.
    // FlutterTimezone.getLocalTimezone() returns the proper IANA name on
    // all supported platforms.
    try {
      final timezoneInfo = await FlutterTimezone.getLocalTimezone();
      ServiceConfig.localTimezone = timezoneInfo.identifier;
    } catch (_) {
      // Fallback for platforms where flutter_timezone does not work.
      // On Linux, try to read /etc/timezone which contains the IANA name.
      if (Platform.isLinux) {
        try {
          final tzFile = File('/etc/timezone');
          if (await tzFile.exists()) {
            final contents = await tzFile.readAsString();
            ServiceConfig.localTimezone = contents.trim();
          }
        } catch (_) {}
      }
    }
    logger.info('Timezone initialized: ${ServiceConfig.localTimezone}');

    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    ServiceConfig.packageName = packageInfo.packageName;
    ServiceConfig.version = packageInfo.version;

    // A demo start (code typed on the calculator) switches to its own
    // preferences, so this must come before the first getInstance().
    await DemoMode.bootstrap();
    ServiceConfig.sharedPreferences = await SharedPreferences.getInstance();

    logger.info(
      'Package: ${ServiceConfig.packageName} v${ServiceConfig.version}',
    );
    // Every database write refreshes the home widgets (debounced) and marks
    // the data to send to the other devices.
    SqliteDatabase.onDatabaseChanged = () {
      _scheduleWidgetRefresh();
      HybridSync.noteDatabaseWrite();
    };
    if (DemoMode.active) SqliteDatabase.onDatabaseChanged = null;
    // A brand-new database starts with the Dinzo categories.
    // The demo is rebuilt from scratch on every entry.
    if (DemoMode.active) {
      await DemoMode.prepare();
    } else {
      // Data arriving from the other device, also before anything reads
      // the database.
      await AutomaticWrites.run(HybridSync.startup);
    }
    if (!DemoMode.active) await AssetWorkspaces.instance.init();
    await CategoryHierarchy.init();
    // Estimates linked to the company's taxes get their amounts.
    await FiscalEstimates.init();

    // Display mode is only available on Android
    if (Platform.isAndroid) {
      await FlutterDisplayMode.setHighRefreshRate();
      logger.debug('High refresh rate enabled (Android)');
    }

    LocaleService.setCurrencyLocale();

    final lightTheme = await MaterialThemeInstance.getLightTheme();
    final darkTheme = await MaterialThemeInstance.getDarkTheme();
    final themeMode = await MaterialThemeInstance.getThemeMode();
    logger.info('Theme loaded: $themeMode');

    // With the disguise on, the launcher's long-press shortcuts ("Add
    // expense") would give the app away. Drop them.
    if (CalculatorGate.enabled) {
      const QuickActions().clearShortcutItems();
      CalculatorGate.install();
    }
    CalculatorGate.attach(() => AppCore.navigatorKey.currentState);
    // No disguise, or the code was typed right before this restart.
    if (!CalculatorGate.enabled || DemoMode.startUnlocked) {
      CalculatorGate.startUnlocked();
    }

    logger.info('App initialization completed successfully');

    runApp(
      TalkerWrapper(
        talker: globalTalker,
        child: MyApp(
          lightTheme: lightTheme,
          darkTheme: darkTheme,
          themeMode: themeMode,
        ),
      ),
    );

    // Handle any pending quick action that arrived before navigation was ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handlePendingQuickAction();
    });
  } catch (e, st) {
    logger.handle(e, st, 'Critical error during app initialization');
    rethrow;
  }
}

class MyApp extends StatefulWidget {
  final ThemeData lightTheme;
  final ThemeData darkTheme;
  final ThemeMode themeMode;

  MyApp({
    required this.lightTheme,
    required this.darkTheme,
    required this.themeMode,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static _MyAppState? _instance;

  late ThemeData _lightTheme;
  late ThemeData _darkTheme;
  late ThemeMode _themeMode;

  @override
  void initState() {
    super.initState();
    _instance = this;
    _lightTheme = widget.lightTheme;
    _darkTheme = widget.darkTheme;
    _themeMode = widget.themeMode;
  }

  @override
  void dispose() {
    if (_instance == this) _instance = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppCore(
      lightTheme: _lightTheme,
      darkTheme: _darkTheme,
      themeMode: _themeMode,
    );
  }
}

class AppCore extends StatelessWidget {
  /// Global navigator key used for quick actions navigation from outside the widget tree.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  // Declare languageLocale as a final instance variable
  final ThemeData lightTheme;
  final ThemeData darkTheme;
  final ThemeMode themeMode;

  // Constructor to initialize the instance variables
  AppCore({
    required this.lightTheme,
    required this.darkTheme,
    required this.themeMode,
  });

  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: AppCore.navigatorKey,
      locale: LocaleService.locale,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [LocaleService.locale],
      debugShowCheckedModeBanner: false,
      scrollBehavior: const AppScrollBehavior(),
      onNavigationNotification: _defaultOnNavigationNotification,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      title: "AUPP",
      // The disguise calculator sits above the real app from the
      // first frame (lib/disguise/calculator-gate.dart). Flutter forbids
      // `home` together with onGenerateInitialRoutes (asserted in debug only).
      routes: {'/': (_) => Shell()},
      onGenerateInitialRoutes: (_) => [
        MaterialPageRoute(
          builder: (_) => Shell(),
          settings: const RouteSettings(name: '/'),
        ),
        if (CalculatorGate.enabled && !DemoMode.startUnlocked)
          CalculatorGate.route(),
      ],
    );
  }
}

bool _defaultOnNavigationNotification(NavigationNotification _) {
  // https://github.com/flutter/flutter/issues/153672#issuecomment-2583262294
  switch (WidgetsBinding.instance.lifecycleState) {
    case null:
    case AppLifecycleState.detached:
    case AppLifecycleState.inactive:
      // Avoid updating the engine when the app isn't ready.
      return true;
    case AppLifecycleState.resumed:
    case AppLifecycleState.hidden:
    case AppLifecycleState.paused:
      SystemNavigator.setFrameworkHandlesBack(true);

      /// This must be `true` instead of `notification.canHandlePop`, otherwise application closes on back gesture.
      return true;
  }
}
