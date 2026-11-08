import 'package:flutter_test/flutter_test.dart';
import 'package:aupp/dinzo/dinzo-config.dart';
import 'package:aupp/dinzo/dinzo-models.dart';
import 'package:aupp/dinzo/dinzo-sync-engine.dart';
import 'package:aupp/models/category-type.dart';
import 'package:aupp/models/category.dart';

const conta = 1;
const investir = 3;

final accounts = [
  DinzoAccount(id: 'nu', type: 'BANK', title: 'Nu', connectorName: 'Nubank'),
  DinzoAccount(id: 'c6', type: 'BANK', title: 'C6', connectorName: 'C6 Bank'),
  DinzoAccount(
    id: 'btg',
    type: 'BANK',
    title: 'BTG Investimentos',
    connectorName: 'BTGPactual',
  ),
];

DinzoTransaction tx(
  String id,
  String account,
  String type,
  double amount, {
  String date = '2026-11-02',
  String description = 'Transferência enviada pelo Pix|Fulano de Tal',
  bool hidden = true,
}) => DinzoTransaction(
  id: id,
  date: date,
  type: type,
  amount: amount,
  description: description,
  accountId: account,
  hidden: hidden,
);

DinzoSyncPlan plan(List<DinzoTransaction> txs, {int? toInvest = investir}) =>
    DinzoSyncEngine(
      config: DinzoConfig(
        startDate: DateTime(2026, 10, 1),
        selfIdentifiers: ['Fulano de Tal'],
      ),
      accounts: accounts,
      categories: const [],
      defaultWalletId: conta,
      toInvestWalletId: toInvest,
      isDailyAccount: (a) => a.id != 'btg',
    ).plan(
      transactions: txs,
      linkedRecords: const [],
      from: DateTime(2026, 10, 1),
      to: DateTime(2026, 11, 30),
    );

void main() {
  test('Pix to a broker is an aporte from the wallet to invest', () {
    final p = plan([
      tx('out', 'nu', 'DEBIT', 100),
      tx('in', 'btg', 'CREDIT', 100, description: 'TRANSFERÊNCIA VIA PIX'),
    ]);
    final item = p.ofKind(DinzoPlanKind.create).single;
    expect(item.transaction!.id, 'out');
    expect(item.categoryType, CategoryType.investment);
    expect(item.desired!.categoryName, Category.investmentName);
    expect(item.desired!.walletId, investir);
    expect(item.desired!.value, -100);
    expect(item.desired!.title, 'Aporte no BTG');
    expect(item.desired!.tags, isNot(contains('Entre contas')));
    // The broker's side stays out.
    expect(p.ofKind(DinzoPlanKind.skipped).map((i) => i.transaction!.id), [
      'in',
    ]);
  });

  test('money back from a broker is a withdrawal into it', () {
    final p = plan([
      tx('out', 'btg', 'DEBIT', 0.5, description: 'Pix'),
      tx('in', 'c6', 'CREDIT', 0.5, description: 'Pix recebido Fulano de Tal'),
    ]);
    final item = p.ofKind(DinzoPlanKind.create).single;
    expect(item.desired!.categoryName, Category.withdrawalName);
    expect(item.desired!.walletId, investir);
    expect(item.desired!.value, 0.5);
    expect(item.desired!.title, 'Resgate do BTG');
  });

  test('between two everyday banks it stays hidden', () {
    final p = plan([
      tx('out', 'nu', 'DEBIT', 250),
      tx('in', 'c6', 'CREDIT', 250, description: 'Pix recebido Fulano de Tal'),
      // Same amount reaching the broker the same day does not take it.
      tx('btg', 'btg', 'CREDIT', 250, description: 'TRANSFERÊNCIA VIA PIX'),
    ]);
    expect(p.ofKind(DinzoPlanKind.create), isEmpty);
  });

  test('a purchase of the same amount is not an aporte', () {
    final p = plan([
      tx('loja', 'nu', 'DEBIT', 100, description: 'LOJA', hidden: false),
      tx('in', 'btg', 'CREDIT', 100, description: 'TRANSFERÊNCIA VIA PIX'),
    ]);
    final item = p.ofKind(DinzoPlanKind.create).single;
    expect(item.transaction!.id, 'loja');
    expect(item.categoryType, CategoryType.expense);
  });

  test('more than 3 days apart is not the same money', () {
    final p = plan([
      tx('out', 'nu', 'DEBIT', 100),
      tx('in', 'btg', 'CREDIT', 100, date: '2026-11-06'),
    ]);
    expect(p.ofKind(DinzoPlanKind.create), isEmpty);
  });

  test('without the wallet to invest yet, it stays hidden', () {
    final p = plan([
      tx('out', 'nu', 'DEBIT', 100),
      tx('in', 'btg', 'CREDIT', 100),
    ], toInvest: null);
    expect(p.ofKind(DinzoPlanKind.create), isEmpty);
  });
}
