import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:aupp/services/service-config.dart';
import 'package:aupp/settings/constants/preferences-keys.dart';

import 'investments-analytics.dart';
import 'stock-catalog.dart';

/// The classes of the portfolio. What goes outside them (funds, pension plans,
/// COE) is left out of the method: the user does not choose what those hold.
enum DiagramClass {
  intlStock('Ações Internacionais'),
  nationalStock('Ações Nacionais'),
  fii('Fundos Imobiliários'),
  reit('REITs'),
  crypto('Reserva de valor'),
  fixedIncome('Renda Fixa');

  final String label;
  const DiagramClass(this.label);

  /// Graded by a questionnaire; the others by a number typed by the user.
  bool get hasQuestionnaire => this != crypto && this != fixedIncome;

  /// The questionnaire of a class: FIIs have their own.
  bool get usesFiiQuestions => this == fii || this == reit;

  /// A purchase needs the price to know how many units fit.
  bool get needsPrice => this == nationalStock || this == fii || this == crypto;

  /// Smallest amount bought: whole shares on the B3, 4 decimals of a coin.
  /// Null is any amount in reais (fixed income; foreign assets in dollars).
  double? get step => switch (this) {
    nationalStock || fii => 1,
    crypto => 0.0001,
    _ => null,
  };
}

/// The grade of a questionnaire: yes +1, no −1, and what does not apply to the
/// asset (debt for a bank) counts nothing. Null until it is all answered: not
/// answered is different from a grade of zero.
int? questionnaireGrade(
  List<String> questions,
  Map<String, bool> answers, {
  Set<String> skipped = const {},
}) {
  var grade = 0;
  var counted = 0;
  for (final question in questions) {
    if (skipped.contains(question)) continue;
    final answer = answers[question];
    if (answer == null) return null;
    grade += answer ? 1 : -1;
    counted++;
  }
  return counted == 0 ? null : grade;
}

/// The questionnaires: companies, funds of buildings, and index funds.
enum QuestionSet { stock, fii, etf }

/// Where an asset stands in Buy and Hold. Selling is never by price: a company
/// that lost its fundamentals first stops receiving money, and only if it keeps
/// getting worse is it sold, slowly.
enum HoldStatus {
  buying('Aportando'),
  paused('Aportes pausados'),
  unwinding('Desmontando aos poucos');

  final String label;
  const HoldStatus(this.label);
}

/// The reasons the course accepts to stop buying or to sell.
const holdReasons = [
  'Perdeu fundamentos: balanços com prejuízo sem justificativa',
  'Perdeu fundamentos: corrupção grave ou fraude',
  'Perdeu fundamentos: distribui mais lucro do que aguenta ou má gestão',
  'Emergência que a reserva não cobriu',
  'Hora de usufruir do patrimônio',
];

/// One line of the portfolio. Fixed income lines group positions by what they
/// pay, since each CDB on its own would say nothing about the choice.
class DiagramAsset {
  final String key;
  final String label;
  final DiagramClass cls;

  /// B3 ticker or coin code, when the line has a Ficha.
  final String? ticker;
  final double value;
  final double quantity;

  /// Current price; null when unknown or meaningless (fixed income).
  final double? price;

  /// Null means not graded yet.
  final num? grade;

  /// Added by the user to study, so the user can take it out. What comes from
  /// the positions and wallets always stays.
  final bool isManual;

  /// An index fund: same class as stocks, its own questions. A gold ETF is a
  /// reserve of value, bought in whole shares.
  final bool isEtf;

  /// Why it cannot receive money now, beyond its grade (the top of the
  /// triangle at its limit).
  final String? blockedReason;

  final HoldStatus status;

  const DiagramAsset({
    required this.key,
    required this.label,
    required this.cls,
    this.ticker,
    this.value = 0,
    this.quantity = 0,
    this.price,
    this.grade,
    this.isManual = false,
    this.isEtf = false,
    this.status = HoldStatus.buying,
    this.blockedReason,
  });

  /// Smallest amount bought: whole shares, 4 decimals of a coin, any amount
  /// of fixed income.
  double? get step => cls == DiagramClass.crypto && isEtf ? 1 : cls.step;

  QuestionSet get questionSet => cls.usesFiiQuestions
      ? QuestionSet.fii
      : isEtf
      ? QuestionSet.etf
      : QuestionSet.stock;

  DiagramAsset withData({
    double? value,
    double? price,
    num? grade,
    HoldStatus? status,
    String? blockedReason,
  }) => DiagramAsset(
    key: key,
    label: label,
    cls: cls,
    ticker: ticker,
    value: value ?? this.value,
    quantity: quantity,
    price: price ?? this.price,
    grade: grade ?? this.grade,
    isManual: isManual,
    isEtf: isEtf,
    status: status ?? this.status,
    blockedReason: blockedReason ?? this.blockedReason,
  );

  /// Why it gets no money, or null when it can.
  String? get ineligibleReason {
    if (status == HoldStatus.paused) return 'aportes pausados';
    if (status == HoldStatus.unwinding) return 'desmontando';
    if (blockedReason != null) return blockedReason;
    final g = grade;
    if (g == null) return 'sem nota';
    if (g <= 0) return 'nota $g';
    if (cls.needsPrice && (price == null || price! <= 0)) return 'sem cotação';
    return null;
  }

