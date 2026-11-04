// The course's measures around the portfolio: financial freedom, the FGC
// limit and the gain above inflation.
import 'package:flutter_test/flutter_test.dart';
import 'package:aupp/services/service-config.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:aupp/dinzo/dinzo-taxes.dart';
import 'package:aupp/investments/benchmark.dart';
import 'package:aupp/investments/freedom.dart';
import 'package:aupp/investments/investments-analytics.dart';
import 'package:aupp/models/category-type.dart';
import 'package:aupp/models/category.dart';
import 'package:aupp/models/record.dart';

void main() {
  setUpAll(() {
    tz.initializeTimeZones();
    ServiceConfig.localTimezone = 'America/Sao_Paulo';
  });

  group('Freedom', () {
    test('8% a year with a quarter kept back', () {
      // 1,319,841.12 at 8% a year pays about 6,369 a month after the 25%.
      expect(Freedom.passiveIncome(1319841.12), closeTo(6368.92, 0.5));
      expect(Freedom.wealthFor(Freedom.passiveIncome(500000)), closeTo(500000, 0.01));
      expect(Freedom.passiveIncome(-10), 0);
    });

    test('living cost: income minus what went to invest, 6 full months', () {
      final expense = Category('Mercado', categoryType: CategoryType.expense);
      final income = Category('Salário', categoryType: CategoryType.income);
      const account = 1, investir = 2, caixinha = 4;
      final buy = Category(
        Category.investmentName,
        categoryType: CategoryType.investment,
      );
      Record record(
        double value,
        Category category,
        DateTime at, {
        int wallet = account,
        int? to,
      }) => Record(
        value,
        'x',
        category,
        at.toUtc(),
        walletId: wallet,
        transferWalletId: to,
      );
      final now = DateTime(2026, 11, 15);
      final records = [
        record(6000, income, DateTime(2026, 5, 5)),
        record(6000, income, DateTime(2026, 10, 5)),
        record(9999, income, DateTime(2026, 11, 2)), // this month: not yet
        record(9999, income, DateTime(2026, 4, 20)), // before the window
        record(-1000, expense, DateTime(2026, 6, 1)), // spent: counts
        // 1500 set aside, then bought with: once.
        record(-1500, expense, DateTime(2026, 6, 2), to: investir),
        record(-1500, buy, DateTime(2026, 6, 3), wallet: investir),
        // Invested straight from the account: not a cost of living either.
        record(-600, buy, DateTime(2026, 6, 4)),
        // A goal: counts as living.
        record(-700, expense, DateTime(2026, 7, 1), to: caixinha),
        // 300 back from Investir: no longer set aside.
        record(-300, expense, DateTime(2026, 9, 1), wallet: investir, to: account),
      ];
      // (12 000 − (1500 + 600 − 300)) ÷ 6.
      expect(
        Freedom.livingCost(
          records,
          now,
          investWallets: {investir},
        ),
        1700,
      );
    });
  });

  group('DepositGuarantee', () {
    Position position(String name, String subType, double balance) {
      final inv = DinzoInvestment.fromJson({
        'id': name + subType,
        'asset_key': name + subType,
        'name': '$subType $name',
        'type': 'FIXED_INCOME',
        'sub_type': subType,
        'balance': balance,
        'issuer': name,
      });
      return InvestmentsOverview.from([inv], DateTime(2026, 11, 1)).positions.single;
    }

    test('only bank fixed income above 250 mil in one institution', () {
      final big = position('Banco X', 'CDB', 200000);
      final more = position('Banco X', 'LCI', 80000);
      final treasury = position('Banco X', 'TREASURY', 500000);
      final over = DepositGuarantee.overLimit([big, more, treasury]);
      expect(over.values.single, 280000);
      expect(DepositGuarantee.overLimit([big]), isEmpty);
    });
  });

  test('inflation counts the months after the start up to the end', () {
    final ipca = {
      DateTime(2026, 1): 0.01,
      DateTime(2026, 2): 0.02,
      DateTime(2026, 3): 0.03,
    };
    expect(
      BenchmarkRates.inflationBetween(ipca, DateTime(2026, 1, 15), DateTime(2026, 3, 1)),
      closeTo(1.02 * 1.03 - 1, 1e-12),
    );
  });
}
