import 'package:aupp/accounts/money-accounts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aupp/dinzo/dinzo-config.dart';
import 'package:aupp/dinzo/dinzo-models.dart';
import 'package:aupp/dinzo/dinzo-sync-engine.dart';
import 'package:aupp/models/category-type.dart';
import 'package:aupp/models/category.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/services/service-config.dart';
import 'package:timezone/data/latest_all.dart' as tz;

const livre = 1;
const caixinhaCarro = 4;

final accounts = [
  DinzoAccount(id: 'card', type: 'CREDIT', title: 'Cartão'),
  DinzoAccount(id: 'pf', type: 'BANK', title: 'Conta PF'),
  DinzoAccount(id: 'pj', type: 'BANK', title: 'Conta PJ'),
];

final categories = [
  DinzoCategory(id: 'moradia', title: 'Moradia'),
  DinzoCategory(id: 'luz', title: 'Luz', parentId: 'moradia'),
  DinzoCategory(id: 'super', title: 'Supermercado'),
  DinzoCategory(id: 'trabalho', title: 'Trabalho'),
  DinzoCategory(id: 'invest', title: 'Investimentos'),
  DinzoCategory(id: 'proventos', title: 'Proventos', parentId: 'invest'),
  DinzoCategory(id: 'juros', title: 'Juros', parentId: 'invest'),
];

DinzoTransaction tx(
  String id, {
  String date = '2026-10-05',
  String type = 'DEBIT',
  double amount = 10,
  String description = 'LOJA',
  String account = 'card',
  String? category,
  int? current,
  int? total,
  bool hidden = false,
  bool projected = false,
}) => DinzoTransaction(
  id: id,
  date: date,
  type: type,
  amount: amount,
  description: description,
  accountId: account,
  categoryId: category,
  installmentCurrent: current,
  installmentTotal: total,
  hidden: hidden,
  projected: projected,
);

DinzoConfig config() => DinzoConfig(
  startDate: DateTime(2026, 10, 1),
  selfIdentifiers: ['Fulano de Tal', '12.345.678'],
  categoryMap: {
    DinzoConfig.categoryKey('moradia', CategoryType.expense):
        'Custos de Moradia',
    DinzoConfig.categoryKey('super', CategoryType.expense): 'Mercado',
    DinzoConfig.categoryKey('trabalho', CategoryType.income): 'Salário',
  },
);

DinzoSyncEngine engine([DinzoConfig? c]) => DinzoSyncEngine(
  config: c ?? config(),
  accounts: accounts,
  categories: categories,
  defaultWalletId: livre,
);

DinzoSyncPlan plan(
  List<DinzoTransaction> txs, {
  List<Record> linked = const [],
  DinzoConfig? c,
}) => engine(c).plan(
  transactions: txs,
  linkedRecords: linked,
  from: DateTime(2026, 9, 1),
  to: DateTime(2026, 10, 31),
);

/// A record as the apply step writes it, optionally with merge-screen
/// overrides in [applied].
Record imported(DinzoTransaction t, {DinzoSnapshot? applied, DinzoConfig? c}) {
  final source = engine(c).sourceFor(t);
  final a = applied ?? source;
  final date = DateTime.parse(a.date);
  return Record(
    a.value,
    a.title,
    a.categoryName == null
        ? null
        : Category(
            a.categoryName,
            categoryType: a.value < 0
                ? CategoryType.expense
                : CategoryType.income,
          ),
    DateTime.utc(date.year, date.month, date.day, 12),
    id: t.id.hashCode,
    walletId: a.walletId,
    tags: a.tags.toSet(),
    dinzoId: t.id,
    dinzoSnapshot: DinzoLink(source, a).toJsonString(),
  );
}

DinzoSnapshot withChanges(
  DinzoSnapshot s, {
  String? title,
  double? value,
  String? category,
  int? wallet,
}) => DinzoSnapshot(
  title: title ?? s.title,
  value: value ?? s.value,
  date: s.date,
  categoryName: category ?? s.categoryName,
  walletId: wallet ?? s.walletId,
  tags: s.tags,
  accountId: s.accountId,
);

