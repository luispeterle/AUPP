import 'package:flutter_test/flutter_test.dart';
import 'package:aupp/desktop/asset-workspaces.dart';
import 'package:aupp/investments/asset-sheet.dart';

void main() {
  test('a BDR of a company is analysed at the SEC', () {
    final apple = B3Instrument.of('AAPL34')!;
    expect(apple.type, B3Type.bdr);
    expect(apple.kind, AssetKind.bdr);
    expect(apple.secTicker, 'AAPL');
    expect(apple.description, 'BDR de Apple Inc. (AAPL nos EUA)');
    expect(B3Instrument.of('M1TA34')!.secTicker, 'META');
  });

  test('a BDR of an ETF is an ETF, with its name abroad', () {
    final sp500 = B3Instrument.of('BIVB39')!;
    expect(sp500.kind, AssetKind.etf);
    expect(sp500.description, 'BDR do iShares Core S&P 500 ETF (IVV nos EUA)');
    expect(sp500.secSeries, 'S000004310:C000012040');
  });

  test('the B3 tells the funds apart', () {
    expect(B3Instrument.of('MXRF11')!.kind, AssetKind.fii);
    expect(B3Instrument.of('KNCA11')!.type, B3Type.fiagro);
    expect(B3Instrument.of('KDIF11')!.type, B3Type.infra);
    expect(B3Instrument.of('KNCA11')!.kind, AssetKind.fund);
    expect(B3Instrument.of('BOVA11')!.type, B3Type.etf);
    expect(B3Instrument.of('IVVB11')!.type, B3Type.etfAbroad);
    expect(B3Instrument.of('BPAC11')!.kind, AssetKind.stock);
    // Found by what names them in the CVM's register ("KINEA INFRA" | FIF...,
    // "BTG PACTUAL CRÉDITO IMOBILIÁRIO" | - FUNDO DE CRI...).
    expect(B3Instrument.of('KDIF11')!.cnpj, '26324298000189');
    expect(B3Instrument.of('BTCI11')!.cnpj, '09552812000114');
    expect(B3Instrument.of('MXRF11')!.cnpj, '97521225000125');
  });

  test('an ordinary share is a share; what is abroad is not in it', () {
    expect(B3Instrument.of('PETR4')!.type, B3Type.share);
    expect(B3Instrument.of('PETR4')!.kind, AssetKind.stock);
    expect(B3Instrument.of('AAPL'), isNull);
    expect(B3Instrument.of('BTC'), isNull);
  });

  test('a ticker newer than the app is told by its number', () {
    expect(B3Instrument.of('ZQZQ34')!.type, B3Type.bdr);
    expect(B3Instrument.of('ZQZQ34')!.secTicker, isNull);
    expect(B3Instrument.of('ZQZQ39')!.type, B3Type.bdrEtf);
    expect(B3Instrument.of('ZQZQ11'), isNull);
  });

  test('names: a Fiagro or an infrastructure fund is not a FII', () {
    expect(
      kindFromNames('KNCA11', 'Kinea Credito Agro Fiagro'),
      AssetKind.fund,
    );
    expect(
      kindFromNames('KDIF11', 'Kinea Infra Fundo Investimento'),
      AssetKind.fund,
    );
    expect(kindFromNames('XPML11', 'XP Malls FII'), AssetKind.fii);
  });

  test("a BDR's workspace analyses its company", () {
    final bdr = AssetWorkspace('AAPL34')..kind = AssetKind.bdr;
    expect(bdr.analysed, 'AAPL');
    expect(bdr.hasAnalysis, isTrue);
    expect(bdr.hasCompare, isTrue);
    final unknown = AssetWorkspace('ZQZQ34')..kind = AssetKind.bdr;
    expect(unknown.hasAnalysis, isFalse);
    final etf = AssetWorkspace('BIVB39')..kind = AssetKind.etf;
    expect(etf.hasAnalysis, isFalse);
    final stock = AssetWorkspace('PETR4')..kind = AssetKind.stock;
    expect(stock.analysed, 'PETR4');
  });

  group('search', () {
    List<String> tickers(String q) => [
      for (final r in searchAssets(q)) r.ticker,
    ];

    test('whole tickers, BDRs included', () {
      expect(tickers('AAPL'), contains('AAPL34'));
      expect(tickers('AAPL'), isNot(contains('AAPL')));
      expect(tickers('BIVB'), ['BIVB39']);
      expect(tickers('PETR'), containsAll(['PETR3', 'PETR4']));
    });

    test('a BDR by its company name, saying what it is', () {
      final apple = searchAssets('apple')
          .firstWhere((r) => r.ticker == 'AAPL34');
      expect(apple.what, 'BDR de Apple Inc. (AAPL nos EUA)');
      expect(tickers('core s&p 500'), contains('BIVB39'));
    });

    test('shares first, the exact ticker before all', () {
      expect(tickers('PETR4').first, 'PETR4');
      expect(searchAssets('PETR4').first.what, isNull);
    });
  });
}
