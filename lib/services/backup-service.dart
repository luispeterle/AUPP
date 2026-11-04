import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:aupp/models/backup.dart';
import 'package:aupp/services/database/exceptions.dart';
import 'package:aupp/services/preferences-backup-service.dart';
import 'package:aupp/services/service-config.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'database/database-interface.dart';


import 'database/sqlite-database.dart';
import 'logger.dart';
import 'package:aupp/services/database/money-model-migration.dart';

/// BackupService contains the methods to create/restore backup file
class BackupService {
  static final _logger = Logger.withClass(BackupService);

  static const String MANDATORY_BACKUP_SUFFIX = "obackup.json";

  // not final because it is swapped in the tests
  static DatabaseInterface database = ServiceConfig.database;

  /// Generates a backup file name containing the app package name, version, and current time.
  static Future<String> generateBackupFileName() async {
    // Get app information
    final packageInfo = await PackageInfo.fromPlatform();
    final appName = packageInfo.packageName.split(".").last; // The package name
    final version = packageInfo.version; // The app version

    // Get current date and time
    final now = DateTime.now();
    final dateStr = now.toIso8601String().split(".")[0]; // Strip milliseconds
    final formattedDate = dateStr.replaceAll(
      ":",
      "-",
    ); // Replace colon to avoid issues in file naming

    // Construct the file name
    return "${appName}_${version}_${formattedDate}_${MANDATORY_BACKUP_SUFFIX}";
  }

  /// Creates a JSON backup file.
  /// [backupFileName] - optional, if not specified uses the generated backup file name.
  /// [directoryPath] - optional, if not specified it uses the application's documents directory.
  static Future<File> createJsonBackupFile({
    String? backupFileName,
    String? directoryPath,
  }) async {
    try {
      _logger.info('Starting backup creation...');

      // Generate backup file name if not provided
      backupFileName ??= await generateBackupFileName();
      _logger.debug('Backup filename: $backupFileName');

      // Use the provided directory path or default to the application's documents directory
      final path = directoryPath != null
          ? Directory(directoryPath)
          : await getApplicationDocumentsDirectory();

      _logger.debug('Backup directory: ${path.path}');

      await path.create(recursive: true);

      final packageInfo = await PackageInfo.fromPlatform();
      final appName = packageInfo.packageName; // The package name
      final version = packageInfo.version; // The app version
      final databaseVersion = SqliteDatabase.version.toString();

      _logger.debug('Fetching data for backup...');
      var records = await database.getAllRecords();
      var categories = await database.getAllCategories();
      var recurrentRecordPatterns = await database.getRecurrentRecordPatterns();
      var recordTagAssociations = await database.getAllRecordTagAssociations();
      var wallets = await database.getAllWallets();
      var prefs = await SharedPreferences.getInstance();
      var preferences = PreferencesBackupService.exportPreferences(prefs);

      _logger.info(
        'Backup data: ${records.length} records, ${categories.length} categories, ${recurrentRecordPatterns.length} recurrent patterns, ${recordTagAssociations.length} tags, ${wallets.length} wallets',
      );

      var backup = Backup(
        appName,
        version,
        databaseVersion,
        categories,
        records,
        recurrentRecordPatterns,
        recordTagAssociations,
        wallets: wallets,
        preferences: preferences,
      );
      var backupJsonStr = jsonEncode(backup.toMap());

      var backupJsonOnDisk = File("${path.path}/$backupFileName");
      var result = await backupJsonOnDisk.writeAsString(backupJsonStr);

      _logger.info(
        'Backup created successfully: ${backupJsonOnDisk.path} (${backupJsonStr.length} bytes)',
      );
      return result;
    } catch (e, st) {
      _logger.handle(e, st, 'Failed to create backup');
      rethrow;
    }
  }

