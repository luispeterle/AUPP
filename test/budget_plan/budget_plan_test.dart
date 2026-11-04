import 'package:flutter_test/flutter_test.dart';
import 'package:aupp/budget_plan/budget-plan.dart';
import 'package:aupp/helpers/records-utility-functions.dart';
import 'package:aupp/records/controllers/tab_records_controller.dart';
import 'package:aupp/models/category-type.dart';
import 'package:aupp/models/category.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/models/wallet.dart';
import 'package:aupp/services/service-config.dart';
import 'package:aupp/settings/constants/preferences-keys.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;

void main() {
  setUpAll(() async {
    tz.initializeTimeZones();
    ServiceConfig.localTimezone = 'UTC';
    // The Extrato's "Total": the spending wallets.
    SharedPreferences.setMockInitialValues({
      PreferencesKeys.totalWallets: [
        'Conta corrente',
        'Vale alimentação',
        'Dinheiro em Papel',
      ],
    });
    ServiceConfig.sharedPreferences = await SharedPreferences.getInstance();
  });

  Category expense(String name, {String? parent}) => Category(
    name,
    categoryType: CategoryType.expense,
    parentName: parent,
  );
  final salario = Category('Salário', categoryType: CategoryType.income);

  final conta = Wallet('Conta corrente', id: 1, isDefault: true);
  final vale = Wallet('Vale alimentação', id: 2);
  final investir = Wallet('Investir', id: 3, kind: WalletKind.toInvest);
  final carro = Wallet('Caixinha Carro', id: 4);
  final outra = Wallet('Viagem 2027', id: 6);
  final papel = Wallet('Dinheiro em Papel', id: 7);
  final wallets = {
    for (final w in [conta, vale, investir, carro,  outra, papel])
      w.id!: w,
  };

  Record record(
    double value,
    Category? category,
    int day, {
    int wallet = 1,
    int? to,
    double? transferValue,
    String? dinzoId,
    int month = 10,
  }) => Record(
    value,
    't',
    category,
    DateTime.utc(2026, month, day, 12),
    walletId: wallet,
    transferWalletId: to,
    transferValue: transferValue,
    dinzoId: dinzoId,
  );

  test('defaults: the plan starts at 25/30/15/15/10/5', () {
    final plan = BudgetPlan();
    expect([for (final g in budgetGroups) plan.percentOf(g.id)], [
      25,
      30,
      15,
      15,
      10,
      5,
    ]);
    expect(plan.totalPercent, 100);
  });

  test('an investment entry counts where the money was still to be used', () {
    final plan = BudgetPlan(wallets: {'Investir': 'liberdade'});
    final buy = Category.investment();
    final usage = BudgetPlanUsage.compute(
      plan: plan,
      records: [
        record(-500, buy, 5),
        record(-900, buy, 6, wallet: 3), // already counted going into Investir
      ],
      walletsById: wallets,
      defaultWalletId: 1,
      month: DateTime(2026, 10, 13),
      now: DateTime(2026, 10, 13, 18),
    );
    expect(usage.usedOf('liberdade'), 500);
    expect(usage.realIncome, 0);
  });

  test('defaults: categories and wallets get their group, new ones alert', () {
    final categories = [
      expense('Moradia'),
      expense('Luz', parent: 'Moradia'),
      expense('Restaurante', parent: 'Alimentação'),
      expense('Cursos', parent: 'Educação'),
      expense('Sem categoria'),
      expense('Coisa nova'),
      salario,
    ];
    final plan = BudgetPlan()
      ..assignDefaults(categories, wallets.values, conta.id);

    expect(plan.groupOfCategory('Luz'), 'fixos');
    expect(plan.groupOfCategory('Restaurante'), 'prazeres');
    expect(plan.groupOfCategory('Cursos'), 'conhecimento');
    expect(plan.groupOfCategory('Sem categoria'), outOfBudget);
    expect(plan.groupOfWallet('Investir'), 'liberdade');
    expect(plan.groupOfWallet('Caixinha Carro'), 'metas');

    expect(plan.unassignedCategories(categories).map((c) => c.name), [
      'Coisa nova',
    ]);
    // Base wallets (Conta corrente, Vale alimentação, cash) never need a group.
    expect(plan.unassignedWallets(wallets.values, conta.id).map((w) => w.name), [
      'Viagem 2027',
    ]);
  });

  test('usage: expenses by category, transfers by wallet, net', () {
    final plan = BudgetPlan(
      categories: {'Luz': 'fixos', 'Restaurante': 'prazeres'},
      wallets: {'Investir': 'liberdade', 'Caixinha Carro': 'metas'},
    );
    final records = [
      record(10000, salario, 8),
      record(-300, expense('Luz'), 8),
      record(-120, expense('Restaurante'), 9),
      record(-80, expense('Restaurante'), 10, wallet: 2), // Vale alimentação
      record(-30, expense('Restaurante'), 10, wallet: 7), // cash
      record(-50, expense('Coisa nova'), 10),
      record(-2000, null, 1, to: 3, transferValue: 2000), // → Investir
      record(-500, null, 1, to: 4, transferValue: 500), // → Caixinha Carro
      record(-200, null, 11, wallet: 4, to: 1, transferValue: 200), // back
      record(-100, null, 11, wallet: 3, to: 4, transferValue: 100), // ignored
      record(-1300, null, 2, wallet: 1, to: 2, transferValue: 1300), // base↔base
      record(-999, expense('Luz'), 12, wallet: 3), // other wallet
      record(-400, expense('Luz'), 20, month: 9), // other month
      record(-700, expense('Luz'), 25), // future
    ];
    final usage = BudgetPlanUsage.compute(
      plan: plan,
      records: records,
      walletsById: wallets,
      defaultWalletId: 1,
      month: DateTime(2026, 10, 13),
      now: DateTime(2026, 10, 13, 18),
    );

    expect(usage.realIncome, 10000);
    expect(usage.usedOf('fixos'), 300);
    expect(usage.usedOf('prazeres'), 230);
    expect(usage.usedOf('liberdade'), 2000);
    expect(usage.usedOf('metas'), 300);
    expect(usage.unassigned, 50);
    expect(usage.ratioOf(plan, 'fixos'), closeTo(300 / 3000, 1e-9));
  });

  test('records tagged "Fora do orçamento" count neither as income nor spending', () {
    final plan = BudgetPlan(categories: {'Presentes/Doações': 'prazeres'});
    final presente = expense('Presentes/Doações');
    final pix = Category('Pix de Alguem', categoryType: CategoryType.income);
    final records = [
      record(12000, salario, 8),
      record(-50, presente, 9),
      // Bought for the girlfriend, who paid it back by Pix.
      record(-200, presente, 10)..tags = {outOfBudgetTag},
      record(200, pix, 11)..tags = {outOfBudgetTag},
      record(-300, null, 11, to: 3, transferValue: 300)..tags = {outOfBudgetTag},
    ];
    final usage = BudgetPlanUsage.compute(
      plan: plan,
      records: records,
      walletsById: wallets,
      defaultWalletId: 1,
      month: DateTime(2026, 10, 13),
      now: DateTime(2026, 10, 13, 18),
    );

    expect(usage.realIncome, 12000);
    expect(usage.usedOf('prazeres'), 50);
    expect(usage.usedOf('liberdade'), 0);
    expect(usage.outside, 200);
    expect(usage.recordsOf('prazeres'), hasLength(1));
  });

  test('usage: the estimate is the base until the salary arrives', () {
    final plan = BudgetPlan();
    BudgetPlanUsage usage(List<Record> records) => BudgetPlanUsage.compute(
      plan: plan,
      records: records,
      walletsById: wallets,
      defaultWalletId: 1,
      month: DateTime(2026, 10, 5),
      now: DateTime(2026, 10, 5, 12),
      estimatedIncome: 11000,
    );

    final before = usage([record(200, salario, 2)]);
    expect(before.base, 11000);
    expect(before.baseIsEstimate, isTrue);

    final after = usage([record(200, salario, 2), record(11500, salario, 4)]);
    expect(after.base, 11700);
    expect(after.baseIsEstimate, isFalse);
  });

  test('upcoming recurrences count before their day; estimated income only as the base', () {
    final plan = BudgetPlan(
      categories: {'Aluguel': 'fixos', 'Restaurante': 'prazeres'},
      wallets: {'Caixinha Carro': 'metas'},
    );
    const est = {'Estimativa'};
    Record upcoming(Record r) => r..isFutureRecord = true;
    final usage = BudgetPlanUsage.compute(
      plan: plan,
      records: [
        record(-300, expense('Restaurante'), 10),
        upcoming(record(-1000, expense('Aluguel'), 20)..tags = est),
        upcoming(record(11000, salario, 28)..tags = est),
        // Monthly transfer to a caixinha (not an estimate).
        upcoming(record(-500, null, 25, to: 4, transferValue: 500)),
        record(-80, expense('Restaurante'), 30), // stored, still ahead
      ],
      walletsById: wallets,
      defaultWalletId: 1,
      month: DateTime(2026, 10),
      now: DateTime(2026, 10, 13, 18),
      estimatedIncome: 11000,
    );

    expect(usage.usedOf('fixos'), 1000);
    expect(usage.usedOf('metas'), 500);
    expect(usage.usedOf('prazeres'), 300);
    expect(usage.realIncome, 0);
    expect(usage.base, 11000);
  });

  test('period: each month keeps its own 100%, summed over the range', () {
    final plan = BudgetPlan(categories: {'Luz': 'fixos'});
    final records = [
      record(9000, salario, 5, month: 9),
      record(-400, expense('Luz'), 20, month: 9),
      record(200, salario, 2), // October: salary not in yet
      record(-300, expense('Luz'), 8),
      record(-100, expense('Luz'), 30, month: 8), // before the range
    ];
    final now = DateTime(2026, 10, 13, 18);
    BudgetPlanUsage month(int m, {double estimate = 0}) =>
        BudgetPlanUsage.compute(
          plan: plan,
          records: records,
          walletsById: wallets,
          defaultWalletId: 1,
          month: DateTime(2026, m),
          now: now,
          from: DateTime(2026, 9, 1),
          to: DateTime(2026, 12, 31, 23, 59, 59),
          estimatedIncome: estimate,
        );
    final usage = BudgetPlanUsage.combine([
      month(9),
      month(10, estimate: 11000),
    ]);

    // September's real income + October's estimate (salary not in yet).
    expect(usage.base, 20000);
    expect(usage.baseIsEstimate, isTrue);
    expect(usage.realIncome, 9200);
    expect(usage.usedOf('fixos'), 700);
    expect(usage.recordsOf('fixos'), hasLength(2));

    // A range inside the month only counts what falls in it.
    final firstWeek = BudgetPlanUsage.compute(
      plan: plan,
      records: records,
      walletsById: wallets,
      defaultWalletId: 1,
      month: DateTime(2026, 10),
      now: now,
      from: DateTime(2026, 10, 1),
      to: DateTime(2026, 10, 7, 23, 59, 59),
    );
    expect(firstWeek.usedOf('fixos'), 0);
    expect(firstWeek.realIncome, 200);
  });

  test('group records match the exact subcategory, never the parent', () {
    final plan = BudgetPlan(
      categories: {'Moradia': 'fixos', 'Luz': 'fixos', 'Móveis': 'conforto'},
      wallets: {'Caixinha Carro': 'metas'},
    );
    final luz = record(-300, expense('Luz', parent: 'Moradia'), 8);
    final moveis = record(-900, expense('Móveis', parent: 'Moradia'), 9);
    final moradia = record(-50, expense('Moradia'), 9);
    final usage = BudgetPlanUsage.compute(
      plan: plan,
      records: [
        luz,
        moveis,
        moradia,
        record(-500, null, 1, to: 4, transferValue: 500, dinzoId: null),
        record(-200, null, 11, wallet: 4, to: 1, transferValue: 200),
      ],
      walletsById: wallets,
      defaultWalletId: 1,
      month: DateTime(2026, 10, 13),
      now: DateTime(2026, 10, 13, 18),
    );

    expect(usage.recordsOf('fixos'), [luz, moradia]);
    expect(usage.recordsOf('conforto'), [moveis]);
    // Transfers show up as view-only expenses of the wallet, netted.
    final metas = usage.recordsOf('metas');
    expect(metas.map((r) => r.category?.name), ['Caixinha Carro', 'Caixinha Carro']);
    expect(metas.map((r) => r.value), [-500, 200]);
    expect(metas.every((r) => !r.isTransfer), isTrue);
    expect(metas.every((r) => r.category?.categoryType == CategoryType.expense),
        isTrue);
  });

  test('a saved plan picks up new categories that have a known default', () {
    final plan = BudgetPlan(categories: {'Luz': 'fixos'});
    final changed = plan.assignDefaults(
      [
        expense('Luz', parent: 'Moradia'),
        expense('Diarista', parent: 'Moradia'),
        expense('Coisa nova'),
      ],
      const [],
      1,
    );
    expect(changed, isTrue);
    expect(plan.groupOfCategory('Diarista'), 'conforto');
    expect(plan.groupOfCategory('Coisa nova'), isNull);
    expect(plan.assignDefaults([expense('Diarista')], const [], 1), isFalse);
  });

  test('plan survives the JSON round trip', () {
    final plan = BudgetPlan(
      percents: {'liberdade': 40, 'fixos': 60},
      categories: {'Luz': 'fixos'},
      wallets: {'Investir': 'liberdade'},
    );
    final back = BudgetPlan.decode(plan.encode())!;
    expect(back.percentOf('liberdade'), 40);
    expect(back.percentOf('conforto'), 0);
    expect(back.groupOfCategory('Luz'), 'fixos');
    expect(back.groupOfWallet(' Investir '), 'liberdade');
    expect(BudgetPlan.decode('not json'), isNull);
  });

  test('income left out of the 100% (a loan) is not the month\'s income', () {
    final emprestimo = Category(
      'Empréstimo recebido',
      categoryType: CategoryType.income,
    );
    final plan = BudgetPlan(incomeOut: {'Empréstimo recebido'});
    final usage = BudgetPlanUsage.compute(
      plan: plan,
      records: [record(10000, salario, 8), record(7000, emprestimo, 9)],
      walletsById: wallets,
      defaultWalletId: 1,
      month: DateTime(2026, 10, 13),
      now: DateTime(2026, 10, 13, 18),
    );
    expect(usage.realIncome, 10000);
    final back = BudgetPlan.decode(plan.encode())!;
    expect(back.countsAsIncome('Empréstimo recebido'), isFalse);
    expect(back.countsAsIncome('Salário'), isTrue);
  });

  test('money set aside: invested in Liberdade Financeira, else saved', () {
    final plan = BudgetPlan(
      wallets: {'Investir': 'liberdade', 'Caixinha Carro': 'metas'},
    );
    expect(plan.isInvestmentWallet('Investir'), isTrue);
    expect(plan.isInvestmentWallet('Caixinha Carro'), isFalse);
    expect(plan.isInvestmentWallet('Sem grupo'), isFalse);
    // Money leaving the counted wallets: invested or saved by the budget
    // group of the destination; coming back: taken.
    final day = DateTime.utc(2026, 10, 10, 12);
    Record move(double v, int from, int to) => Record(v, 't', null, day,
        walletId: from, transferWalletId: to, transferValue: v.abs());
    final split = SetAsideSplit(
      TabRecordsController.applyTransferAwareWalletFilter([
        move(-2000, 1, 3), // → Investir
        move(-500, 1, 4), // → Caixinha Carro
        move(-200, 4, 1), // back from the caixinha
        move(-100, 3, 4), // between two others: nothing
      ], {1}),
      (id) => id != null && plan.isInvestmentWallet(wallets[id]!.name),
    );
    expect(split.invested.map((r) => r.value), [-2000]);
    expect(split.saved.map((r) => r.value), [-500]);
    expect(split.taken.map((r) => r.value), [200]);
  });
}
