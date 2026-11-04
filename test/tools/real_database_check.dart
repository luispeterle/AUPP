// Opens a copy of the real data with the current code, as the app does when it
// starts, and writes what came out. Run by scripts/check-data.sh (the name has
// no _test on purpose: it is not part of the suite, and it never touches the
// real files). scripts/check-db.py then judges the result.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aupp/investments/asset-lots.dart';
import 'package:aupp/services/database/sqlite-database.dart';
import 'package:aupp/services/service-config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest_all.dart' as tz;

void main() {
  final copy = Platform.environment['AUPP_CHECK_DIR'];

  test('the current code opens the real data', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tz.initializeTimeZones();
    ServiceConfig.localTimezone = 'America/Sao_Paulo';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => copy,
        );
    final file = File('$copy/shared_preferences.json');
    final saved = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    SharedPreferences.setMockInitialValues({
      for (final e in saved.entries)
        if (e.key.startsWith('flutter.') &&
            e.key != 'flutter.databaseFolderPath')
          e.key.substring(8): e.value is List
              ? (e.value as List).cast<String>()
              : e.value as Object,
    });
    ServiceConfig.sharedPreferences = await SharedPreferences.getInstance();
    SqliteDatabase.setDatabaseForTesting(null);

    expect(await ServiceConfig.database.getCountRecords(), greaterThan(0));
    await AssetLots.checkLinks();

    final prefs = ServiceConfig.sharedPreferences!;
    await file.writeAsString(
      jsonEncode({
        ...saved,
        for (final key in prefs.getKeys()) 'flutter.$key': prefs.get(key),
      }),
    );
    await (await SqliteDatabase.instance.database)?.close();
  }, skip: copy == null ? 'Needs AUPP_CHECK_DIR' : false);
}