  bool get isEligible => ineligibleReason == null;
}

class DiagramSuggestion {
  final DiagramAsset asset;
  final double amount;

  /// Units to buy; null when bought by value.
  final double? units;

  /// Share of the whole portfolio after the contribution (0–100).
  final double sharePctAfter;

  const DiagramSuggestion(
    this.asset,
    this.amount,
    this.units,
    this.sharePctAfter,
  );
}

class DiagramPlan {
  final List<DiagramSuggestion> suggestions;

  /// What found no place: rounding, or no class below its target that can
  /// receive it. It stays uninvested rather than breaking the targets.
  final double unassigned;
  final double total;

  const DiagramPlan(this.suggestions, this.unassigned, this.total);
}

/// Splits a contribution in three steps. Between classes: by how far each is
/// below its target, on the portfolio after the contribution. Within a class:
/// each eligible asset's ideal is its grade over the sum of the grades, and the
/// money goes by how far it is below that. Finally rounded down to what can be
/// bought, buying one more of what lacks most while it fits. It never suggests
/// selling, and an asset above its ideal gets nothing, whatever its grade.
DiagramPlan planContribution({
  required List<DiagramAsset> assets,
  required Map<DiagramClass, double> targetPercent,
  required double amount,
}) {
  final held = assets.fold<double>(0, (sum, a) => sum + a.value);
  final totalAfter = held + math.max(amount, 0);
  if (amount <= 0) return DiagramPlan(const [], 0, held);

  double classValue(DiagramClass cls) => assets
      .where((a) => a.cls == cls)
      .fold<double>(0, (sum, a) => sum + a.value);

  // Step 1: between the classes.
  final gaps = <DiagramClass, double>{};
  for (final cls in DiagramClass.values) {
    final target = targetPercent[cls] ?? 0;
    if (target <= 0) continue;
    if (!assets.any((a) => a.cls == cls && a.isEligible)) continue;
    final gap = target / 100 * totalAfter - classValue(cls);
    if (gap > 0) gaps[cls] = gap;
  }
  final allGaps = gaps.values.fold<double>(0, (a, b) => a + b);
  final scale = allGaps > amount ? amount / allGaps : 1.0;

  final bought = <String, ({double amount, double? units})>{};
  var unassigned = amount;

  for (final entry in gaps.entries) {
    final cls = entry.key;
    final share = entry.value * scale;
    final eligible = assets.where((a) => a.cls == cls && a.isEligible).toList();
    final grades = eligible.fold<double>(0, (sum, a) => sum + a.grade!);
    // Step 2: within the class.
    final classTotal =
        eligible.fold<double>(0, (sum, a) => sum + a.value) + share;
    final lacks = {
      for (final asset in eligible)
        asset.key: math.max(
          0.0,
          asset.grade! / grades * classTotal - asset.value,
        ),
    };
    final allLacks = lacks.values.fold<double>(0, (a, b) => a + b);
    if (allLacks <= 0) continue;

    // Step 3: what can really be bought.
    var left = share;
    final remaining = <String, double>{};
    for (final asset in eligible) {
      final ideal = share * lacks[asset.key]! / allLacks;
      if (ideal <= 0) continue;
      final step = asset.step;
      if (step == null) {
        bought[asset.key] = (amount: ideal, units: null);
        left -= ideal;
        continue;
      }
      final units = _floorTo(ideal / asset.price!, step);
      final spent = units * asset.price!;
      if (units > 0) bought[asset.key] = (amount: spent, units: units);
      left -= spent;
      remaining[asset.key] = ideal - spent;
    }
    // The change buys one more unit of what lacks most, while it fits.
    if (remaining.isNotEmpty) {
      while (true) {
        DiagramAsset? best;
        for (final asset in eligible) {
          final lacking = remaining[asset.key];
          if (lacking == null || asset.step! * asset.price! > left + 1e-9) {
            continue;
          }
          if (best == null || lacking > remaining[best.key]!) best = asset;
        }
        if (best == null) break;
        final step = best.step!;
        final cost = step * best.price!;
        final current = bought[best.key];
        bought[best.key] = (
          amount: (current?.amount ?? 0) + cost,
          units: _floorTo((current?.units ?? 0) + step + step / 1000, step),
        );
        remaining[best.key] = remaining[best.key]! - cost;
        left -= cost;
      }
    }
    unassigned -= share - left;
  }

  final suggestions = [
    for (final asset in assets)
      if (bought[asset.key] case final buy?)
        DiagramSuggestion(
          asset,
          buy.amount,
          buy.units,
          totalAfter <= 0 ? 0 : (asset.value + buy.amount) / totalAfter * 100,
        ),
  ]..sort((a, b) => b.amount.compareTo(a.amount));
  return DiagramPlan(
    suggestions,
    unassigned < 0.005 ? 0 : unassigned,
    totalAfter,
  );
}

double _floorTo(double value, double step) {
  final steps = (value / step + 1e-9).floorToDouble();
  // Back through the decimals of the step, so that 0.0003 is not 0.00030000004.
  return double.parse((steps * step).toStringAsFixed(4));
}

const fixedIncomeGroups = {
  'rf:cdi': 'Indexados ao CDI',
  'rf:pre': 'Prefixado',
  'rf:ipca': 'IPCA',
  'rf:outros': 'Outros',
};

