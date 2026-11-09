import 'package:flutter_test/flutter_test.dart';
import 'package:aupp/dinzo/broker-payment.dart';
import 'package:aupp/investments/freedom.dart';
import 'package:aupp/models/category-type.dart';
import 'package:aupp/models/category.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/models/records-per-day.dart';
import 'package:timezone/data/latest_all.dart' as tz;

const conta = 1;
const investir = 3;

Record paid(double value, {CategoryType type = CategoryType.expense}) => Record(
  value,
  'Maria Souza',
  Category('Presentes', categoryType: type),
  DateTime.utc(2026, 11, 9, 12),
  walletId: conta,
  dinzoId: 'abc',
);

void main() {
  setUpAll(tz.initializeTimeZones);

  test('a payment from the BTG gets a withdrawal of the same value', () {
    final c = BrokerPayment.companionFor(paid(-50), 'BTG')!;
    expect(c.value, 50);
    expect(c.title, 'Resgate do BTG');
    expect(c.isInvestmentSell, isTrue);
    expect(c.walletId, conta);
    expect(c.utcDateTime, DateTime.utc(2026, 11, 9, 12));
    expect(c.dinzoId, 'livre:pago:abc');
    expect(c.tags, {'BTG'});
  });

  test('money received at the BTG gets an aporte', () {
    final c = BrokerPayment.companionFor(
      paid(80, type: CategoryType.income),
      'BTG',
    )!;
    expect(c.value, -80);
    expect(c.title, 'Aporte no BTG');
    expect(c.isInvestmentBuy, isTrue);
  });

  test('nothing for an everyday bank, an aporte or a record of the app', () {
    expect(BrokerPayment.companionFor(paid(-50), null), isNull);
    expect(
      BrokerPayment.companionFor(
        paid(-50, type: CategoryType.investment),
        'BTG',
      ),
      isNull,
    );
    expect(
      BrokerPayment.companionFor(paid(-50)..dinzoId = 'livre:x', 'BTG'),
      isNull,
    );
  });

  test('the day nets to zero and the money counts as taken back', () {
    final expense = paid(-50);
    final withdrawal = BrokerPayment.companionFor(expense, 'BTG')!;
    final day = RecordsPerDay(
      DateTime(2026, 11, 9),
      records: [expense, withdrawal],
    );
    expect(day.balance, closeTo(0, 0.001));
    expect(day.setAside, 50);
  });

  test('Liberdade financeira: invested goes down by what came back', () {
    final income = Record(
      1000,
      'Salário',
      Category('Salário', categoryType: CategoryType.income),
      DateTime.utc(2026, 10, 5, 12),
      walletId: conta,
    );
    final expense = Record(
      -50,
      'Maria Souza',
      Category('Presentes', categoryType: CategoryType.expense),
      DateTime.utc(2026, 10, 9, 12),
      walletId: conta,
      dinzoId: 'abc',
    );
    final withdrawal = BrokerPayment.companionFor(expense, 'BTG')!;
    final aporte = Record(
      -200,
      'Aporte no BTG',
      Category.investment(),
      DateTime.utc(2026, 10, 10, 12),
      walletId: conta,
    );
    final now = DateTime(2026, 11, 9);
    final months = Freedom.months;
    expect(
      Freedom.livingCost(
        [income, expense, withdrawal, aporte],
        now,
        investWallets: {investir},
      ),
      closeTo((1000 - (200 - 50)) / months, 0.001),
    );
  });
}
