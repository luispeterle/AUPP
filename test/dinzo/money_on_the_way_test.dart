// Tesouro bought in an everyday bank leaves the account a day or two before
// the Dinzo shows the position: in between it is still money.
import 'package:flutter_test/flutter_test.dart';
import 'package:aupp/dinzo/daily-money.dart';
import 'package:aupp/dinzo/dinzo-api.dart';
import 'package:aupp/dinzo/dinzo-config.dart';
import 'package:aupp/dinzo/dinzo-models.dart';
import 'package:aupp/dinzo/dinzo-sync-engine.dart';
import 'package:aupp/dinzo/dinzo-taxes.dart';
import 'package:aupp/services/service-config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final today = DateTime(2026, 11, 20);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ServiceConfig.sharedPreferences = await SharedPreferences.getInstance();
  });

  DinzoTransaction tx(String id, String type, double amount, String text) =>
      DinzoTransaction(
        id: id,
        date: '2026-11-18',
        type: type,
        amount: amount,
        description: text,
        accountId: 'nu',
        categoryId: 'aplicacao',
      );

  DinzoSyncEngine engine({bool tesouroIsMoney = true}) => DinzoSyncEngine(
    config: DinzoConfig(startDate: DateTime(2026, 10, 1)),
    accounts: [
      DinzoAccount(
        id: 'nu',
        type: 'BANK',
        title: 'Nu',
        connectorName: 'Nubank',
      ),
    ],
    categories: const [],
    defaultWalletId: 1,
    toInvestWalletId: 3,
    isDailyAccount: (_) => true,
    isDailyProduct: (bank, product) => product != 'Tesouro' || tesouroIsMoney,
  );

  DinzoInvestment tesouro(double balance, String purchase) =>
      DinzoInvestment.fromJson({
        'id': purchase,
        'asset_key': 'tesouro-$purchase',
        'name': 'Tesouro Selic 2031',
        'type': 'FIXED_INCOME',
        'sub_type': 'TREASURY',
        'balance': balance,
        'purchase_date': purchase,
        'broker': 'Nubank',
      });

  group('what the sync sees leaving', () {
    test('Tesouro kept as everyday money in the bank', () {
      final sent = engine().onTheWayIn([
        tx('t', 'DEBIT', 9918.49, 'Aplicação em Tesouro Direto'),
        tx('rdb', 'DEBIT', 100, 'Aplicação RDB'),
        tx('volta', 'CREDIT', 50, 'Resgate RDB'),
      ]);
      expect(sent.map((m) => (m.bank, m.product, m.amount)), [
        ('Nubank', 'Tesouro', 9918.49),
      ]);
    });

    test('Tesouro chosen as an investment there is an aporte, not money', () {
      final sent = engine(
        tesouroIsMoney: false,
      ).onTheWayIn([tx('t', 'DEBIT', 9918.49, 'Aplicação em Tesouro Direto')]);
      expect(sent, isEmpty);
    });
  });

  group('what is still on its way', () {
    Future<void> sent(List<MoneyOnTheWay> moves) =>
        DailyMoney.rememberSent(moves, today);

    final first = MoneyOnTheWay(
      'Nubank',
      'Tesouro',
      DateTime(2026, 11, 18),
      9918.49,
    );
    final second = MoneyOnTheWay(
      'Nubank',
      'Tesouro',
      DateTime(2026, 11, 19),
      607.55,
    );

    test('nothing shown yet: all of it', () async {
      await sent([first, second]);
      final way = DailyMoney.inTransit(const [], now: today).single;
      expect(way.amount, closeTo(10526.04, 1e-6));
      expect(way.since, DateTime(2026, 11, 18));
    });

    test('the position shows, at its price of the day: nothing left', () async {
      await sent([first, second]);
      expect(
        DailyMoney.inTransit([tesouro(10530.10, '2026-11-18')], now: today),
        isEmpty,
      );
    });

    test('only part shows: the rest is still on its way', () async {
      await sent([first, second]);
      final way = DailyMoney.inTransit([
        tesouro(9920, '2026-11-18'),
      ], now: today).single;
      expect(way.amount, closeTo(606.04, 1e-6));
    });

    test('a position from before does not count as the new one', () async {
      await sent([first]);
      final way = DailyMoney.inTransit([
        tesouro(5000, '2026-03-02'),
      ], now: today).single;
      expect(way.amount, closeTo(9918.49, 1e-6));
    });

    test(
      'after ${DailyMoney.inTransitDays} days it is waited for no more',
      () async {
        await sent([first]);
        expect(
          DailyMoney.inTransit(const [], now: DateTime(2026, 12, 1)),
          isEmpty,
        );
      },
    );
  });
}
