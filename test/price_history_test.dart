import 'package:flutter_test/flutter_test.dart';
import 'package:aupp/components/source-mark.dart';
import 'package:aupp/investments/asset-sheet.dart';
import 'package:aupp/investments/price-history.dart';
import 'package:aupp/investments/yahoo-chart.dart';

void main() {
  test('Yahoo: closes as they were, days without one skipped', () {
    final day = DateTime(2026, 3, 2, 13).millisecondsSinceEpoch ~/ 1000;
    final parsed = YahooChart.parse({
      'chart': {
        'result': [
          {
            'meta': {'regularMarketPrice': 12.5, 'currency': 'BRL'},
            'timestamp': [day, day + 86400, day + 2 * 86400],
            'indicators': {
              'quote': [
                {
                  'close': [10.0, null, 11.5],
                },
              ],
              'adjclose': [
                {
                  'adjclose': [9.0, null, 10.5],
                },
              ],
            },
          },
        ],
      },
    });
    expect(parsed.closes, [
      (DateTime(2026, 3, 2), 10.0),
      (DateTime(2026, 3, 4), 11.5),
    ]);
    expect(parsed.price, 12.5);
    expect(parsed.currency, 'BRL');
    expect(YahooChart.parse({'chart': {'result': null}}).closes, isEmpty);
  });

  test('a B3 ticker gets the suffix; one abroad stays as is', () {
    expect(YahooChart.symbolOf('PETR4'), 'PETR4.SA');
    expect(YahooChart.symbolOf('AAPL34'), 'AAPL34.SA');
    expect(YahooChart.symbolOf('VOO'), 'VOO');
    expect(YahooChart.symbolOf('SIE.DE'), 'SIE.DE');
  });

  test('a range keeps its days; a shorter history stays whole', () {
    final history = [
      for (var i = 0; i < 800; i++)
        (DateTime(2024, 1, 1).add(Duration(days: i)), i.toDouble()),
    ];
    final year = inRange(history, PriceRange.y1);
    expect(year.first.$1, history.last.$1.subtract(const Duration(days: 365)));
    expect(year.last, history.last);
    expect(inRange(history, PriceRange.y5), history);
    expect(inRange(history, PriceRange.all), history);
  });

  test('every quote says its price is not from an official source', () {
    final brapi = AssetQuote.fromBrapiJson('PETR4', {
      'results': [
        {
          'data': {'regularMarketPrice': 40.0},
        },
      ],
    })!;
    expect(brapi.priceSource, Unofficial.brapi);
    expect(brapi.historySource, Unofficial.brapi);
    final coin = AssetQuote.fromCoinGeckoJson('BTC', {
      'prices': [
        [1, 100.0],
        [2, 110.0],
      ],
    })!;
    expect(coin.priceSource, Unofficial.coingecko);
    expect(PriceRangeBar.nameOf(Unofficial.yahoo), 'Yahoo Finance');
  });

  test('a choice of range only when there is one to make', () {
    List<(DateTime, double)> days(int count) => [
      for (var i = 0; i < count; i++)
        (DateTime(2020, 1, 1).add(Duration(days: i)), 1.0),
    ];
    // brapi's three months: 3M and Máx would be the same chart.
    expect(PriceRangeBar.rangesOf(days(92)), [PriceRange.m3]);
    expect(PriceRangeBar.rangesOf(days(800)), [
      PriceRange.m3,
      PriceRange.m6,
      PriceRange.y1,
      PriceRange.all,
    ]);
    expect(PriceRangeBar.rangesOf(days(3650)), PriceRange.values);
    // Five years and a bit: Máx is almost 5A.
    expect(PriceRangeBar.rangesOf(days(1900)).last, PriceRange.y5);
  });
}
