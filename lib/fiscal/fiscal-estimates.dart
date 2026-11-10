import 'dart:async';

import 'package:aupp/accounts/money-accounts.dart';
import 'package:aupp/dinzo/estimate-link.dart';
import 'package:aupp/models/category-type.dart';
import 'package:aupp/models/recurrent-period.dart';
import 'package:aupp/models/recurrent-record-pattern.dart';
import 'package:aupp/services/database/sqlite-database.dart';
import 'package:aupp/services/logger.dart';
import 'package:aupp/services/service-config.dart';
import 'package:flutter/foundation.dart';

import 'fiscal-data.dart';
import 'fiscal-engine.dart';
import 'fiscal-store.dart';
import 'fiscal-tables.dart';

/// The estimates of a company's taxes and accountant. Each occurrence in a
/// month shows that month's amount: the DAS and the DCTFWeb (INSS + IRRF of
/// the pró-labore) of the month before, due on the 20th, and the
/// accountant's fee. With [FiscalData.autoEstimates] the estimates are
/// created here. Kept in memory and recomputed when the data changes.
class FiscalEstimates {
  FiscalEstimates._();

  static final _logger = Logger.withClass(FiscalEstimates);

  /// Pattern id → month of the occurrence → amount.
  static final Map<String, Map<YearMonth, double>> _values = {};

  /// Bumped after each recomputation.
  static final changes = ValueNotifier<int>(0);

  static Timer? _debounce;
  static bool _started = false;
  static bool _running = false;

  static Future<void> init() async {
    if (_started) return;
    _started = true;
    RecurrentRecordPattern.computedValue = valueFor;
    SqliteDatabase.dataChangeNotifier.addListener(_schedule);
    MoneyAccounts.changes.addListener(_schedule);
    await refresh();
  }

