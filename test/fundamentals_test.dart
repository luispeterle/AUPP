// The analysis indicators, on Petrobras's figures of June 2026 (last twelve
// months) and its 2021 year, against the values research sites show.
import 'package:flutter_test/flutter_test.dart';
import 'package:aupp/investments/b3-market.dart';
import 'package:aupp/investments/cvm-statements.dart';
import 'package:aupp/investments/cvm-store.dart';
import 'package:aupp/investments/diagram.dart';
import 'package:aupp/investments/fundamentals.dart';

Figures _figures(Map<Figure, double> millions) => Figures({
  for (final e in millions.entries) e.key: e.value * 1e6,
});

final _ttm = _figures({
  Figure.revenue: 548493,
  Figure.grossProfit: 277512,
  Figure.ebit: 185746,
  Figure.incomeTax: -47134,
  Figure.netIncome: 133756,
  Figure.assets: 1279019,
  Figure.currentAssets: 154971,
  Figure.cash: 53764,
  Figure.inventory: 50307,
  Figure.currentLiabilities: 181372,
  Figure.grossDebt: 366533,
  Figure.equity: 481854,
  Figure.cfo: 214359,
  Figure.capex: -109021,
  Figure.depreciation: 87577,
  Figure.dividendsPaid: 38327,
});

Figures _year(double revenue, double ebit, double income, {double roe = 0.2}) =>
    _figures({
      Figure.revenue: revenue,
      Figure.ebit: ebit,
      Figure.depreciation: 60000,
      Figure.netIncome: income,
      Figure.equity: income / roe,
      Figure.grossDebt: 300000,
      Figure.cash: 60000,
      Figure.dividendsPaid: 50000,
    });

CvmCompany _petrobras({Map<String, (int, int)> units = const {}}) => CvmCompany(
  code: '009512',
  name: 'PETROBRAS',
  founded: DateTime(1953, 10, 3),
  control: 'Estatal Holding',
  tickers: {
    'PETR3': ShareClass.on,
    'PETR4': ShareClass.pn,
    for (final t in units.keys) t: ShareClass.unit,
  },
  units: units,
  years: {
    2021: _year(452668, 210831, 107264),
    2022: _year(641256, 294255, 189005),
    2023: _year(511994, 189342, 125166),
    2024: _year(490829, 137201, 37009),
    2025: _year(497549, 145628, 110605),
  },
  ttm: _ttm,
  ttmEnd: DateTime(2026, 6, 30),
  sharesOn: 7442231382,
  sharesPn: 5446501379,
);

