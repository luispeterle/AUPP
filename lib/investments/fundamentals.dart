import 'dart:math' as math;

import 'package:intl/intl.dart';

import 'package:aupp/investments/cvm-statements.dart';

/// The groups of the analysis, in the order they are shown.
enum IndicatorGroup {
  valuation('Valuation'),
  debt('Endividamento'),
  efficiency('Eficiência'),
  returns('Rentabilidade'),
  growth('Crescimento');

  const IndicatorGroup(this.label);
  final String label;
}

enum IndicatorFormat { ratio, percent, money, perShare }

/// What an indicator is computed from: the figures of a period and, for the
/// last twelve months, the price.
class IndicatorInput {
  final Figures figures;

  /// Null for a past year: there is no price to go with it.
  final double? price;
  final double? marketCap;

  /// Shares a ticker stands for: 3 for a unit of 1 ON and 2 PN.
  final double sharesPerTicker;
  final double? shares;
  final CvmCompany company;

  /// The year the period ends; for growth over five years.
  final int year;
  final Figures? fiveYearsBefore;

  /// Proventos paid a year, average of the last five.
  final double? averageDividend;

  const IndicatorInput({
    required this.figures,
    required this.company,
    required this.year,
    this.price,
    this.marketCap,
    this.sharesPerTicker = 1,
    this.shares,
    this.fiveYearsBefore,
    this.averageDividend,
  });

  double? get perShareFactor =>
      shares == null || shares! <= 0 ? null : sharesPerTicker / shares!;

  double? get eps {
    final factor = perShareFactor;
    final income = figures[Figure.netIncome];
    return factor == null || income == null ? null : income * factor;
  }

  double? get bookPerShare {
    final factor = perShareFactor;
    final equity = figures[Figure.equity];
    return factor == null || equity == null ? null : equity * factor;
  }

  double? get enterpriseValue {
    final cap = marketCap;
    final debt = figures.netDebt;
    return cap == null || debt == null ? null : cap + debt;
  }
}

double? _div(double? a, double? b) =>
    a == null || b == null || b == 0 ? null : a / b;

/// A positive multiple: price over a loss means nothing.
double? _multiple(double? a, double? b) =>
    a == null || b == null || b <= 0 ? null : a / b;

double? _cagr(double? now, double? before) {
  if (now == null || before == null || now <= 0 || before <= 0) return null;
  return math.pow(now / before, 1 / 5) - 1;
}

/// An indicator of the analysis and how it is computed. [formula] is shown to
/// the user, so that every number can be checked by hand.
class Indicator {
  final String id;
  final String label;
  final IndicatorGroup group;
  final IndicatorFormat format;
  final String formula;

  /// Which way is better when comparing companies; null when neither is.
  final bool? higherIsBetter;

  /// Needs the price, so it has no history.
  final bool usesPrice;

  final double? Function(IndicatorInput input) compute;

  const Indicator(
    this.id,
    this.label,
    this.group,
    this.format,
    this.formula,
    this.compute, {
    this.higherIsBetter,
    this.usesPrice = false,
  });

  static Indicator byId(String id) => all.firstWhere((i) => i.id == id);

