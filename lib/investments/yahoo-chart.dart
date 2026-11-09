import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:aupp/investments/asset-sheet.dart';
import 'package:aupp/services/logger.dart';

/// Daily closes and the last price from Yahoo Finance's chart endpoint, for
/// the years of history brapi's plan does not give (three months). Not an
/// official source and not a documented API: everything from here is marked
/// ([Unofficial.yahoo]).
class YahooChart {
  static final _logger = Logger.withClass(YahooChart);

  /// "PETR4" → "PETR4.SA"; a ticker abroad as is ("AAPL", "SIE.DE").
  static String symbolOf(String ticker) =>
      isB3Ticker(ticker) ? '$ticker.SA' : ticker;

  /// Closes (not adjusted: the price as it was) and what the answer says of
  /// the last price. Empty closes when Yahoo has no history of it; [fetch]
  /// gives null when it did not answer.
  static ({List<(DateTime, double)> closes, double? price, String? currency})
  parse(Map<String, dynamic> json) {
    final result = ((json['chart'] as Map?)?['result'] as List?)?.firstOrNull;
    if (result is! Map) return (closes: const [], price: null, currency: null);
    final meta = (result['meta'] as Map?) ?? const {};
    final times = (result['timestamp'] as List?) ?? const [];
    final quote =
        (((result['indicators'] as Map?)?['quote'] as List?)?.firstOrNull
            as Map?) ??
        const {};
    final closes = (quote['close'] as List?) ?? const [];
    final out = <(DateTime, double)>[];
    for (var i = 0; i < times.length && i < closes.length; i++) {
      final close = (closes[i] as num?)?.toDouble();
      if (close == null || close <= 0) continue;
      final at = DateTime.fromMillisecondsSinceEpoch(
        (times[i] as num).toInt() * 1000,
      );
      out.add((DateTime(at.year, at.month, at.day), close));
    }
    return (
      closes: out,
      price: (meta['regularMarketPrice'] as num?)?.toDouble(),
      currency: meta['currency'] as String?,
    );
  }

  static Future<
    ({List<(DateTime, double)> closes, double? price, String? currency})?
  >
  fetch(String ticker, http.Client client, {String range = '10y'}) async {
    try {
      final response = await client
          .get(
            Uri.https(
              'query1.finance.yahoo.com',
              '/v8/finance/chart/${symbolOf(ticker)}',
              {'range': range, 'interval': '1d'},
            ),
            // Says who asks; it answers without passing for a browser.
            headers: const {'User-Agent': 'AUPP'},
          )
          // A phone's connection may be busy with the reports downloaded
          // when the app opens.
          .timeout(const Duration(seconds: 60));
      if (response.statusCode != 200) return null;
      return parse(jsonDecode(response.body) as Map<String, dynamic>);
    } catch (e, st) {
      _logger.handle(e, st, 'Yahoo chart of $ticker failed');
      return null;
    }
  }
}
