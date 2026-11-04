import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:aupp/investments/cvm-statements.dart';
import 'package:aupp/services/logger.dart';

/// Contact the SEC asks of automated clients, sent in every request. Comes
/// from the build (private/build.env), never from the repository.
const secContact = String.fromEnvironment('SEC_CONTACT');

/// A company listed in the United States (its own shares or ADRs of a
/// foreign company), from the SEC's list.
class SecListing {
  final int cik;
  final String name;
  final String ticker;
  final String? exchange;

  const SecListing(this.cik, this.name, this.ticker, this.exchange);
}

String _fold(String text) {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const to = 'aaaaaeeeeiiiiooooouuuucn';
  final buffer = StringBuffer();
  for (final char in text.toLowerCase().split('')) {
    final index = from.indexOf(char);
    buffer.write(index < 0 ? char : to[index]);
  }
  return buffer.toString();
}

/// Every ticker the SEC knows, kept on disk and fetched again each month: the
/// base of the search for assets abroad.
class SecCatalog extends ChangeNotifier {
  static final instance = SecCatalog();
  static final _logger = Logger.withClass(SecCatalog);
  static const _url = 'https://www.sec.gov/files/company_tickers_exchange.json';

  Map<String, SecListing> _byTicker = {};
  DateTime? fetchedAt;
  Future<void>? _running;

  /// Names of tickers found elsewhere (another exchange, by OpenFIGI), kept
  /// so that they show by name later.
  Map<String, String> _names = {};

  @visibleForTesting
  Future<File> Function() file = () async => File(
    p.join((await getApplicationSupportDirectory()).path, 'sec-tickers.json'),
  );

  @visibleForTesting
  http.Client Function() client = http.Client.new;

  SecListing? operator [](String ticker) => _byTicker[ticker.toUpperCase()];