  static final all = <Indicator>[
    // Valuation.
    Indicator(
      'dy',
      'Dividend yield',
      IndicatorGroup.valuation,
      IndicatorFormat.percent,
      'Proventos pagos nos últimos 12 meses ÷ valor de mercado',
      (i) => _div(i.figures[Figure.dividendsPaid], i.marketCap),
      higherIsBetter: true,
      usesPrice: true,
    ),
    Indicator(
      'pl',
      'P/L',
      IndicatorGroup.valuation,
      IndicatorFormat.ratio,
      'Preço ÷ lucro por ação (LPA)',
      (i) => _multiple(i.price, i.eps),
      higherIsBetter: false,
      usesPrice: true,
    ),
    Indicator(
      'pvp',
      'P/VP',
      IndicatorGroup.valuation,
      IndicatorFormat.ratio,
      'Preço ÷ valor patrimonial por ação (VPA)',
      (i) => _multiple(i.price, i.bookPerShare),
      higherIsBetter: false,
      usesPrice: true,
    ),
    Indicator(
      'lpa',
      'LPA',
      IndicatorGroup.valuation,
      IndicatorFormat.perShare,
      'Lucro líquido ÷ número de ações (sem as de tesouraria)',
      (i) => i.eps,
      higherIsBetter: true,
    ),
    Indicator(
      'vpa',
      'VPA',
      IndicatorGroup.valuation,
      IndicatorFormat.perShare,
      'Patrimônio líquido ÷ número de ações',
      (i) => i.bookPerShare,
      higherIsBetter: true,
    ),
    Indicator(
      'evEbitda',
      'EV/EBITDA',
      IndicatorGroup.valuation,
      IndicatorFormat.ratio,
      'Valor da firma ÷ EBITDA (EBIT + depreciação e amortização)',
      (i) => _multiple(i.enterpriseValue, i.figures.ebitda),
      higherIsBetter: false,
      usesPrice: true,
    ),
    Indicator(
      'evEbit',
      'EV/EBIT',
      IndicatorGroup.valuation,
      IndicatorFormat.ratio,
      'Valor da firma ÷ EBIT (lucro operacional)',
      (i) => _multiple(i.enterpriseValue, i.figures[Figure.ebit]),
      higherIsBetter: false,
      usesPrice: true,
    ),
    Indicator(
      'pEbitda',
      'P/EBITDA',
      IndicatorGroup.valuation,
      IndicatorFormat.ratio,
      'Valor de mercado ÷ EBITDA',
      (i) => _multiple(i.marketCap, i.figures.ebitda),
      higherIsBetter: false,
      usesPrice: true,
    ),
    Indicator(
      'pEbit',
      'P/EBIT',
      IndicatorGroup.valuation,
      IndicatorFormat.ratio,
      'Valor de mercado ÷ EBIT',
      (i) => _multiple(i.marketCap, i.figures[Figure.ebit]),
      higherIsBetter: false,
      usesPrice: true,
    ),
    Indicator(
      'psr',
      'P/Receita (PSR)',
      IndicatorGroup.valuation,
      IndicatorFormat.ratio,
      'Valor de mercado ÷ receita líquida',
      (i) => i.company.financial
          ? null
          : _multiple(i.marketCap, i.figures[Figure.revenue]),
      higherIsBetter: false,
      usesPrice: true,
    ),
    Indicator(
      'pFco',
      'P/FCO',
      IndicatorGroup.valuation,
      IndicatorFormat.ratio,
      'Valor de mercado ÷ fluxo de caixa operacional',
      (i) => i.company.financial
          ? null
          : _multiple(i.marketCap, i.figures[Figure.cfo]),
      higherIsBetter: false,
      usesPrice: true,
    ),
    Indicator(
      'pFcl',
      'P/FCL',
      IndicatorGroup.valuation,
      IndicatorFormat.ratio,
      'Valor de mercado ÷ fluxo de caixa livre (operacional − investimento em '
          'imobilizado e intangível)',
      (i) => i.company.financial
          ? null
          : _multiple(i.marketCap, i.figures.freeCashFlow),
      higherIsBetter: false,
      usesPrice: true,
    ),
    Indicator(
      'evRevenue',
      'EV/Receita',
      IndicatorGroup.valuation,
      IndicatorFormat.ratio,
      'Valor da firma ÷ receita líquida',
      (i) => _multiple(i.enterpriseValue, i.figures[Figure.revenue]),
      higherIsBetter: false,
      usesPrice: true,
    ),
    Indicator(
      'earningsYield',
      'Earnings yield',
      IndicatorGroup.valuation,
      IndicatorFormat.percent,
      'Lucro líquido ÷ valor de mercado (o inverso do P/L)',
      (i) => _div(i.figures[Figure.netIncome], i.marketCap),
      higherIsBetter: true,
      usesPrice: true,
    ),
    Indicator(
      'graham',
      'Graham',
      IndicatorGroup.valuation,
      IndicatorFormat.perShare,
      '√(22,5 × LPA × VPA). Serve para eliminar, não é preço-alvo',
      (i) {
        final eps = i.eps;
        final book = i.bookPerShare;
        if (eps == null || book == null || eps <= 0 || book <= 0) return null;
        return math.sqrt(22.5 * eps * book);
      },
      usesPrice: true,
    ),
    Indicator(
      'bazin',
      'Bazin',
      IndicatorGroup.valuation,
      IndicatorFormat.perShare,
      'Proventos por ação, média de 5 anos ÷ 6%. Serve para eliminar, não é '
          'preço-alvo',
      (i) {
        final average = i.averageDividend;
        final factor = i.perShareFactor;
        if (average == null || factor == null || average <= 0) return null;
        return average * factor / 0.06;
      },
      usesPrice: true,
    ),
    Indicator(
      'ev',
      'Valor da firma (EV)',
      IndicatorGroup.valuation,
      IndicatorFormat.money,
      'Valor de mercado + dívida líquida',
      (i) => i.enterpriseValue,
      usesPrice: true,
    ),
    Indicator(
      'marketCap',
      'Valor de mercado',
      IndicatorGroup.valuation,
      IndicatorFormat.money,
      'Ações ON × preço da ON + ações PN × preço da PN',
      (i) => i.marketCap,
      higherIsBetter: true,
      usesPrice: true,
    ),
    // Debt.
    Indicator(
      'netDebtEbitda',
      'Dív. líq./EBITDA',
      IndicatorGroup.debt,
      IndicatorFormat.ratio,
      '(Empréstimos e financiamentos − caixa e aplicações) ÷ EBITDA',
      (i) => _div(i.figures.netDebt, i.figures.ebitda),
      higherIsBetter: false,
    ),
    Indicator(
      'netDebtEquity',
      'Dív. líq./PL',
      IndicatorGroup.debt,
      IndicatorFormat.ratio,
      'Dívida líquida ÷ patrimônio líquido',
      (i) => _div(i.figures.netDebt, i.figures[Figure.equity]),
      higherIsBetter: false,
    ),
    Indicator(
      'grossDebtEquity',
      'Dív. bruta/PL',
      IndicatorGroup.debt,
      IndicatorFormat.ratio,
      'Empréstimos e financiamentos ÷ patrimônio líquido',
      (i) => _div(i.figures[Figure.grossDebt], i.figures[Figure.equity]),
      higherIsBetter: false,
    ),
    Indicator(
      'netDebt',
      'Dívida líquida',
      IndicatorGroup.debt,
      IndicatorFormat.money,
      'Empréstimos e financiamentos (com arrendamentos) − caixa e aplicações',
      (i) => i.figures.netDebt,
      higherIsBetter: false,
    ),
    Indicator(
      'currentRatio',
      'Liq. corrente',
      IndicatorGroup.debt,
      IndicatorFormat.ratio,
      'Ativo circulante ÷ passivo circulante',
      (i) => _div(
        i.figures[Figure.currentAssets],
        i.figures[Figure.currentLiabilities],
      ),
      higherIsBetter: true,
    ),
    Indicator(
      'quickRatio',
      'Liq. seca',
      IndicatorGroup.debt,
      IndicatorFormat.ratio,
      '(Ativo circulante − estoques) ÷ passivo circulante',
      (i) {
        final current = i.figures[Figure.currentAssets];
        return current == null
            ? null
            : _div(
                current - (i.figures[Figure.inventory] ?? 0),
                i.figures[Figure.currentLiabilities],
              );
      },
      higherIsBetter: true,
    ),
    Indicator(
      'cashRatio',
      'Liq. imediata',
      IndicatorGroup.debt,
      IndicatorFormat.ratio,
      'Caixa e aplicações ÷ passivo circulante',
      (i) => _div(i.figures[Figure.cash], i.figures[Figure.currentLiabilities]),
      higherIsBetter: true,
    ),
    Indicator(
      'equityAssets',
      'PL/Ativos',
      IndicatorGroup.debt,
      IndicatorFormat.ratio,
      'Patrimônio líquido ÷ ativo total',
      (i) => _div(i.figures[Figure.equity], i.figures[Figure.assets]),
      higherIsBetter: true,
    ),
    Indicator(
      'liabilitiesAssets',
      'Passivos/Ativos',
      IndicatorGroup.debt,
      IndicatorFormat.ratio,
      '(Ativo total − patrimônio líquido) ÷ ativo total',
      (i) {
        final assets = i.figures[Figure.assets];
        final equity = i.figures[Figure.equity];
        return assets == null || equity == null
            ? null
            : _div(assets - equity, assets);
      },
      higherIsBetter: false,
    ),
    // Efficiency.
    Indicator(
      'grossMargin',
      'Margem bruta',
      IndicatorGroup.efficiency,
      IndicatorFormat.percent,
      'Lucro bruto ÷ receita líquida',
      (i) => _div(i.figures[Figure.grossProfit], i.figures[Figure.revenue]),
      higherIsBetter: true,
    ),
    Indicator(
      'ebitdaMargin',
      'Margem EBITDA',
      IndicatorGroup.efficiency,
      IndicatorFormat.percent,
      'EBITDA ÷ receita líquida',
      (i) => _div(i.figures.ebitda, i.figures[Figure.revenue]),
      higherIsBetter: true,
    ),
    Indicator(
      'ebitMargin',
      'Margem EBIT',
      IndicatorGroup.efficiency,
      IndicatorFormat.percent,
      'EBIT ÷ receita líquida. Prefira à margem EBITDA',
      (i) => _div(i.figures[Figure.ebit], i.figures[Figure.revenue]),
      higherIsBetter: true,
    ),
    Indicator(
      'netMargin',
      'Margem líquida',
      IndicatorGroup.efficiency,
      IndicatorFormat.percent,
      'Lucro líquido ÷ receita líquida (indústria ~8%, serviços ~20%)',
      (i) => i.company.financial
          ? null
          : _div(i.figures[Figure.netIncome], i.figures[Figure.revenue]),
      higherIsBetter: true,
    ),
    // Returns.
    Indicator(
      'roe',
      'ROE',
      IndicatorGroup.returns,
      IndicatorFormat.percent,
      'Lucro líquido ÷ patrimônio líquido',
      (i) => _div(i.figures[Figure.netIncome], i.figures[Figure.equity]),
      higherIsBetter: true,
    ),
    Indicator(
      'roic',
      'ROIC',
      IndicatorGroup.returns,
      IndicatorFormat.percent,
      '(EBIT − imposto de renda) ÷ (patrimônio líquido + dívida bruta)',
      (i) {
        final ebit = i.figures[Figure.ebit];
        final equity = i.figures[Figure.equity];
        if (ebit == null || equity == null) return null;
        return _div(
          ebit + (i.figures[Figure.incomeTax] ?? 0),
          equity + (i.figures[Figure.grossDebt] ?? 0),
        );
      },
      higherIsBetter: true,
    ),
    Indicator(
      'roa',
      'ROA',
      IndicatorGroup.returns,
      IndicatorFormat.percent,
      'Lucro líquido ÷ ativo total',
      (i) => _div(i.figures[Figure.netIncome], i.figures[Figure.assets]),
      higherIsBetter: true,
    ),
    Indicator(
      'payout',
      'Payout',
      IndicatorGroup.returns,
      IndicatorFormat.percent,
      'Proventos pagos ÷ lucro líquido',
      (i) {
        final income = i.figures[Figure.netIncome];
        return income == null || income <= 0
            ? null
            : _div(i.figures[Figure.dividendsPaid], income);
      },
    ),
    Indicator(
      'assetTurnover',
      'Giro do ativo',
      IndicatorGroup.returns,
      IndicatorFormat.ratio,
      'Receita líquida ÷ ativo total',
      (i) => i.company.financial
          ? null
          : _div(i.figures[Figure.revenue], i.figures[Figure.assets]),
      higherIsBetter: true,
    ),
    // Growth.
    Indicator(
      'cagrRevenue',
      'CAGR receita 5a',
      IndicatorGroup.growth,
      IndicatorFormat.percent,
      '(Receita dos últimos 12 meses ÷ receita de 5 anos antes)^(1/5) − 1',
      (i) => _cagr(i.figures[Figure.revenue], i.fiveYearsBefore?[Figure.revenue]),
      higherIsBetter: true,
    ),
    Indicator(
      'cagrEbitda',
      'CAGR EBITDA 5a',
      IndicatorGroup.growth,
      IndicatorFormat.percent,
      'O mesmo, com o EBITDA',
      (i) => _cagr(i.figures.ebitda, i.fiveYearsBefore?.ebitda),
      higherIsBetter: true,
    ),
    Indicator(
      'cagrEbit',
      'CAGR EBIT 5a',
      IndicatorGroup.growth,
      IndicatorFormat.percent,
      'O mesmo, com o EBIT',
      (i) => _cagr(i.figures[Figure.ebit], i.fiveYearsBefore?[Figure.ebit]),
      higherIsBetter: true,
    ),
    Indicator(
      'cagrIncome',
      'CAGR lucro 5a',
      IndicatorGroup.growth,
      IndicatorFormat.percent,
      'O mesmo, com o lucro líquido',
      (i) => _cagr(
        i.figures[Figure.netIncome],
        i.fiveYearsBefore?[Figure.netIncome],
      ),
      higherIsBetter: true,
    ),
  ];
}

