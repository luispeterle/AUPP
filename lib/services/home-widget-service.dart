import 'package:aupp/accounts/money-accounts.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:aupp/demo/demo-mode.dart';
import 'package:aupp/helpers/records-utility-functions.dart';
import 'package:aupp/home_widgets/widget_views.dart';
import 'package:aupp/models/category-type.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/services/database/database-interface.dart';
import 'package:aupp/services/logger.dart';
import 'package:aupp/services/service-config.dart';
import 'package:aupp/style.dart';

/// Android home screen widgets (overview, income, expenses, balance).
///
/// The native side renders text itself, so figures stay crisp at any widget
/// size; only the small sparkline charts are bitmaps. Values follow the
/// homepage time interval setting. Refresh happens on app events (record
/// changes, launch) plus a manual refresh; Android additionally
/// redraws on its own schedule.
class HomeWidgetService {
  static final _logger = Logger.withClass(HomeWidgetService);

  static const String _providerPackage = 'app.aupp.widget';
  static const String overviewProvider =
      '$_providerPackage.AuppOverviewWidgetProvider';
  static const String incomeProvider =
      '$_providerPackage.AuppIncomeWidgetProvider';
  static const String expensesProvider =
      '$_providerPackage.AuppExpensesWidgetProvider';
  static const String balanceProvider =
      '$_providerPackage.AuppBalanceWidgetProvider';

  /// Widgets are an Android-only feature in this app.
  static bool get isSupported => Platform.isAndroid;

  static DatabaseInterface get _database => ServiceConfig.database;

  /// Recomputes every widget's data and pushes an update. Best effort:
  /// failures only log so callers (UI event handlers) never break.
  static Future<void> refreshAll() async {
    // The demo's made-up numbers never reach the home screen.
    if (!isSupported || DemoMode.active) return;
    try {
      const dark = true;
      await HomeWidget.saveWidgetData<bool>('aupp_dark', dark);
      // App's own background so widgets blend in (dynamic seed theme:
      // read the live theme, fall back to the default seed scheme).
      const brightness = Brightness.dark;
      final surface = MaterialThemeInstance.currentTheme?.colorScheme.surface ??
          ColorScheme.fromSeed(
                  seedColor: MaterialThemeInstance.defaultSeedColor,
                  brightness: brightness)
              .surface;
      await HomeWidget.saveWidgetData(
          'aupp_background_color', surface.toARGB32());
      final interval = getHomepageTimeIntervalEnumSetting();
      final monthStartDay = getHomepageRecordsMonthStartDay();
      final records = MoneyAccounts.withoutTransfers(
          await getRecordsByHomepageTimeInterval(_database, interval,
              monthStartDay: monthStartDay));

      await _refreshTotals(dark, records);
    } catch (e, st) {
      _logger.handle(e, st, 'Failed to refresh home screen widgets');
    }
  }

  /// Balance color when amount colorization is disabled: green when
  /// positive, red when negative.
  static Color _balanceFallback(double total) =>
      total >= 0 ? Colors.green : Colors.red;