void main() {
  final prices = {'PETR3': 60.01, 'PETR4': 52.71};
  final f = Fundamentals(_petrobras(), 'PETR3', prices);
  double value(String id) => f.value(Indicator.byId(id))!;

  test('market cap: each class at its own price', () {
    expect(f.marketCap, closeTo(7442231382 * 60.01 + 5446501379 * 52.71, 1));
  });

  test('a class without a price takes the other\'s; a unit splits its price', () {
    final onlyOn = Fundamentals.marketCapOf(_petrobras(), {'PETR3': 60.0});
    expect(onlyOn, closeTo(12888732761 * 60.0, 1));
    final unit = Fundamentals.marketCapOf(
      _petrobras(units: {'PETR11': (1, 2)}),
      {'PETR11': 150.0},
    );
    expect(unit, closeTo(12888732761 * 50.0, 1));
  });

  test('per share and multiples', () {
    expect(value('lpa'), closeTo(10.38, 0.01));
    expect(value('vpa'), closeTo(37.39, 0.01));
    expect(value('pl'), closeTo(5.78, 0.01));
    expect(value('pvp'), closeTo(1.61, 0.01));
    expect(value('evEbitda'), closeTo(3.83, 0.01));
    expect(value('evEbit'), closeTo(5.63, 0.01));
    expect(value('earningsYield'), closeTo(0.1823, 0.0001));
  });

  test('a unit stands for its shares', () {
    final unit = Fundamentals(
      _petrobras(units: {'PETR11': (1, 2)}),
      'PETR11',
      {...prices, 'PETR11': 180.0},
    );
    expect(unit.value(Indicator.byId('lpa')), closeTo(10.38 * 3, 0.03));
  });

  test('debt, margins and returns', () {
    expect(value('netDebtEbitda'), closeTo(1.14, 0.01));
    expect(value('netDebtEquity'), closeTo(0.65, 0.01));
    expect(value('ebitdaMargin'), closeTo(0.4983, 0.0001));
    expect(value('ebitMargin'), closeTo(0.3386, 0.0001));
    expect(value('roe'), closeTo(0.2776, 0.0001));
    // (EBIT − tax) ÷ (equity + gross debt).
    expect(value('roic'), closeTo(0.1634, 0.0001));
    expect(value('payout'), closeTo(0.2865, 0.0001));
  });

  test('growth: twelve months against the year five years before', () {
    expect(value('cagrRevenue'), closeTo(0.0392, 0.0001));
    expect(value('cagrIncome'), closeTo(0.0451, 0.0001));
    expect(value('cagrEbit'), closeTo(-0.0250, 0.0001));
  });

  test('a loss gives no multiple', () {
    final loss = Fundamentals(
      CvmCompany(
        code: '1',
        name: 'X',
        tickers: const {'XPTO3': ShareClass.on},
        ttm: _figures({Figure.netIncome: -10, Figure.equity: 100}),
        ttmEnd: DateTime(2026, 6, 30),
        sharesOn: 1e6,
      ),
      'XPTO3',
      const {'XPTO3': 10},
    );
    expect(loss.value(Indicator.byId('pl')), isNull);
    expect(
      loss.criteria(DateTime(2026, 11, 1))['O P/L está abaixo de 30?']?.$1,
      isFalse,
    );
  });

  test('history needs no price and skips what has one', () {
    expect(f.history(Indicator.byId('roe')).keys, [2021, 2022, 2023, 2024, 2025]);
    expect(f.history(Indicator.byId('pl')), isEmpty);
  });

  test('the criteria the numbers answer, all of them real questions', () {
    final criteria = f.criteria(DateTime(2026, 11, 1));
    expect(
      DiagramState.defaultStockQuestions,
      containsAll(criteria.keys),
      reason: 'a renamed question would never match',
    );
    expect(criteria['Tem mais de 30 anos de mercado?']?.$1, isTrue);
    expect(criteria['É uma empresa grande (blue chip)?']?.$1, isTrue);
    expect(
      criteria['É independente do governo e de um único cliente?']?.$1,
      isFalse,
    );
    expect(
      criteria['A dívida líquida é menor que o lucro dos últimos 12 meses?']?.$1,
      isFalse,
    );
    expect(criteria['O P/VP está abaixo de 5?']?.$1, isTrue);
    expect(criteria['Tem histórico de pagar dividendos?']?.$1, isTrue);
    expect(
      criteria.containsKey('É líder no seu setor, no país ou no mundo?'),
      isFalse,
    );
  });

  test('fair prices: Graham and Bazin against the price, in bands', () {
    final graham = f.graham!;
    expect(graham.fair, closeTo(93.43, 0.01));
    expect(graham.upside, closeTo(93.43 / 60.01 - 1, 0.001));
    expect(graham.band, FairBand.veryCheap);
    // 50 000 mi a year over 12,9 bi shares ÷ 6%.
    expect(f.bazin!.fair, closeTo(50000e6 / 12888732761 / 0.06, 0.01));
    expect(FairBand.of(-0.5), FairBand.veryExpensive);
    expect(FairBand.of(-0.2), FairBand.expensive);
    expect(FairBand.of(0.05), FairBand.near);
    expect(FairBand.of(0.2), FairBand.below);
  });

  test('proventos per share each year', () {
    expect(f.dividendsPerShare[2025], closeTo(50000e6 / 12888732761, 1e-9));
  });

  test('tag along by the segment', () {
    expect(tagAlongOf('Novo Mercado'), startsWith('100%'));
    expect(tagAlongOf('Nível 2 de Governança Corporativa'), contains('ON e PN'));
    expect(tagAlongOf('Nível 1 de Governança Corporativa'), startsWith('80%'));
    expect(tagAlongOf(null), isNull);
  });

  test('best and worst of a row follow the better side', () {
    final pl = Indicator.byId('pl');
    expect(bestAndWorst(pl, [5.8, null, 12.0, 30.0]), (5.8, 30.0));
    expect(bestAndWorst(Indicator.byId('roe'), [0.1, 0.3]), (0.3, 0.1));
    expect(bestAndWorst(pl, [5.8]), isNull);
    expect(bestAndWorst(Indicator.byId('ev'), [1.0, 2.0]), isNull);
  });

  test('a company whose register has no ticker is found by brapi\'s name', () {
    CvmStore.instance.setForTest([
      CvmCompany(code: '4030', name: 'CIA SIDERURGICA NACIONAL', sharesOn: 1e9),
    ]);
    B3Market.instance.setForTest([
      const MarketRow(ticker: 'CSNA3', name: 'Cia. Siderúrgica Nacional S.A.', price: 4),
      const MarketRow(ticker: 'XPTO3', name: 'Outra', price: 1),
    ]);
    final found = CvmStore.instance.byTicker('CSNA3')!;
    expect(found.code, '4030');
    expect(found.tickers, {'CSNA3': ShareClass.on});
    expect(Fundamentals.marketCapOf(found, B3Market.instance.prices), 4e9);
    expect(CvmStore.instance.byTicker('XPTO3'), isNull);
  });

  test('brapi\'s list: rows with a price, peers by subsector', () {
    final rows = B3Market.parse({
      'stocks': [
        {'stock': 'PETR4', 'close': 52.71, 'volume': 61743200, 'sector': 'Energy Minerals', 'subsector': 'Petróleo e Gás Integrado'},
        {'stock': 'PETR3', 'close': 60.01, 'volume': 22506600, 'sector': 'Energy Minerals', 'subsector': 'Petróleo e Gás Integrado'},
        {'stock': 'PRIO3', 'close': 40.0, 'volume': 9000000, 'sector': 'Energy Minerals', 'subsector': 'Exploração e Produção'},
        {'stock': 'VBBR3', 'close': 20.0, 'volume': 5000000, 'sector': 'Retail Trade', 'subsector': 'Exploração, Refino e Distribuição'},
        {'stock': 'PETR4F', 'close': 52.71},
        {'stock': 'XXXX3', 'close': null},
      ],
    });
    expect(rows.keys, ['PETR4', 'PETR3', 'PRIO3', 'VBBR3']);
    final market = B3Market()..setForTest(rows.values);
    // The subsector, written two ways, then the sector.
    final petr3 = rows['PETR3']!;
    market.setForTest([
      ...rows.values.where((r) => r.ticker != 'PETR3'),
      MarketRow(
        ticker: 'PETR3',
        name: petr3.name,
        price: petr3.price,
        volume: petr3.volume,
        sector: petr3.sector,
        subsector: 'Exploração. Refino e Distribuição',
      ),
    ]);
    expect(
      market.peersOf('PETR3').map((r) => r.ticker),
      ['PETR3', 'VBBR3', 'PETR4', 'PRIO3'],
    );
    expect(market.prices['PRIO3'], 40.0);
  });
}
