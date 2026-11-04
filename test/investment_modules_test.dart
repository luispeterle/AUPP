// Nacional, Internacional and Cripto: the search of a ticker abroad and the
// parts of the Divisão.
import 'package:flutter_test/flutter_test.dart';
import 'package:aupp/investments/diagram-page.dart';
import 'package:aupp/investments/diagram.dart';
import 'package:aupp/investments/ticker-search.dart';

void main() {
  group('searchAbroad', () {
    test('by ticker, by name, and with a typo', () {
      expect(searchAbroad('nvda').first, 'NVDA');
      expect(searchAbroad('nvdea').first, 'NVDA');
      expect(searchAbroad('nvidia').first, 'NVDA');
      expect(searchAbroad('apple').first, 'AAPL');
      expect(searchAbroad('VOO').first, 'VOO');
      expect(searchAbroad('realty'), contains('O'));
    });

    test('nothing for nothing, nor for what is far from every name', () {
      expect(searchAbroad(''), isEmpty);
      expect(searchAbroad('zzzzzz'), isEmpty);
    });
  });

  group('divisionOf', () {
    DiagramAsset asset(String key, DiagramClass cls, double value) =>
        DiagramAsset(key: key, label: key, cls: cls, ticker: key, value: value);

    test('each class on its own, with its own target', () {
      final groups = divisionOf(
        [
          asset('PETR4', DiagramClass.nationalStock, 300),
          asset('CDB A', DiagramClass.fixedIncome, 200),
          asset('CDB B', DiagramClass.fixedIncome, 250),
          asset('MXRF11', DiagramClass.fii, 100),
          asset('VOO', DiagramClass.intlStock, 900),
          asset('BBAS3', DiagramClass.nationalStock, 0),
        ],
        const [
          DiagramClass.nationalStock,
          DiagramClass.fii,
          DiagramClass.fixedIncome,
        ],
        {
          DiagramClass.nationalStock: 15,
          DiagramClass.fii: 15,
          DiagramClass.fixedIncome: 35,
          DiagramClass.intlStock: 25,
        },
      );
      expect(
        [
          for (final g in groups)
            (g.label, g.target, g.slices.map((s) => s.label).join(','), g.total),
        ],
        [
          ('Ações Nacionais', 15.0, 'PETR4', 300.0),
          ('Fundos Imobiliários', 15.0, 'MXRF11', 100.0),
          ('Renda Fixa', 35.0, 'Renda fixa', 450.0),
        ],
      );
    });
  });
}
