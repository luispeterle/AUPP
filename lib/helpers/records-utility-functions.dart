import 'dart:collection';
import 'package:aupp/services/locale-service.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/number_symbols.dart';
import 'package:intl/number_symbols_data.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/models/records-per-day.dart';
import 'package:aupp/models/wallet.dart';
import 'package:aupp/services/database/database-interface.dart';
import 'package:aupp/services/service-config.dart';
import 'package:aupp/settings/constants/homepage-time-interval.dart';
import 'package:aupp/settings/constants/overview-time-interval.dart';
import 'package:aupp/settings/constants/preferences-defaults-values.dart';

import 'banner-image-service.dart';
import 'datetime-utility-functions.dart';

List<RecordsPerDay> groupRecordsByDay(List<Record?> records) {
  /// Groups the records by days using a Map<DateTime, List<Record>>.
  /// It returns a list of RecordsPerDay objects, each containing at least 1 record.
  Map<DateTime, List<Record?>> movementsGroups = {};

  // Iterate over each record and group them by date (year, month, day).
  for (var record in records) {
    if (record != null) {
      DateTime dateKey = DateTime(
          record.dateTime.year, record.dateTime.month, record.dateTime.day);

      if (!movementsGroups.containsKey(dateKey)) {
        movementsGroups[dateKey] = [];
      }
      movementsGroups[dateKey]!.add(record);
    }
  }

  // Convert the map to a queue of RecordsPerDay objects.
  Queue<RecordsPerDay> movementsPerDay = Queue();
  movementsGroups.forEach((date, groupedMovements) {
    if (groupedMovements.isNotEmpty) {
      groupedMovements.sort((a, b) {
        if (a == null || b == null) return 0;
        final timeCmp = b.dateTime.compareTo(a.dateTime);
        if (timeCmp != 0) return timeCmp;
        return (b.id ?? 0).compareTo(a.id ?? 0);
      });
      movementsPerDay.addFirst(RecordsPerDay(date, records: groupedMovements));
    }
  });

  // Convert the queue to a list and sort it in descending order by date.
  var movementsDayList = movementsPerDay.toList();
  movementsDayList.sort((b, a) => a.dateTime!.compareTo(b.dateTime!));

  return movementsDayList;
}

String getGroupingSeparator() =>
    PreferencesDefaultValues.getLocaleGroupingSeparator();

String getDecimalSeparator() =>
    PreferencesDefaultValues.getLocaleDecimalSeparator();

/// Typing the other separator types the decimal one.
bool getOverwriteDotValue() => getDecimalSeparator() == ",";

bool getOverwriteCommaValue() => getDecimalSeparator() == ".";

int getNumberDecimalDigits() => 2;

bool getAmountInputAutoDecimalShift() => true;

Locale getCurrencyLocale() {
  return ServiceConfig.currencyLocale!;
}

/// Builds a [NumberFormat] using the user's locale/separator customizations.
///
/// If [decimalDigits] is provided, it overrides the global
/// default of [getNumberDecimalDigits] for this format only.
NumberFormat getNumberFormatWithCustomizations(
    {turnOffGrouping = false, locale, int? decimalDigits}) {
  NumberFormat? numberFormat;

  decimalDigits ??= getNumberDecimalDigits();

  try {
    if (locale == null) {
      locale = getCurrencyLocale();
    }

    final localeTag = LocaleService.tag;

    NumberFormat referenceNumberFormat = new NumberFormat.currency(
        locale: localeTag, symbol: "", decimalDigits: decimalDigits);

    numberFormatSymbols['custom_locale'] = new NumberSymbols(
        NAME: "c",
        DECIMAL_SEP: getDecimalSeparator(),
        GROUP_SEP: getGroupingSeparator(),
        PERCENT: referenceNumberFormat.symbols.PERCENT,
        ZERO_DIGIT: referenceNumberFormat.symbols.ZERO_DIGIT,
        PLUS_SIGN: referenceNumberFormat.symbols.PLUS_SIGN,
        MINUS_SIGN: referenceNumberFormat.symbols.MINUS_SIGN,
        EXP_SYMBOL: referenceNumberFormat.symbols.EXP_SYMBOL,
        PERMILL: referenceNumberFormat.symbols.PERMILL,
        INFINITY: referenceNumberFormat.symbols.INFINITY,
        NAN: referenceNumberFormat.symbols.NAN,
        DECIMAL_PATTERN: referenceNumberFormat.symbols.DECIMAL_PATTERN,
        SCIENTIFIC_PATTERN: referenceNumberFormat.symbols.SCIENTIFIC_PATTERN,
        PERCENT_PATTERN: referenceNumberFormat.symbols.PERCENT_PATTERN,
        CURRENCY_PATTERN: referenceNumberFormat.symbols.CURRENCY_PATTERN,
        DEF_CURRENCY_CODE: referenceNumberFormat.symbols.DEF_CURRENCY_CODE);

    numberFormat = new NumberFormat.currency(
        locale: "custom_locale", symbol: "", decimalDigits: decimalDigits);

    // Copy over some properties
    numberFormat.maximumIntegerDigits =
        referenceNumberFormat.maximumIntegerDigits;
    numberFormat.minimumIntegerDigits =
        referenceNumberFormat.minimumIntegerDigits;

    numberFormat.minimumExponentDigits =
        referenceNumberFormat.minimumExponentDigits;

    numberFormat.maximumFractionDigits =
        referenceNumberFormat.maximumFractionDigits;
    numberFormat.minimumFractionDigits =
        referenceNumberFormat.minimumFractionDigits;

    numberFormat.maximumSignificantDigits =
        referenceNumberFormat.maximumSignificantDigits;
    numberFormat.minimumSignificantDigits =
        referenceNumberFormat.minimumSignificantDigits;
  } on Exception catch (_) {
    numberFormat = new NumberFormat.currency(
        locale: "en_US", symbol: "", decimalDigits: decimalDigits);
  } on ArgumentError catch (_) {
    numberFormat = new NumberFormat.currency(
        locale: "en_US", symbol: "", decimalDigits: decimalDigits);
  }

  if (turnOffGrouping) {
    numberFormat.turnOffGrouping();
  }

  return numberFormat;
}

