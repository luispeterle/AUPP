import 'package:flutter/widgets.dart';
import 'package:aupp/demo/demo-mode.dart';
import 'package:aupp/dinzo/dinzo-auto-sync.dart';
import 'package:aupp/services/preferences-backup-service.dart';
import 'package:aupp/services/database/sqlite-database.dart';

/// A source of records that lives outside this repository and syncs next to
/// the Dinzo: it runs on app open/resume and on pull to refresh, shows up in
/// the Extrato's sync pill and has a section in Configurações → Integrações com API.
/// Registered by `registerPrivateExtensions`; none in the public build.
abstract class SyncExtension {
  /// Full name, for the sync notification.
  String get name;

  /// Short name, for the sync pill.
  String get shortName;

  /// Same states as the Dinzo automatic sync; null = nothing to show.
  ValueNotifier<DinzoAutoSyncStatus?> get status;

  bool get configured;

  /// Throws on failure only when [force] (the user asked for it).
  Future<void> run({bool force = false});

  Future<void> whenIdle();

  void clearStatus();

  /// Preferences that go in the backup, with their validators.
  Map<String, bool Function(Object)> get portablePrefs => const {};

  /// Device-only preferences that point at data being wiped.
  List<String> get staleKeysOnWipe => const [];

  Widget settingsSection();

  /// Pages opened from the calculator disguise by typing the code and "C".
  Map<String, WidgetBuilder> get calculatorCodes => const {};
}

class SyncExtensions {
  static final List<SyncExtension> all = [];

  static void add(SyncExtension extension) {
    all.add(extension);
    extension.portablePrefs.forEach(PreferencesBackupService.registerPortable);
  }

  static bool isPortablePref(String key) =>
      all.any((e) => e.portablePrefs.containsKey(key));

  static bool get anyConfigured => all.any((e) => e.configured);

  /// The page an extension opens for [code] typed in the calculator. None in
  /// the demo, which has no real data.
  static WidgetBuilder? calculatorPage(String code) {
    if (DemoMode.active) return null;
    for (final e in all) {
      final page = e.calculatorCodes[code];
      if (page != null) return page;
    }
    return null;
  }

  static List<String> get staleKeysOnWipe => [
    for (final e in all) ...e.staleKeysOnWipe,
  ];

  /// Nothing runs on a read-only database (data from a newer app).
  static void runAll() {
    if (SqliteDatabase.readOnly) return;
    for (final e in all) {
      e.run();
    }
  }

  static Future<void> runAllForced() async {
    if (SqliteDatabase.readOnly) return;
    await Future.wait([for (final e in all) e.run(force: true)]);
  }

  static Future<void> whenIdle() =>
      Future.wait([for (final e in all) e.whenIdle()]);
}
