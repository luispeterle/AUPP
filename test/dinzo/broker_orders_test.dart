import 'package:flutter_test/flutter_test.dart';
import 'package:aupp/dinzo/broker-orders.dart';
import 'package:aupp/dinzo/dinzo-taxes.dart';
import 'package:aupp/models/category.dart';

const investir = 3;

DinzoInvestment position(
  String code,
  String broker,
  List<DinzoInvestmentMovement> movements, {
  String type = 'ETF',
}) => DinzoInvestment(
  assetKey: '$type|code:$code',
  name: code,
  type: type,
  balance: 21.76,
  code: code,
  broker: broker,
  movements: movements,
);

DinzoInvestmentMovement move(String type, String date, double amount) =>
    DinzoInvestmentMovement(
      id: '$type$date',
      type: type,
      date: date,
      amount: amount,
    );

void main() {
  List<BrokerOrder> orders(
    List<DinzoInvestment> investments, {
    Set<String> banksWithEntries = const {},
  }) => BrokerOrders.of(
    investments,
    banksWithEntries: banksWithEntries,
    since: DateTime(2026, 11, 1),
    isMoney: (_) => false,
  );

  test('a bank that sends no entries: its orders come from its positions', () {
    final found = orders([
      position('GOLD11', 'Rico Investimentos', [
        move('BUY', '2026-11-09', 19.9),
        move('SELL', '2026-11-20', 10),
      ]),
    ]);
    final records = found.map((o) => o.record(investir)).toList();
    expect(records.map((r) => r.title), [
      'Compra de GOLD11 no Rico',
      'Venda de GOLD11 no Rico',
    ]);
    expect(records.map((r) => r.value), [-19.9, 10]);
    expect(records.map((r) => r.category!.name), [
      Category.investmentName,
      Category.withdrawalName,
    ]);
    expect(records.map((r) => r.walletId), everyElement(investir));
    expect(records.first.dinzoId, startsWith(BrokerOrders.prefix));
    expect(records.first.tags, {'Rico'});
  });

  test('a bank that sends entries has its orders there: none here', () {
    final found = orders(
      [
        position('BTCI11', 'BTGPactual', [move('BUY', '2026-11-09', 7.15)]),
      ],
      banksWithEntries: {'BTG'},
    );
    expect(found, isEmpty);
  });

  test('before the wallets explain each month, it is in their balances', () {
    expect(
      orders([
        position('GOLD11', 'Rico Investimentos', [
          move('BUY', '2026-10-20', 19.9),
        ]),
      ]),
      isEmpty,
    );
  });

  test('a position kept as everyday money moves no money', () {
    final found = BrokerOrders.of(
      [
        position('TESOURO', 'Rico Investimentos', [
          move('BUY', '2026-11-09', 100),
        ]),
      ],
      banksWithEntries: const {},
      since: DateTime(2026, 11, 1),
      isMoney: (_) => true,
    );
    expect(found, isEmpty);
  });
}
