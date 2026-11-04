// The company module's taxes, with invented companies.
import 'package:aupp/fiscal/fiscal-data.dart';
import 'package:aupp/fiscal/fiscal-engine.dart';
import 'package:aupp/fiscal/fiscal-tables.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const office = '8219-9/99'; // Anexo III direct
  const software = '6201-5/01'; // Fator R

  RevenueEntry revenue(
    YearMonth m,
    double value, {
    String activity = office,
    RevenueSource source = RevenueSource.account,
  }) => RevenueEntry(
    month: m,
    value: value,
    activity: activity,
    source: source,
    key: '${m.key}-$value-${source.name}',
  );

  /// A MEI opened in Jul/2025 that became a Simples ME in Nov/2026, billing
  /// [monthly] every month in [activity].
  FiscalEngine transformed({
    String activity = office,
    double monthly = 10000,
    List<MonthlyValue> proLabore = const [],
    YearMonth? today,
    YearMonth until = const YearMonth(2027, 12),
  }) {
    final data = FiscalData(
      regimes: [
        Regime(RegimeKind.mei, DateTime(2025, 7, 29), DateTime(2026, 10, 31)),
        Regime(RegimeKind.simples, DateTime(2026, 11, 1)),
      ],
      activities: [activity],
      proLabore: [...proLabore],
    );
    final entries = [
      for (var m = const YearMonth(2025, 7); !m.isAfter(until); m = m.add(1))
        revenue(m, monthly, activity: activity),
    ];
    return FiscalEngine(data, entries, today: today ?? const YearMonth(2026, 11));
  }

  group('tables', () {
    test('effective rate of the Simples', () {
      expect(FiscalTables.effectiveRate(Annex.iii, 150000), 0.06);
      expect(FiscalTables.effectiveRate(Annex.v, 0), 0.155);
      // 240.000 × 11,2% − 9.360 = 17.520 → 7,3%.
      expect(
        FiscalTables.effectiveRate(Annex.iii, 240000),
        closeTo(0.073, 1e-9),
      );
    });

    test('IRRF of the pró-labore with the 2026 reduction', () {
      final t = FiscalTables.forYear(2026);
      expect(t.irrf(1621), 0);
      expect(t.irrf(5000), 0);
      // 6.000 − 660 = 5.340 → 559,77; reduction 978,62 − 0,133145 × 6.000.
      expect(t.irrf(6000), closeTo(380.02, 0.01));
      expect(t.inss(20000), closeTo(932.31, 0.01));
    });

    test('a year without a line uses the latest one', () {
      expect(FiscalTables.forYear(2031).year, 2026);
      expect(FiscalTables.forYear(2025).dasMei, 80.90);
    });
  });

  group('MEI', () {
    test('a fixed DAS, and the limit of the year', () {
      final e = transformed(monthly: 9000);
      final m = e.month(const YearMonth(2026, 3));
      expect(m.regime, RegimeKind.mei);
      expect(m.das, 86.05);
      expect(m.warnings, isEmpty);
      // 10 × 9.000 = 90.000: over 81.000, under 97.200.
      expect(
        e.month(const YearMonth(2026, 10)).warnings.single,
        contains('imposto sobre o excesso'),
      );
    });

    test('the opening year has 6.750 per month open', () {
      final e = transformed(monthly: 9000);
      expect(e.meiYearUse(const YearMonth(2025, 12)).$2, 6750 * 6);
    });
  });

  group('Simples after the MEI', () {
    test('Anexo III direct pays 6% whatever the payroll', () {
      final m = transformed().month(const YearMonth(2026, 12));
      expect(m.regime, RegimeKind.simples);
      expect(m.fatorR, isNull);
      expect(m.das, 600);
      expect(m.warnings, contains('Sem pró-labore'));
    });

    test('a Fator R activity carries the MEI months without payroll', () {
      final e = transformed(
        activity: software,
        proLabore: [MonthlyValue(const YearMonth(2026, 11), 1621)],
      );
      final m = e.month(const YearMonth(2026, 12));
      // Window dec/25..nov/26: 1.621 of payroll over 120.000.
      expect(m.fatorR, closeTo(1621 / 120000, 1e-9));
      expect(m.annexes[software], Annex.v);
      expect(m.das, closeTo(1550, 0.01));
      expect(m.inAnnexV, isTrue);
    });

    test('from 2027 the window skips the previous month', () {
      final e = transformed(activity: software);
      expect(e.fatorRWindow(const YearMonth(2026, 12)), (
        const YearMonth(2025, 12),
        const YearMonth(2026, 11),
      ));
      expect(e.fatorRWindow(const YearMonth(2027, 1)), (
        const YearMonth(2025, 12),
        const YearMonth(2026, 11),
      ));
    });

    test('no payroll at all: Fator R 0,01', () {
      final m = transformed(activity: software).month(const YearMonth(2027, 3));
      expect(m.fatorR, 0.01);
    });

    test('the pró-labore that reaches 28% in a month', () {
      final e = transformed(activity: software);
      final plan = e.planFatorR(
        const YearMonth(2027, 6),
        const YearMonth(2026, 11),
      );
      // Window may/26..apr/27: 120.000 × 28% over the 6 Simples months.
      expect(plan.proLabore, closeTo(5600, 0.01));

      final paid = transformed(
        activity: software,
        proLabore: [MonthlyValue(const YearMonth(2026, 11), 5600)],
      );
      final june = paid.month(const YearMonth(2027, 6));
      expect(june.fatorR, closeTo(0.28, 1e-9));
      expect(june.annexes[software], Annex.iii);
    });

    test('INSS and IRRF of the pró-labore go in the DCTFWeb', () {
      final e = transformed(
        proLabore: [MonthlyValue(const YearMonth(2026, 11), 6000)],
      );
      final m = e.month(const YearMonth(2026, 11));
      expect(m.inss, 660);
      expect(m.irrf, closeTo(380.02, 0.01));
      expect(m.dctfweb, closeTo(1040.02, 0.01));
      expect(m.due, DateTime(2026, 12, 20));
    });
  });

  test('invoices of different activities in the same month', () {
    final data = FiscalData(
      regimes: [Regime(RegimeKind.simples, DateTime(2026, 1, 1))],
      activities: [office, software],
    );
    final e = FiscalEngine(data, [
      for (var m = 1; m <= 6; m++) revenue(YearMonth(2026, m), 10000),
      revenue(const YearMonth(2026, 7), 6000),
      revenue(const YearMonth(2026, 7), 4000, activity: software),
    ], today: const YearMonth(2026, 7));
    final july = e.month(const YearMonth(2026, 7));
    expect(july.revenueByActivity, {office: 6000, software: 4000});
    expect(july.annexes, {office: Annex.iii, software: Annex.v});
    // 6.000 × 6% + 4.000 × 15,5%.
    expect(july.das, closeTo(360 + 620, 0.01));
  });

  group('a new company', () {
    FiscalEngine fresh(String start, {String activity = software}) {
      final data = FiscalData(
        regimes: [Regime(RegimeKind.simples, DateTime.parse(start))],
        activities: [activity],
      );
      final first = YearMonth.of(DateTime.parse(start));
      return FiscalEngine(data, [
        revenue(first, 6000, activity: activity),
        revenue(first.add(1), 12000, activity: activity),
        revenue(first.add(2), 9000, activity: activity),
      ], today: first);
    }

    test('the RBT12 is proportional while it is young', () {
      final e = fresh('2026-03-10');
      expect(e.rbt12(const YearMonth(2026, 3)), 6000 * 12);
      expect(e.rbt12(const YearMonth(2026, 5)), (6000 + 12000) / 2 * 12);
    });

    test('from 2027, Fator R 28% in the first two months', () {
      final e = fresh('2027-02-01');
      expect(e.month(const YearMonth(2027, 2)).annexes[software], Annex.iii);
      expect(e.month(const YearMonth(2027, 3)).annexes[software], Annex.iii);
      expect(e.month(const YearMonth(2027, 4)).fatorR, 0.01);
    });
  });

  test('forecasts count only from today on, in months with no revenue', () {
    final data = FiscalData(
      regimes: [Regime(RegimeKind.simples, DateTime(2026, 1, 1))],
      activities: [office],
    );
    final e = FiscalEngine(data, [
      revenue(const YearMonth(2026, 9), 11000, source: RevenueSource.forecast),
      revenue(const YearMonth(2026, 11), 11000, source: RevenueSource.forecast),
      revenue(const YearMonth(2026, 11), 9500),
      revenue(const YearMonth(2026, 12), 11000, source: RevenueSource.forecast),
    ], today: const YearMonth(2026, 11));
    expect(e.revenueOf(const YearMonth(2026, 9)), 0);
    expect(e.revenueOf(const YearMonth(2026, 11)), 9500);
    expect(e.month(const YearMonth(2026, 11)).forecast, isFalse);
    expect(e.revenueOf(const YearMonth(2026, 12)), 11000);
    expect(e.month(const YearMonth(2026, 12)).forecast, isTrue);
  });

  test('an invoice typed in adds to the forecast; money arriving replaces it',
      () {
    final data = FiscalData(
      regimes: [Regime(RegimeKind.simples, DateTime(2026, 1, 1))],
      activities: [office],
    );
    final e = FiscalEngine(data, [
      revenue(const YearMonth(2026, 12), 11000, source: RevenueSource.forecast),
      revenue(const YearMonth(2026, 12), 500, source: RevenueSource.manual),
      revenue(const YearMonth(2027, 1), 11000, source: RevenueSource.forecast),
      revenue(const YearMonth(2027, 1), 10800),
    ], today: const YearMonth(2026, 11));
    expect(e.revenueOf(const YearMonth(2026, 12)), 11500);
    expect(e.revenueOf(const YearMonth(2027, 1)), 10800);
  });

  test('a forecast changes activity from a month on, not before', () {
    final data = FiscalData(activities: [office, software]);
    data.setForecastActivity('p', const YearMonth(2027, 3), software);
    expect(data.activityOfForecast('p', const YearMonth(2027, 2)), office);
    expect(data.activityOfForecast('p', const YearMonth(2027, 3)), software);
    expect(data.activityOfForecast('p', const YearMonth(2027, 9)), software);
    data.setForecastActivity('p', const YearMonth(2027, 6), office);
    expect(data.activityOfForecast('p', const YearMonth(2027, 5)), software);
    expect(data.activityOfForecast('p', const YearMonth(2027, 6)), office);
    final back = FiscalData.fromJson(data.toJson());
    expect(back.activityOfForecast('p', const YearMonth(2027, 4)), software);
  });

  test('yearly income tax of the profit above the tax-free share', () {
    final data = FiscalData(
      regimes: [Regime(RegimeKind.mei, DateTime(2025, 7, 29))],
      activities: [office],
      otherExpenses: {2026: 350.40},
    );
    final e = FiscalEngine(data, [
      for (var m = 1; m <= 10; m++)
        revenue(YearMonth(2026, m), 9610),
    ], today: const YearMonth(2026, 11));
    final ir = e.incomeTax(2026);
    expect(ir.revenue, closeTo(96100, 0.01));
    expect(ir.das, closeTo(12 * 86.05, 0.01));
    expect(ir.taxableProfit, closeTo(63965, 0.01));
    // Simplified 20%: base 51.172 → 3.407,82; reduction 2.316,28.
    expect(ir.adjustment, closeTo(1091.54, 0.05));

    data.fullBookkeeping = true;
    expect(FiscalEngine(data, e.entries, today: e.today).incomeTax(2026)
        .adjustment, 0);
  });

  test('the data survives its JSON', () {
    final data = FiscalData(
      regimes: [Regime(RegimeKind.simples, DateTime(2026, 11, 1))],
      activities: [office, software],
      proLabore: [MonthlyValue(const YearMonth(2026, 11), 1621)],
      manualRevenues: [
        ManualRevenue('a', const YearMonth(2025, 8), 8000, description: 'NF'),
      ],
      adjustments: {
        'dz1': RevenueAdjustment(
          parts: [
            RevenuePart(const YearMonth(2025, 12), 1900),
            RevenuePart(const YearMonth(2026, 1), 6100),
          ],
        ),
        'dz2': RevenueAdjustment(status: PaymentStatus.notRevenue),
        'dz3': RevenueAdjustment(status: PaymentStatus.invoice),
      },
      forecastPatterns: ['p1'],
      dasPattern: 'p2',
      otherExpenses: {2026: 100},
    );
    final back = FiscalData.fromJson(data.toJson());
    expect(back.toJson(), data.toJson());
    expect(back.proLaboreAt(const YearMonth(2027, 3)), 1621);
    expect(back.proLaboreAt(const YearMonth(2026, 10)), 0);
  });
}
