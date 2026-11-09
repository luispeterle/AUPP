import 'dart:io';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:aupp/settings/constants/preferences-keys.dart';
import 'package:aupp/services/service-config.dart';
import 'package:flutter/services.dart';
import 'package:aupp/demo/demo-mode.dart';
import 'package:aupp/disguise/calculator-page.dart';
import 'package:aupp/services/sync-extensions.dart';

/// Fork (2026-10-14): the app opens as a yellow calculator. Typing the code
/// and "C" reveals the real app; anything else is just a calculation. After
/// [relockAfter] in the background, or as soon as the phone is locked, the
/// calculator covers everything again. While unlocked, a notification says
/// so and until when (native: UnlockedNotification).
/// [DemoMode.code] and "C" opens the demo instead (fake data, restarts the
/// app to switch between the two).
class CalculatorGate {
  static const code = '555';

  /// Optional (Configurações → Disfarce e demonstração), off by default.
  /// Phone only: the preference travels in backups, and the computer has
  /// no recents screen or launcher shortcuts to hide from.
  static bool get enabled =>
      Platform.isAndroid &&
      (ServiceConfig.sharedPreferences?.getBool(
            PreferencesKeys.disguiseEnabled,
          ) ??
          false);

  static bool isCode(String typed) =>
      typed == code ||
      typed == DemoMode.code ||
      SyncExtensions.calculatorPage(typed) != null;
  static const relockAfter = Duration(minutes: 10);

  static const _appChannel = MethodChannel('aupp/app');

  /// The screen went off, or "Bloquear agora" on the notification.
  static const _lockChannel = MethodChannel('aupp/lock');

  static final _firstUnlock = Completer<void>();
  static bool _locked = true;
  static Route<void>? _route;
  static DateTime? _hiddenAt;
  static final List<VoidCallback> _pending = [];
  // ignore: unused_field
  static AppLifecycleListener? _listener;

  /// Completes the first time the code is typed; nothing of the real app
  /// (auth, syncs, notifications) starts before that.
  static Future<void> get firstUnlock => _firstUnlock.future;

  static void install() {
    _listener = AppLifecycleListener(
      onHide: () {
        _hiddenAt = DateTime.now();
        if (!_locked) _notifyUnlocked(_hiddenAt!.add(relockAfter));
      },
      onShow: () {
        _maybeRelock();
        if (!_locked) _notifyUnlocked(null);
      },
    );
    _lockChannel.setMethodCallHandler((call) async {
      if (call.method == 'lock') _lock();
    });
  }

  /// The disguise was turned on or off in Configurações: the notification
  /// shows only while it is on.
  static void settingChanged() {
    if (enabled && !_locked) {
      _notifyUnlocked(null);
    } else if (!enabled) {
      _appChannel.invokeMethod('locked').catchError((_) {});
    }
  }

  /// [until] null: unlocked while the app shows.
  static void _notifyUnlocked(DateTime? until) {
    if (!enabled) return;
    _appChannel.invokeMethod('unlocked', {
      'until': until?.millisecondsSinceEpoch,
    }).catchError((_) {});
  }

  /// The calculator route, placed above the real app from the first frame
  /// (MaterialApp.onGenerateInitialRoutes) and pushed again on relock.
  static Route<void> route() => _route = PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) => PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            // Back leaves the app like a plain calculator would.
            if (!didPop) _appChannel.invokeMethod('moveToBack');
          },
          child: ScaffoldMessenger(child: CalculatorPage(onCode: _onCode)),
        ),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      );

  /// The demo is built fresh on every entry, and the real app never runs in
  /// the same process as the demo: switching modes (or re-entering the demo)
  /// restarts the app.
  static void _onCode(BuildContext context, String typed) {
    // An extension's page opens over the calculator, which stays locked.
    final page = SyncExtensions.calculatorPage(typed);
    if (page != null) {
      Navigator.of(context).push(MaterialPageRoute(builder: page));
      return;
    }
    final wantsDemo = typed == DemoMode.code;
    if (wantsDemo) {
      DemoMode.enterAndRestart();
    } else if (DemoMode.active) {
      DemoMode.leaveAndRestart();
    } else {
      _unlock(context);
    }
  }

  /// Demo start: the code was typed before the restart, so the calculator
  /// does not show again.
  static void startUnlocked() {
    _locked = false;
    if (!_firstUnlock.isCompleted) _firstUnlock.complete();
  }

  static void _unlock(BuildContext context) {
    final route = _route;
    _locked = false;
    _route = null;
    if (route != null && route.isActive) {
      Navigator.of(context).removeRoute(route);
    }
    if (!_firstUnlock.isCompleted) _firstUnlock.complete();
    _notifyUnlocked(null);
    final pending = List.of(_pending);
    _pending.clear();
    for (final fn in pending) {
      fn();
    }
  }

  static void _maybeRelock() {
    final hiddenAt = _hiddenAt;
    _hiddenAt = null;
    if (_locked || hiddenAt == null) return;
    if (DateTime.now().difference(hiddenAt) < relockAfter) return;
    _lock();
  }

  static void _lock() {
    if (_locked || !enabled) return;
    final navigator = _navigator?.call();
    if (navigator == null) return;
    _locked = true;
    navigator.push(route());
    _appChannel.invokeMethod('locked').catchError((_) {});
  }

  static NavigatorState? Function()? _navigator;

  /// Where the calculator is pushed on relock (the root navigator).
  static void attach(NavigatorState? Function() navigator) =>
      _navigator = navigator;

  /// Runs [fn] now if the real app is showing, otherwise right after the
  /// code is typed (resume handlers: no sync behind the calculator).
  static void whenUnlocked(VoidCallback fn) {
    _maybeRelock();
    if (_locked) {
      _pending.add(fn);
    } else {
      fn();
    }
  }
}