  /// "TOYOTA MOTOR CORP/" → "Toyota Motor Corp".
  static String displayName(String name) {
    final plain = name.replaceAll(RegExp(r'\s*/[A-Z]{2}/?$|/$'), '').trim();
    if (plain != plain.toUpperCase()) return plain;
    return plain
        .toLowerCase()
        .split(' ')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  /// The name of a ticker abroad, if known.
  String? nameOf(String ticker) {
    final code = ticker.toUpperCase();
    final listing = _byTicker[code];
    return listing != null ? displayName(listing.name) : _names[code];
  }

  @visibleForTesting
  Future<File> Function() namesFile = () async => File(
    p.join((await getApplicationSupportDirectory()).path, 'foreign-names.json'),
  );

  /// Keeps the name of a ticker found on another exchange.
  Future<void> remember(String ticker, String name) async {
    final code = ticker.toUpperCase();
    if (_byTicker.containsKey(code) || _names[code] == name) return;
    _names[code] = name;
    try {
      await (await namesFile()).writeAsString(jsonEncode(_names));
    } catch (e, st) {
      _logger.handle(e, st, 'Names not saved');
    }
  }
  bool get ready => _byTicker.isNotEmpty;
  Iterable<SecListing> get listings => _byTicker.values;

  @visibleForTesting
  void setForTest(Iterable<SecListing> listings) {
    _byTicker = {for (final l in listings) l.ticker: l};
    fetchedAt = DateTime.now();
  }

  static Map<String, SecListing> parse(Map<String, dynamic> json) {
    final fields = (json['fields'] as List).cast<String>();
    final cik = fields.indexOf('cik');
    final name = fields.indexOf('name');
    final ticker = fields.indexOf('ticker');
    final exchange = fields.indexOf('exchange');
    final out = <String, SecListing>{};
    for (final row in json['data'] as List) {
      final cells = row as List;
      final symbol = (cells[ticker] as String?)?.toUpperCase();
      if (symbol == null || symbol.isEmpty) continue;
      // The first is the company's main listing.
      out.putIfAbsent(
        symbol,
        () => SecListing(
          (cells[cik] as num).toInt(),
          cells[name] as String,
          symbol,
          cells[exchange] as String?,
        ),
      );
    }
    return out;
  }

  /// Ticker first, then name; the exchanges before the over-the-counter.
  List<SecListing> search(String query, {int limit = 20}) {
    final upper = query.trim().toUpperCase();
    if (upper.isEmpty) return const [];
    final folded = _fold(query.trim());
    final exact = <SecListing>[];
    final byTicker = <SecListing>[];
    final byName = <SecListing>[];
    for (final l in _byTicker.values) {
      if (l.ticker == upper) {
        exact.add(l);
      } else if (upper.length >= 2 && l.ticker.startsWith(upper)) {
        byTicker.add(l);
      } else if (folded.length >= 3 && _fold(l.name).contains(folded)) {
        byName.add(l);
      }
    }
    int rank(SecListing a, SecListing b) {
      final otc = (a.exchange == 'OTC' ? 1 : 0) - (b.exchange == 'OTC' ? 1 : 0);
      return otc != 0 ? otc : a.ticker.length.compareTo(b.ticker.length);
    }

    return [...exact, ...byTicker..sort(rank), ...byName..sort(rank)]
        .take(limit)
        .toList();
  }

  Future<void> ensure() async {
    if (!ready) await _loadSaved();
    final at = fetchedAt;
    if (at != null && DateTime.now().difference(at) < const Duration(days: 30)) {
      return;
    }
    return _running ??= _fetch().whenComplete(() => _running = null);
  }

  Future<void> _loadSaved() async {
    try {
      final names = await namesFile();
      if (await names.exists()) {
        _names = (jsonDecode(await names.readAsString()) as Map)
            .cast<String, String>();
      }
    } catch (_) {}
    try {
      final saved = await file();
      if (!await saved.exists()) return;
      _byTicker = parse(jsonDecode(await saved.readAsString()) as Map<String, dynamic>);
      fetchedAt = await saved.lastModified();
      notifyListeners();
    } catch (e, st) {
      _logger.handle(e, st, 'Ignoring the saved SEC list');
    }
  }

  Future<void> _fetch() async {
    if (secContact.isEmpty) return;
    final http_ = client();
    try {
      final response = await http_
          .get(Uri.parse(_url), headers: secHeaders)
          .timeout(const Duration(seconds: 60));
      if (response.statusCode != 200) {
        _logger.warning('SEC list: HTTP ${response.statusCode}');
        return;
      }
      final listings = parse(jsonDecode(response.body) as Map<String, dynamic>);
      if (listings.isEmpty) return;
      _byTicker = listings;
      fetchedAt = DateTime.now();
      await (await file()).writeAsString(response.body);
      notifyListeners();
    } catch (e, st) {
      _logger.handle(e, st, 'SEC list failed');
    } finally {
      http_.close();
    }
  }
}

Map<String, String> get secHeaders => {
  'User-Agent': 'AUPP $secContact',
  'Accept-Encoding': 'gzip',
};

/// A fact of a concept: a period (or an instant: no start) and its value.
class _Fact {
  final DateTime? start;
  final DateTime end;
  final double value;
  final String form;
  final String filed;

  const _Fact(this.start, this.end, this.value, this.form, this.filed);

  int get days => start == null ? 0 : end.difference(start!).inDays;
  bool get yearly => days >= 340 && days <= 390;
  bool get annualReport =>
      form.startsWith('10-K') || form.startsWith('20-F') || form.startsWith('40-F');
}

/// How a figure is found in the SEC's facts: concepts in order of preference
/// (US GAAP and IFRS), added up when [sum], and the sign the CVM's statements
/// use (costs, taxes and payments negative).
class _Source {
  final List<List<String>> concepts;
  final bool negate;

