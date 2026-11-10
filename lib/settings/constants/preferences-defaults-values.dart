import 'package:intl/intl.dart';
import 'package:aupp/settings/constants/preferences-keys.dart';

import '../../services/service-config.dart';

class PreferencesDefaultValues {
  static final defaultValues = <String, dynamic>{
    PreferencesKeys.databaseFolderPath: '', // Empty means the default location
    // Manual one-off records allowed on a fresh install (the
    // Dinzo is optional); "Dinzo only" users switch it off.
    PreferencesKeys.allowManualRecords: true,
  };

  static String getLocaleGroupingSeparator() {
    if (ServiceConfig.currencyLocale == null) {
      NumberFormat currencyLocaleNumberFormat = new NumberFormat.currency();
      return currencyLocaleNumberFormat.symbols.GROUP_SEP;
    }
    String existingCurrencyLocale = ServiceConfig.currencyLocale.toString();
    NumberFormat currencyLocaleNumberFormat =
        new NumberFormat.currency(locale: existingCurrencyLocale);
    return currencyLocaleNumberFormat.symbols.GROUP_SEP;
  }

  static String getLocaleDecimalSeparator() {
    if (ServiceConfig.currencyLocale == null) {
      NumberFormat currencyLocaleNumberFormat = new NumberFormat.currency();
      return currencyLocaleNumberFormat.symbols.DECIMAL_SEP;
    }
    String existingCurrencyLocale = ServiceConfig.currencyLocale.toString();
    NumberFormat currencyLocaleNumberFormat =
        new NumberFormat.currency(locale: existingCurrencyLocale);
    return currencyLocaleNumberFormat.symbols.DECIMAL_SEP;
  }
}
