import 'package:flutter_test/flutter_test.dart';
import 'package:aupp/dinzo/dinzo-taxes.dart';

DinzoInvestmentMovement move(
  String type,
  String date,
  double amount, [
  double? net,
]) => DinzoInvestmentMovement(
  id: '$type$date$amount',
  type: type,
  date: date,
  amount: amount,
  netAmount: net,
);

({double tax, double uncoveredBalance}) _estimate(
  List<DinzoInvestment> investments,
  DateTime today,
) {
  var tax = 0.0, uncovered = 0.0;
  for (final inv in investments) {
    final t = DinzoTaxes.positionTax(inv, today);
    tax += t.tax;
    if (!inv.archived && inv.balance > 0 && t.cost == null) {
      uncovered += inv.balance;
    }
  }
  double round(double v) => (v * 100).roundToDouble() / 100;
  return (tax: round(tax), uncoveredBalance: round(uncovered));
}

void main() {
  final today = DateTime(2026, 10, 12);

  group('estimate (reported balances are already net of tax)', () {
    double embedded(double netProfit, double rate) =>
        netProfit / (1 - rate) - netProfit;

    test('tax embedded in the balance, by holding period', () {
      final e = _estimate([
        // 173 days → 22.5%; R$ 607.21 net profit
        DinzoInvestment(
          assetKey: 'a',
          name: 'CDB',
          type: 'FIXED_INCOME',
          balance: 10607.21,
          purchaseDate: '2026-04-22',
          movements: [move('BUY', '2026-04-22', 10000)],
        ),
        // 400 days → 17.5%; R$ 100 net profit
        DinzoInvestment(
          assetKey: 'b',
          name: 'CDB',
          type: 'FIXED_INCOME',
          balance: 1100,
          purchaseDate: '2025-09-07',
          movements: [move('BUY', '2025-09-07', 1000)],
        ),
      ], today);
      expect(
        e.tax,
        closeTo(embedded(607.21, 0.225) + embedded(100, 0.175), 0.01),
      );
      expect(e.uncoveredBalance, 0);
    });

    test('gross value rebuilt from the net balance', () {
      final t = DinzoTaxes.positionTax(
        DinzoInvestment(
          assetKey: 'a',
          name: 'CDB',
          type: 'FIXED_INCOME',
          balance: 10607.21,
          purchaseDate: '2026-04-22',
          movements: [move('BUY', '2026-04-22', 10000)],
        ),
        today,
      );
      expect(t.profit, closeTo(607.21, 0.001));
      expect(t.grossProfit, closeTo(607.21 / 0.775, 0.01));
    });

    test('partial redemptions take their share of the cost', () {
      // Bought 1000, sold 600 gross; 500 left → remaining cost 1000×500/1100.
      final e = _estimate([
        DinzoInvestment(
          assetKey: 'a',
          name: 'CDB',
          type: 'FIXED_INCOME',
          balance: 500,
          purchaseDate: '2026-09-01',
          movements: [
            move('BUY', '2026-09-01', 1000),
            move('SELL', '2026-10-01', 600, 590),
          ],
        ),
      ], today);
      expect(e.tax, closeTo(embedded(500 - 1000 * 500 / 1100, 0.225), 0.01));
    });

    test('positions without cost history are reported, not guessed', () {
      final e = _estimate([
        DinzoInvestment(
          assetKey: 'c',
          name: 'Cofrinho',
          type: 'FIXED_INCOME',
          balance: 9194.44,
          rate: 120,
          rateType: 'CDI',
        ),
      ], today);
      expect(e.tax, 0);
      expect(e.uncoveredBalance, 9194.44);
    });

    test('funds (come-cotas) and exempt products carry no tax', () {
      final e = _estimate([
        DinzoInvestment(
          assetKey: 'f',
          name: 'Fundo',
          type: 'MUTUAL_FUND',
          balance: 4400,
          movements: [move('BUY', '2026-01-01', 4000)],
        ),
        DinzoInvestment(
          assetKey: 'l',
          name: 'LCI',
          type: 'FIXED_INCOME',
          balance: 1100,
          taxExempt: true,
          movements: [move('BUY', '2026-01-01', 1000)],
        ),
      ], today);
      expect(e.tax, 0);
    });
  });
}
