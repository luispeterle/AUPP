import 'package:flutter_test/flutter_test.dart';
import 'package:aupp/helpers/records-utility-functions.dart';
import 'package:aupp/models/category-type.dart';
import 'package:aupp/models/category.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/models/records-per-day.dart';
import 'package:aupp/records/controllers/tab_records_controller.dart';
import 'package:aupp/services/service-config.dart';
import 'package:timezone/data/latest_all.dart' as tz;

const contaCorrente = 1;
const caixinha = 2;

void main() {
  setUpAll(() {
    tz.initializeTimeZones();
    ServiceConfig.localTimezone = 'UTC';
  });

  final day = DateTime.utc(2026, 10, 10, 12);
  final mercado = Category('Mercado', categoryType: CategoryType.expense);
  final salario = Category('Salário', categoryType: CategoryType.income);

  List<Record?> records() => [
    Record(-100, 'Mercado', mercado, day, walletId: contaCorrente),
    Record(1000, 'Salário', salario, day, walletId: contaCorrente),
    // Conta corrente → caixinha (virtual move)
    Record(
      -300,
      'Caixinha',
      null,
      day,
      walletId: contaCorrente,
      transferWalletId: caixinha,
    ),
  ];

  RecordsPerDay perDay(List<Record?> rs) =>
      RecordsPerDay(DateTime(2026, 10, 10), records: rs);

  test('all wallets: a move between own wallets is not spending', () {
    final rs = perDay(records());
    expect(rs.expenses, -100);
    expect(rs.income, 1000);
    expect(balanceRelevantRecords(records()), hasLength(2));
  });

  test('only Conta corrente: money sent to a caixinha is set aside, not spent',
      () {
    final filtered = TabRecordsController.applyTransferAwareWalletFilter(
      records(),
      {contaCorrente},
    );
    final rs = perDay(filtered);
    expect(rs.expenses, -100);
    expect(rs.income, 1000);
    expect(rs.setAside, -300);
    expect(rs.balance, 600);
    expect(balanceRelevantRecords(filtered), hasLength(3));
  });

  test('only the caixinha: money it received is taken in, not income', () {
    final filtered = TabRecordsController.applyTransferAwareWalletFilter(
      records(),
      {caixinha},
    );
    final rs = perDay(filtered);
    expect(rs.income, 0);
    expect(rs.expenses, 0);
    expect(rs.setAside, 300);
    expect(rs.balance, 300);
  });

  test('both sides selected: still nets to zero', () {
    final filtered = TabRecordsController.applyTransferAwareWalletFilter(
      records(),
      {contaCorrente, caixinha},
    );
    expect(perDay(filtered).expenses, -100);
  });

  test('a purchase paid partly with a caixinha: real and full expenses', () {
    final compra = Category('Carro', categoryType: CategoryType.expense);
    List<Record?> rs() => [
      Record(-1000, 'Carro', compra, day,
          walletId: contaCorrente, dinzoId: 'p'),
      Record(-600, 'Carro · Caixinha', null, day,
          walletId: caixinha,
          transferWalletId: contaCorrente,
          dinzoId: '${Record.splitPrefix}p'),
    ];
    double sum(Iterable<Record> rs) =>
        rs.fold(0.0, (t, r) => t + (r.value ?? 0));
    final onlyConta =
        TabRecordsController.applyTransferAwareWalletFilter(rs(), {contaCorrente});
    expect(sum(realExpenses(onlyConta)), -400); // what the month paid
    expect(perDay(onlyConta).expenses, -1000); // full, shown small
    expect(perDay(onlyConta).income, 0);
    expect(perDay(onlyConta).balance, -400);
    expect(purchaseParts(onlyConta), hasLength(1));
    // The caixinha's part is "Retirado": income − full − set aside + taken
    // back = balance.
    final split = SetAsideSplit(onlyConta, (_) => false);
    expect(sum(split.taken), 600);
    expect(0 - 1000 - sum(split.saved) + sum(split.taken),
        perDay(onlyConta).balance);
    // Both wallets counted: the caixinha's money is spending money too.
    final both = TabRecordsController.applyTransferAwareWalletFilter(
        rs(), {contaCorrente, caixinha});
    expect(sum(realExpenses(both)), -1000);
    expect(purchaseParts(both), isEmpty);
  });
}
