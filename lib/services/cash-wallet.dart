import 'package:aupp/models/wallet.dart';
import 'package:aupp/services/service-config.dart';
import 'package:aupp/settings/constants/preferences-keys.dart';

/// Fork: the wallet of paper money, chosen in the wallet's edit page. A
/// record typed by hand ("Manual") always moves it, never the default
/// wallet, whose money is the banks' and comes from Dinzo.
///
/// Kept by wallet name (portable, goes in the backup) like [TotalWallets]:
/// ids change on restore. Nothing chosen = the default wallet, as before.
class CashWallet {
  static String _key(String name) => name.trim().toLowerCase();

  static String? get name {
    final saved = ServiceConfig.sharedPreferences?.getString(
      PreferencesKeys.cashWallet,
    );
    return saved == null || saved.trim().isEmpty ? null : saved;
  }

  static bool isCash(Wallet w) {
    final chosen = name;
    return chosen != null && _key(chosen) == _key(w.name);
  }

  /// The chosen wallet among [all], unless it is archived or gone.
  static Wallet? findIn(Iterable<Wallet> all) {
    for (final w in all) {
      if (!w.isArchived && isCash(w)) return w;
    }
    return null;
  }

  static Future<Wallet?> find() async =>
      findIn(await ServiceConfig.database.getAllWallets());

  /// Makes [wallet] the paper money one, or none.
  static Future<void> save(Wallet? wallet) async {
    final prefs = ServiceConfig.sharedPreferences;
    if (wallet == null) {
      await prefs?.remove(PreferencesKeys.cashWallet);
    } else {
      await prefs?.setString(PreferencesKeys.cashWallet, wallet.name.trim());
    }
  }

  /// Keeps a renamed wallet as the paper money one.
  static Future<void> rename(String from, String to) async {
    final chosen = name;
    if (chosen == null || _key(chosen) != _key(from)) return;
    await ServiceConfig.sharedPreferences?.setString(
      PreferencesKeys.cashWallet,
      to.trim(),
    );
  }
}