/// Which fixed income line a position belongs to, by what it pays.
String fixedIncomeGroupOf(Position position) {
  final inv = position.inv;
  final type = (inv.rateType ?? '').toUpperCase();
  if (type.contains('IPCA')) return 'rf:ipca';
  if (type.contains('CDI') || type.contains('SELIC')) return 'rf:cdi';
  if ((inv.fixedAnnualRate ?? 0) > 0) return 'rf:pre';
  if (position.product == 'Cofrinho') return 'rf:cdi';
  return 'rf:outros';
}

/// The class of a position; null when it stays out of the method.
DiagramClass? diagramClassOf(String product) => switch (product) {
  'CDB' ||
  'LCI' ||
  'LCA' ||
  'Cofrinho' ||
  'Tesouro' ||
  'Renda fixa' => DiagramClass.fixedIncome,
  'Ações' || 'ETF' => DiagramClass.nationalStock,
  'FII' => DiagramClass.fii,
  'Cripto' => DiagramClass.crypto,
  _ => null,
};

/// A fund that holds gold (GOLD11): a reserve of value, like a coin.
bool isGoldFund(Position position) {
  final text = '${position.inv.code ?? ''} ${position.inv.name}'.toUpperCase();
  return text.contains('GOLD') || text.contains('OURO');
}

/// A coin held in the app's wallets (the Dinzo does not see those).
class DiagramCoin {
  final String code;
  final String name;
  final double quantity;
  final double value;

  const DiagramCoin(this.code, this.name, this.quantity, this.value);
}

/// The lines of the portfolio: what is held, plus what the user added to study.
/// Returns also how much stays out of the method.
({List<DiagramAsset> assets, double outside, double fixedIncomeHeld})
diagramAssetsFrom({
  required List<Position> positions,
  required List<DiagramCoin> coins,
  required DiagramState state,
}) {
  final lines = <String, DiagramAsset>{};
  var outside = 0.0;

  void add(DiagramAsset line) {
    final current = lines[line.key];
    lines[line.key] = current == null
        ? line
        : DiagramAsset(
            key: line.key,
            label: line.label,
            cls: line.cls,
            ticker: line.ticker,
            value: current.value + line.value,
            quantity: current.quantity + line.quantity,
            price: line.price ?? current.price,
            isEtf: line.isEtf || current.isEtf,
          );
  }

  for (final position in positions) {
    final cls = diagramClassOf(position.product);
    if (cls == null) {
      outside += position.balance;
      continue;
    }
    if (cls == DiagramClass.fixedIncome) {
      final group = fixedIncomeGroupOf(position);
      add(
        DiagramAsset(
          key: group,
          label: fixedIncomeGroups[group]!,
          cls: cls,
          value: position.balance,
        ),
      );
      continue;
    }
    final ticker = StockCompany.tickerOf(position.inv);
    final gold = cls == DiagramClass.nationalStock && isGoldFund(position);
    final quantity = (position.inv.raw['quantity'] as num?)?.toDouble() ?? 0;
    add(
      DiagramAsset(
        key: ticker ?? position.inv.assetKey,
        label: ticker ?? position.inv.name,
        cls: gold ? DiagramClass.crypto : cls,
        ticker: ticker,
        value: position.balance,
        quantity: quantity,
        price: (position.inv.raw['value'] as num?)?.toDouble(),
        isEtf: gold || position.product == 'ETF',
      ),
    );
  }
  for (final coin in coins) {
    add(
      DiagramAsset(
        key: coin.code,
        label: coin.code,
        cls: DiagramClass.crypto,
        ticker: coin.code,
        value: coin.value,
        quantity: coin.quantity,
        price: coin.quantity > 0 ? coin.value / coin.quantity : null,
      ),
    );
  }
  final fixedIncome = lines.values
      .where((line) => line.cls == DiagramClass.fixedIncome)
      .fold<double>(0, (sum, line) => sum + line.value);
  for (final entry in state.watched.entries) {
    lines.putIfAbsent(
      entry.key,
      () => DiagramAsset(
        key: entry.key,
        label: entry.key,
        cls: entry.value,
        ticker: entry.key,
        isManual: true,
        isEtf: state.watchedEtfs.contains(entry.key),
      ),
    );
  }
  final assets = lines.values
      .map(
        (line) => line.withData(
          grade: state.gradeOf(line),
          status: state.statusOf(line.key),
        ),
      )
      .toList();
  assets.sort((a, b) {
    final byClass = b.cls.index.compareTo(a.cls.index);
    return byClass != 0 ? byClass : b.value.compareTo(a.value);
  });
  return (assets: assets, outside: outside, fixedIncomeHeld: fixedIncome);
}

/// Share of its class an eligible asset should have (0–100): its grade over the
/// sum of the grades of the eligible assets of the class. What the official
/// tool calls "recomendado".
double idealShareInClass(DiagramAsset asset, List<DiagramAsset> assets) {
  if (!asset.isEligible) return 0;
  final grades = assets
      .where((a) => a.cls == asset.cls && a.isEligible)
      .fold<double>(0, (sum, a) => sum + a.grade!);
  return grades <= 0 ? 0 : asset.grade! / grades * 100;
}

