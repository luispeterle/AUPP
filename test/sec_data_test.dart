// Companies abroad from the SEC: the list of tickers, the facts in US GAAP and
// IFRS read into the same figures as the CVM's, the last twelve months from
// the quarterly reports, and the price from the home exchange.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:aupp/investments/asset-sheet.dart';
import 'package:aupp/investments/cvm-statements.dart';
import 'package:aupp/investments/fundamentals.dart';
import 'package:aupp/investments/home-listing.dart';
import 'package:aupp/investments/sec-data.dart';

Map<String, dynamic> _fact(
  String? start,
  String end,
  num value, {
  String form = '10-K',
  String filed = '2025-10-31',
}) => {
  'start': ?start,
  'end': end,
  'val': value,
  'form': form,
  'filed': filed,
};

Map<String, dynamic> _concept(String unit, List<Map<String, dynamic>> facts) =>
    {
      'units': {unit: facts},
    };

/// An Apple-like company: fiscal year ending in September, a 10-Q after it.
Map<String, dynamic> _usFacts() {
  const y24 = ('2023-10-01', '2024-09-28');
  const y25 = ('2024-09-29', '2025-09-27');
  const q26 = ('2025-09-28', '2026-06-27');
  const q25 = ('2024-09-29', '2025-06-28');
  Map<String, dynamic> flow(num a24, num a25, num ytd26, num ytd25) =>
      _concept('USD', [
        _fact(y24.$1, y24.$2, a24),
        _fact(y25.$1, y25.$2, a25),
        _fact(q26.$1, q26.$2, ytd26, form: '10-Q', filed: '2026-07-31'),
        _fact(q25.$1, q25.$2, ytd25, form: '10-Q', filed: '2025-08-01'),
      ]);
  Map<String, dynamic> instant(num a24, num a25, num q) => _concept('USD', [
    _fact(null, y24.$2, a24),
    _fact(null, y25.$2, a25),
    _fact(null, q26.$2, q, form: '10-Q', filed: '2026-07-31'),
  ]);
  return {
    'cik': 320193,
    'entityName': 'Apple Inc.',
    'facts': {
      'dei': {
        'EntityCommonStockSharesOutstanding': _concept('shares', [
          _fact(null, '2026-07-17', 14594180000, form: '10-Q'),
        ]),
      },
      'us-gaap': {
        // The concept changed: the old one for the older year.
        'Revenues': _concept('USD', [_fact(y24.$1, y24.$2, 391035e6)]),
        'RevenueFromContractWithCustomerExcludingAssessedTax': flow(
          390000e6,
          416161e6,
          330000e6,
          313000e6,
        ),
        'NetIncomeLoss': flow(93736e6, 112010e6, 100000e6, 84000e6),
        'OperatingIncomeLoss': flow(123216e6, 133050e6, 110000e6, 98000e6),
        'IncomeTaxExpenseBenefit': flow(29749e6, 20719e6, 17000e6, 15000e6),
        'PaymentsToAcquirePropertyPlantAndEquipment': flow(
          9447e6,
          12715e6,
          10000e6,
          9000e6,
        ),
        'NetCashProvidedByUsedInOperatingActivities': flow(
          118254e6,
          111482e6,
          95000e6,
          81000e6,
        ),
        'StockholdersEquity': instant(56950e6, 73733e6, 80000e6),
        'Assets': instant(364980e6, 359241e6, 350000e6),
        'LongTermDebt': instant(96700e6, 90678e6, 88000e6),
        'CommercialPaper': instant(9967e6, 7979e6, 5000e6),
        'CashAndCashEquivalentsAtCarryingValue': instant(
          29943e6,
          35934e6,
          30000e6,
        ),
      },
    },
  };
}