/// Prices of the B3, by ticker.
typedef Prices = Map<String, double>;

/// How the price stands against a fair price. The bands are the app's own.
enum FairBand {
  veryExpensive('Muito caro'),
  expensive('Caro'),
  near('Próximo do justo'),
  below('Abaixo do justo'),
  veryCheap('Muito barato');

  const FairBand(this.label);
  final String label;

  /// By the upside: below −30%, −10%, +10%, +30%.
  static FairBand of(double upside) => upside < -0.3
      ? veryExpensive
      : upside < -0.1
      ? expensive
      : upside <= 0.1
      ? near
      : upside <= 0.3
      ? below
      : veryCheap;
}

/// A fair price from a formula, against the current price.
class FairPrice {
  final double fair;
  final double price;

  const FairPrice(this.fair, this.price);

  /// How much the price would rise to reach the fair one.
  double get upside => fair / price - 1;
  FairBand get band => FairBand.of(upside);
}

/// Tag along by the rules of the listing segment; a company's bylaws can give
/// more.
String? tagAlongOf(String? segment) {
  final name = segment?.toLowerCase() ?? '';
  if (name.isEmpty) return null;
  if (name.contains('novo mercado') || name.contains('mais')) {
    return '100% (segmento)';
  }
  if (name.contains('nível 2') || name.contains('nivel 2')) {
    return '100% ON e PN (segmento)';
  }
  return '80% ON, PN sem (lei)';
}

