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
  test('a Pix to a broker is money changing banks: still to invest', () {
    final p = plan([
      tx('out', 'nu', 'DEBIT', 100),
      tx('in', 'btg', 'CREDIT', 100, description: 'TRANSFERÊNCIA VIA PIX'),
    ]);
    expect(p.ofKind(DinzoPlanKind.create), isEmpty);
  });

  test('money back from a broker is none either', () {
    final p = plan([
      tx('out', 'btg', 'DEBIT', 0.5, description: 'Pix'),
      tx('in', 'c6', 'CREDIT', 0.5, description: 'Pix recebido Fulano de Tal'),
    ]);
    expect(p.ofKind(DinzoPlanKind.create), isEmpty);
  });

  test('between two everyday banks it stays hidden', () {
    final p = plan([
      tx('out', 'nu', 'DEBIT', 250),
      tx('in', 'c6', 'CREDIT', 250, description: 'Pix recebido Fulano de Tal'),
      tx('btg', 'btg', 'CREDIT', 250, description: 'TRANSFERÊNCIA VIA PIX'),
    ]);
    expect(p.ofKind(DinzoPlanKind.create), isEmpty);
  });

  test('a purchase of the same amount is an expense, nothing else', () {
    final p = plan([
      tx('loja', 'nu', 'DEBIT', 100, description: 'LOJA', hidden: false),
      tx('in', 'btg', 'CREDIT', 100, description: 'TRANSFERÊNCIA VIA PIX'),
    ]);
    final item = p.ofKind(DinzoPlanKind.create).single;
    expect(item.transaction!.id, 'loja');
    expect(item.categoryType, CategoryType.expense);
  });

  group('orders executed at a broker', () {
    DinzoTransaction btg(
      String id,
      String type,
      double amount,
      String description, {
      String date = '2026-11-06',
    }) => tx(id, 'btg', type, amount, date: date, description: description);

    test('a stock bought is an aporte from the wallet to invest', () {
      final item = plan([
        btg(
          'liq',
          'DEBIT',
          40.25,
          'LIQ BOLSA - VISTA BRUTO - PREGÃO: 04/11/2026 - EXEC.: 85 - S 46780',
        ),
      ]).ofKind(DinzoPlanKind.create).single;
      expect(item.categoryType, CategoryType.investment);
      expect(item.desired!.categoryName, Category.investmentName);
      expect(item.desired!.walletId, investir);
      expect(item.desired!.value, -40.25);
      expect(item.desired!.title, 'Compra de Ações no BTG');
      // An order is paid with nothing: no "Débito".
      expect(item.desired!.tags, ['BTG']);
    });

    test('a stock sold is a withdrawal into the wallet to invest', () {
      final item = plan([
        btg('liq', 'CREDIT', 70, 'LIQ BOLSA - VISTA BRUTO - PREGÃO: 05/11'),
      ]).ofKind(DinzoPlanKind.create).single;
      expect(item.desired!.categoryName, Category.withdrawalName);
      expect(item.desired!.walletId, investir);
      expect(item.desired!.value, 70);
      expect(item.desired!.title, 'Venda de Ações no BTG');
    });

    test('Tesouro bought there, filed under no investment category', () {
      final item = plan([
        btg('td', 'DEBIT', 31.7, 'Compra de Tesouro Direto: NTN-B 15/08/2032'),
      ]).ofKind(DinzoPlanKind.create).single;
      expect(item.desired!.value, -31.7);
      expect(item.desired!.title, 'Compra de Tesouro no BTG');
    });

    test("the account's own yield box is money staying in the account", () {
      final p = plan([
        btg('apl', 'DEBIT', 80.4, 'CONTA REMUNERADA - APLICAÇÃO AUTOMÁTICA'),
        btg('res', 'CREDIT', 22.6, 'CONTA REMUNERADA - RESGATE APLICAÇÃO'),
      ]);
      expect(p.ofKind(DinzoPlanKind.create), isEmpty);
    });

    test('a product chosen as everyday money there is no order', () {
      final p =
          DinzoSyncEngine(
            config: DinzoConfig(startDate: DateTime(2026, 10, 1)),
            accounts: accounts,
            categories: const [],
            defaultWalletId: conta,
            toInvestWalletId: investir,
            isDailyAccount: (a) => !a.id.startsWith('btg'),
            isDailyProduct: (bank, product) => product == 'Tesouro',
          ).plan(
            transactions: [
              btg('td', 'DEBIT', 31.7, 'Compra de Tesouro Direto: NTN-B 2032'),
            ],
            linkedRecords: const [],
            from: DateTime(2026, 10, 1),
            to: DateTime(2026, 11, 30),
          );
      expect(p.ofKind(DinzoPlanKind.create), isEmpty);
    });
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

    test("the broker's side of a Pix to it stays out even if visible", () {
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
      expect(p.ofKind(DinzoPlanKind.create), isEmpty);
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
        'out': 'Pix Enviado',
        'in': 'Pix Recebido',
        'tef': 'Transferência Enviada',
      });
    });
  });

  test('renamed in Dinzo, an entry is still read by what the bank wrote', () {
    DinzoTransaction renamed(
      String id,
      String account,
      String type,
      String bankText,
    ) => DinzoTransaction(
      id: id,
      date: '2026-11-10',
      type: type,
      amount: 50,
      description: 'Nome que eu dei',
      originalDescription: bankText,
      accountId: account,
    );
    final p = plan([
      renamed('fatura', 'nu', 'DEBIT', 'Pagamento de fatura'),
      renamed('div', 'btg', 'CREDIT', 'DIVIDENDOS ITSA4'),
    ]);
    final reasons = {for (final i in p.items) i.transaction!.id: i.skipReason};
    expect(reasons['fatura'], DinzoSkipReason.internalTransfer);
    expect(reasons['div'], DinzoSkipReason.outsideDailyBanks);
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
      bool Function(String bank, String product)? isDailyProduct,
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
          isDailyProduct: isDailyProduct ?? (_, _) => true,
          aportesFrom: DateTime(2026, 11, 1),
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

    test('a transfer to myself whose other side Dinzo does not show is '
        'money changing banks too', () {
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
      expect(p.ofKind(DinzoPlanKind.create), isEmpty);
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
      expect(p.ofKind(DinzoPlanKind.create), isEmpty);
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

    test('the C6 moving its own CDBs is money that stays in the bank', () {
      DinzoTransaction c6(String id, String type, String description) =>
          DinzoTransaction(
            id: id,
            date: '2026-11-17',
            type: type,
            amount: 20.53,
            description: description,
            accountId: 'c6',
            categoryId: 'aplicacao',
          );
      final p = unpaired([
        c6('aplica', 'DEBIT', 'APLICAÇÃO DE CDB'),
        c6('garant', 'DEBIT', 'CDB C6 LIM.GARANT.'),
        c6('volta', 'CREDIT', 'CDB C6 LIM. GARANT.'),
        c6('resgate', 'CREDIT', 'RESGATE DE CDB'),
      ]);
      expect(p.ofKind(DinzoPlanKind.create), isEmpty);

      // CDB in the C6 chosen as an investment: it leaves the wallets.
      final chosen = unpaired(
        [
          c6('aplica', 'DEBIT', 'APLICAÇÃO DE CDB'),
          c6('resgate', 'CREDIT', 'RESGATE DE CDB'),
        ],
        isDailyProduct: (bank, product) => !(bank == 'C6' && product == 'CDB'),
      );
      expect(
        chosen.ofKind(DinzoPlanKind.create).map((i) => i.desired!.title),
        unorderedEquals(['Compra de CDB no C6', 'Resgate de CDB no C6']),
      );
      expect(
        chosen.ofKind(DinzoPlanKind.create).map((i) => i.desired!.walletId),
        everyElement(investir),
      );
    });

    test('any bank moving its own products stays, whatever its wording', () {
      DinzoTransaction bank(String id, String type, String description) =>
          DinzoTransaction(
            id: id,
            date: '2026-11-17',
            type: type,
            amount: 120,
            description: description,
            accountId: 'c6',
            categoryId: 'aplicacao',
          );
      final p = unpaired([
        bank('inter', 'DEBIT', 'APLICACAO CDB DI LIQUIDEZ'),
        bank('lci', 'CREDIT', 'RESG LCI 90D'),
        bank('picpay', 'DEBIT', 'Guardado no Cofrinho'),
        bank('itau', 'DEBIT', 'APLIC AUT MAIS'),
        bank('santander', 'CREDIT', 'RESGATE CONTAMAX'),
      ]);
      expect(p.ofKind(DinzoPlanKind.create), isEmpty);
    });

    test('a Pix to a stock broker is money changing banks, even when Dinzo '
        'files it under Investimentos', () {
      final p = unpaired([
        DinzoTransaction(
          id: 'pix',
          date: '2026-11-17',
          type: 'DEBIT',
          amount: 300,
          description: 'Pix enviado para XP Investimentos CDB',
          accountId: 'c6',
          categoryId: 'aplicacao',
        ),
      ]);
      expect(p.ofKind(DinzoPlanKind.create), isEmpty);
    });

    test('Tesouro bought in an everyday bank follows the choice of the '
        'product there', () {
      final txs = [
        DinzoTransaction(
          id: 'tesouro',
          date: '2026-11-18',
          type: 'DEBIT',
          amount: 9918.49,
          description: 'Aplicação em Tesouro Direto',
          accountId: 'nu',
          categoryId: 'aplicacao',
        ),
      ];
      expect(unpaired(txs).ofKind(DinzoPlanKind.create), isEmpty);
      final chosen = unpaired(
        txs,
        isDailyProduct: (bank, product) => product != 'Tesouro',
      );
      expect(
        chosen.ofKind(DinzoPlanKind.create).single.desired!.value,
        -9918.49,
      );
    });

    test('stocks chosen as an investment in the Nubank: the order leaves the '
        'wallets; an entry that does not say the product stays', () {
      DinzoTransaction nu(String id, String type, double amount, String text) =>
          DinzoTransaction(
            id: id,
            date: '2026-11-10',
            type: type,
            amount: amount,
            description: text,
            accountId: 'nu',
            categoryId: 'aplicacao',
          );
      final txs = [
        nu('ordem', 'DEBIT', 2500.4, 'Compra de Renda Variável'),
        nu('sobra', 'CREDIT', 20.24, 'Valor recebido de Investimentos'),
      ];
      expect(unpaired(txs).ofKind(DinzoPlanKind.create), isEmpty);
      final chosen = unpaired(
        txs,
        isDailyProduct: (bank, product) => product != 'Ações',
      );
      expect(chosen.ofKind(DinzoPlanKind.create).map((i) => i.desired!.value), [
        -2500.4,
      ]);
    });

    test('a Nubank stock order renamed by the user is still an aporte: '
        'the rename goes to the Dinzo description, the bank text stays', () {
      final order = DinzoTransaction(
        id: 'bbas3',
        date: '2026-11-24',
        type: 'DEBIT',
        amount: 1200.5,
        description: 'BBAS3 X 100',
        originalDescription: 'Compra de Renda Variável',
        accountId: 'nu',
      );
      final item = unpaired(
        [order],
        isDailyProduct: (bank, product) => product != 'Ações',
      ).ofKind(DinzoPlanKind.create).single;
      expect(item.categoryType, CategoryType.investment);
      expect(item.desired!.categoryName, Category.investmentName);
      expect(item.desired!.walletId, investir);
      expect(item.desired!.value, -1200.5);
    });

    test('an aporte renamed keeps the name after a sync from scratch: the '
        'name is in Dinzo, the bank text says how it was made', () {
      DinzoTransaction order(String description) => DinzoTransaction(
        id: 'bbas3',
        date: '2026-11-24',
        type: 'DEBIT',
        amount: 1200.5,
        description: description,
        originalDescription: 'Compra de Renda Variável',
        accountId: 'nu',
      );
      String titleOf(DinzoTransaction t) => unpaired(
        [t],
        isDailyProduct: (bank, product) => product != 'Ações',
      ).ofKind(DinzoPlanKind.create).single.desired!.title;
      expect(titleOf(order('BBAS3 X 100')), 'BBAS3 X 100');
      // Not renamed: Dinzo has the bank text in both.
      expect(
        titleOf(order('Compra de Renda Variável')),
        'Compra de Ações no Nubank',
      );
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