void setNumberFormatCache() {
  Locale toSet = ServiceConfig.currencyLocale!;
  ServiceConfig.currencyNumberFormat =
      getNumberFormatWithCustomizations(locale: toSet);
  ServiceConfig.currencyNumberFormatWithoutGrouping =
      getNumberFormatWithCustomizations(locale: toSet, turnOffGrouping: true);
}

String getCurrencyValueString(double? value, {turnOffGrouping = false}) {
  if (value == null) return "";
  NumberFormat? numberFormat;
  if (turnOffGrouping) {
    numberFormat = ServiceConfig.currencyNumberFormatWithoutGrouping;
  } else {
    numberFormat = ServiceConfig.currencyNumberFormat;
  }
  if (numberFormat == null) {
    setNumberFormatCache();
    if (turnOffGrouping) {
      numberFormat = ServiceConfig.currencyNumberFormatWithoutGrouping!;
    } else {
      numberFormat = ServiceConfig.currencyNumberFormat!;
    }
  }
  // The format is built with an empty symbol, but locales whose currency
  // pattern places the symbol after the number (e.g. it, de, fr) keep the
  // space reserved for it, yielding a trailing space. The symbol is inserted
  // separately, so strip any stray leading/trailing whitespace.
  return numberFormat.format(value).trim();
}

/// Like [tryParseCurrencyString] but preserves a leading minus sign.
/// Use this when the input may legitimately be negative (e.g. wallet balance).
double? tryParseSignedCurrencyString(String toParse) {
  final isNegative = toParse.trimLeft().startsWith('-');
  final result = tryParseCurrencyString(toParse.replaceFirst('-', ''));
  if (result == null) return null;
  return isNegative ? -result : result;
}

double? tryParseCurrencyString(String toParse) {
  try {
    // Apparently numberFormat.parse is very fragile if for some reason
    // the string contains characters which are not the decimal or the
    // group separator, for this reason, it is better to strip those characters
    // in advance.
    toParse = stripUnknownPatternCharacters(toParse);
    NumberFormat? numberFormat = ServiceConfig.currencyNumberFormat;
    if (numberFormat == null) {
      setNumberFormatCache();
      numberFormat = ServiceConfig.currencyNumberFormat!;
    }
    double r = numberFormat.parse(toParse).toDouble();
    return r;
  } catch (e) {
    return null;
  }
}

String stripUnknownPatternCharacters(String toParse) {
  String decimalSeparator = getDecimalSeparator();
  String groupingSeparator = getGroupingSeparator();
  // Use a regular expression to keep only digits,
  // the decimal separator, and the grouping separator
  String pattern = '[0-9' +
      RegExp.escape(decimalSeparator) +
      RegExp.escape(groupingSeparator) +
      ']';
  RegExp regex = RegExp(pattern);
  String result =
      toParse.split('').where((char) => regex.hasMatch(char)).join();
  return result;
}

// -1 for default
ImageProvider getBackgroundImage(int monthIndex) {
  return BannerImageService.getBannerImage(monthIndex);
}