  const _Source(this.concepts, {this.negate = false});
}

/// Reads the SEC's company facts (data.sec.gov/api/xbrl/companyfacts) into the
/// same figures as the CVM's, so that Análise and Comparar work the same.
class SecFacts {
  static const _sources = <Figure, _Source>{
    Figure.revenue: _Source([
      ['us-gaap:Revenues'],
      ['us-gaap:RevenueFromContractWithCustomerExcludingAssessedTax'],
      ['us-gaap:RevenueFromContractWithCustomerIncludingAssessedTax'],
      ['us-gaap:SalesRevenueNet'],
      ['ifrs-full:Revenue'],
      ['ifrs-full:RevenueFromContractsWithCustomers'],
    ]),
    Figure.costs: _Source([
      ['us-gaap:CostOfRevenue'],
      ['us-gaap:CostOfGoodsAndServicesSold'],
      ['ifrs-full:CostOfSales'],
    ], negate: true),
    Figure.grossProfit: _Source([
      ['us-gaap:GrossProfit'],
      ['ifrs-full:GrossProfit'],
    ]),
    Figure.operatingExpenses: _Source([
      ['us-gaap:OperatingExpenses'],
    ], negate: true),
    Figure.ebit: _Source([
      ['us-gaap:OperatingIncomeLoss'],
      ['ifrs-full:ProfitLossFromOperatingActivities'],
    ]),
    Figure.incomeTax: _Source([
      ['us-gaap:IncomeTaxExpenseBenefit'],
      ['ifrs-full:IncomeTaxExpenseContinuingOperations'],
    ], negate: true),
    Figure.netIncome: _Source([
      ['us-gaap:NetIncomeLoss'],
      ['ifrs-full:ProfitLossAttributableToOwnersOfParent'],
      ['us-gaap:ProfitLoss'],
      ['ifrs-full:ProfitLoss'],
    ]),
    Figure.assets: _Source([
      ['us-gaap:Assets'],
      ['ifrs-full:Assets'],
    ]),
    Figure.currentAssets: _Source([
      ['us-gaap:AssetsCurrent'],
      ['ifrs-full:CurrentAssets'],
    ]),
    Figure.nonCurrentAssets: _Source([
      ['us-gaap:AssetsNoncurrent'],
      ['ifrs-full:NoncurrentAssets'],
    ]),
    Figure.cash: _Source([
      [
        'us-gaap:CashAndCashEquivalentsAtCarryingValue',
        'us-gaap:ShortTermInvestments',
      ],
      ['us-gaap:CashAndCashEquivalentsAtCarryingValue'],
      ['ifrs-full:CashAndCashEquivalents'],
    ]),
    Figure.inventory: _Source([
      ['us-gaap:InventoryNet'],
      ['ifrs-full:Inventories'],
    ]),
    Figure.currentLiabilities: _Source([
      ['us-gaap:LiabilitiesCurrent'],
      ['ifrs-full:CurrentLiabilities'],
    ]),
    Figure.nonCurrentLiabilities: _Source([
      ['us-gaap:LiabilitiesNoncurrent'],
      ['ifrs-full:NoncurrentLiabilities'],
    ]),
    // Debt with leases, as in the CVM's "Empréstimos e Financiamentos".
    Figure.grossDebt: _Source([
      ['us-gaap:LongTermDebt', 'us-gaap:ShortTermBorrowings', 'us-gaap:CommercialPaper'],
      ['us-gaap:LongTermDebtNoncurrent', 'us-gaap:LongTermDebtCurrent', 'us-gaap:ShortTermBorrowings'],
      ['us-gaap:DebtInstrumentCarryingAmount'],
      ['ifrs-full:Borrowings', 'ifrs-full:LeaseLiabilities'],
      ['ifrs-full:NoncurrentBorrowings', 'ifrs-full:CurrentBorrowings', 'ifrs-full:LeaseLiabilities'],
    ]),
    Figure.equity: _Source([
      ['us-gaap:StockholdersEquity'],
      ['ifrs-full:EquityAttributableToOwnersOfParent'],
      ['us-gaap:StockholdersEquityIncludingPortionAttributableToNoncontrollingInterest'],
      ['ifrs-full:Equity'],
    ]),
    Figure.cfo: _Source([
      ['us-gaap:NetCashProvidedByUsedInOperatingActivities'],
      ['ifrs-full:CashFlowsFromUsedInOperatingActivities'],
    ]),
    Figure.cfi: _Source([
      ['us-gaap:NetCashProvidedByUsedInInvestingActivities'],
      ['ifrs-full:CashFlowsFromUsedInInvestingActivities'],
    ]),
    Figure.cff: _Source([
      ['us-gaap:NetCashProvidedByUsedInFinancingActivities'],
      ['ifrs-full:CashFlowsFromUsedInFinancingActivities'],
    ]),
    Figure.fxEffect: _Source([
      ['us-gaap:EffectOfExchangeRateOnCashCashEquivalentsRestrictedCashAndRestrictedCashEquivalents'],
      ['us-gaap:EffectOfExchangeRateOnCashAndCashEquivalents'],
      ['ifrs-full:EffectOfExchangeRateChangesOnCashAndCashEquivalents'],
    ]),
    Figure.cashEnd: _Source([
      ['us-gaap:CashCashEquivalentsRestrictedCashAndRestrictedCashEquivalents'],
      ['us-gaap:CashAndCashEquivalentsAtCarryingValue'],
      ['ifrs-full:CashAndCashEquivalents'],
    ]),
    Figure.capex: _Source([
      ['us-gaap:PaymentsToAcquirePropertyPlantAndEquipment', 'us-gaap:PaymentsToAcquireIntangibleAssets'],
      ['us-gaap:PaymentsToAcquireProductiveAssets'],
      [
        'ifrs-full:PurchaseOfPropertyPlantAndEquipmentClassifiedAsInvestingActivities',
        'ifrs-full:PurchaseOfIntangibleAssetsClassifiedAsInvestingActivities',
      ],
      ['ifrs-full:PurchaseOfPropertyPlantAndEquipment', 'ifrs-full:PurchaseOfIntangibleAssets'],
    ], negate: true),
    Figure.depreciation: _Source([
      ['us-gaap:DepreciationDepletionAndAmortization'],
      ['us-gaap:DepreciationAndAmortization'],
      ['us-gaap:DepreciationAmortizationAndAccretionNet'],
      ['ifrs-full:AdjustmentsForDepreciationAndAmortisationExpense'],
      ['ifrs-full:DepreciationAndAmortisationExpense'],
    ]),
    Figure.dividendsPaid: _Source([
      ['us-gaap:PaymentsOfDividends'],
      ['us-gaap:PaymentsOfDividendsCommonStock'],
      ['ifrs-full:DividendsPaidClassifiedAsFinancingActivities'],
      ['ifrs-full:DividendsPaid'],
    ]),
  };

