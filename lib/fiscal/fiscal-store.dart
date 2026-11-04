import 'package:aupp/accounts/money-accounts.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/models/recurrent-period.dart';
import 'package:aupp/models/recurrent-record-pattern.dart';
import 'package:aupp/services/service-config.dart';

import 'fiscal-data.dart';
import 'fiscal-engine.dart';
import 'fiscal-tables.dart';

/// A payment that reached one of the company's accounts, with what the user
/// changed on it.
class CompanyPayment {
  final Record record;
  final String key;
  final RevenueAdjustment? adjustment;

  const CompanyPayment(this.record, this.key, this.adjustment);

  YearMonth get month => YearMonth.of(record.dateTime);
  PaymentStatus? get status => adjustment?.status;

  /// Not checked yet: counts as an invoice of its month meanwhile.
  bool get pending => status == null;
  bool get counts => adjustment?.counts ?? true;
}

/// One company with everything its taxes are computed from.
class CompanyTaxes {
  final Company company;
  final List<CompanyPayment> payments;
  final FiscalEngine engine;

  const CompanyTaxes(this.company, this.payments, this.engine);

  FiscalData get data => company.fiscal;
}

class FiscalStore {
  FiscalStore._();

  /// How far estimates are forecast.
  static const forecastMonths = 18;

  static YearMonth get currentMonth => YearMonth.of(DateTime.now());

  /// The company's revenue and taxes as they are now.
  static Future<CompanyTaxes> load(
    Company company, {
    List<Record?>? records,
  }) async {
    final all = records ?? await ServiceConfig.database.getAllRecords();
    final payments = paymentsOf(company, all);
    final patterns = <RecurrentRecordPattern>[
      for (final id in company.fiscal.forecastPatterns)
        ?await ServiceConfig.database.getRecurrentRecordPattern(id),
    ];
    final today = currentMonth;
    final entries = entriesOf(
      company.fiscal,
      payments,
      patterns,
      from: today,
      until: today.add(forecastMonths),
    );
    return CompanyTaxes(
      company,
      payments,
      FiscalEngine(company.fiscal, entries, today: today),
    );
  }

  /// Money that came into the company's accounts: not money between own
  /// accounts, not estimates.
  static List<CompanyPayment> paymentsOf(
    Company company,
    List<Record?> records,
  ) {
    final banks = {for (final b in company.banks) b.trim().toLowerCase()};
    final out = <CompanyPayment>[];
    for (final r in records) {
      if (r == null || r.isFutureRecord || (r.value ?? 0) <= 0) continue;
      if (r.tags.contains(MoneyAccounts.transferTag)) continue;
      if (!banks.contains(MoneyAccounts.accountOf(r).toLowerCase())) continue;
      final key = FiscalData.revenueKey(dinzoId: r.dinzoId, recordId: r.id);
      out.add(CompanyPayment(r, key, company.fiscal.adjustments[key]));
    }
    out.sort((a, b) => a.record.utcDateTime.compareTo(b.record.utcDateTime));
    return out;
  }

  /// The revenue entries of the company: its payments (as adjusted), the
  /// invoices typed in, and the forecast of [patterns] from [from] to
  /// [until].
  static List<RevenueEntry> entriesOf(
    FiscalData data,
    List<CompanyPayment> payments,
    List<RecurrentRecordPattern> patterns, {
    required YearMonth from,
    required YearMonth until,
  }) {
    final main = data.mainActivity ?? '';
    final entries = <RevenueEntry>[];
    for (final p in payments) {
      if (!p.counts) continue;
      final parts =
          p.adjustment?.parts ?? [RevenuePart(p.month, p.record.value!)];
      for (final part in parts) {
        entries.add(
          RevenueEntry(
            month: part.month,
            value: part.value,
            activity: part.activity ?? p.adjustment?.activity ?? main,
            source: RevenueSource.account,
            key: p.key,
            title: p.record.title ?? '',
            date: p.record.dateTime,
            pending: p.pending,
          ),
        );
      }
    }
    for (final m in data.manualRevenues) {
      entries.add(
        RevenueEntry(
          month: m.month,
          value: m.value,
          activity: m.activity ?? main,
          source: RevenueSource.manual,
          key: m.id,
          title: m.description ?? 'Nota avulsa',
        ),
      );
    }
    for (final pattern in patterns) {
      for (final (date, value) in occurrences(pattern, from, until)) {
        entries.add(
          RevenueEntry(
            month: YearMonth.of(date),
            value: value,
            activity: data.activityOfForecast(
              pattern.id ?? '',
              YearMonth.of(date),
            ),
            source: RevenueSource.forecast,
            key: pattern.id ?? '',
            title: pattern.title ?? 'Estimativa',
            date: date,
          ),
        );
      }
    }
    return entries;
  }

  /// Monthly occurrences of [pattern] from [from] to [until] (other
  /// periods are approximated by their months).
  static List<(DateTime, double)> occurrences(
    RecurrentRecordPattern pattern,
    YearMonth from,
    YearMonth until,
  ) {
    final start = pattern.utcDateTime.toLocal();
    final end = pattern.utcEndDate?.toLocal();
    final step = switch (pattern.recurrentPeriod) {
      RecurrentPeriod.EveryThreeMonths => 3,
      RecurrentPeriod.EveryFourMonths => 4,
      RecurrentPeriod.EveryYear => 12,
      _ => 1,
    };
    final out = <(DateTime, double)>[];
    for (var m = YearMonth.of(start); !m.isAfter(until); m = m.add(step)) {
      if (m.isBefore(from)) continue;
      final lastDay = DateTime(m.year, m.month + 1, 0).day;
      final date = DateTime(
        m.year,
        m.month,
        start.day > lastDay ? lastDay : start.day,
      );
      if (end != null && date.isAfter(end)) break;
      final value = pattern.valueFor(date)?.abs() ?? 0;
      if (value > 0) out.add((date, value));
    }
    return out;
  }
}