void main() {
  setUpAll(() {
    tz.initializeTimeZones();
    ServiceConfig.localTimezone = 'UTC';
  });

  group('what gets imported', () {
    test('installment 1/N becomes one record with the full amount', () {
      final p = plan([tx('a', amount: 163.08, current: 1, total: 10)]);
      final item = p.ofKind(DinzoPlanKind.create).single;
      expect(item.desired!.value, -1630.80);
      expect(item.desired!.date, '2026-10-05');
      expect(item.description, contains('10x de 163,08'));
    });

    test('a later installment gives the exact total of the purchase', () {
      // 12x of 323,92: the bank puts the leftover cents in the first one.
      final p = plan([
        tx('a', date: '2026-10-05', amount: 27.03, current: 1, total: 12),
        tx('a2', date: '2026-11-05', amount: 26.99, current: 2, total: 12),
      ]);
      expect(p.ofKind(DinzoPlanKind.create).single.desired!.value, -323.92);
    });

    test('without a later installment the total is estimated', () {
      final p = plan([tx('a', amount: 27.03, current: 1, total: 12)]);
      expect(p.ofKind(DinzoPlanKind.create).single.desired!.value, -324.36);
    });

    test('the exact total updates a record imported with the estimate', () {
      final first = tx('a', amount: 27.03, current: 1, total: 12);
      final p = plan(
        [
          first,
          tx('a2', date: '2026-10-30', amount: 26.99, current: 2, total: 12),
        ],
        linked: [imported(first)],
      );
      final item = p.items.firstWhere((i) => i.transaction?.id == 'a');
      expect(item.kind, DinzoPlanKind.update);
      expect(item.desired!.value, -323.92);
    });

    test('installments of other purchases are not mixed in', () {
      final p = plan([
        tx('a', amount: 57.16, current: 1, total: 6),
        // Another store, another card, another plan, far off in value.
        tx('x', description: 'OUTRA', amount: 57.12, current: 2, total: 6,
            date: '2026-11-05'),
        tx('y', account: 'pf', amount: 57.12, current: 2, total: 6,
            date: '2026-11-05'),
        tx('z', amount: 57.12, current: 2, total: 3, date: '2026-11-05'),
        tx('w', amount: 50, current: 2, total: 6, date: '2026-11-05'),
      ]);
      final first = p.items.firstWhere((i) => i.transaction?.id == 'a');
      expect(first.desired!.value, -342.96);
    });

    test('interest charged on a card is an expense, not an investment', () {
      final p = plan([
        tx('j', category: 'juros', amount: 7.44,
            description: 'Juros de dívida encerrada'),
      ]);
      expect(p.items.single.kind, DinzoPlanKind.create);
      expect(p.items.single.desired!.value, -7.44);
    });

    test('installments 2..N never create records', () {
      final p = plan([tx('b', current: 3, total: 10)]);
      expect(p.ofKind(DinzoPlanKind.create), isEmpty);
      expect(p.items.single.skipReason, DinzoSkipReason.laterInstallment);
    });

    test('transactions before the start date are left out entirely', () {
      final p = plan([tx('c', date: '2026-09-30', current: 1, total: 12)]);
      expect(p.items, isEmpty);
    });

    test('projections are left out entirely', () {
      expect(plan([tx('d', projected: true)]).items, isEmpty);
    });

    test('hidden transactions are skipped', () {
      final p = plan([tx('e', hidden: true, description: 'Aplicação RDB')]);
      expect(p.items.single.skipReason, DinzoSkipReason.hidden);
    });

    test('transfers to and from the user come in marked, a bill is left out',
        () {
      final p = plan([
        tx(
          'f',
          account: 'pj',
          description: 'Transferência enviada pelo Pix|Fulano de Tal',
        ),
        tx(
          'g',
          account: 'pf',
          type: 'CREDIT',
          description: 'Transferência Recebida|12.345.678 FULANO',
        ),
        tx('h', account: 'pf', description: 'Pagamento efetuado|BANCO C6 S.A.'),
      ]);
      final byId = {for (final i in p.items) i.transaction!.id: i};
      for (final id in ['f', 'g']) {
        expect(byId[id]!.kind, DinzoPlanKind.create);
        expect(byId[id]!.source!.tags, contains(MoneyAccounts.transferTag));
      }
      expect(byId['h']!.skipReason, DinzoSkipReason.internalTransfer);
    });

    test('a card bill paid from a bank account is internal on both sides', () {
      final p = plan([
        tx(
          'pay',
          account: 'pf',
          amount: 5628.89,
          description: 'C6 BANK',
          date: '2026-10-08',
        ),
        tx(
          'inc',
          account: 'card',
          type: 'CREDIT',
          amount: 5628.89,
          description: 'Inclusao de Pagamento Ciclo Corrente',
        ),
      ]);
      expect(
        p.items.map((i) => i.skipReason),
        everyElement(DinzoSkipReason.internalTransfer),
      );
    });

    test('a refund on the card is still imported', () {
      final p = plan([
        tx(
          'ref',
          account: 'card',
          type: 'CREDIT',
          amount: 81.54,
          description: 'Refund',
        ),
      ]);
      expect(p.ofKind(DinzoPlanKind.create), hasLength(1));
    });

    test(
      'investment moves and yield are left to the free-wallet adjustment',
      () {
        final p = plan([
          tx(
            'y1',
            account: 'pf',
            type: 'CREDIT',
            amount: 0.29,
            description: 'Rendimentos',
            category: 'proventos',
          ),
          tx(
            'y2',
            account: 'pf',
            type: 'CREDIT',
            amount: 5235.45,
            description: 'Valor recebido de Investimentos',
          ),
          tx(
            'y3',
            account: 'pf',
            amount: 52.98,
            description: 'Valor transferido para Investimentos',
          ),
          // Nubank stock order: Dinzo files it under Compras.
          tx(
            'y4',
            account: 'pf',
            amount: 2714.79,
            description: 'Compra de Renda Variável',
            category: 'super',
          ),
        ]);
        expect(
          p.items.map((i) => i.skipReason),
          everyElement(DinzoSkipReason.investment),
        );
      },
    );

    test('cashback is income, not an investment move', () {
      final p = plan([
        tx(
          'cb',
          account: 'pf',
          type: 'CREDIT',
          amount: 1.04,
          description: 'Resgate de Cashback',
        ),
      ]);
      expect(p.ofKind(DinzoPlanKind.create), hasLength(1));
    });

    test('a name only matches when it opens the counterparty', () {
      final c = config()..selfIdentifiers.add('Maria Souza');
      final p = plan([
        tx(
          'self',
          account: 'pf',
          type: 'CREDIT',
          description: 'Transferência enviada pelo Pix|Maria Souza',
        ),
        tx(
          'dad',
          account: 'pf',
          type: 'CREDIT',
          description: 'Transferência Recebida|JOSE MARIA SOUZA',
        ),
        tx(
          'doc',
          account: 'pf',
          type: 'CREDIT',
          description: 'Pix recebido de 12.345.678 OUTRO NOME',
        ),
      ], c: c);
      final byId = {for (final i in p.items) i.transaction!.id: i};
      bool own(String id) =>
          byId[id]!.source!.tags.contains(MoneyAccounts.transferTag);
      expect(own('self'), isTrue);
      expect(own('dad'), isFalse);
      expect(own('doc'), isTrue);
    });

    test('a Pix to someone else is a normal expense', () {
      final p = plan([
        tx('i', account: 'pf', description: 'Pix enviado Outra Pessoa'),
      ]);
      expect(p.ofKind(DinzoPlanKind.create), hasLength(1));
    });

    test('user-ignored transactions are skipped', () {
      final c = config()..ignoredIds.add('j');
      final p = plan([tx('j')], c: c);
      expect(p.items.single.skipReason, DinzoSkipReason.ignoredByUser);
    });
  });

  group('how records look', () {
    test('Nubank "Kind|Counterparty" keeps the counterparty as title', () {
      expect(
        DinzoSyncEngine.cleanTitle(
          'Transferência enviada pelo Pix|CERSUL - COOPE',
        ),
        'CERSUL - COOPE',
      );
      expect(
        DinzoSyncEngine.cleanTitle('POSTO   ROMANO  LTDA'),
        'POSTO ROMANO LTDA',
      );
    });

    test('credits are positive income, debits negative expenses', () {
      final p = plan([
        tx(
          'k',
          account: 'pj',
          type: 'CREDIT',
          amount: 9000,
          category: 'trabalho',
        ),
      ]);
      final item = p.ofKind(DinzoPlanKind.create).single;
      expect(item.desired!.value, 9000);
      expect(item.categoryType, CategoryType.income);
      expect(item.desired!.categoryName, 'Salário');
    });

    test('a mapped parent category covers its subcategories', () {
      final p = plan([tx('l', category: 'luz')]);
      expect(p.items.single.desired!.categoryName, 'Custos de Moradia');
    });

    test('the record gets the Dinzo subcategory; AUPP knows its parent', () {
      final e = engine(DinzoConfig(startDate: DateTime(2026, 10, 1)));
      final p = e.plan(
        transactions: [tx('m', category: 'luz')],
        linkedRecords: const [],
        from: DateTime(2026, 9, 1),
        to: DateTime(2026, 10, 31),
      );
      expect(p.items.single.desired!.categoryName, 'Luz');
      expect(e.parentTitles['Luz'], 'Moradia');
    });

    test('tags tell the bank and how the money moved', () {
      final e = DinzoSyncEngine(
        config: config(),
        accounts: [
          DinzoAccount(
            id: 'c6card',
            type: 'CREDIT',
            title: 'BANDEIRADO',
            connectorName: 'C6 Bank',
          ),
          DinzoAccount(
            id: 'c6',
            type: 'BANK',
            title: 'C6 BANK',
            connectorName: 'C6 Bank',
          ),
          DinzoAccount(
            id: 'nupj',
            type: 'BANK',
            title: 'Nu',
            connectorName: 'Nubank Empresas',
          ),
          DinzoAccount(
            id: 'mp',
            type: 'BANK',
            title: 'MP',
            connectorName: 'Mercado Pago',
          ),
        ],
        categories: categories,
        defaultWalletId: livre,
      );
      List<String> tagsOf(String account, String description) =>
          e.syncedTagsFor(tx('x', account: account, description: description));
      expect(tagsOf('c6card', 'POSTO ROMANO'), ['C6', 'Crédito']);
      expect(tagsOf('nupj', 'Transferência enviada pelo Pix|CERSUL'), [
        'Nubank PJ',
        'Pix',
      ]);
      expect(tagsOf('mp', 'Pagamento de conta LOJAS'), [
        'Boleto',
        'Mercado Pago',
      ]);
      expect(tagsOf('nupj', 'Transferência Recebida|LOJAS EXEMPLO'), [
        'Nubank PJ',
        'Transferência',
      ]);
      expect(tagsOf('c6', 'CLINICA DR. SALVARO'), ['C6', 'Débito']);
    });

    test('a bank/method change in Dinzo updates the tags', () {
      final t = tx('tg', description: 'LOJA');
      final r = imported(t);
      final item = plan(
        [tx('tg', account: 'pf', description: 'LOJA')],
        linked: [r],
      ).items.single;
      expect(item.kind, DinzoPlanKind.update);
      expect(item.desired!.tags, isNot(contains('Crédito')));
    });

    test('transactions Dinzo has not categorised go to "Sem categoria"', () {
      final p = plan([tx('m2')]);
      expect(
        p.items.single.desired!.categoryName,
        DinzoSyncEngine.uncategorized,
      );
    });

    test('a merchant rule wins over the category map, wallet included', () {
      final c = config()
        ..merchantRules['oficina'] = const DinzoMerchantRule(
          categoryName: 'Despesas Carro',
          walletId: caixinhaCarro,
        );
      final p = plan([
        tx('n', description: 'OFICINA 123', category: 'super'),
      ], c: c);
      final d = p.items.single.desired!;
      expect(d.categoryName, 'Despesas Carro');
      expect(d.walletId, caixinhaCarro);
    });

    test('new records go to the default wallet', () {
      expect(plan([tx('o')]).items.single.desired!.walletId, livre);
    });
  });

  group('syncing again', () {
    test('nothing changed → unchanged', () {
      final t = tx('p', category: 'super');
      final p = plan([t], linked: [imported(t)]);
      expect(p.items.single.kind, DinzoPlanKind.unchanged);
    });

    test('merge-screen choices survive a later sync', () {
      final t = tx('q');
      final source = engine().sourceFor(t);
      final r = imported(
        t,
        applied: withChanges(
          source,
          category: 'Despesas Carro',
          wallet: caixinhaCarro,
        ),
      );
      expect(plan([t], linked: [r]).items.single.kind, DinzoPlanKind.unchanged);
    });

    test('a Dinzo change on an untouched field updates only that field', () {
      final t = tx('r', amount: 10);
      final source = engine().sourceFor(t);
      final r = imported(
        t,
        applied: withChanges(
          source,
          category: 'Despesas Carro',
          wallet: caixinhaCarro,
        ),
      );
      final p = plan([tx('r', amount: 12)], linked: [r]);
      final item = p.items.single;
      expect(item.kind, DinzoPlanKind.update);
      expect(item.selected, isTrue);
      expect(item.desired!.value, -12);
      expect(item.desired!.categoryName, 'Despesas Carro');
      expect(item.desired!.walletId, caixinhaCarro);
    });

    test('a Dinzo change on a locally edited field is a conflict, local wins by default', () {
      final t = tx('s', category: 'super');
      final r = imported(t);
      r.category = Category('Restaurante', categoryType: CategoryType.expense);
      final p = plan([tx('s', category: 'luz')], linked: [r]);
      final item = p.items.single;
      expect(item.kind, DinzoPlanKind.conflict);
      expect(item.selected, isFalse);
    });

    test('a local edit with no Dinzo change stays untouched', () {
      final t = tx('t', category: 'super');
      final r = imported(t);
      r.title = 'Mercado do bairro';
      expect(plan([t], linked: [r]).items.single.kind, DinzoPlanKind.unchanged);
    });

    test('a wallet changed on the record survives Dinzo updates', () {
      final t = tx('w1', amount: 10);
      final r = imported(t);
      r.walletId = caixinhaCarro; // paid by the caixinha, set on the record
      final item = plan([tx('w1', amount: 15)], linked: [r]).items.single;
      expect(item.kind, DinzoPlanKind.update);
      expect(item.selected, isTrue);
      expect(item.desired!.value, -15);
      expect(item.desired!.walletId, caixinhaCarro);
    });

    test('categorising in Dinzo later updates the record', () {
      final c = DinzoConfig(startDate: DateTime(2026, 10, 1));
      final r = imported(tx('u'), c: c);
      final item = plan(
        [tx('u', category: 'luz')],
        linked: [r],
        c: c,
      ).items.single;
      expect(item.kind, DinzoPlanKind.update);
      expect(item.desired!.categoryName, 'Luz');
    });
  });

  group('removals', () {
    test('a linked transaction missing from the window is removed', () {
      final r = imported(tx('v', date: '2026-10-03'));
      final item = plan([], linked: [r]).items.single;
      expect(item.kind, DinzoPlanKind.remove);
      expect(item.selected, isTrue);
    });

    test('records outside the fetched window are left alone', () {
      final r = imported(tx('w', date: '2026-08-15'));
      expect(plan([], linked: [r]).items, isEmpty);
    });

    test('a locally edited record proposed for removal starts unselected', () {
      final r = imported(tx('x'));
      r.title = 'editado';
      expect(plan([], linked: [r]).items.single.selected, isFalse);
    });

    test('a linked transaction that became hidden is removed', () {
      final r = imported(tx('y'));
      final item = plan([tx('y', hidden: true)], linked: [r]).items.single;
      expect(item.kind, DinzoPlanKind.remove);
      expect(item.skipReason, DinzoSkipReason.hidden);
    });

    test('a pending purchase re-issued under a new id is an update, not delete + create', () {
      final r = imported(tx('old', date: '2026-10-08', amount: 115.40));
      final p = plan(
        [tx('new', date: '2026-10-10', amount: 116.10)],
        linked: [r],
      );
      final item = p.items.single;
      expect(item.kind, DinzoPlanKind.update);
      expect(item.existing!.dinzoId, 'old');
      expect(item.transaction!.id, 'new');
      expect(item.desired!.value, -116.10);
    });
  });
}
