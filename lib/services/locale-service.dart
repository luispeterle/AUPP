import 'dart:ui';

import 'package:aupp/helpers/records-utility-functions.dart';
import 'package:aupp/services/service-config.dart';

/// The app speaks Brazilian Portuguese and counts in reais.
class LocaleService {
  static const Locale locale = Locale('pt', 'BR');

  /// The same, as intl names it.
  static const String tag = 'pt_BR';

  static void setCurrencyLocale() {
    ServiceConfig.currencyLocale = locale;
    ServiceConfig.currencyNumberFormat =
        getNumberFormatWithCustomizations(locale: locale);
    ServiceConfig.currencyNumberFormatWithoutGrouping =
        getNumberFormatWithCustomizations(locale: locale, turnOffGrouping: true);
  }
}
