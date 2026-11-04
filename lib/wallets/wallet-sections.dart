import 'package:aupp/models/wallet.dart';
import 'package:aupp/services/total-wallets.dart';

/// Where a wallet goes on the wallets page. Follows from what the wallet is,
/// never from its id or its position: a new caixinha lands among the others
/// whatever was created before it.
enum WalletSection {
  /// The money to spend: the wallets of the "Total" ([TotalWallets]).
  daily('Dia a dia'),

  /// Money set aside for something.
  boxes('Caixinhas'),

  /// The emergency reserve and the money waiting to be invested.
  reserves('Reservas');

  final String label;

  const WalletSection(this.label);

  static WalletSection of(Wallet wallet, int? defaultWalletId) {
    if (wallet.kind != WalletKind.normal) return reserves;
    if (wallet.isDefault || TotalWallets.includes(wallet, defaultWalletId)) {
      return daily;
    }
    return boxes;
  }

  /// [wallets] by section, each in the order given (the reserves by kind:
  /// the emergency one comes before investing).
  static Map<WalletSection, List<Wallet>> split(List<Wallet> wallets) {
    final defaultId = wallets.where((w) => w.isDefault).firstOrNull?.id;
    final result = {for (final section in values) section: <Wallet>[]};
    for (final wallet in wallets) {
      result[of(wallet, defaultId)]!.add(wallet);
    }
    result[reserves] = [
      for (final kind in _reserveOrder)
        ...result[reserves]!.where((w) => w.kind == kind),
    ];
    return result;
  }

  static const _reserveOrder = [
    WalletKind.emergency,
    WalletKind.opportunity,
    WalletKind.toInvest,
  ];

  /// After the last caixinha (or any wallet): what a new one gets.
  static int nextSortOrder(Iterable<Wallet> wallets) => wallets.fold(
    0,
    (next, w) => w.sortOrder >= next ? w.sortOrder + 1 : next,
  );
}
