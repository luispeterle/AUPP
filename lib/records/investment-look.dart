import 'package:aupp/investments/investments-analytics.dart';
import 'package:aupp/investments/stock-catalog.dart';
import 'package:aupp/models/record.dart';

/// How an aporte or a resgate shows in the Extrato when its title says what
/// was bought: the company's logo for a B3 ticker ("BBAS3 X 1", "Compra de
/// GOLD11 no Rico"), Tesouro Direto's for a Tesouro ("Tesouro IPCA+ 2032",
/// "Compra de Tesouro no BTG").
class InvestmentLook {
  static final _ticker = RegExp(r'^[A-Z]{4}\d{1,2}$');
  static final _tesouro = RegExp(r'\btesouro\b', caseSensitive: false);

  /// Asset path of the logo; null when [record] is no aporte or resgate, or
  /// its title names nothing known.
  static String? logoOf(Record record) {
    if (!record.isInvestmentFlow) return null;
    final title = (record.title ?? '').trim();
    if (_tesouro.hasMatch(title)) {
      return Institution.tesouroDireto.logo;
    }
    for (final word in title.split(RegExp(r'\s+'))) {
      final code = word.toUpperCase();
      if (!_ticker.hasMatch(code)) continue;
      final logo = StockCompany.of(code)?.logo;
      if (logo != null) return logo;
    }
    return null;
  }
}