Future<List<Record?>> getAllRecords(DatabaseInterface database) async {
  return await database.getAllRecords();
}

Future<DateTime?> getDateTimeFirstRecord(DatabaseInterface database) async {
  return await database.getDateTimeFirstRecord();
}

Future<List<Record?>> getRecordsByInterval(
    DatabaseInterface database, DateTime? _from, DateTime? _to) async {
  return await database.getAllRecordsInInterval(_from, _to);
}

Future<List<Record?>> getRecordsByYear(DatabaseInterface database, int year) async {
  /// Returns the list of movements of a given year identified by
  /// :year integer.
  DateTime _from = new DateTime(year, 1, 1);
  DateTime _to = new DateTime(year, 12, 31, 23, 59);
  return await getRecordsByInterval(database, _from, _to);
}

HomepageTimeInterval getHomepageTimeIntervalEnumSetting() =>
    HomepageTimeInterval.CurrentMonth;

OverviewTimeInterval getHomepageOverviewWidgetTimeIntervalEnumSetting() =>
    OverviewTimeInterval.DisplayedRecords;

int getHomepageRecordsMonthStartDay() => 1;

// 'MMMd' provides the localized month name and day (e.g., "Jan 15")
String getShortDateStr(DateTime date) {
  return DateFormat.MMMd().format(date);
}

String getHeaderFromHomepageTimeInterval(HomepageTimeInterval timeInterval) {
  DateTime _now = DateTime.now();
  switch (timeInterval) {
    case HomepageTimeInterval.CurrentMonth:
      return getMonthStr(_now);
    case HomepageTimeInterval.CurrentYear:
      return getYearStr(_now);
    case HomepageTimeInterval.All:
      return 'Todos os registros';
    case HomepageTimeInterval.CurrentWeek:
      return getWeekStr(_now);
  }
}

Future<List<DateTime>> getTimeIntervalFromHomepageTimeInterval(
    DatabaseInterface database, HomepageTimeInterval timeInterval,
    {int monthStartDay = 1}) async {
  DateTime now = DateTime.now();

  if (timeInterval == HomepageTimeInterval.All) {
    DateTime? firstRecord = await database.getDateTimeFirstRecord();
    if (firstRecord == null) {
      // Fallback to current month if no records exist
      return calculateInterval(HomepageTimeInterval.CurrentMonth, now,
          monthStartDay: monthStartDay);
    }
    return [firstRecord, now];
  }

  return calculateInterval(timeInterval, now, monthStartDay: monthStartDay);
}

HomepageTimeInterval mapOverviewTimeIntervalToHomepageTimeInterval(
    OverviewTimeInterval overviewTimeInterval) {
  if (overviewTimeInterval == OverviewTimeInterval.FixAllRecords) {
    return HomepageTimeInterval.All;
  }
  if (overviewTimeInterval == OverviewTimeInterval.FixCurrentYear) {
    return HomepageTimeInterval.CurrentYear;
  }
  if (overviewTimeInterval == OverviewTimeInterval.FixCurrentMonth) {
    return HomepageTimeInterval.CurrentMonth;
  }
  return HomepageTimeInterval.CurrentMonth;
}

Future<List<Record?>> getRecordsByHomepageTimeInterval(
    DatabaseInterface database, HomepageTimeInterval timeInterval,
    {int monthStartDay = 1}) async {
  DateTime _now = DateTime.now();
  switch (timeInterval) {
    case HomepageTimeInterval.CurrentMonth:
      var cycle = calculateMonthCycle(DateTime.now(), monthStartDay);
      return await getRecordsByInterval(database, cycle[0], cycle[1]);
    case HomepageTimeInterval.CurrentYear:
      return await getRecordsByYear(database, _now.year);
    case HomepageTimeInterval.All:
      return await getAllRecords(database);
    case HomepageTimeInterval.CurrentWeek:
      return await getRecordsByInterval(
          database, getStartOfWeek(_now), getEndOfWeek(_now));
  }
}

/// The caixinha's part of each purchase paid partly with one
/// ([Record.isSplitPart]), by the purchase's dinzo_id, when the part enters
/// the counted wallets ([Record.countsAsSetAside]) and the purchase is in
/// [records] too: money the month didn't pay.
Map<String, Record> purchaseParts(Iterable<Record?> records) {
  final purchases = {
    for (final r in records)
      if (r != null && r.dinzoId != null && r.countsAsExpense) r.dinzoId!,
  };
  return {
    for (final r in records)
      if (r != null &&
          r.countsAsSetAside &&
          (r.value ?? 0) > 0 &&
          purchases.contains(r.splitParentDinzoId))
        r.splitParentDinzoId!: r,
  };
}