/// The emergency reserve comes before any investment: a contribution fills it
/// first, and only the rest goes to the portfolio.
({double toReserve, double toPortfolio}) splitForReserve({
  required double amount,
  required double reserve,
  required double target,
}) {
  final missing = math.max(0.0, target - reserve);
  final toReserve = math.min(math.max(amount, 0.0), missing);
  return (toReserve: toReserve, toPortfolio: math.max(amount, 0.0) - toReserve);
}

/// The roots of the Cerrado tree: where the money is. Seven or more painted is a
/// diversified portfolio.
enum CerradoRoot {
  emergency('Reserva de emergência', true),
  fixedIncome('Renda fixa no Brasil', true),
  stocks('Ações no Brasil', true),
  fiis('Fundos imobiliários no Brasil', true),
  etfs('ETFs no Brasil', true),
  etfsAbroad('ETFs no exterior', false),
  stocksAbroad('Ações no exterior', false),
  reits('REITs no exterior', false),
  digital('Reserva de valor digital', true),
  physical('Reserva de valor física', false),
  company('Uma empresa', false);

  final String label;

  /// In Brazil, or the reserve; the others are abroad or outside the market.
  final bool home;
  const CerradoRoot(this.label, this.home);

  static const diversified = 7;
}

/// Which roots have money.
Map<CerradoRoot, bool> cerradoRoots({
  required List<DiagramAsset> assets,
  required double emergencyReserve,
  required double fixedIncomeHeld,
}) {
  bool holds(bool Function(DiagramAsset) test) =>
      assets.any((a) => a.value > 0 && test(a));
  final seen = {
    CerradoRoot.emergency: emergencyReserve > 0,
    CerradoRoot.fixedIncome: fixedIncomeHeld > 0,
    CerradoRoot.stocks: holds(
      (a) => a.cls == DiagramClass.nationalStock && !a.isEtf,
    ),
    CerradoRoot.fiis: holds((a) => a.cls == DiagramClass.fii),
    CerradoRoot.etfs: holds(
      (a) => a.cls == DiagramClass.nationalStock && a.isEtf,
    ),
    CerradoRoot.stocksAbroad: holds(
      (a) => a.cls == DiagramClass.intlStock && !a.isEtf,
    ),
    CerradoRoot.etfsAbroad: holds(
      (a) => a.cls == DiagramClass.intlStock && a.isEtf,
    ),
    CerradoRoot.reits: holds((a) => a.cls == DiagramClass.reit),
    CerradoRoot.digital: holds((a) => a.cls == DiagramClass.crypto && !a.isEtf),
    CerradoRoot.physical: holds((a) => a.cls == DiagramClass.crypto && a.isEtf),
  };
  return {
    for (final root in CerradoRoot.values)
      root: seen[root] ?? false,
  };
}

/// The course's inverted triangle for stocks: a wide base of perennial,
/// profitable companies, strategic ones in the middle, speculation on top.
enum PortfolioTier {
  base('Base', 'Setores perenes, empresas antigas e lucrativas'),
  middle('Meio', 'Setores estratégicos, empresas em crescimento e com lucro'),
  top('Topo', 'Especulação: dinheiro que se aceita perder');

  final String label;
  final String description;
  const PortfolioTier(this.label, this.description);

  /// The base is about 60% of stocks; the top never more than 10% of wealth.
  static const baseShare = 60.0;
  static const topLimit = 10.0;
}

/// The profiles of the course's risk questionnaire (PIAR) and the range each
/// gives to a group of classes, in % of the portfolio. "Abroad" adds stocks,
/// ETFs and fixed income ETFs outside Brazil; the reserve of value adds gold
/// and crypto. A reference, never a ready portfolio.
enum PiarProfile {
  extremelyAggressive('Extremamente agressivo'),
  risky('Arriscado'),
  balanced('Equilibrado'),
  conservative('Conservador'),
  ultraConservative('Ultraconservador');

  final String label;
  const PiarProfile(this.label);

  Map<PiarGroup, (double, double)> get ranges => switch (this) {
    extremelyAggressive => const {
      PiarGroup.fixedIncome: (10, 25),
      PiarGroup.brStocks: (10, 30),
      PiarGroup.abroad: (15, 45),
      PiarGroup.realEstate: (0, 10),
      PiarGroup.valueReserve: (0, 10),
      PiarGroup.opportunity: (0, 10),
    },
    risky => const {
      PiarGroup.fixedIncome: (20, 30),
      PiarGroup.brStocks: (5, 20),
      PiarGroup.abroad: (15, 40),
      PiarGroup.realEstate: (5, 15),
      PiarGroup.valueReserve: (5, 10),
      PiarGroup.opportunity: (0, 15),
    },
    balanced => const {
      PiarGroup.fixedIncome: (20, 30),
      PiarGroup.brStocks: (5, 15),
      PiarGroup.abroad: (10, 25),
      PiarGroup.realEstate: (10, 20),
      PiarGroup.valueReserve: (0, 5),
      PiarGroup.opportunity: (5, 15),
    },
    conservative => const {
      PiarGroup.fixedIncome: (10, 40),
      PiarGroup.brStocks: (10, 30),
      PiarGroup.abroad: (25, 70),
      PiarGroup.realEstate: (10, 20),
      PiarGroup.valueReserve: (5, 13),
      PiarGroup.opportunity: (0, 0),
    },
    ultraConservative => const {
      PiarGroup.fixedIncome: (20, 50),
      PiarGroup.brStocks: (5, 15),
      PiarGroup.abroad: (30, 80),
      PiarGroup.realEstate: (5, 25),
      PiarGroup.valueReserve: (0, 16),
      PiarGroup.opportunity: (0, 0),
    },
  };

