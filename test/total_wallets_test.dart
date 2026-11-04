// The spending wallets (Extrato's "Total") are kept by name.
import 'package:flutter_test/flutter_test.dart';
import 'package:aupp/models/wallet.dart';
import 'package:aupp/services/service-config.dart';
import 'package:aupp/services/total-wallets.dart';
import 'package:aupp/settings/constants/preferences-keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final conta = Wallet('Conta corrente', id: 1, isDefault: true);
  final vale = Wallet('Vale alimentação', id: 2);
  final caixinha = Wallet('Caixinha Carro', id: 3);
  final all = [conta, vale, caixinha];

  Future<void> start(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    ServiceConfig.sharedPreferences = await SharedPreferences.getInstance();
  }

  test('nothing chosen: only the default wallet', () async {
    await start({});
    expect(TotalWallets.idsIn(all, conta.id), {1});
    expect(TotalWallets.chosenIn(all), isEmpty);
  });

  test('chosen by name, whatever the ids', () async {
    await start({
      PreferencesKeys.totalWallets: ['conta corrente ', 'Vale alimentação'],
    });
    expect(TotalWallets.idsIn(all, conta.id), {1, 2});
    expect(TotalWallets.includes(caixinha, conta.id), isFalse);
  });

  test('a renamed wallet stays chosen', () async {
    await start({
      PreferencesKeys.totalWallets: ['Conta corrente', 'Vale'],
    });
    await TotalWallets.rename('Vale', 'Vale alimentação');
    expect(TotalWallets.names, ['Conta corrente', 'Vale alimentação']);
  });
}