/// The expenses in [records] at what the month really paid: a
/// purchase partly paid with a caixinha counts without that part (view
/// copies, never saved). The full amount stays available from
/// [Record.countsAsExpense].
List<Record> realExpenses(Iterable<Record?> records) {
  final parts = purchaseParts(records);
  return [
    for (final r in records)
      if (r != null && r.countsAsExpense)
        parts[r.dinzoId] == null
            ? r
            : r.copyWith(value: (r.value ?? 0) + (parts[r.dinzoId]!.value ?? 0)),
  ];
}

/// Money moved between the counted wallets and the others
/// ([Record.countsAsSetAside]), as the summaries show it under income /
/// expenses / balance: [invested] (to a wallet where [isInvestment] says so,
/// i.e. Liberdade Financeira in the budget plan), [saved] (other goals, like
/// the caixinhas) and [taken] back, including the caixinha parts of
/// purchases: Receitas − total gasto − Investido − Guardado + Retirado =
/// Saldo.
class SetAsideSplit {
  final List<Record> invested = [], saved = [], taken = [];

  SetAsideSplit(
    Iterable<Record?> records,
    bool Function(int? walletId) isInvestment,
  ) {
    for (final r in records) {
      if (r != null && r.isInvestmentBuy) invested.add(r);
      if (r != null && r.isInvestmentSell) taken.add(r);
      if (r == null || !r.countsAsSetAside) continue;
      if ((r.value ?? 0) >= 0) {
        taken.add(r);
      } else if (isInvestment(r.transferWalletId)) {
        invested.add(r);
      } else {
        saved.add(r);
      }
    }
  }
}

/// Returns [records] excluding transfers between the user's own wallets:
/// they net to zero and shouldn't count toward a balance total, matching
/// [RecordsPerDay.balance]'s own exclusion of transfers from income/expenses.
List<Record?> balanceRelevantRecords(List<Record?> records) =>
    records.where((r) => r != null && r.countsTowardTotals).toList();

// Softer green/red (the Material 700/400 shades were too strong).
Color incomeAmountColor(Brightness brightness) =>
    brightness == Brightness.dark
        ? const Color(0xFF81B98C)
        : const Color(0xFF4F8A5B);

Color expenseAmountColor(Brightness brightness) =>
    brightness == Brightness.dark
        ? const Color(0xFFE08A84)
        : const Color(0xFFB5524D);

Color _greenShade(Brightness brightness) => incomeAmountColor(brightness);

Color _redShade(Brightness brightness) => expenseAmountColor(brightness);

/// Returns the color used to display [amount], based purely on its sign:
/// green when positive or zero, red when negative. Returns null when amount
/// colorization is disabled.
Color? getAmountColor(double amount, Brightness brightness) {
  return amount >= 0 ? _greenShade(brightness) : _redShade(brightness);
}

/// Returns the color to use for [record]'s amount.
///
/// A transfer between the user's own wallets nets to zero overall, so it's
/// colored neutrally (returns null) when both its wallets - or no wallet
/// filter at all - are currently visible. When exactly one side is visible
/// ([Record.isSingleSideTransferView], set by a wallet-filtered records
/// list), it's colored by sign like a normal record instead: red when
/// leaving the visible wallet, green when arriving into it - [record.value]
/// is already signed for that perspective by the filter that produced it.
/// Non-transfer records are always colored by sign.
Color? getRecordAmountColor(Record record, Brightness brightness) {
  if (record.isTransfer && !record.isSingleSideTransferView) return null;
  // A refund and its expense count for nothing (RefundLink).
  if (record.isRefundPair) return null;
  return getAmountColor(record.value ?? 0.0, brightness);
}

/// The sum of [records].
double recordsTotal(Iterable<Record?> records, {bool isAbsValue = false}) =>
    records.whereType<Record>().fold(
          0.0,
          (sum, r) => sum + (isAbsValue ? r.value!.abs() : r.value!),
        );

/// [value] in reais, with the symbol.
String formatMoney(double value) {
  var numberFormat = ServiceConfig.currencyNumberFormat;
  if (numberFormat == null) {
    setNumberFormatCache();
    numberFormat = ServiceConfig.currencyNumberFormat;
  }
  return 'R\$ ${numberFormat!.format(value).trim()}';
}

/// The sum of the balances of [wallets].
double walletsTotal(Iterable<Wallet> wallets) =>
    wallets.fold(0.0, (sum, w) => sum + (w.balance ?? 0.0));