/// A company seen through one of its tickers, at today's prices.
class Fundamentals {
  final CvmCompany company;
  final String ticker;
  final double? price;
  final double? marketCap;

  Fundamentals._(this.company, this.ticker, this.price, this.marketCap);

  factory Fundamentals(CvmCompany company, String ticker, Prices prices) =>
      Fundamentals._(
        company,
        ticker,
        prices[ticker],
        marketCapOf(company, prices),
      );

  /// A company abroad: [price] per ordinary share, in the currency of its
  /// statements; the market cap is that times its shares.
  factory Fundamentals.priced(
    CvmCompany company,
    String ticker,
    double? price,
  ) {
    final shares = company.shares;
    return Fundamentals._(
      company,
      ticker,
      price,
      price == null || shares == null || shares <= 0 ? null : price * shares,
    );
  }

  Figures? get ttm => company.ttm;

  /// ON and PN at their own prices. A class without a price takes the other's,
  /// and one traded only in units takes the unit's price split by its shares.
  static double? marketCapOf(CvmCompany company, Prices prices) {
    double? priceOf(ShareClass kind) {
      for (final e in company.tickers.entries) {
        if (e.value == kind && prices[e.key] != null) return prices[e.key];
      }
      return null;
    }

    var on = priceOf(ShareClass.on);
    var pn = priceOf(ShareClass.pn);
    if (on == null && pn == null) {
      for (final e in company.units.entries) {
        final price = prices[e.key];
        final (unitOn, unitPn) = e.value;
        if (price != null && unitOn + unitPn > 0) {
          on = pn = price / (unitOn + unitPn);
          break;
        }
      }
    }
    on ??= pn;
    pn ??= on;
    if (on == null || company.shares == null) return null;
    return (company.sharesOn ?? 0) * on + (company.sharesPn ?? 0) * pn!;
  }