  /// The currency most of the money facts are in: the one the statements are
  /// reported in (some also give a translation to dollars).
  static String? reportingCurrency(Map<String, dynamic> facts) {
    final counts = <String, int>{};
    for (final taxonomy in ['us-gaap', 'ifrs-full']) {
      final concepts = facts[taxonomy] as Map? ?? const {};
      for (final name in ['Assets', 'Revenue', 'Revenues', 'NetIncomeLoss', 'ProfitLoss', 'Equity', 'StockholdersEquity']) {
        final units = (concepts[name] as Map?)?['units'] as Map?;
        for (final e in (units ?? const {}).entries) {
          if (RegExp(r'^[A-Z]{3}$').hasMatch(e.key as String)) {
            counts[e.key as String] = (counts[e.key] ?? 0) + (e.value as List).length;
          }
        }
      }
    }
    if (counts.isEmpty) return null;
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  static List<_Fact> _facts(
    Map<String, dynamic> facts,
    String concept,
    String unit,
  ) {
    final [taxonomy, name] = concept.split(':');
    final units = ((facts[taxonomy] as Map?)?[name] as Map?)?['units'] as Map?;
    final items = units?[unit] as List?;
    if (items == null) return const [];
    return [
      for (final item in items)
        if (DateTime.tryParse((item as Map)['end'] as String? ?? '')
            case final end?)
          _Fact(
            DateTime.tryParse(item['start'] as String? ?? ''),
            end,
            (item['val'] as num).toDouble(),
            item['form'] as String? ?? '',
            item['filed'] as String? ?? '',
          ),
    ];
  }

  /// Per period (start or null, end), the value of the latest filing.
  static Map<(DateTime?, DateTime), _Fact> _byPeriod(Iterable<_Fact> facts) {
    final out = <(DateTime?, DateTime), _Fact>{};
    for (final f in facts) {
      final key = (f.start, f.end);
      final known = out[key];
      if (known == null || known.filed.compareTo(f.filed) < 0) out[key] = f;
    }
    return out;
  }

  /// The values of a figure by period. Each period takes the first option in
  /// [_Source.concepts] that has all its parts there.
  static Map<(DateTime?, DateTime), _Fact> _figure(
    Map<String, dynamic> facts,
    _Source source,
    String unit,
  ) {
    final out = <(DateTime?, DateTime), _Fact>{};
    for (final option in source.concepts) {
      final parts = [
        for (final concept in option) _byPeriod(_facts(facts, concept, unit)),
      ];
      // The first part is required; the others add when present.
      for (final e in parts.first.entries) {
        if (out.containsKey(e.key)) continue;
        var value = e.value.value;
        for (final other in parts.skip(1)) {
          value += other[e.key]?.value ?? 0;
        }
        out[e.key] = _Fact(
          e.value.start,
          e.value.end,
          source.negate ? -value.abs() : value,
          e.value.form,
          e.value.filed,
        );
      }
    }
    return out;
  }

  /// Shares outstanding: the cover page's count (all classes on the same
  /// date), or the weighted average of the income statement.
  static double? shares(Map<String, dynamic> facts) {
    final cover = _facts(facts, 'dei:EntityCommonStockSharesOutstanding', 'shares');
    if (cover.isNotEmpty) {
      final last = cover.map((f) => f.end).reduce((a, b) => a.isAfter(b) ? a : b);
      final latestFiling = cover
          .where((f) => f.end == last)
          .map((f) => f.filed)
          .reduce((a, b) => a.compareTo(b) >= 0 ? a : b);
      return cover
          .where((f) => f.end == last && f.filed == latestFiling)
          .fold<double>(0, (sum, f) => sum + f.value);
    }
    for (final concept in [
      'us-gaap:WeightedAverageNumberOfSharesOutstandingBasic',
      'ifrs-full:WeightedAverageShares',
    ]) {
      final found = _facts(facts, concept, 'shares');
      if (found.isEmpty) continue;
      return found.reduce((a, b) => a.end.isAfter(b.end) ? a : b).value;
    }
    return null;
  }

  /// A company from its facts and submissions (data.sec.gov/submissions).
  static CvmCompany? parse(
    String ticker,
    Map<String, dynamic> factsJson,
    Map<String, dynamic>? submissions,
  ) {
    final facts = (factsJson['facts'] as Map?)?.cast<String, dynamic>();
    if (facts == null) return null;
    final currency = reportingCurrency(facts);
    if (currency == null) return null;
    final byFigure = {
      for (final e in _sources.entries) e.key: _figure(facts, e.value, currency),
    };
    // The yearly periods of the annual reports, by the year they end.
    final yearEnds = <int, (DateTime, DateTime)>{};
    for (final figure in [Figure.revenue, Figure.netIncome, Figure.cfo]) {
      for (final f in byFigure[figure]!.values) {
        if (!f.yearly || !f.annualReport) continue;
        final known = yearEnds[f.end.year];
        if (known == null || known.$2.isBefore(f.end)) {
          yearEnds[f.end.year] = (f.start!, f.end);
        }
      }
    }
    Figures period(DateTime? start, DateTime end) => Figures({
      for (final e in byFigure.entries)
        if (e.key.isFlow
            ? e.value[(start, end)]
            : e.value[(null, end)] case final fact?)
          e.key: fact.value,
    });
    final now = DateTime.now();
    final years = <int, Figures>{
      for (final e in yearEnds.entries)
        if (e.key > now.year - 12) e.key: period(e.value.$1, e.value.$2),
    };
    years.removeWhere((_, f) => f.values.length < 3);
    if (years.isEmpty) return null;
    final lastYear = years.keys.reduce(math.max);
    final (lastStart, lastEnd) = yearEnds[lastYear]!;
    var ttm = years[lastYear]!;
    var ttmEnd = lastEnd;
    // Quarterly reports after the year: year + this year so far − the same
    // months a year before.
    DateTime? quarterEnd;
    for (final f in byFigure[Figure.netIncome]!.values) {
      if (f.start == null || f.annualReport || !f.end.isAfter(lastEnd)) continue;
      if ((f.start!.difference(lastEnd).inDays - 1).abs() > 7) continue;
      if (quarterEnd == null || f.end.isAfter(quarterEnd)) quarterEnd = f.end;
    }
    if (quarterEnd != null) {
      final ytdStart = byFigure[Figure.netIncome]!.values
          .firstWhere(
            (f) => f.end == quarterEnd && !f.annualReport && f.start != null &&
                (f.start!.difference(lastEnd).inDays - 1).abs() <= 7,
          )
          .start!;
      final values = <Figure, double>{};
      for (final e in byFigure.entries) {
        final figure = e.key;
        if (!figure.isFlow) {
          final instant = e.value[(null, quarterEnd)];
          if (instant != null) values[figure] = instant.value;
          continue;
        }
        final total = ttm[figure];
        final now_ = e.value[(ytdStart, quarterEnd)];
        _Fact? before;
        for (final f in e.value.values) {
          if (f.start == null) continue;
          if ((f.start!.difference(lastStart).inDays).abs() <= 7 &&
              (f.end.difference(DateTime(quarterEnd.year - 1, quarterEnd.month, quarterEnd.day)).inDays).abs() <= 7) {
            before = f;
          }
        }
        if (total != null && now_ != null && before != null) {
          values[figure] = total + now_.value - before.value;
        }
      }
      if (values[Figure.netIncome] != null) {
        ttm = Figures(values);
        ttmEnd = quarterEnd;
      }
    }
    final sic = int.tryParse(submissions?['sic'] as String? ?? '');
    final cik = (factsJson['cik'] as num?)?.toInt();
    final name = (factsJson['entityName'] as String?) ??
        (submissions?['name'] as String?) ??
        ticker;
    final exchanges = (submissions?['exchanges'] as List?)?.cast<String>();
    final shareCount = shares(facts);
    return CvmCompany(
      code: 'SEC$cik',
      name: name,
      cnpj: null,
      sector: submissions?['sicDescription'] as String?,
      segment: exchanges == null || exchanges.isEmpty ? null : exchanges.join(', '),
      tickers: {ticker: ShareClass.on},
      financial:
          sic != null && sic >= 6000 && sic < 6500 && ttm[Figure.ebit] == null,
      years: years,
      ttm: ttm,
      ttmEnd: ttmEnd,
      sharesOn: shareCount,
      sharesPn: 0,
      currency: currency,
      foreignIssuer: years.isNotEmpty &&
          byFigure[Figure.netIncome]!.values.any(
            (f) => f.form.startsWith('20-F') || f.form.startsWith('40-F'),
          ),
    );
  }

  /// The last year's filings worth reading: results, annual and quarterly
  /// reports and current reports.
  static List<CvmNotice> notices(
    Map<String, dynamic> submissions,
    DateTime since,
  ) {
    final recent = (submissions['filings'] as Map?)?['recent'] as Map?;
    if (recent == null) return const [];
    final cik = int.tryParse(submissions['cik']?.toString() ?? '');
    final forms = (recent['form'] as List).cast<String>();
    const items = {
      '1.01': 'Acordo relevante',
      '2.01': 'Aquisição ou venda de ativos',
      '2.02': 'Resultados',
      '2.05': 'Reestruturação',
      '5.02': 'Mudança na diretoria ou conselho',
      '5.07': 'Votação em assembleia',
      '7.01': 'Divulgação ao mercado',
      '8.01': 'Outros eventos',
    };
    final out = <CvmNotice>[];
    for (var i = 0; i < forms.length; i++) {
      final form = forms[i];
      final category = switch (form) {
        '10-K' || '20-F' || '40-F' => 'Relatório anual',
        '10-Q' => 'Relatório trimestral',
        '8-K' || '6-K' => 'Comunicado',
        _ => null,
      };
      if (category == null) continue;
      final date = DateTime.tryParse(recent['filingDate'][i] as String);
      if (date == null || date.isBefore(since)) continue;
      final codes = (recent['items'][i] as String? ?? '')
          .split(',')
          .where((c) => c.isNotEmpty);
      final description = (recent['primaryDocDescription'][i] as String? ?? '')
          .trim();
      final subject = [
        for (final c in codes) ?items[c],
      ].join(', ');
      final accession = (recent['accessionNumber'][i] as String).replaceAll('-', '');
      out.add(
        CvmNotice(
          date,
          codes.contains('2.02') ? 'Resultados' : category,
          subject.isNotEmpty
              ? subject
              : description.isNotEmpty
              ? '$form · $description'
              : form,
          'https://www.sec.gov/Archives/edgar/data/$cik/$accession/'
          '${recent['primaryDocument'][i]}',
        ),
      );
    }
    return out;
  }
}

/// The companies abroad looked at, fetched from the SEC when first asked and
/// kept on disk for a day.
class SecStore {
  static final instance = SecStore();
  static final _logger = Logger.withClass(SecStore);
  static const freshFor = Duration(days: 1);

