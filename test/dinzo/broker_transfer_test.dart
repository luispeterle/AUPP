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
  DinzoAccount(
    id: 'btgb',
    type: 'BANK',
    title: 'BTG Banking',
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
      isDailyAccount: (a) => !a.id.startsWith('btg'),
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
    expect(item.desired!.title, 'Aporte do Nubank para o BTG');
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
    expect(item.desired!.title, 'Resgate do BTG para o C6');
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

  group('inside the banks outside the everyday ones', () {
    test('BTG Banking → BTG Investimentos stays out (Dinzo hid one side)', () {
      final p = plan([
        tx('out', 'btgb', 'DEBIT', 0.1, date: '2026-11-09', description: 'Tef'),
        tx(
          'in',
          'btg',
          'CREDIT',
          0.1,
          date: '2026-11-09',
          description: 'RECEBIMENTO TRANSFERÊNCIA',
          hidden: false,
        ),
      ]);
      expect(p.ofKind(DinzoPlanKind.create), isEmpty);
      expect(p.ofKind(DinzoPlanKind.skipped).map((i) => i.skipReason).toSet(), {
        DinzoSkipReason.hidden,
        DinzoSkipReason.outsideDailyBanks,
      });
    });

    test("the broker's side of an aporte stays out even if visible", () {
      final p = plan([
        tx('out', 'nu', 'DEBIT', 100),
        tx(
          'in',
          'btg',
          'CREDIT',
          100,
          description: 'TRANSFERÊNCIA A CRÉDITO VIA PIX',
          hidden: false,
        ),
      ]);
      expect(p.ofKind(DinzoPlanKind.create).single.transaction!.id, 'out');
    });

    test("a broker's own entry stays out", () {
      final p = plan([
        tx(
          'jcp',
          'btg',
          'CREDIT',
          3.21,
          description: 'JUROS S/ CAPITAL BBAS3',
          hidden: false,
        ),
      ]);
      expect(
        p.ofKind(DinzoPlanKind.skipped).single.skipReason,
        DinzoSkipReason.outsideDailyBanks,
      );
    });

    test('a Pix to someone else from the BTG is an expense', () {
      final p = plan([
        tx(
          'pix-out',
          'btgb',
          'DEBIT',
          50,
          description: 'Pix enviado Maria Souza',
          hidden: false,
        ),
        // An everyday bank's own investment move of the same amount is not
        // its other side.
        tx('rdb', 'nu', 'CREDIT', 50, description: 'Resgate RDB'),
      ]);
      final item = p.ofKind(DinzoPlanKind.create).single;
      expect(item.transaction!.id, 'pix-out');
      expect(item.categoryType, CategoryType.expense);
      expect(item.desired!.walletId, conta);
      expect(item.desired!.value, -50);
    });

    test('the BTG sends only "Pix": the title says which way', () {
      final p = plan([
        tx('out', 'btgb', 'DEBIT', 0.13, description: 'Pix', hidden: false),
        tx('in', 'btgb', 'CREDIT', 0.12, description: 'Pix', hidden: false),
        tx('tef', 'btgb', 'DEBIT', 0.2, description: 'Tef', hidden: false),
      ]);
      final titles = {
        for (final i in p.ofKind(DinzoPlanKind.create))
          i.transaction!.id: i.desired!.title,
      };
      expect(titles, {
        'out': 'Pix enviado',
        'in': 'Pix recebido',
        'tef': 'Transferência enviada',
      });
    });

    test('the bank name of an account outside the everyday ones', () {
      final engine = DinzoSyncEngine(
        config: DinzoConfig(startDate: DateTime(2026, 10, 1)),
        accounts: accounts,
        categories: const [],
        defaultWalletId: conta,
        isDailyAccount: (a) => !a.id.startsWith('btg'),
      );
      expect(engine.outsideBankOf('btgb'), 'BTG');
      expect(engine.outsideBankOf('nu'), isNull);
    });
  });
}