void main() {
  test('the SEC list: tickers, the first listing of a company, search', () {
    final listings = SecCatalog.parse({
      'fields': ['cik', 'name', 'ticker', 'exchange'],
      'data': [
        [320193, 'Apple Inc.', 'AAPL', 'Nasdaq'],
        [1094517, 'TOYOTA MOTOR CORP/', 'TM', 'NYSE'],
        [1094517, 'TOYOTA MOTOR CORP/', 'TOYOF', 'OTC'],
        [1000184, 'SAP SE', 'SAP', 'NYSE'],
      ],
    });
    final catalog = SecCatalog()..setForTest(listings.values);
    expect(catalog.search('toyota').map((l) => l.ticker), ['TM', 'TOYOF']);
    expect(catalog.search('sap').first.ticker, 'SAP');
    expect(SecCatalog.displayName('TOYOTA MOTOR CORP/'), 'Toyota Motor Corp');
    expect(SecCatalog.displayName('Apple Inc.'), 'Apple Inc.');
    expect(catalog.nameOf('TM'), 'Toyota Motor Corp');
  });

  test('US GAAP facts: years by the end of the fiscal year, signs as the CVM',
      () {
    final company = SecFacts.parse('AAPL', _usFacts(), {'sic': '3571'})!;
    expect(company.currency, 'USD');
    expect(company.foreignIssuer, isFalse);
    expect(company.years.keys, containsAll([2024, 2025]));
    final y25 = company.years[2025]!;
    expect(y25[Figure.revenue], 416161e6);
    expect(company.years[2024]![Figure.revenue], 391035e6, reason: 'old concept');
    expect(y25[Figure.incomeTax], -20719e6);
    expect(y25[Figure.capex], -12715e6);
    expect(y25[Figure.grossDebt], 90678e6 + 7979e6);
    expect(company.shares, 14594180000);
  });

  test('the company number may come as text with zeros', () {
    final facts = {..._usFacts(), 'cik': '0000320193'};
    expect(SecFacts.parse('AAPL', facts, null)!.code, 'SEC320193');
  });

  test('the last twelve months from the 10-Q', () {
    final company = SecFacts.parse('AAPL', _usFacts(), null)!;
    expect(company.ttmEnd, DateTime(2026, 6, 27));
    expect(company.ttm![Figure.revenue], 416161e6 + 330000e6 - 313000e6);
    expect(company.ttm![Figure.netIncome], 112010e6 + 100000e6 - 84000e6);
    expect(company.ttm![Figure.equity], 80000e6, reason: 'the quarter balance');
  });

  test('IFRS facts in the currency most facts are in', () {
    final company = SecFacts.parse('SAP', {
      'cik': 1000184,
      'entityName': 'SAP SE',
      'facts': {
        'ifrs-full': {
          'Revenue': {
            'units': {
              'EUR': [
                _fact('2024-01-01', '2024-12-31', 34176e6, form: '20-F'),
                _fact('2025-01-01', '2025-12-31', 36800e6, form: '20-F'),
              ],
              // A convenience translation of the last year.
              'USD': [_fact('2025-01-01', '2025-12-31', 40000e6, form: '20-F')],
            },
          },
          'ProfitLossAttributableToOwnersOfParent': _concept('EUR', [
            _fact('2024-01-01', '2024-12-31', 3150e6, form: '20-F'),
            _fact('2025-01-01', '2025-12-31', 7000e6, form: '20-F'),
          ]),
          'EquityAttributableToOwnersOfParent': _concept('EUR', [
            _fact(null, '2024-12-31', 44000e6, form: '20-F'),
            _fact(null, '2025-12-31', 46000e6, form: '20-F'),
          ]),
          'Borrowings': _concept('EUR', [
            _fact(null, '2025-12-31', 7000e6, form: '20-F'),
          ]),
          'LeaseLiabilities': _concept('EUR', [
            _fact(null, '2025-12-31', 1500e6, form: '20-F'),
          ]),
        },
      },
    }, null)!;
    expect(company.currency, 'EUR');
    expect(company.foreignIssuer, isTrue);
    expect(company.years[2025]![Figure.revenue], 36800e6);
    expect(company.years[2025]![Figure.grossDebt], 8500e6);
    expect(company.ttmEnd, DateTime(2025, 12, 31), reason: 'no quarters');
  });

  test('current reports become notices, results marked', () {
    final notices = SecFacts.notices({
      'cik': '320193',
      'filings': {
        'recent': {
          'accessionNumber': ['0000320193-26-000018', '0000320193-26-000020', 'x'],
          'filingDate': ['2026-07-30', '2026-07-31', '2026-07-01'],
          'form': ['8-K', '10-Q', '4'],
          'items': ['2.02,9.01', '', ''],
          'primaryDocument': ['a.htm', 'b.htm', 'c.htm'],
          'primaryDocDescription': ['8-K', '10-Q', ''],
        },
      },
    }, DateTime(2025, 11, 1));
    expect(notices.map((n) => n.category), ['Resultados', 'Relatório trimestral']);
    expect(notices.first.subject, 'Resultados');
    expect(
      notices.first.url,
      'https://www.sec.gov/Archives/edgar/data/320193/000032019326000018/a.htm',
    );
  });

  group('home listing', () {
    test('a name to search and the symbols brapi takes', () {
      expect(HomeListing.searchName('TOYOTA MOTOR CORP/'), 'TOYOTA MOTOR');
      expect(HomeListing.searchName('SAP SE'), 'SAP');
      expect(HomeListing.searchName('NOVO NORDISK A S'), 'NOVO NORDISK');
      expect(const FigiListing('SIEMENS AG-REG', 'SIE', 'GY').symbols, ['SIE.DE']);
      expect(
        const FigiListing('NOVO NORDISK A/S-B', 'NOVOB', 'DC').symbols,
        ['NOVOB.CO', 'NOVO-B.CO'],
      );
      expect(const FigiListing('X', 'X', 'US').symbols, isEmpty);
    });

    test('OpenFIGI: common stocks on the exchanges brapi quotes', () {
      final found = OpenFigi.parse({
        'data': [
          {'name': 'SIEMENS AG-REG', 'ticker': 'SIE', 'exchCode': 'GY', 'securityType2': 'Common Stock'},
          {'name': 'SIEMENS AG-REG', 'ticker': 'SIE', 'exchCode': 'US', 'securityType2': 'Common Stock'},
          {'name': 'SIEMENS AG-SPON ADR', 'ticker': 'SIEGY', 'exchCode': 'GY', 'securityType2': 'Depositary Receipt'},
          {'name': 'TAIWAN SEMICONDUCTOR MANUFAC', 'ticker': '2330', 'exchCode': 'TT (Taiwan Stock Exchange)', 'securityType2': 'Common Stock'},
        ],
      });
      expect(found.map((f) => f.ticker), ['SIE', '2330']);
      expect(found.last.symbols, ['2330.TW']);
    });

    test('an ADR is priced at home, in the statements\' currency', () async {
      Fx.setForTest({'USD': 5.0, 'JPY': 0.035});
      final quotes = {
        'TM': const AssetQuote(ticker: 'TM', price: 195.71, currency: 'USD'),
        '7203.T': const AssetQuote(ticker: '7203.T', price: 3070, currency: 'JPY'),
      };
      HomeListing.quote = (symbol) async => quotes[symbol];
      final saved = <String, String>{};
      HomeListing.file = () async => throw UnsupportedError('no disk');
      OpenFigi.client = () => MockClient(
        (_) async => http.Response(
          jsonEncode({
            'data': [
              {'name': 'TOYOTA MOTOR CORP', 'ticker': '7203', 'exchCode': 'JT', 'securityType2': 'Common Stock'},
            ],
          }),
          200,
        ),
      );
      final toyota = CvmCompany(
        code: 'SEC1094517',
        name: 'TOYOTA MOTOR CORP/',
        currency: 'JPY',
        foreignIssuer: true,
        sharesOn: 13e9,
      );
      final price = (await HomeListing.priceFor(toyota, 'TM'))!;
      expect(price.symbol, '7203.T');
      expect(price.price, 3070);
      expect(price.currency, 'JPY');
      // 195,71 USD × 5 ÷ 0,035 = 27 959 JPY: about 9 shares... of 3070.
      expect(price.adrShares, closeTo(195.71 * 5 / 0.035 / 3070, 1e-9));
      final f = Fundamentals.priced(toyota, 'TM', price.price);
      expect(f.marketCap, 3070 * 13e9);
      expect(saved, isEmpty);
    });
  });

  test('tickers of the B3 and abroad', () {
    expect(isB3Ticker('PETR4'), isTrue);
    expect(isB3Ticker('TAEE11'), isTrue);
    expect(isB3Ticker('B3SA3'), isTrue);
    expect(isB3Ticker('AAPL'), isFalse);
    expect(isB3Ticker('SIE.DE'), isFalse);
    expect(isB3Ticker('7203.T'), isFalse);
  });

  test('abroad, the sites are the AUVP\'s international pages and the SEC', () {
    final us = assetLinks('AAPL', 'Apple');
    expect(us.map((l) => l.label), ['AUVP Analítica', 'SEC', 'RI da empresa', 'Notícias']);
    expect(us.first.url.toString(), 'https://analitica.auvp.com.br/stocks/AAPL');
    expect(
      assetLinks('VOO', 'Vanguard', kind: AssetKind.etf).first.url.path,
      '/etfs/VOO',
    );
    expect(assetLinks('SIE.DE', 'Siemens').map((l) => l.label), ['RI da empresa', 'Notícias']);
    // EDGAR's page wants the company's number; given a ticker it shows the
    // last company seen.
    SecCatalog.instance.setForTest([
      const SecListing(1045810, 'NVIDIA CORP', 'NVDA', 'Nasdaq'),
    ]);
    String sec(String ticker) => assetLinks(ticker, ticker)
        .firstWhere((l) => l.label == 'SEC')
        .url
        .toString();
    expect(sec('NVDA'), 'https://www.sec.gov/edgar/browse/?CIK=1045810');
    expect(sec('XYZW'), contains('/cgi-bin/browse-edgar?action=getcompany&CIK=XYZW'));
  });
}