  final _companies = <String, (CvmCompany, List<CvmNotice>)>{};
  final _pending = <String, Future<(CvmCompany, List<CvmNotice>)?>>{};

  @visibleForTesting
  Future<Directory> Function() folder = () async =>
      Directory(p.join((await getApplicationSupportDirectory()).path, 'sec'));

  @visibleForTesting
  http.Client Function() client = http.Client.new;

  @visibleForTesting
  void setForTest(String ticker, CvmCompany company, [List<CvmNotice> notices = const []]) =>
      _companies[ticker] = (company, notices);

  /// Already loaded, for drawing without waiting.
  (CvmCompany, List<CvmNotice>)? cached(String ticker) => _companies[ticker];

  Future<(CvmCompany, List<CvmNotice>)?> load(String ticker) {
    final known = _companies[ticker];
    if (known != null) return Future.value(known);
    // A block: an arrow would hand back the pending future, which then
    // waits for itself.
    return _pending[ticker] ??= _load(ticker).whenComplete(() {
      _pending.remove(ticker);
    });
  }

  Future<(CvmCompany, List<CvmNotice>)?> _load(String ticker) async {
    await SecCatalog.instance.ensure();
    final listing = SecCatalog.instance[ticker];
    if (listing == null) return null;
    final cik = listing.cik.toString().padLeft(10, '0');
    final dir = await folder();
    await dir.create(recursive: true);
    Future<Map<String, dynamic>?> get(String name, String url) async {
      final file = File(p.join(dir.path, '$name-$cik.json'));
      if (await file.exists() &&
          DateTime.now().difference(await file.lastModified()) < freshFor) {
        return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      }
      if (secContact.isEmpty) return null;
      final http_ = client();
      try {
        final response = await http_
            .get(Uri.parse(url), headers: secHeaders)
            .timeout(const Duration(seconds: 60));
        if (response.statusCode != 200) {
          _logger.warning('$name of $ticker: HTTP ${response.statusCode}');
          // An old copy beats nothing.
          return await file.exists()
              ? jsonDecode(await file.readAsString()) as Map<String, dynamic>
              : null;
        }
        await file.writeAsString(response.body);
        return jsonDecode(response.body) as Map<String, dynamic>;
      } finally {
        http_.close();
      }
    }

    try {
      final facts = await get(
        'facts',
        'https://data.sec.gov/api/xbrl/companyfacts/CIK$cik.json',
      );
      final submissions = await get(
        'submissions',
        'https://data.sec.gov/submissions/CIK$cik.json',
      );
      if (facts == null) return null;
      final company = SecFacts.parse(ticker, facts, submissions);
      if (company == null) return null;
      final found = (
        company,
        submissions == null
            ? const <CvmNotice>[]
            : SecFacts.notices(
                submissions,
                DateTime.now().subtract(const Duration(days: 366)),
              ),
      );
      return _companies[ticker] = found;
    } catch (e, st) {
      _logger.handle(e, st, 'SEC data of $ticker failed');
      return null;
    }
  }
}