  double _middle(PiarGroup group) {
    final range = ranges[group];
    return range == null ? 0 : (range.$1 + range.$2) / 2;
  }

  /// The range of a group over the portfolio of the diagram. The profile's
  /// ranges are over the whole wealth, opportunity reserve included; the
  /// targets leave that reserve out, so the ranges grow by its middle share.
  (double, double) portfolioRange(PiarGroup group) {
    final (low, high) = ranges[group]!;
    final scale = 100 / (100 - _middle(PiarGroup.opportunity));
    return (low * scale, high * scale);
  }

  /// Targets that fit the profile: the middle of each range, scaled to 100%
  /// and kept inside [portfolioRange], in whole numbers. Real estate goes
  /// about 3/4 to FIIs and 1/4 to REITs.
  Map<DiagramClass, double> get suggestedTargets {
    final groups = [
      for (final group in ranges.keys)
        if (group != PiarGroup.opportunity) group,
    ];
    final pinned = <PiarGroup, double>{};
    Map<PiarGroup, double> spread() {
      final free = [
        for (final g in groups)
          if (!pinned.containsKey(g)) g,
      ];
      final left = 100 - pinned.values.fold(0.0, (a, b) => a + b);
      final weight = free.fold(0.0, (sum, g) => sum + _middle(g));
      return {
        ...pinned,
        for (final g in free)
          g: weight <= 0 ? left / free.length : _middle(g) / weight * left,
      };
    }

    // A group pushed out of its range stays at the edge, and the others share
    // what is left.
    var shares = spread();
    while (true) {
      final out = <PiarGroup, double>{
        for (final g in groups)
          if (!pinned.containsKey(g))
            if (shares[g]!.clamp(portfolioRange(g).$1, portfolioRange(g).$2)
                case final edge when edge != shares[g])
              g: edge,
      };
      if (out.isEmpty) break;
      pinned.addAll(out);
      shares = spread();
    }

    final whole = <PiarGroup, int>{};
    for (final g in groups) {
      final (low, high) = portfolioRange(g);
      whole[g] = shares[g]!.floor().clamp(low.ceil(), high.floor());
    }
    var missing = 100 - whole.values.fold(0, (a, b) => a + b);
    while (missing != 0) {
      final up = missing > 0;
      PiarGroup? best;
      for (final g in groups) {
        final (low, high) = portfolioRange(g);
        final next = whole[g]! + (up ? 1 : -1);
        if (next > high.floor() || next < low.ceil()) continue;
        final gap = shares[g]! - whole[g]!;
        if (best == null ||
            (up
                ? gap > shares[best]! - whole[best]!
                : gap < shares[best]! - whole[best]!)) {
          best = g;
        }
      }
      if (best == null) break;
      whole[best] = whole[best]! + (up ? 1 : -1);
      missing += up ? -1 : 1;
    }

    final realEstate = whole[PiarGroup.realEstate] ?? 0;
    final reit = realEstate ~/ 4;
    final targets = <DiagramClass, double>{
      DiagramClass.fixedIncome: (whole[PiarGroup.fixedIncome] ?? 0).toDouble(),
      DiagramClass.nationalStock: (whole[PiarGroup.brStocks] ?? 0).toDouble(),
      DiagramClass.intlStock: (whole[PiarGroup.abroad] ?? 0).toDouble(),
      DiagramClass.fii: (realEstate - reit).toDouble(),
      DiagramClass.reit: reit.toDouble(),
      DiagramClass.crypto: (whole[PiarGroup.valueReserve] ?? 0).toDouble(),
    };
    return {
      for (final e in targets.entries)
        if (e.value > 0) e.key: e.value,
    };
  }
}

enum PiarGroup {
  fixedIncome('Renda fixa', [DiagramClass.fixedIncome]),
  brStocks('Ações no Brasil', [DiagramClass.nationalStock]),
  abroad('Exterior (ações, ETFs, renda fixa)', [DiagramClass.intlStock]),
  realEstate('FIIs e REITs', [DiagramClass.fii, DiagramClass.reit]),
  valueReserve('Reserva de valor', [DiagramClass.crypto]),
  opportunity('Reserva de oportunidade', []);

  final String label;
  final List<DiagramClass> classes;
  const PiarGroup(this.label, this.classes);
}

/// How far the top of the triangle may still grow, and whether it is full.
({double top, double share, bool full}) topOfTriangle(
  List<DiagramAsset> assets,
  Map<String, PortfolioTier> tiers, {
  required double wealth,
}) {
  final top = assets
      .where((a) => tiers[a.key] == PortfolioTier.top)
      .fold<double>(0, (sum, a) => sum + a.value);
  final share = wealth <= 0 ? 0.0 : top / wealth * 100;
  return (top: top, share: share, full: share >= PortfolioTier.topLimit);
}

