import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aupp/models/backup.dart';
import 'package:aupp/models/recurrent-period.dart';
import 'package:aupp/models/recurrent-record-pattern.dart';
import 'package:aupp/models/wallet.dart';
import 'package:aupp/services/backup-service.dart';
import 'package:aupp/services/service-config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest_all.dart' as tz;

import '../helpers/test_database.dart';

/// Wallet ids change on restore when the device already has wallets. The
/// records were remapped but a recurring transfer kept the backup's
/// destination id, so "Investir" started feeding whatever wallet took that
/// id on the device (seen for real).
void main() {
  late Directory dir;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tz.initializeTimeZones();
    ServiceConfig.localTimezone = 'UTC';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/package_info'),
          (call) async => {
            'appName': 'AUPP',
            'packageName': 'x',
            'version': '1.15.14',
            'buildNumber': '1',
          },
        );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ServiceConfig.sharedPreferences = await SharedPreferences.getInstance();
    await TestDatabaseHelper.setupTestDatabase();
    BackupService.database = ServiceConfig.database;
    dir = await Directory.systemTemp.createTemp('restore_transfer');
  });

  tearDown(() => dir.delete(recursive: true));

  test('a restored recurring transfer still points at its wallet', () async {
    final db = ServiceConfig.database;
    // On the device: the default wallet and "Vale alimentação" (id 2).
    final vale = await db.addWallet(Wallet('Vale alimentação'));
    expect(vale, 2);

    // In the backup: "Investir" is id 2, and the recurrence sends money to it.
    final backup = Backup(
      'AUPP',
      '1.15.14',
      '35',
      [],
      [],
      [
        RecurrentRecordPattern(
          -2000,
          'Investir',
          null,
          DateTime.utc(2026, 10, 1, 3),
          RecurrentPeriod.EveryMonth,
          id: 'p-investir',
          walletId: 1,
          transferWalletId: 2,
        ),
      ],
      [],
      wallets: [
        Wallet('Conta corrente', id: 1, isDefault: true),
        Wallet('Investir', id: 2),
      ],
    );
    final file = File('${dir.path}/b.json')
      ..writeAsStringSync(jsonEncode(backup.toMap()));

    expect(await BackupService.importDataFromBackupFile(file), isTrue);

    final wallets = {
      for (final w in await db.getAllWallets()) w.id: w.name,
    };
    final pattern = await db.getRecurrentRecordPattern('p-investir');
    expect(wallets[pattern!.transferWalletId], 'Investir');
    expect(wallets[pattern.walletId], 'Conta corrente');
  });
}