  static Future<void> _refreshTotals(    bool dark,
    List<Record?> records,
  ) async {
    const brightness = Brightness.dark;
    final incomeRecords = records.where((r) =>
        r?.category?.categoryType == CategoryType.income && !r!.isOwnMove);
    final expenseRecords = records.where((r) =>
        r?.category?.categoryType == CategoryType.expense && !r!.isOwnMove);
    final balanceRecords = records.where((r) => r != null && !r.isOwnMove);

    String text(Iterable<Record?> rs, {required bool isBalance}) {
      return formatMoney(recordsTotal(rs, isAbsValue: !isBalance));
    }

    Future<void> save(String key, Object value) =>
        HomeWidget.saveWidgetData(key, value);

    final incomeTotal =
        recordsTotal(incomeRecords);
    final expenseTotal =
        recordsTotal(expenseRecords);
    final balanceResult = recordsTotal(balanceRecords,
        isAbsValue: false);

    await save('aupp_overview_label_income', 'Rendas');
    await save('aupp_overview_label_expenses', 'Despesas');
    await save('aupp_overview_label_balance', 'Saldo');
    await save(
        'aupp_overview_income', text(incomeRecords, isBalance: false));
    await save(
        'aupp_overview_expenses', text(expenseRecords, isBalance: false));
    await save(
        'aupp_overview_balance', text(balanceRecords, isBalance: true));
    await save('aupp_overview_income_color',
        (getAmountColor(incomeTotal, brightness) ?? Colors.green).toARGB32());
    await save('aupp_overview_expenses_color',
        (getAmountColor(expenseTotal, brightness) ?? Colors.red).toARGB32());
    await save('aupp_overview_balance_color',
        (getAmountColor(balanceResult, brightness) ??
                _balanceFallback(balanceResult))
            .toARGB32());
    final balanceSeries = dailySeries(balanceRecords, isBalance: true);
    if (balanceSeries.length > 1) {
      final overviewSpark = await _renderSparkline(
        prefix: 'aupp_overview',
        values: balanceSeries,
        color: getAmountColor(balanceResult, brightness) ??
            _balanceFallback(balanceResult),
      );
      if (overviewSpark != null) {
        await save('aupp_overview_spark', overviewSpark);
      }
    }
    await HomeWidget.updateWidget(qualifiedAndroidName: overviewProvider);

    await _refreshSingle(
      provider: incomeProvider,
      prefix: 'aupp_income',
      label: 'Rendas',
      amount: text(incomeRecords, isBalance: false),
      color: getAmountColor(incomeTotal, brightness),
      sparkline: dailySeries(incomeRecords, isBalance: false),
    );
    await _refreshSingle(
      provider: expensesProvider,
      prefix: 'aupp_expenses',
      label: 'Despesas',
      amount: text(expenseRecords, isBalance: false),
      color: getAmountColor(expenseTotal, brightness),
      sparkline: dailySeries(expenseRecords, isBalance: false),
    );
    await _refreshSingle(
      provider: balanceProvider,
      prefix: 'aupp_balance',
      label: 'Saldo',
      amount: text(balanceRecords, isBalance: true),
      color: getAmountColor(balanceResult, brightness) ??
          _balanceFallback(balanceResult),
      sparkline: dailySeries(balanceRecords, isBalance: true),
    );
  }

  static Future<void> _refreshSingle({
    required String provider,
    required String prefix,
    required String label,
    required String amount,
    required Color? color,
    required List<double> sparkline,
  }) async {
    await HomeWidget.saveWidgetData('${prefix}_label', label);
    await HomeWidget.saveWidgetData('${prefix}_value', amount);
    if (color != null) {
      await HomeWidget.saveWidgetData('${prefix}_color', color.toARGB32());
    }
    if (sparkline.length > 1 && color != null) {
      final path = await _renderSparkline(
          prefix: prefix, values: sparkline, color: color);
      if (path != null) {
        await HomeWidget.saveWidgetData('${prefix}_spark', path);
      }
    }
    await HomeWidget.updateWidget(qualifiedAndroidName: provider);
  }

  /// Daily totals over the interval for sparklines (signed for balance,
  /// absolute otherwise), capped to the most recent 31 days.
  static List<double> dailySeries(
    Iterable<Record?> records, {
    required bool isBalance,
  }) {
    final byDay = <DateTime, double>{};
    for (final record in records) {
      if (record?.value == null || record!.isOwnMove) continue;
      final day = DateTime(
        record.localDateTime.year,
        record.localDateTime.month,
        record.localDateTime.day,
      );
      final value = isBalance ? record.value! : record.value!.abs();
      byDay[day] = (byDay[day] ?? 0) + value;
    }
    final days = byDay.keys.toList()..sort();
    final tail = days.length > 31 ? days.sublist(days.length - 31) : days;
    return [for (final day in tail) byDay[day]!];
  }

  /// Renders a transparent sparkline chart for [prefix], returning its path.
  static Future<String?> _renderSparkline({
    required String prefix,
    required List<double> values,
    required Color color,
  }) async {
    try {
      return await HomeWidget.renderFlutterWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 300,
            height: 60,
            child: HomeWidgetSparkline(values: values, color: color),
          ),
        ),
        key: '${prefix}_spark',
        logicalSize: const Size(300, 60),
        pixelRatio: 3.0,
      );
    } catch (e, st) {
      _logger.handle(e, st, 'Failed to render widget sparkline');
      return null;
    }
  }

}
