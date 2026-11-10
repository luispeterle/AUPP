import 'package:aupp/models/wallet.dart';
import 'package:aupp/services/service-config.dart';
import 'package:aupp/settings/constants/preferences-keys.dart';

/// The wallets whose money is "to spend", chosen in the Extrato's
/// wallet picker ("Total" column). Everything that splits spending money
/// from money set aside reads this set: the Extrato totals, "O mês até
/// agora", the budget base, "Para que está guardado" and the Dinzo free
/// balance. A transfer from one of them to another wallet is spending, the
/// way back is income, and a move inside either side doesn't count.
///
/// Kept by wallet name (portable, goes in the backup): ids change on restore.
/// Nothing chosen = only the default wallet.
class TotalWallets {
  static String _key(String name) => name.trim().toLowerCase();

  static List<String> get names =>
      ServiceConfig.sharedPreferences?.getStringList(
        PreferencesKeys.totalWallets,
      ) ??
      const [];

  /// Whether [w] is one of the chosen wallets ([defaultWalletId] when none).
  static bool includes(Wallet w, int? defaultWalletId) {
    final chosen = names.map(_key).toSet();
    if (chosen.isEmpty) return w.id != null && w.id == defaultWalletId;
    return chosen.contains(_key(w.name));
  }

  /// A goal: money set aside for something, which is neither to spend nor
  /// waiting to be invested.
  static bool isGoal(Wallet w, int? defaultWalletId) =>
      w.id != defaultWalletId &&
      !w.isArchived &&
      !includes(w, defaultWalletId) &&
      !w.isInvestmentReserve;

  /// The chosen wallets among [all], or [] when nothing is chosen (the
  /// Extrato then totals the listed wallets).
  static List<Wallet> chosenIn(Iterable<Wallet> all) {
    final chosen = names.map(_key).toSet();
    return all.where((w) => chosen.contains(_key(w.name))).toList();
  }

  /// Ids of the spending wallets among [all] ([defaultWalletId] when none
  /// is chosen).
  static Set<int> idsIn(Iterable<Wallet> all, int? defaultWalletId) => {
    for (final w in all)
      if (w.id != null && includes(w, defaultWalletId)) w.id!,
  };

  static Future<void> save(Iterable<Wallet> wallets) async {
    await ServiceConfig.sharedPreferences?.setStringList(
      PreferencesKeys.totalWallets,
      wallets.map((w) => w.name.trim()).toList(),
    );
  }

  /// Keeps a renamed wallet in the set.
  static Future<void> rename(String from, String to) async {
    final current = names;
    if (!current.any((n) => _key(n) == _key(from))) return;
    await ServiceConfig.sharedPreferences?.setStringList(
      PreferencesKeys.totalWallets,
      [for (final n in current) _key(n) == _key(from) ? to.trim() : n],
    );
  }
}