  double get sharesPerTicker {
    final unit = company.units[ticker];
    return unit == null ? 1 : (unit.$1 + unit.$2).toDouble();
  }

  /// The year the last twelve months end in.
  int? get year => company.ttmEnd?.year;

  /// Proventos paid a year, average of the last five closed years.
  double? get averageDividend {
    final years = company.sortedYears.reversed.take(5).toList();
    if (years.isEmpty) return null;
    final paid = [
      for (final y in years) company.years[y]![Figure.dividendsPaid] ?? 0,
    ];
    return paid.reduce((a, b) => a + b) / years.length;
  }

  IndicatorInput? get _current {
    final figures = ttm;
    final year = this.year;
    if (figures == null || year == null) return null;
    return IndicatorInput(
      figures: figures,
      company: company,
      year: year,
      price: price,
      marketCap: marketCap,
      sharesPerTicker: sharesPerTicker,
      shares: company.shares,
      fiveYearsBefore: company.years[year - 5],
      averageDividend: averageDividend,
    );
  }

  FairPrice? _fair(String id) {
    final fair = value(Indicator.byId(id));
    final price = this.price;
    return fair == null || price == null || price <= 0
        ? null
        : FairPrice(fair, price);
  }

  /// Graham: √(22,5 × LPA × VPA).
  FairPrice? get graham => _fair('graham');

