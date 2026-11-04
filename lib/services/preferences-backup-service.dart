import 'dart:convert';

import 'package:aupp/services/logger.dart';
import 'package:aupp/settings/constants/preferences-keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Handles the portable subset of SharedPreferences used by backup files.
///
/// Preferences are intentionally restored one at a time. A removed key,
/// changed type, invalid enum/index, malformed serialized value, or failing
/// setter can never prevent the remaining settings from being restored.
class PreferencesBackupService {
  static final _logger = Logger.withContext('PreferencesBackupService');

  static final Set<String> _portableKeys = {
    // Number and currency formatting

    // Homepage and records

    // Categories and wallets
    PreferencesKeys.categoryListSortOption,
    // Kept because this legacy key is still written by the category tab.
    'defaultCategorySortOption',
    PreferencesKeys.walletListSortOption,
    PreferencesKeys.walletsEnabled,
    PreferencesKeys.showWalletBarOnHomepage,

    // Statistics

    // In-app keyboard

    // Portable saved data that lives in SharedPreferences

    // Dinzo integration (fork-only). The API key is deliberately absent.
    PreferencesKeys.dinzoConfig,
    PreferencesKeys.assetLots,
    PreferencesKeys.dailyBanks,
    PreferencesKeys.companies,
    PreferencesKeys.assetNotes,
    PreferencesKeys.portfolioDiagram,
    PreferencesKeys.allowManualRecords,
    PreferencesKeys.budgetPlan,
    PreferencesKeys.totalWallets,
    PreferencesKeys.disguiseEnabled,
  };

  /// Adds a preference of a sync extension to the backup.
  static void registerPortable(String key, bool Function(Object) validator) {
    _portableKeys.add(key);
    _validators[key] = validator;
  }

  static final Map<String, bool Function(Object)> _validators = {
    // Booleans
    for (final key in [
      PreferencesKeys.walletsEnabled,
      PreferencesKeys.showWalletBarOnHomepage,
    ])
      key: (value) => value is bool,

    // Integer options
    PreferencesKeys.categoryListSortOption: _intIn({0, 1, 2, 3}),
    'defaultCategorySortOption': _intIn({0, 1, 2, 3}),
    PreferencesKeys.walletListSortOption: _intIn({0, 1, 2, 3}),

    // Strings with finite option sets.

    // Free-form but typed strings
    PreferencesKeys.dinzoConfig: _isJsonObject,
    PreferencesKeys.assetLots: _isJsonObject,
    PreferencesKeys.dailyBanks: _isJsonObject,
    PreferencesKeys.companies: _isJsonObject,
    PreferencesKeys.assetNotes: _isJsonObject,
    PreferencesKeys.portfolioDiagram: _isJsonObject,
    PreferencesKeys.allowManualRecords: (value) => value is bool,
    PreferencesKeys.budgetPlan: _isJsonObject,
    PreferencesKeys.disguiseEnabled: (value) => value is bool,
    PreferencesKeys.totalWallets: (value) =>
        value is List && value.every((item) => item is String),

  };

  /// Exports only recognized, portable, JSON-safe preferences that are
  /// currently present. Missing preferences are omitted so defaults remain
  /// active after restore.
  static Map<String, dynamic> exportPreferences(SharedPreferences prefs) {
    final result = <String, dynamic>{};
    var present = 0;
    var exported = 0;
    var skippedInvalid = 0;
    var skippedErrors = 0;

    _logger.info(
      'Starting portable preference export (${_portableKeys.length} recognized keys)',
    );
    for (final key in _portableKeys) {
      if (!prefs.containsKey(key)) continue;
      present++;
      try {
        final value = prefs.get(key);
        if (value == null) {
          skippedInvalid++;
          _logger.warning(
            'Skipping preference during export: $key has a null value',
          );
        } else if (_isValid(key, value)) {
          result[key] = value;
          exported++;
          _logger.debug('Exported preference: $key');
        } else {
          skippedInvalid++;
          _logger.warning(
            'Skipping preference during export: $key has an invalid type or value',
          );
        }
      } catch (error, stackTrace) {
        skippedErrors++;
        _logger.handle(
          error,
          stackTrace,
          'Skipping preference during export: $key',
        );
      }
    }
    _logger.info(
      'Portable preference export completed: $exported exported, ${present - exported} skipped, $skippedInvalid invalid, $skippedErrors errors',
    );
    return result;
  }

  /// Restores preferences independently, skipping every unknown or invalid
  /// entry without aborting the rest of the backup import.
  static Future<void> restorePreferences(
    SharedPreferences prefs,
    Map<String, dynamic> preferences,
  ) async {
    var restored = 0;
    var skippedUnknown = 0;
    var skippedInvalid = 0;
    var skippedErrors = 0;

    _logger.info(
      'Starting portable preference restore (${preferences.length} entries)',
    );
    for (final entry in preferences.entries) {
      final key = entry.key;
      final value = entry.value;
      if (!_portableKeys.contains(key)) {
        skippedUnknown++;
        _logger.warning('Skipping unknown preference from backup: $key');
        continue;
      }
      try {
        if (!_isValid(key, value)) {
          skippedInvalid++;
          _logger.warning(
            'Skipping invalid preference from backup: $key has an invalid type or value',
          );
          continue;
        }
        await _setPreference(prefs, key, value);
        restored++;
        _logger.debug('Restored preference: $key');
      } catch (error, stackTrace) {
        skippedErrors++;
        _logger.handle(
          error,
          stackTrace,
          'Skipping preference during restore: $key',
        );
      }
    }
    _logger.info(
      'Portable preference restore completed: $restored restored, $skippedUnknown unknown, $skippedInvalid invalid, $skippedErrors errors',
    );
  }

  static bool _isValid(String key, Object value) {
    final validator = _validators[key];
    return validator != null && validator(value);
  }

  static Future<void> _setPreference(
    SharedPreferences prefs,
    String key,
    Object value,
  ) async {
    final bool applied;
    if (value is bool) {
      applied = await prefs.setBool(key, value);
    } else if (value is int) {
      applied = await prefs.setInt(key, value);
    } else if (value is double) {
      applied = await prefs.setDouble(key, value);
    } else if (value is String) {
      applied = await prefs.setString(key, value);
    } else if (value is List && value.every((item) => item is String)) {
      applied = await prefs.setStringList(key, value.cast<String>());
    } else {
      throw const FormatException('Unsupported SharedPreferences value type');
    }
    if (!applied) {
      throw StateError('SharedPreferences rejected the value');
    }
  }

  static bool Function(Object) _intIn(Set<int> allowed) =>
      (value) => value is int && allowed.contains(value);

  static bool _isJsonObject(Object value) {
    if (value is! String || value.isEmpty) return false;
    try {
      return jsonDecode(value) is Map<String, dynamic>;
    } catch (_) {
      return false;
    }
  }

}
