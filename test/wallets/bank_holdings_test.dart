// "Saldo nos bancos": accounts, cards and positions grouped by bank.
import 'package:flutter_test/flutter_test.dart';
import 'package:aupp/dinzo/dinzo-models.dart';
import 'package:aupp/dinzo/dinzo-taxes.dart';
import 'package:aupp/wallets/bank-balances-page.dart';

void main() {
  DinzoInvestment position(
    String type,
    String broker,
    double balance, {
    bool archived = false,
  }) => DinzoInvestment(
    assetKey: '$type$broker$balance',
    name: 'Ativo',
    type: type,
    balance: balance,
    broker: broker,
    archived: archived,
    movements: const [],
  );

  test('by bank, everyday banks first, cards apart', () {
    final banks = BankHoldings.group(
      [
        DinzoAccount(id: '1', type: 'BANK', title: 'Conta', balance: 50, connectorName: 'Nubank'),
        DinzoAccount.fromJson({
          'id': '2',
          'type': 'CREDIT',
          'title': 'Roxinho',
          'balance': 300,
          'credit': {'limit': 2000},
          'open_finance': {'connector_name': 'Nubank'},
        }),
        DinzoAccount(id: '3', type: 'BANK', title: 'Velha', balance: 9, connectorName: 'C6 Bank', archived: true),
        DinzoAccount(id: '4', type: 'BANK', title: 'Carteira', balance: 5),
      ],
      [
        position('FIXED_INCOME', 'Nubank', 1000),
        position('EQUITY', 'Nubank', 700),
        position('FIXED_INCOME', 'BTG Pactual', 4000),
        position('FIXED_INCOME', 'Nubank', 1, archived: true),
      ],
    );
    expect(banks.map((b) => b.institution.name), ['Nubank', 'Contas sem banco', 'BTG']);
    final nubank = banks.first;
    expect(nubank.isDaily, isTrue);
    expect(nubank.accountsTotal, 50);
    expect(nubank.fixedIncomeTotal, 1000);
    expect(nubank.otherTotal, 700);
    expect(nubank.total, 1750);
    expect(nubank.cards.single.creditLimit, 2000);
    expect(nubank.cardsTotal, 300);
    expect(banks.last.isDaily, isFalse);
  });
}