  /// Imports data from a backup file. If an encryption password is provided,
  /// it attempts to decrypt the file content before importing.
  ///
  /// [inputFile] - the backup file to import.
  static Future<bool> importDataFromBackupFile(File inputFile) async {
    try {
      _logger.info('Starting backup import from: ${inputFile.path}');
      String fileContent = await inputFile.readAsString();

      var jsonMap = jsonDecode(fileContent);
      Backup backup = Backup.fromMap(jsonMap);
      _logger.info(
        'Importing: ${backup.records.length} records, ${backup.categories.length} categories, ${backup.wallets.length} wallets',
      );

      // Restore portable preferences independently. A malformed, obsolete, or
      // failing setting is skipped and cannot abort the database restore.
      if (backup.preferences.isNotEmpty) {
        SharedPreferences? restorePrefs;
        try {
          restorePrefs = await SharedPreferences.getInstance();
        } catch (error, stackTrace) {
          // Preferences are optional for legacy/database-only imports. A
          // missing platform implementation must not prevent the actual data
          // from being restored.
          _logger.handle(
            error,
            stackTrace,
            'Skipping preferences because they are unavailable',
          );
        }
        if (restorePrefs != null) {
          await PreferencesBackupService.restorePreferences(
            restorePrefs,
            backup.preferences,
          );

        }
      }

      // Profiles of old backups (the app no longer has them) are ignored:
      // everything is restored together.

      // Insert wallets and build backup_id → new_db_id mapping
      final walletIdMap = <int, int>{}; // backup wallet id → new db wallet id

      // Check if a default wallet already exists in the database
      final existingDefaultWallet = await database.getDefaultWallet();
      final int? existingDefaultWalletId = existingDefaultWallet?.id;

      // Existing wallets, for name-based merging
      final existingWallets = await database.getAllWallets();

      for (var backupWallet in backup.wallets) {
        final backupId = backupWallet.id;
        int? mappedWalletId;

        // Check if this is a default wallet and reuse existing default
        if (backupWallet.isDefault && existingDefaultWalletId != null) {
          mappedWalletId = existingDefaultWalletId;
        } else {
          // Check if a wallet with the same name exists
          final match = existingWallets.where(
            (w) => w.name.toLowerCase() == backupWallet.name.toLowerCase(),
          );
          if (match.isNotEmpty) {
            mappedWalletId = match.first.id;
          }
        }

        if (mappedWalletId != null) {
          // Reuse existing wallet
          if (backupId != null) {
            walletIdMap[backupId] = mappedWalletId;
          }
          // Fork: a device default wallet still carrying the factory name
          // takes the backup's name (e.g. "Conta corrente").
          final existingDefault = existingDefaultWallet;
          if (backupWallet.isDefault &&
              existingDefault != null &&
              mappedWalletId == existingDefault.id &&
              const {'Default Wallet', 'Carteira padrão'}
                  .union({'Carteira padrão'})
                  .contains(existingDefault.name) &&
              backupWallet.name.trim().isNotEmpty &&
              backupWallet.name != existingDefault.name) {
            existingDefault.name = backupWallet.name;
            await database.updateWallet(existingDefault.id!, existingDefault);
          }
        } else {
          // Insert without the old id so the DB auto-assigns a new one
          backupWallet.id = null;
          final newId = await database.addWallet(backupWallet);
          if (backupId != null) {
            walletIdMap[backupId] = newId;
          }
          // Add to existing list for subsequent duplicates
          final newWallet = await database.getWalletById(newId);
          if (newWallet != null) existingWallets.add(newWallet);
        }
      }

      // Records with no wallet mapping (old backups, missing wallet data, etc.)
      // fall back to the Default Wallet, which always exists.
      final defaultWallet = await database.getDefaultWallet();
      final fallbackWalletId = defaultWallet?.id;

      // Add categories
      for (var backupCategory in backup.categories) {
        try {
          await database.addCategory(backupCategory);
        } on ElementAlreadyExists {
          print("${backupCategory!.name} already exists.");
        }
      }

      // Build a map of record ID -> tags from the backup's tag associations
      final recordIdToTags = <int, Set<String>>{};
      for (var assoc in backup.recordTagAssociations) {
        recordIdToTags
            .putIfAbsent(assoc.recordId, () => <String>{})
            .add(assoc.tagName);
      }
      _logger.info(
          'Restoring backup: ${backup.recordTagAssociations.length} tag associations '
          'across ${recordIdToTags.length} records');

      // Populate record.tags and remap wallet_id
      for (var record in backup.records) {
        if (record == null) continue;
        if (record.id != null && recordIdToTags.containsKey(record.id)) {
          record.tags = recordIdToTags[record.id]!;
        }
        // Remap wallet_id from backup id to new db id
        if (record.walletId != null &&
            walletIdMap.containsKey(record.walletId)) {
          record.walletId = walletIdMap[record.walletId];
        } else if (fallbackWalletId != null) {
          record.walletId = fallbackWalletId;
        }
        // Remap transfer_wallet_id from backup id to new db id
        if (record.transferWalletId != null &&
            walletIdMap.containsKey(record.transferWalletId)) {
          record.transferWalletId = walletIdMap[record.transferWalletId];
        } else if (record.transferWalletId != null &&
            !walletIdMap.containsKey(record.transferWalletId)) {
          // Destination wallet not found in backup mapping — clear the transfer
          record.transferWalletId = null;
        }
      }

      // Add records in batch — Phase 2 will correctly map tags to new IDs
      await database.addRecordsInBatch(backup.records);

      // Add recurrent patterns
      for (var backupRecurrentPatterns in backup.recurrentRecordsPattern) {
        // Remap wallet_id — fall back to default wallet when the backup
        // wallet is missing (mirrors the record remapping logic above).
        if (backupRecurrentPatterns.walletId != null &&
            walletIdMap.containsKey(backupRecurrentPatterns.walletId)) {
          backupRecurrentPatterns.walletId =
              walletIdMap[backupRecurrentPatterns.walletId];
        } else if (fallbackWalletId != null) {
          backupRecurrentPatterns.walletId = fallbackWalletId;
        }
        // Remap transfer_wallet_id too (fork fix, 2026-10-13): upstream left
        // the backup id, so recurring transfers pointed at whichever wallet
        // took that id on this device (e.g. "Investir" → another wallet).
        if (backupRecurrentPatterns.transferWalletId != null) {
          if (walletIdMap.containsKey(backupRecurrentPatterns.transferWalletId)) {
            backupRecurrentPatterns.transferWalletId =
                walletIdMap[backupRecurrentPatterns.transferWalletId];
          } else {
            _logger.warning(
              'Recurrent transfer "${backupRecurrentPatterns.title}" points at '
              'a wallet missing from the backup; keeping it unchanged',
            );
          }
        }
        String? recurrentPatternId = backupRecurrentPatterns.id;
        if (await database.getRecurrentRecordPattern(recurrentPatternId) ==
            null) {
          await database.addRecurrentRecordPattern(backupRecurrentPatterns);
        } else {
          print(
            "Recurrent pattern with id $recurrentPatternId already exists.",
          );
        }
      }

      _logger.info('Backup imported successfully');
      // A backup from before the current way of keeping the money.
      final sqlite = database is SqliteDatabase
          ? await (database as SqliteDatabase).database
          : null;
      if (sqlite != null && await MoneyModelMigration.needed(sqlite)) {
        await sqlite.transaction(MoneyModelMigration.run);
      }
      return true;
    } catch (e, st) {
      _logger.handle(e, st, 'Failed to import backup');
      return false;
    }
  }

}
