// The wallets page groups by what each wallet is: dia a dia, caixinhas,
// reservas. A new caixinha goes among the caixinhas, not after the reserves.
import 'package:flutter_test/flutter_test.dart';
import 'package:aupp/models/wallet.dart';
import 'package:aupp/services/service-config.dart';
import 'package:aupp/settings/constants/preferences-keys.dart';
import 'package:aupp/wallets/wallet-sections.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      PreferencesKeys.totalWallets: ['Conta corrente', 'Dinheiro'],
    });
    ServiceConfig.sharedPreferences = await SharedPreferences.getInstance();
  });

  List<String> names(List<Wallet> wallets) => [for (final w in wallets) w.name];

  test('in sections, whatever the order and the ids', () {
    final split = WalletSection.split([
      Wallet('Investir', id: 3, kind: WalletKind.toInvest, sortOrder: 0),
      Wallet('Caixinha Viagem', id: 9, sortOrder: 1),
      Wallet('Conta corrente', id: 1, isDefault: true, sortOrder: 2),
      Wallet('Reserva', id: 11, kind: WalletKind.emergency, sortOrder: 3),
      Wallet('Caixinha Carro', id: 5, sortOrder: 4),
      Wallet('Dinheiro', id: 2, sortOrder: 5),
    ]);
    expect(names(split[WalletSection.daily]!), ['Conta corrente', 'Dinheiro']);
    expect(
      names(split[WalletSection.boxes]!),
      ['Caixinha Viagem', 'Caixinha Carro'],
    );
    expect(names(split[WalletSection.reserves]!), ['Reserva', 'Investir']);
  });

  test('a new caixinha goes after every wallet there is', () {
    final wallets = [
      Wallet('Conta corrente', sortOrder: 0),
      Wallet('Caixinha', sortOrder: 4),
      Wallet('Investir', kind: WalletKind.toInvest, sortOrder: 2),
    ];
    final next = WalletSection.nextSortOrder(wallets);
    expect(next, 5);
    final split = WalletSection.split([
      ...wallets,
      Wallet('Caixinha nova', sortOrder: next),
    ]);
    expect(names(split[WalletSection.boxes]!), ['Caixinha', 'Caixinha nova']);
    expect(names(split[WalletSection.reserves]!), ['Investir']);
  });
}