  /// Bazin: proventos per share over the last five years ÷ 6%.
  FairPrice? get bazin => _fair('bazin');

  /// Proventos paid per share each year, at today's share count.
  Map<int, double> get dividendsPerShare {
    final shares = company.shares;
    if (shares == null || shares <= 0) return const {};
    return {
      for (final y in company.sortedYears)
        if (company.years[y]![Figure.dividendsPaid] case final paid?)
          y: paid * sharesPerTicker / shares,
    };
  }

  /// The indicator today: last twelve months and the current price.
  double? value(Indicator indicator) {
    final input = _current;
    return input == null ? null : indicator.compute(input);
  }

  /// The indicator at the end of each closed year, oldest first. Empty for
  /// what needs a price.
  Map<int, double> history(Indicator indicator) {
    if (indicator.usesPrice) return const {};
    final out = <int, double>{};
    for (final year in company.sortedYears) {
      final value = indicator.compute(
        IndicatorInput(
          figures: company.years[year]!,
          company: company,
          year: year,
          sharesPerTicker: sharesPerTicker,
          shares: company.shares,
          fiveYearsBefore: company.years[year - 5],
        ),
      );
      if (value != null && value.isFinite) out[year] = value;
    }
    return out;
  }

  /// Answers of the stock questionnaire that the numbers give, with why. The
  /// rest (leadership, management, innovation) stays with the user.
  /// [brlPerUnit] turns the statements' currency into reais, for the size of
  /// a blue chip; without it that question is left out.
  Map<String, (bool, String)> criteria(DateTime now, {double? brlPerUnit = 1}) {
    final out = <String, (bool, String)>{};
    final input = _current;
    if (input == null) return out;
    String pct(double v) => '${(v * 100).toStringAsFixed(1).replaceAll('.', ',')}%';
    String num2(double v) => v.toStringAsFixed(2).replaceAll('.', ',');
    final recent = company.sortedYears.reversed.take(5).toList().reversed.toList();

    final roe = history(Indicator.byId('roe'));
    final roeYears = [for (final y in recent) ?roe[y]];
    if (roeYears.length >= 3) {
      out['O ROE é consistentemente acima de 5%? (empresa endividada: olhar o ROIC)'] =
          (
            roeYears.every((v) => v > 0.05),
            'ROE de ${recent.first} a ${recent.last}: '
                '${roeYears.map(pct).join(' · ')}',
          );
    }

    final cagrRevenue = value(Indicator.byId('cagrRevenue'));
    final cagrIncome = value(Indicator.byId('cagrIncome'));
    if (cagrRevenue != null || cagrIncome != null) {
      // Over the five years, not per year.
      bool grew(double? cagr) => cagr != null && math.pow(1 + cagr, 5) > 1.05;
      out['Receita ou lucro cresceram nos últimos 5 anos?'] = (
        grew(cagrRevenue) || grew(cagrIncome),
        'Por ano: receita ${cagrRevenue == null ? '—' : pct(cagrRevenue)}, '
            'lucro ${cagrIncome == null ? '—' : pct(cagrIncome)}',
      );
    }

    if (recent.length >= 3) {
      final paid = [
        for (final y in recent) company.years[y]![Figure.dividendsPaid] ?? 0,
      ];
      out['Tem histórico de pagar dividendos?'] = (
        paid.every((v) => v > 0),
        'Pagou em ${paid.where((v) => v > 0).length} de ${recent.length} anos '
            '(${recent.first}–${recent.last})',
      );
    }

    final since = company.founded ?? company.listed;
    if (since != null) {
      final age = now.difference(since).inDays ~/ 365;
      out['Tem mais de 30 anos de mercado?'] = (
        age >= 30,
        '${company.founded != null ? 'Fundada' : 'Listada'} em ${since.year}: '
            '$age anos',
      );
    }

    final cap = marketCap == null || brlPerUnit == null
        ? null
        : marketCap! * brlPerUnit;
    if (cap != null) {
      out['É uma empresa grande (blue chip)?'] = (
        cap >= 50e9,
        'Valor de mercado de R\$ ${NumberFormat('#,##0.0', 'pt_BR').format(cap / 1e9)} bi '
            '(blue chip a partir de R\$ 50 bi)',
      );
    }

    if (company.stateControlled) {
      out['É independente do governo e de um único cliente?'] = (
        false,
        'Controle: ${company.control}',
      );
    }

    if (!company.financial) {
      final leverage = history(Indicator.byId('netDebtEbitda'));
      final years = [for (final y in recent) ?leverage[y]];
      if (years.length >= 3) {
        out['A dívida líquida/EBITDA ficou abaixo de 2 nos últimos 5 anos?'] = (
          years.every((v) => v < 2),
          'De ${recent.first} a ${recent.last}: ${years.map(num2).join(' · ')}',
        );
      }
      final debt = input.figures.netDebt;
      final income = input.figures[Figure.netIncome];
      if (debt != null && income != null) {
        out['A dívida líquida é menor que o lucro dos últimos 12 meses?'] = (
          debt < income,
          'Dívida líquida ${_bi(debt, company.currency)} · lucro '
              '${_bi(income, company.currency)}',
        );
      }
      final ebit = input.figures[Figure.ebit];
      if (ebit != null) {
        out['Teve lucro operacional (EBIT) no último ano?'] = (
          ebit > 0,
          'EBIT dos últimos 12 meses: ${_bi(ebit, company.currency)}',
        );
      }
    }

    final income = input.figures[Figure.netIncome];
    final pl = value(Indicator.byId('pl'));
    if (pl != null || (income != null && income <= 0)) {
      out['O P/L está abaixo de 30?'] = (
        pl != null && pl < 30,
        pl == null ? 'Prejuízo nos últimos 12 meses' : 'P/L ${num2(pl)}',
      );
    }
    final pvp = value(Indicator.byId('pvp'));
    if (pvp != null) {
      out['O P/VP está abaixo de 5?'] = (pvp < 5, 'P/VP ${num2(pvp)}');
    }
    return out;
  }

  static String _bi(double value, String currency) =>
      '${currency == 'BRL' ? 'R\$' : currency} '
      '${NumberFormat('#,##0.0', 'pt_BR').format(value / 1e9)} bi';
}

/// Of a row of companies, which value is the best and which the worst; null
/// when the indicator has no better side or fewer than two values.
(double, double)? bestAndWorst(Indicator indicator, Iterable<double?> values) {
  final higher = indicator.higherIsBetter;
  final known = [
    for (final v in values)
      if (v != null && v.isFinite) v,
  ];
  if (higher == null || known.length < 2) return null;
  final max = known.reduce(math.max);
  final min = known.reduce(math.min);
  if (max == min) return null;
  return higher ? (max, min) : (min, max);
}
