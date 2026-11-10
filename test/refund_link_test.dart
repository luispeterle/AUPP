import 'package:aupp/accounts/money-accounts.dart';
import 'package:aupp/models/category-type.dart';
import 'package:aupp/models/category.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/models/wallet.dart';
import 'package:aupp/records/refund-link.dart';
import 'package:aupp/services/service-config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest_all.dart' as tz;

import 'helpers/test_database.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tz.initializeTimeZones();
    ServiceConfig.localTimezone = 'UTC';
  });

  late int conta;

  setUp(() async {
    await TestDatabaseHelper.setupTestDatabase();
    conta = (await ServiceConfig.database.getDefaultWallet())!.id!;
    await RefundLink.loadAccount();
  });

  final rent = Category('Aluguel', categoryType: CategoryType.expense);
  final other = Category('Outros', categoryType: CategoryType.income);

  Record record(
    double value,
    String title,
    Category c,
    int day, {
    int? id,
    int? wallet,
    Set<String>? tags,
  }) => Record(
    value,
    title,
    c,
    DateTime.utc(2026, 5, day, 12),
    id: id,
    walletId: wallet ?? conta,
    tags: tags,
  );

  group('suggestions', () {
    test('an income named like a refund, with an expense of the same amount',
        () {
      final paid = record(-800, 'Aluguel', rent, 7, id: 1);
      final failed = record(-800, 'Aluguel', rent, 7, id: 2);
      final refund = record(800, 'Estorno Aluguel', other, 7, id: 3);
      final salary = record(800, 'Pix recebido', other, 7, id: 4);
      RefundLink.markSuggestions([paid, failed, refund, salary]);
      expect(refund.refundSuggestion, isNotNull);
      expect(refund.refundSuggestion!.value, -800);
      // Not named like a refund: nothing is suggested.
      expect(salary.refundSuggestion, isNull);
    });

    test('never an expense after the refund nor long before it', () {
      final later = record(-50, 'Shopee', rent, 20, id: 1);
      final refund = record(50, 'Reembolso Shopee', other, 10, id: 2);
      RefundLink.markSuggestions([later, refund]);
      expect(refund.refundSuggestion, isNull);
    });

    test('one expense per refund', () {
      final fee = record(-98, 'Tarifa', rent, 1, id: 1);
      final a = record(98, 'Estorno Tarifa', other, 1, id: 2);
      final b = record(98, 'Estorno Tarifa', other, 2, id: 3);
      RefundLink.markSuggestions([fee, a, b]);
      expect(
        [a, b].where((r) => r.refundSuggestion != null),
        hasLength(1),
      );
    });

    test('only the Conta corrente, never a Pix between my accounts', () async {
      final papel = await ServiceConfig.database.addWallet(
        Wallet('Dinheiro em Papel', sortOrder: 1),
      );
      final cash = record(-50, 'Mercado', rent, 1, id: 1, wallet: papel);
      final own = record(
        -50,
        'Fulano de Tal',
        rent,
        1,
        id: 2,
        tags: {MoneyAccounts.transferTag},
      );
      final refund = record(50, 'Estorno Mercado', other, 2, id: 3);
      RefundLink.markSuggestions([cash, own, refund]);
      expect(refund.refundSuggestion, isNull);
      expect(RefundLink.canBeUndone(cash), isFalse);
      expect(RefundLink.canBeUndone(own), isFalse);
      final voucher = record(50, 'Estorno', other, 2, id: 4, wallet: papel);
      expect(RefundLink.canBeRefund(voucher), isFalse);
    });

    test('a linked refund is not suggested again', () {
      final fee = record(-98, 'Tarifa', rent, 1, id: 1);
      final refund = record(98, 'Estorno Tarifa', other, 1, id: 2)
        ..refundLink = '{}';
      RefundLink.markSuggestions([fee, refund]);
      expect(refund.refundSuggestion, isNull);
    });
  });

  group('linking', () {
    Future<(Record, Record)> stored() async {
      final db = ServiceConfig.database;
      for (final c in [rent, other]) {
        if (await db.getCategory(c.name!, c.categoryType!) == null) {
          await db.addCategory(c);
        }
      }
      final expense = await db.getRecordById(
        await db.addRecord(record(-997, 'Curso', rent, 14)),
      );
      final refund = await db.getRecordById(
        await db.addRecord(record(997, 'Reembolso Curso', other, 14)),
      );
      return (expense!, refund!);
    }

    test('neither side counts any more; each keeps its category', () async {
      final db = ServiceConfig.database;
      final (expense, refund) = await stored();
      await RefundLink.link(refund, expense);

      final r = (await db.getRecordById(refund.id!))!;
      final e = (await db.getRecordById(expense.id!))!;
      for (final side in [r, e]) {
        expect(side.isRefundPair, isTrue);
        expect(side.countsAsExpense, isFalse);
        expect(side.countsAsIncome, isFalse);
        expect(side.countsTowardTotals, isFalse);
        expect(side.isOwnMove, isTrue);
      }
      expect(r.category?.name, 'Outros');
      expect(e.category?.name, 'Aluguel');
      expect((await RefundLink.expenseOf(r))?.id, e.id);
      expect((await RefundLink.refundsOf(e)).single.id, r.id);
      expect(RefundLink.decode(r.refundLink)!.isRefund, isTrue);
      expect(RefundLink.decode(e.refundLink)!.isRefund, isFalse);
    });

    test('unlinking either side frees both', () async {
      final db = ServiceConfig.database;
      final (expense, refund) = await stored();
      await RefundLink.link(refund, expense);
      await RefundLink.unlink((await db.getRecordById(expense.id!))!);

      for (final id in [refund.id!, expense.id!]) {
        final back = (await db.getRecordById(id))!;
        expect(back.refundLink, isNull);
        expect(back.countsTowardTotals, isTrue);
      }
    });

    test('deleting one side lets the other count again', () async {
      final db = ServiceConfig.database;
      final (expense, refund) = await stored();
      await RefundLink.link(refund, expense);
      await db.deleteRecordById(refund.id);

      final left = (await db.getRecordById(expense.id!))!;
      expect(left.refundLink, isNull);
      expect(left.countsAsExpense, isTrue);
    });

    test('the list: its amount or more, the same amount first', () async {
      final db = ServiceConfig.database;
      final (expense, refund) = await stored();
      await db.addRecord(record(-20, 'Padaria', rent, 14));
      await db.addRecord(record(-1500, 'Mecânica', rent, 13));
      await db.addRecord(
        Record(-2000, 'Aluguel do mês', rent, DateTime.utc(2026, 5, 14, 12))
          ..recurrencePatternId = 'p'
          ..walletId = conta,
      );
      final list = await RefundLink.candidates(refund);
      expect(list.map((r) => r.title), ['Curso', 'Mecânica']);
      expect(list.first.id, expense.id);
    });

    test('a partial refund takes its part off the expense', () async {
      final db = ServiceConfig.database;
      final (expense, _) = await stored();
      final partial = (await db.getRecordById(
        await db.addRecord(record(100, 'Reembolso Curso', other, 20)),
      ))!;
      await RefundLink.link(partial, expense);

      final r = (await db.getRecordById(partial.id!))!;
      final e = (await db.getRecordById(expense.id!))!;
      expect(r.isRefundPair, isFalse);
      expect(e.isRefundPair, isFalse);
      // The refund is in the expense's category, positive: it lowers it.
      expect(r.category?.name, 'Aluguel');
      expect(r.value, 100);
      expect(r.countsAsExpense, isTrue);
      expect(r.countsAsIncome, isFalse);
      expect(e.countsAsExpense, isTrue);
      expect(e.value! + r.value!, -897);
      expect(RefundLink.decode(e.refundLink)!.isPartial, isTrue);
      expect(RefundLink.decode(e.refundLink)!.refunded, 100);

      await RefundLink.unlink(e);
      final back = (await db.getRecordById(partial.id!))!;
      expect(back.refundLink, isNull);
      expect(back.category?.name, 'Outros');
      expect(back.countsAsIncome, isTrue);
    });

    test('never more than the expense', () async {
      final db = ServiceConfig.database;
      final (expense, _) = await stored();
      final big = (await db.getRecordById(
        await db.addRecord(record(2000, 'Reembolso', other, 20)),
      ))!;
      await RefundLink.link(big, expense);
      expect((await db.getRecordById(big.id!))!.refundLink, isNull);
    });

    group('several refunds of one purchase', () {
      Future<Record> income(double value, String title) async {
        final db = ServiceConfig.database;
        return (await db.getRecordById(
          await db.addRecord(record(value, title, other, 20)),
        ))!;
      }

      Future<Record> purchase() async {
        final db = ServiceConfig.database;
        await stored();
        return (await db.getRecordById(
          await db.addRecord(record(-1000, 'Shopee', rent, 10)),
        ))!;
      }

      test('never more than what is left of it', () async {
        final db = ServiceConfig.database;
        final shopee = await purchase();
        final a = await income(600, 'Reembolso Shopee');
        final b = await income(700, 'Reembolso Shopee');
        await RefundLink.link(a, shopee);

        final after = (await db.getRecordById(shopee.id!))!;
        expect(RefundLink.leftOf(after), 400);
        expect(RefundLink.fits(b, after), isFalse);
        expect(
          (await RefundLink.candidates(b)).map((r) => r.id),
          isNot(contains(shopee.id)),
        );
        await RefundLink.link(b, after);
        expect((await db.getRecordById(b.id!))!.refundLink, isNull);
      });

      test('600 and 400: the purchase counts nothing', () async {
        final db = ServiceConfig.database;
        final shopee = await purchase();
        final a = await income(600, 'Reembolso Shopee');
        final b = await income(400, 'Reembolso Shopee');
        await RefundLink.link(a, shopee);
        expect(
          (await RefundLink.candidates(b)).map((r) => r.id),
          contains(shopee.id),
        );
        await RefundLink.link(b, (await db.getRecordById(shopee.id!))!);

        final e = (await db.getRecordById(shopee.id!))!;
        final ra = (await db.getRecordById(a.id!))!;
        final rb = (await db.getRecordById(b.id!))!;
        expect(RefundLink.decode(e.refundLink)!.refunded, 1000);
        expect(RefundLink.leftOf(e), 0);
        expect(e.value! + ra.value! + rb.value!, 0);
        for (final r in [ra, rb]) {
          expect(r.category?.name, 'Aluguel');
          expect(r.countsAsIncome, isFalse);
        }
        expect(await RefundLink.refundsOf(e), hasLength(2));
      });

      test('unlinking one refund keeps the other', () async {
        final db = ServiceConfig.database;
        final shopee = await purchase();
        final a = await income(600, 'Reembolso Shopee');
        final b = await income(300, 'Reembolso Shopee');
        await RefundLink.link(a, shopee);
        await RefundLink.link(b, (await db.getRecordById(shopee.id!))!);
        await RefundLink.unlink((await db.getRecordById(a.id!))!);

        final e = (await db.getRecordById(shopee.id!))!;
        expect(RefundLink.decode(e.refundLink)!.refunded, 300);
        expect(RefundLink.leftOf(e), 700);
        final back = (await db.getRecordById(a.id!))!;
        expect(back.refundLink, isNull);
        expect(back.category?.name, 'Outros');
      });

      test('deleting the purchase lets every refund go', () async {
        final db = ServiceConfig.database;
        final shopee = await purchase();
        final a = await income(600, 'Reembolso Shopee');
        final b = await income(300, 'Reembolso Shopee');
        await RefundLink.link(a, shopee);
        await RefundLink.link(b, (await db.getRecordById(shopee.id!))!);
        await db.deleteRecordById(shopee.id);

        for (final id in [a.id!, b.id!]) {
          final back = (await db.getRecordById(id))!;
          expect(back.refundLink, isNull);
          expect(back.category?.name, 'Outros');
          expect(back.countsAsIncome, isTrue);
        }
      });
    });
  });
}