/// Targets, grades and questions. Goes in the backup and to the other devices.
class DiagramState {
  static const defaultStockQuestions = [
    'O ROE é consistentemente acima de 5%? (empresa endividada: olhar o ROIC)',
    'Receita ou lucro cresceram nos últimos 5 anos?',
    'Tem histórico de pagar dividendos?',
    'Investe em inovação, num setor que não está ficando obsoleto?',
    'Tem mais de 30 anos de mercado?',
    'É líder no seu setor, no país ou no mundo?',
    'O setor existe há mais de 100 anos?',
    'É uma empresa grande (blue chip)?',
    'Tem boa governança, sem histórico de corrupção?',
    'É independente do governo e de um único cliente?',
    'A dívida líquida/EBITDA ficou abaixo de 2 nos últimos 5 anos?',
    ..._addedStockQuestions,
  ];

  /// The criteria of the course's tool that the first version lacked. Added to a
  /// saved list once ([_questionsVersion]), so no answer is lost.
  static const _addedStockQuestions = [
    'A dívida líquida é menor que o lucro dos últimos 12 meses?',
    'Teve lucro operacional (EBIT) no último ano?',
    'O P/L está abaixo de 30?',
    'O P/VP está abaixo de 5?',
  ];

  static const defaultFiiQuestions = [
    'Os imóveis ficam em regiões nobres?',
    'Os imóveis são novos, com pouca manutenção?',
    'O P/VP está abaixo de 1? (acima de 1,5, melhor evitar)',
    'Paga dividendos consistentes há mais de 4 anos?',
    'Não depende de um único inquilino ou imóvel?',
    'O rendimento está na média ou acima da média do seu tipo?',
    ..._addedFiiQuestions,
  ];

  static const _addedFiiQuestions = [
    'A vacância é baixa?',
    'Os contratos de aluguel são longos?',
    'A taxa de administração é baixa?',
  ];

  static const defaultEtfQuestions = [
    'Replica um índice amplo e conhecido?',
    'A taxa de administração é baixa?',
    'Tem patrimônio grande e boa liquidez?',
    'Existe há vários anos?',
    'Acompanha bem o índice, com pouca diferença?',
    'Não repete o que já tenho na carteira?',
  ];

  static const _questionsVersion = 2;

  /// Targets of whoever has not set any: those of the balanced profile.
  static final defaultTargets = PiarProfile.balanced.suggestedTargets;

  /// Where to find each answer, by the labels of [assetLinks].
  static const questionSources = <String, List<String>>{
    'O ROE é consistentemente acima de 5%? (empresa endividada: olhar o ROIC)':
        ['AUVP Analítica'],
    'Receita ou lucro cresceram nos últimos 5 anos?': ['AUVP Analítica'],
    'Tem histórico de pagar dividendos?': ['AUVP Analítica'],
    'Investe em inovação, num setor que não está ficando obsoleto?': [
      'RI da empresa',
      'Notícias',
    ],
    'Tem mais de 30 anos de mercado?': ['RI da empresa'],
    'É líder no seu setor, no país ou no mundo?': [
      'AUVP Analítica',
      'Notícias',
    ],
    'É uma empresa grande (blue chip)?': ['AUVP Analítica'],
    'Tem boa governança, sem histórico de corrupção?': [
      'AUVP Analítica',
      'Notícias',
    ],
    'É independente do governo e de um único cliente?': ['RI da empresa'],
    'A dívida líquida/EBITDA ficou abaixo de 2 nos últimos 5 anos?': [
      'AUVP Analítica',
    ],
    'A dívida líquida é menor que o lucro dos últimos 12 meses?': [
      'AUVP Analítica',
    ],
    'Teve lucro operacional (EBIT) no último ano?': ['AUVP Analítica'],
    'O P/L está abaixo de 30?': ['AUVP Analítica'],
    'O P/VP está abaixo de 5?': ['AUVP Analítica'],
    'Os imóveis ficam em regiões nobres?': ['Funds Explorer', 'Gestora'],
    'Os imóveis são novos, com pouca manutenção?': ['Gestora'],
    'O P/VP está abaixo de 1? (acima de 1,5, melhor evitar)': [
      'Funds Explorer',
    ],
    'Paga dividendos consistentes há mais de 4 anos?': ['Clube FII'],
    'Não depende de um único inquilino ou imóvel?': [
      'Funds Explorer',
      'Gestora',
    ],
    'O rendimento está na média ou acima da média do seu tipo?': [
      'Funds Explorer',
    ],
    'A vacância é baixa?': ['Funds Explorer'],
    'Os contratos de aluguel são longos?': ['Gestora'],
    'A taxa de administração é baixa?': ['AUVP Analítica', 'Gestora'],
    'Replica um índice amplo e conhecido?': ['Gestora'],
    'Tem patrimônio grande e boa liquidez?': ['AUVP Analítica'],
    'Existe há vários anos?': ['AUVP Analítica'],
    'Acompanha bem o índice, com pouca diferença?': ['TradingView'],
  };

  /// Months that open a review of the grades, on their 1st: results come
  /// each quarter. Until every graded asset is reviewed, no contribution.
  static const reviewMonths = [2, 5, 8, 11];

  /// The review in force on [now]: the last 1st of [reviewMonths] up to it.
  static DateTime reviewStart(DateTime now) {
    for (var back = 0; back < 12; back++) {
      final month = DateTime(now.year, now.month - back);
      if (reviewMonths.contains(month.month)) return month;
    }
    return DateTime(now.year, now.month);
  }

