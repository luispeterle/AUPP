import 'package:flutter_test/flutter_test.dart';
import 'package:aupp/dinzo/dinzo-config.dart';
import 'package:aupp/dinzo/dinzo-models.dart';
import 'package:aupp/dinzo/dinzo-sync-engine.dart';
import 'package:aupp/models/category-type.dart';
import 'package:aupp/models/category.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/services/service-config.dart';
import 'package:timezone/data/latest_all.dart' as tz;

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
    // It still left the everyday banks, to somewhere unknown.
    final item = p.ofKind(DinzoPlanKind.create).single;
    expect(item.transaction!.id, 'out');
    expect(item.desired!.title, 'Aporte do Nubank');
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

  group('aportes whose other side Dinzo does not show', () {
    setUpAll(() {
      tz.initializeTimeZones();
      ServiceConfig.localTimezone = 'UTC';
    });

    final categories = [
      DinzoCategory(id: 'invest', title: 'Investimentos'),
      DinzoCategory(id: 'aplicacao', title: 'Aplicação', parentId: 'invest'),
      DinzoCategory(id: 'proventos', title: 'Proventos', parentId: 'invest'),
    ];

    DinzoSyncPlan unpaired(
      List<DinzoTransaction> txs, {
      List<Record> linked = const [],
    }) =>
        DinzoSyncEngine(
          config: DinzoConfig(
            startDate: DateTime(2026, 10, 1),
            selfIdentifiers: ['Fulano de Tal'],
          ),
          accounts: accounts,
          categories: categories,
          defaultWalletId: conta,
          toInvestWalletId: investir,
          isDailyAccount: (a) => !a.id.startsWith('btg'),
          unpairedAportesFrom: DateTime(2026, 11, 1),
        ).plan(
          transactions: txs,
          linkedRecords: linked,
          from: DateTime(2026, 10, 1),
          to: DateTime(2026, 11, 30),
        );

    DinzoTransaction invested(String id, String description, {String? date}) =>
        DinzoTransaction(
          id: id,
          date: date ?? '2026-11-08',
          type: 'DEBIT',
          amount: 300,
          description: description,
          accountId: 'nu',
          categoryId: 'aplicacao',
        );

    test('a Pix to a crypto exchange is an aporte to it', () {
      final p = unpaired([
        invested('okx', 'Transferência enviada pelo Pix|OKX SERVICOS DIGITAIS'),
      ]);
      final item = p.ofKind(DinzoPlanKind.create).single;
      expect(item.categoryType, CategoryType.investment);
      expect(item.desired!.categoryName, Category.investmentName);
      expect(item.desired!.walletId, investir);
      expect(item.desired!.value, -300);
      expect(item.desired!.title, 'Aporte do Nubank para o OKX');
    });

    test('a transfer to myself that reached no everyday bank', () {
      final p = unpaired([
        tx('ted', 'c6', 'DEBIT', 31.36, date: '2026-11-06'),
        tx(
          'back',
          'nu',
          'CREDIT',
          26,
          date: '2026-11-07',
          description: 'Pix recebido de Fulano de Tal',
        ),
      ]);
      final titles = {
        for (final i in p.ofKind(DinzoPlanKind.create))
          i.transaction!.id: (i.desired!.title, i.desired!.categoryName),
      };
      expect(titles, {
        'ted': ('Aporte do C6', Category.investmentName),
        'back': ('Resgate para o Nubank', Category.withdrawalName),
      });
    });

    test('a transfer that failed and came back is none', () {
      final p = unpaired([
        tx(
          'failed',
          'c6',
          'DEBIT',
          31.36,
          date: '2026-11-06',
          description: 'Transferência enviada Fulano de Tal',
        ),
        tx(
          'refund',
          'c6',
          'CREDIT',
          31.36,
          date: '2026-11-06',
          description: 'Reembolso de transferência enviada Fulano de Tal',
          hidden: false,
        ),
        tx(
          'sent',
          'c6',
          'DEBIT',
          31.36,
          date: '2026-11-06',
          description: 'Transferência enviada Fulano de Tal',
        ),
      ]);
      expect(p.ofKind(DinzoPlanKind.create).map((i) => i.transaction!.id), [
        'sent',
      ]);
    });

    test('money that stays in the bank and its yield are none', () {
      final p = unpaired([
        invested('rdb', 'Aplicação RDB'),
        invested('acoes', 'Compra de Renda Variável'),
        DinzoTransaction(
          id: 'rend',
          date: '2026-11-08',
          type: 'CREDIT',
          amount: 0.53,
          description: 'Rendimentos',
          accountId: 'nu',
          categoryId: 'proventos',
        ),
      ]);
      expect(p.ofKind(DinzoPlanKind.create), isEmpty);
    });

    test('before the wallets explain each month, it is in their balances', () {
      final okx = invested(
        'okx',
        'Transferência enviada pelo Pix|OKX SERVICOS DIGITAIS',
        date: '2026-10-08',
      );
      expect(unpaired([okx]).ofKind(DinzoPlanKind.create), isEmpty);
      // One already recorded stays.
      final recorded = Record(
        -300,
        'Aporte do Nubank para o OKX',
        Category(
          Category.investmentName,
          categoryType: CategoryType.investment,
        ),
        DateTime.utc(2026, 10, 8, 12),
        walletId: investir,
        dinzoId: 'okx',
      );
      final p = unpaired([okx], linked: [recorded]);
      expect(p.ofKind(DinzoPlanKind.remove), isEmpty);
    });
  });
}