  static void _schedule() {
    if (_running) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), refresh);
  }

  static double? valueFor(RecurrentRecordPattern pattern, DateTime local) =>
      _values[pattern.id]?[YearMonth.of(local)];

  static Future<void> refresh() async {
    if (_running) return;
    _running = true;
    try {
      final companies = MoneyAccounts.companies();
      final next = <String, Map<YearMonth, double>>{};
      var saved = false;
      final records = companies.any((c) => c.fiscal.isSetUp)
          ? await ServiceConfig.database.getAllRecords()
          : null;
      for (final company in companies) {
        if (!company.fiscal.isSetUp) continue;
        final taxes = await FiscalStore.load(company, records: records);
        final now = FiscalStore.currentMonth;
        final months = taxes.engine.months(now.add(FiscalStore.forecastMonths));
        final byMonth = {for (final m in months) m.month: m};
        final data = company.fiscal;
        if (data.autoEstimates && !SqliteDatabase.readOnly) {
          saved |= await _ensurePatterns(company, byMonth);
        }
        // Taxes of a month are paid in the next one.
        void fill(String? id, double? Function(FiscalMonth paidIn) amount) {
          if (id == null) return;
          next[id] = {
            for (final m in months)
              if (amount(m) case final v? when v > 0) m.month: v,
          };
        }

        fill(data.dasPattern, (m) {
          final before = byMonth[m.month.add(-1)];
          return before?.regime == null ? null : before!.das;
        });
        fill(data.dctfwebPattern, (m) {
          final before = byMonth[m.month.add(-1)];
          return (before?.proLabore ?? 0) > 0 ? before!.dctfweb : null;
        });
        fill(data.feePattern, (m) => m.accountantFee);
        for (final p in data.otherPayments) {
          if (p.patternId != null) next[p.patternId!] = {p.month: p.value};
        }
      }
      _values
        ..clear()
        ..addAll(next);
      if (saved) await MoneyAccounts.saveCompanies(companies);
      changes.value++;
    } catch (e, st) {
      _logger.handle(e, st, 'Company taxes could not be computed');
    } finally {
      _running = false;
    }
  }

  /// Creates the company's estimates still missing (or deleted). They are
  /// the user's data from then on (they reach the other devices with the
  /// company, which keeps their ids). Returns whether the company changed.
  static Future<bool> _ensurePatterns(
    Company company,
    Map<YearMonth, FiscalMonth> byMonth,
  ) async {
    final db = ServiceConfig.database;
    final data = company.fiscal;
    final now = FiscalStore.currentMonth;
    var changed = false;
    final linked = await EstimateLink.linkedOccurrences();

    /// Whether the estimate [id] is still there; it is paid by Pix (each
    /// month expects its code), so the tag is put back when missing. One
    /// gone because linking consumed it (EstimateLink.deleteIfDone) was
    /// paid, not deleted: it is not created again.
    Future<bool> exists(String? id) async {
      if (id == null) return false;
      final pattern = await db.getRecurrentRecordPattern(id);
      if (pattern == null) return linked.containsKey(id);
      if (!pattern.tags.contains('Pix')) {
        pattern.tags = {...pattern.tags, 'Pix'};
        await db.updateRecordPatternById(id, pattern);
      }
      return true;
    }

    Future<String> create({
      required String title,
      required String categoryName,
      required YearMonth first,
      required int day,
      required double value,
      bool once = false,
    }) async {
      final category =
          await db.getCategory(categoryName, CategoryType.expense) ??
          await db.getCategory('Impostos/Taxas', CategoryType.expense);
      final wallet = await db.getDefaultWallet();
      final date = DateTime(first.year, first.month, day, 12).toUtc();
      final pattern = RecurrentRecordPattern(
        -(value.abs() < 0.01 ? 0.01 : value.abs()),
        title,
        category,
        date,
        RecurrentPeriod.EveryMonth,
        utcEndDate: once ? date : null,
        walletId: wallet?.id,
        tags: {
          if (company.banks.isNotEmpty) company.banks.first,
          'Estimativa',
          'Pix',
        },
      );
      await db.addRecurrentRecordPattern(pattern);
      _logger.info('Estimate created for ${company.name}: $title');
      return pattern.id!;
    }

    // DAS: from this month (last month's), while there is a regime.
    final last = byMonth[now.add(-1)];
    if (last?.regime != null && !await exists(data.dasPattern)) {
      data.dasPattern = await create(
        title: 'DAS',
        categoryName: 'Tributos',
        first: now,
        day: 20,
        value: last!.das,
      );
      changed = true;
    }

    // DCTFWeb: once a pró-labore is paid, from the month after it.
    YearMonth? firstPay;
    for (final c in data.proLabore) {
      if (c.value <= 0) continue;
      if (firstPay == null || c.since.isBefore(firstPay)) firstPay = c.since;
    }
    if (firstPay != null && !await exists(data.dctfwebPattern)) {
      var first = firstPay.add(1);
      if (first.isBefore(now)) first = now;
      data.dctfwebPattern = await create(
        title: 'DCTFWeb (INSS + IRRF)',
        categoryName: 'Tributos',
        first: first,
        day: 20,
        value: byMonth[first.add(-1)]?.dctfweb ?? 0,
      );
      changed = true;
    }

    // Accountant: from the first fee (not before this month).
    YearMonth? firstFee;
    for (final c in data.accountantFee) {
      if (c.value <= 0) continue;
      if (firstFee == null || c.since.isBefore(firstFee)) firstFee = c.since;
    }
    if (firstFee != null && !await exists(data.feePattern)) {
      final first = firstFee.isBefore(now) ? now : firstFee;
      data.feePattern = await create(
        title: 'Contabilidade',
        categoryName: 'Impostos/Taxas',
        first: first,
        day: data.accountantDay.clamp(1, 28),
        value: data.accountantFeeAt(first),
      );
      changed = true;
    }

    // One-off payments from this month on: an estimate on their day.
    for (final p in data.otherPayments) {
      if (p.month.isBefore(now) || await exists(p.patternId)) continue;
      p.patternId = await create(
        title: p.description,
        categoryName: 'Impostos/Taxas',
        first: p.month,
        day: p.day.clamp(1, 28),
        value: p.value,
        once: true,
      );
      changed = true;
    }
    return changed;
  }
}