  /// The date of the next review, after [now].
  static DateTime nextReview(DateTime now) {
    for (var ahead = 1; ahead <= 12; ahead++) {
      final month = DateTime(now.year, now.month + ahead);
      if (reviewMonths.contains(month.month)) return month;
    }
    return DateTime(now.year + 1, now.month);
  }

  final Map<DiagramClass, double> targets;

  /// Tickers added to study, without a position.
  final Map<String, DiagramClass> watched;

  /// Which of [watched] are index funds.
  final Set<String> watchedEtfs;
  final Map<String, Map<String, bool>> answers;

  /// Questions that do not apply to an asset, by asset.
  final Map<String, Set<String>> skipped;
  final Map<String, num> typedGrades;

  /// When each grade last changed.
  final Map<String, DateTime> gradedAt;
  final Map<String, HoldStatus> status;

  /// Why an asset was paused or is being sold.
  final Map<String, String> statusNotes;
  List<String> stockQuestions;
  List<String> fiiQuestions;
  List<String> etfQuestions;
  double lastContribution;

  /// The emergency reserve to have before investing.
  double emergencyTarget;

  /// Where each stock or fund sits in the triangle.
  final Map<String, PortfolioTier> tiers;

  /// Sector of each ticker, from brapi.dev, kept to avoid asking again.
  final Map<String, String> sectors;

  /// Quantity held abroad, by ticker (the Dinzo does not see foreign brokers).
  /// The value comes from the quote, in dollars, times the dollar.
  final Map<String, double> abroad;

  /// The usual monthly contribution: a sum above 10 times it is spread.
  double monthlyContribution;
  PiarProfile? piarProfile;

  DiagramState({
    Map<DiagramClass, double>? targets,
    Map<String, DiagramClass>? watched,
    Set<String>? watchedEtfs,
    Map<String, Map<String, bool>>? answers,
    Map<String, Set<String>>? skipped,
    Map<String, num>? typedGrades,
    Map<String, DateTime>? gradedAt,
    Map<String, HoldStatus>? status,
    Map<String, String>? statusNotes,
    List<String>? stockQuestions,
    List<String>? fiiQuestions,
    List<String>? etfQuestions,
    this.lastContribution = 0,
    this.emergencyTarget = 20000,
    Map<String, PortfolioTier>? tiers,
    Map<String, String>? sectors,
    Map<String, double>? abroad,
    this.monthlyContribution = 0,
    PiarProfile? piarProfile,
  }) : piarProfile =
           piarProfile ??
           (targets == null || targets.isEmpty ? PiarProfile.balanced : null),
       abroad = abroad ?? {},
       tiers = tiers ?? {},
       sectors = sectors ?? {},
       targets = targets == null || targets.isEmpty
           ? Map.of(defaultTargets)
           : targets,
       watched = watched ?? {},
       watchedEtfs = watchedEtfs ?? {},
       answers = answers ?? {},
       skipped = skipped ?? {},
       typedGrades = typedGrades ?? {},
       gradedAt = gradedAt ?? {},
       status = status ?? {},
       statusNotes = statusNotes ?? {},
       stockQuestions = stockQuestions ?? List.of(defaultStockQuestions),
       fiiQuestions = fiiQuestions ?? List.of(defaultFiiQuestions),
       etfQuestions = etfQuestions ?? List.of(defaultEtfQuestions);

  List<String> questionsOf(QuestionSet set) => switch (set) {
    QuestionSet.stock => stockQuestions,
    QuestionSet.fii => fiiQuestions,
    QuestionSet.etf => etfQuestions,
  };

  static List<String> defaultsOf(QuestionSet set) => switch (set) {
    QuestionSet.stock => defaultStockQuestions,
    QuestionSet.fii => defaultFiiQuestions,
    QuestionSet.etf => defaultEtfQuestions,
  };

  void setQuestions(QuestionSet set, List<String> questions) {
    switch (set) {
      case QuestionSet.stock:
        stockQuestions = questions;
      case QuestionSet.fii:
        fiiQuestions = questions;
      case QuestionSet.etf:
        etfQuestions = questions;
    }
  }

  num? gradeOf(DiagramAsset asset) => asset.cls.hasQuestionnaire
      ? questionnaireGrade(
          questionsOf(asset.questionSet),
          answers[asset.key] ?? const {},
          skipped: skipped[asset.key] ?? const {},
        )
      : typedGrades[asset.key];

  HoldStatus statusOf(String key) => status[key] ?? HoldStatus.buying;

  /// A grade just changed.
  void touch(String key, {DateTime? at}) =>
      gradedAt[key] = at ?? DateTime.now();

  /// Graded before the review in force.
  bool isStale(String key, DateTime now) {
    final at = gradedAt[key];
    return at != null && at.isBefore(reviewStart(now));
  }

  /// The assets with a questionnaire still to be reviewed this quarter: never
  /// graded, or graded before the review began.
  List<DiagramAsset> pendingReview(List<DiagramAsset> assets, DateTime now) {
    final start = reviewStart(now);
    return [
      for (final asset in assets)
        if (asset.cls.hasQuestionnaire &&
            (gradedAt[asset.key] == null ||
                gradedAt[asset.key]!.isBefore(start)))
          asset,
    ];
  }

  /// Forgets what was written about an asset added by hand, for removing it.
  void forget(String key) {
    watched.remove(key);
    watchedEtfs.remove(key);
    answers.remove(key);
    skipped.remove(key);
    typedGrades.remove(key);
    gradedAt.remove(key);
    status.remove(key);
    statusNotes.remove(key);
    tiers.remove(key);
    abroad.remove(key);
  }

  double get targetTotal => targets.values.fold(0, (a, b) => a + b);

  static DiagramClass? _classNamed(Object? name) =>
      DiagramClass.values.where((c) => c.name == name).firstOrNull;

  static List<String>? _withAdded(List<String>? saved, List<String> added) =>
      saved == null
      ? null
      : [...saved, ...added.where((q) => !saved.contains(q))];

  factory DiagramState.decode(String? raw) {
    if (raw == null || raw.isEmpty) return DiagramState();
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final old = ((json['questionsVersion'] as num?) ?? 1) < _questionsVersion;
      var stock = (json['stockQuestions'] as List?)?.cast<String>();
      var fii = (json['fiiQuestions'] as List?)?.cast<String>();
      if (old) {
        stock = _withAdded(stock, _addedStockQuestions);
        fii = _withAdded(fii, _addedFiiQuestions);
      }
      return DiagramState(
        targets: {
          for (final e in (json['targets'] as Map? ?? const {}).entries)
            if (_classNamed(e.key) != null)
              _classNamed(e.key)!: (e.value as num).toDouble(),
        },
        watched: {
          for (final e in (json['watched'] as Map? ?? const {}).entries)
            if (_classNamed(e.value) != null)
              e.key as String: _classNamed(e.value)!,
        },
        watchedEtfs: {
          ...(json['watchedEtfs'] as List? ?? const []).cast<String>(),
        },
        answers: {
          for (final e in (json['answers'] as Map? ?? const {}).entries)
            e.key as String: (e.value as Map).cast<String, bool>(),
        },
        skipped: {
          for (final e in (json['skipped'] as Map? ?? const {}).entries)
            e.key as String: {...(e.value as List).cast<String>()},
        },
        typedGrades: Map<String, num>.from(
          json['typedGrades'] as Map? ?? const {},
        ),
        gradedAt: {
          for (final e in (json['gradedAt'] as Map? ?? const {}).entries)
            if (DateTime.tryParse(e.value as String) != null)
              e.key as String: DateTime.parse(e.value as String),
        },
        status: {
          for (final e in (json['status'] as Map? ?? const {}).entries)
            if (HoldStatus.values.any((s) => s.name == e.value))
              e.key as String: HoldStatus.values.byName(e.value as String),
        },
        statusNotes: Map<String, String>.from(
          json['statusNotes'] as Map? ?? const {},
        ),
        stockQuestions: stock,
        fiiQuestions: fii,
        etfQuestions: (json['etfQuestions'] as List?)?.cast<String>(),
        lastContribution: (json['lastContribution'] as num?)?.toDouble() ?? 0,
        emergencyTarget: (json['emergencyTarget'] as num?)?.toDouble() ?? 20000,
        tiers: {
          for (final e in (json['tiers'] as Map? ?? const {}).entries)
            if (PortfolioTier.values.any((t) => t.name == e.value))
              e.key as String: PortfolioTier.values.byName(e.value as String),
        },
        sectors: Map<String, String>.from(json['sectors'] as Map? ?? const {}),
        abroad: {
          for (final e in (json['abroad'] as Map? ?? const {}).entries)
            e.key as String: (e.value as num).toDouble(),
        },
        monthlyContribution:
            (json['monthlyContribution'] as num?)?.toDouble() ?? 0,
        piarProfile: PiarProfile.values
            .where((p) => p.name == json['piarProfile'])
            .firstOrNull,
      );
    } catch (_) {
      return DiagramState();
    }
  }

  String encode() => jsonEncode({
    'questionsVersion': _questionsVersion,
    'targets': {for (final e in targets.entries) e.key.name: e.value},
    'watched': {for (final e in watched.entries) e.key: e.value.name},
    'watchedEtfs': watchedEtfs.toList(),
    'answers': answers,
    'skipped': {for (final e in skipped.entries) e.key: e.value.toList()},
    'typedGrades': typedGrades,
    'gradedAt': {
      for (final e in gradedAt.entries) e.key: e.value.toIso8601String(),
    },
    'status': {
      for (final e in status.entries)
        if (e.value != HoldStatus.buying) e.key: e.value.name,
    },
    'statusNotes': statusNotes,
    'stockQuestions': stockQuestions,
    'fiiQuestions': fiiQuestions,
    'etfQuestions': etfQuestions,
    'lastContribution': lastContribution,
    'emergencyTarget': emergencyTarget,
    'tiers': {for (final e in tiers.entries) e.key: e.value.name},
    'sectors': sectors,
    'abroad': abroad,
    'monthlyContribution': monthlyContribution,
    'piarProfile': ?piarProfile?.name,
  });

  static DiagramState load() => DiagramState.decode(
    ServiceConfig.sharedPreferences?.getString(
      PreferencesKeys.portfolioDiagram,
    ),
  );

  /// Bumped on every save: on the computer this page and a Ficha stay open side
  /// by side, each with its own copy.
  static final revision = ValueNotifier<int>(0);

  Future<void> save() async {
    final saved = ServiceConfig.sharedPreferences?.setString(
      PreferencesKeys.portfolioDiagram,
      encode(),
    );
    revision.value++;
    await saved;
  }
}
