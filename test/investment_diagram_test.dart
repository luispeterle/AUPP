// The portfolio method: grades, and how a contribution is split between classes
// and assets.
import 'package:flutter_test/flutter_test.dart';
import 'package:aupp/investments/diagram.dart';

void main() {
  DiagramAsset asset(
    String key,
    DiagramClass cls, {
    double value = 0,
    double? price,
    num? grade,
  }) => DiagramAsset(
    key: key,
    label: key,
    cls: cls,
    ticker: key,
    value: value,
    price: price,
    grade: grade,
  );

  group('questionnaireGrade', () {
    const questions = ['a', 'b', 'c'];

    test('yes counts +1 and no counts -1', () {
      expect(questionnaireGrade(questions, {'a': true, 'b': true, 'c': true}), 3);
      expect(questionnaireGrade(questions, {'a': true, 'b': true, 'c': false}), 1);
      expect(questionnaireGrade(questions, {'a': false, 'b': false, 'c': false}), -3);
    });

    test('not fully answered has no grade, which is different from zero', () {
      expect(questionnaireGrade(questions, {'a': true}), isNull);
      expect(questionnaireGrade(['a', 'b'], {'a': true, 'b': false}), 0);
      expect(questionnaireGrade([], {}), isNull);
    });

    test('an answer to a question that changed does not count', () {
      expect(questionnaireGrade(['nova'], {'antiga': true}), isNull);
    });
  });

  group('eligibility', () {
    test('needs a positive grade and, when bought in units, a price', () {
      final ok = asset('A', DiagramClass.nationalStock, price: 10, grade: 1);
      expect(ok.isEligible, isTrue);
      expect(asset('A', DiagramClass.nationalStock, price: 10).ineligibleReason, 'sem nota');
      expect(asset('A', DiagramClass.nationalStock, price: 10, grade: 0).isEligible, isFalse);
      expect(asset('A', DiagramClass.nationalStock, price: 10, grade: -3).isEligible, isFalse);
      expect(asset('A', DiagramClass.nationalStock, grade: 3).ineligibleReason, 'sem cotação');
    });

    test('fixed income needs no price', () {
      expect(asset('rf', DiagramClass.fixedIncome, grade: 5).isEligible, isTrue);
    });
  });

  group('planContribution', () {
    DiagramSuggestion? of(DiagramPlan plan, String key) =>
        plan.suggestions.where((s) => s.asset.key == key).firstOrNull;

    void balances(DiagramPlan plan, double amount) {
      final spent = plan.suggestions.fold<double>(0, (s, x) => s + x.amount);
      expect(spent + plan.unassigned, closeTo(amount, 0.01));
      expect(plan.unassigned, greaterThanOrEqualTo(0));
      for (final s in plan.suggestions) {
        expect(s.amount, greaterThan(0));
      }
    }

    test('goes to the class below its target, on the total after it', () {
      final plan = planContribution(
        assets: [
          asset('RF', DiagramClass.fixedIncome, value: 900, grade: 5),
          asset('ACAO', DiagramClass.nationalStock, value: 100, price: 10, grade: 3),
        ],
        targetPercent: {
          DiagramClass.fixedIncome: 50,
          DiagramClass.nationalStock: 50,
        },
        amount: 200,
      );
      // Total after = 1200, so each class should have 600: only stocks lack.
      expect(of(plan, 'RF'), isNull);
      expect(of(plan, 'ACAO')!.amount, closeTo(200, 0.001));
      expect(of(plan, 'ACAO')!.units, 20);
      balances(plan, 200);
    });

    test('splits by the gaps when the money does not close them all', () {
      final plan = planContribution(
        assets: [
          asset('RF', DiagramClass.fixedIncome, value: 0, grade: 5),
          asset('X', DiagramClass.crypto, value: 0, price: 0.0001, grade: 5),
        ],
        targetPercent: {DiagramClass.fixedIncome: 75, DiagramClass.crypto: 25},
        amount: 1000,
      );
      expect(of(plan, 'RF')!.amount, closeTo(750, 0.01));
      expect(of(plan, 'X')!.amount, closeTo(250, 0.01));
      balances(plan, 1000);
    });

    test('within a class the ideal follows the grades', () {
      final plan = planContribution(
        assets: [
          asset('A', DiagramClass.fixedIncome, grade: 3),
          asset('B', DiagramClass.fixedIncome, grade: 1),
        ],
        targetPercent: {DiagramClass.fixedIncome: 100},
        amount: 1000,
      );
      expect(of(plan, 'A')!.amount, closeTo(750, 0.001));
      expect(of(plan, 'B')!.amount, closeTo(250, 0.001));
      expect(of(plan, 'A')!.units, isNull);
    });

    test('a high grade does not buy what is already above its ideal', () {
      final plan = planContribution(
        assets: [
          asset('ALTA', DiagramClass.fixedIncome, value: 1000, grade: 8),
          asset('BAIXA', DiagramClass.fixedIncome, value: 0, grade: 2),
        ],
        targetPercent: {DiagramClass.fixedIncome: 100},
        amount: 100,
      );
      // Total 1100: ideals 880 and 220; ALTA is over.
      expect(of(plan, 'ALTA'), isNull);
      expect(of(plan, 'BAIXA')!.amount, closeTo(100, 0.001));
    });

    test('no grade, or a grade of zero or less, gets nothing but counts', () {
      final plan = planContribution(
        assets: [
          asset('SEM', DiagramClass.nationalStock, value: 500, price: 10),
          asset('ZERO', DiagramClass.nationalStock, price: 10, grade: 0),
          asset('NEG', DiagramClass.nationalStock, price: 10, grade: -1),
          asset('BOA', DiagramClass.nationalStock, price: 10, grade: 1),
        ],
        targetPercent: {DiagramClass.nationalStock: 100},
        amount: 100,
      );
      expect(plan.suggestions.single.asset.key, 'BOA');
      expect(plan.total, 600);
    });

    test('a class without anything to buy leaves its money undistributed', () {
      final plan = planContribution(
        assets: [
          asset('RF', DiagramClass.fixedIncome, value: 100, grade: 5),
          asset('SEM', DiagramClass.nationalStock, price: 10),
        ],
        targetPercent: {
          DiagramClass.fixedIncome: 50,
          DiagramClass.nationalStock: 50,
        },
        amount: 100,
      );
      // Only fixed income can receive, up to its 50% of 200: nothing lacks.
      expect(plan.suggestions, isEmpty);
      expect(plan.unassigned, 100);
    });

    test('a class above its target gets nothing and it never suggests selling', () {
      final plan = planContribution(
        assets: [
          asset('RF', DiagramClass.fixedIncome, value: 10000, grade: 8),
          asset('A', DiagramClass.nationalStock, price: 10, grade: 1),
        ],
        targetPercent: {
          DiagramClass.fixedIncome: 10,
          DiagramClass.nationalStock: 90,
        },
        amount: 100,
      );
      expect(of(plan, 'RF'), isNull);
      expect(of(plan, 'A')!.amount, 100);
    });

    test('shares are whole, rounded down, and the change buys more of what lacks most', () {
      final plan = planContribution(
        assets: [
          asset('A', DiagramClass.nationalStock, price: 30, grade: 1),
          asset('B', DiagramClass.nationalStock, price: 30, grade: 1),
        ],
        targetPercent: {DiagramClass.nationalStock: 100},
        amount: 100,
      );
      // 50 each is 1 share (30), and 40 is left: one more share of one of them.
      expect(of(plan, 'A')!.units! + of(plan, 'B')!.units!, 3);
      expect(plan.unassigned, closeTo(10, 0.001));
      balances(plan, 100);
    });

    test('what is too expensive for the money stays undistributed', () {
      final plan = planContribution(
        assets: [asset('CARA', DiagramClass.nationalStock, price: 500, grade: 1)],
        targetPercent: {DiagramClass.nationalStock: 100},
        amount: 100,
      );
      expect(plan.suggestions, isEmpty);
      expect(plan.unassigned, 100);
    });

    test('coins go in 4 decimals', () {
      final plan = planContribution(
        assets: [asset('BTC', DiagramClass.crypto, price: 300000, grade: 5)],
        targetPercent: {DiagramClass.crypto: 100},
        amount: 100,
      );
      final buy = plan.suggestions.single;
      expect(buy.units, 0.0003);
      expect(buy.amount, closeTo(90, 0.001));
      balances(plan, 100);
    });

    test('share after the contribution is of the whole portfolio', () {
      final plan = planContribution(
        assets: [asset('A', DiagramClass.fixedIncome, value: 100, grade: 1)],
        targetPercent: {DiagramClass.fixedIncome: 100},
        amount: 100,
      );
      expect(plan.suggestions.single.sharePctAfter, closeTo(100, 0.001));
    });

    test('nothing to split, nothing suggested', () {
      final plan = planContribution(
        assets: [asset('A', DiagramClass.fixedIncome, value: 50, grade: 1)],
        targetPercent: {DiagramClass.fixedIncome: 100},
        amount: 0,
      );
      expect(plan.suggestions, isEmpty);
      expect(plan.unassigned, 0);
      expect(plan.total, 50);
    });

    test('with no targets everything stays undistributed', () {
      final plan = planContribution(
        assets: [asset('A', DiagramClass.fixedIncome, grade: 1)],
        targetPercent: const {},
        amount: 50,
      );
      expect(plan.suggestions, isEmpty);
      expect(plan.unassigned, 50);
    });

    test('the sum always closes, across many cases', () {
      for (final amount in [1.0, 37.5, 999.99, 10000.0, 123456.78]) {
        final plan = planContribution(
          assets: [
            asset('A', DiagramClass.nationalStock, value: 3000, price: 31.7, grade: 5),
            asset('B', DiagramClass.nationalStock, value: 100, price: 7.13, grade: 1),
            asset('C', DiagramClass.fii, value: 500, price: 8.88, grade: 2),
            asset('D', DiagramClass.crypto, value: 900, price: 412345.67, grade: 3),
            asset('E', DiagramClass.fixedIncome, value: 20000, grade: 8),
            asset('F', DiagramClass.fixedIncome, value: 100, grade: 3),
          ],
          targetPercent: {
            DiagramClass.nationalStock: 40,
            DiagramClass.fii: 10,
            DiagramClass.crypto: 10,
            DiagramClass.fixedIncome: 40,
          },
          amount: amount,
        );
        balances(plan, amount);
      }
    });
  });

  group('DiagramState', () {
    test('survives a round trip', () {
      final state = DiagramState(
        targets: {DiagramClass.fii: 30, DiagramClass.fixedIncome: 70},
        watched: {'VALE3': DiagramClass.nationalStock},
        answers: {
          'PETR4': {'a': true, 'b': false},
        },
        typedGrades: {'rf:cdi': 7},
        stockQuestions: ['a', 'b'],
        lastContribution: 1500,
      );
      final read = DiagramState.decode(state.encode());
      expect(read.targets[DiagramClass.fii], 30);
      expect(read.watched['VALE3'], DiagramClass.nationalStock);
      expect(read.answers['PETR4'], {'a': true, 'b': false});
      expect(read.typedGrades['rf:cdi'], 7);
      expect(read.stockQuestions, ['a', 'b']);
      expect(read.fiiQuestions, DiagramState.defaultFiiQuestions);
      expect(read.lastContribution, 1500);
    });

    test('without targets, those of the balanced profile', () {
      final read = DiagramState.decode('{"targets": {}}');
      expect(read.targets, PiarProfile.balanced.suggestedTargets);
      expect(read.piarProfile, PiarProfile.balanced);
    });

    test('each profile suggests whole targets, summing 100%, inside its '
        'ranges', () {
      for (final profile in PiarProfile.values) {
        final targets = profile.suggestedTargets;
        expect(
          targets.values.fold(0.0, (a, b) => a + b),
          100,
          reason: profile.label,
        );
        for (final value in targets.values) {
          expect(value, value.roundToDouble(), reason: profile.label);
        }
        for (final group in profile.ranges.keys) {
          if (group == PiarGroup.opportunity) continue;
          final (low, high) = profile.portfolioRange(group);
          final mine = group.classes.fold(
            0.0,
            (sum, c) => sum + (targets[c] ?? 0),
          );
          expect(
            mine,
            inInclusiveRange(low, high),
            reason: '${profile.label}: ${group.label}',
          );
        }
      }
    });

    test('a damaged value does not break the page', () {
      final read = DiagramState.decode('{not json');
      expect(read.targets, DiagramState.defaultTargets);
      expect(read.stockQuestions, DiagramState.defaultStockQuestions);
    });

    test('the grade comes from the questionnaire or from what was typed', () {
      final state = DiagramState(
        answers: {
          'PETR4': {'a': true, 'b': true},
        },
        typedGrades: {'BTC': 4},
        stockQuestions: ['a', 'b'],
      );
      expect(state.gradeOf(asset('PETR4', DiagramClass.nationalStock)), 2);
      expect(state.gradeOf(asset('VALE3', DiagramClass.nationalStock)), isNull);
      expect(state.gradeOf(asset('BTC', DiagramClass.crypto)), 4);
      expect(state.gradeOf(asset('XMR', DiagramClass.crypto)), isNull);
    });

    test('FIIs, REITs and ETFs have their own questions', () {
      final state = DiagramState();
      QuestionSet setOf(DiagramClass cls, {bool etf = false}) => DiagramAsset(
        key: 'x',
        label: 'x',
        cls: cls,
        isEtf: etf,
      ).questionSet;
      expect(state.questionsOf(setOf(DiagramClass.fii)), hasLength(9));
      expect(state.questionsOf(setOf(DiagramClass.reit)), hasLength(9));
      expect(state.questionsOf(setOf(DiagramClass.nationalStock)), hasLength(15));
      expect(state.questionsOf(setOf(DiagramClass.intlStock)), hasLength(15));
      expect(
        state.questionsOf(setOf(DiagramClass.nationalStock, etf: true)),
        DiagramState.defaultEtfQuestions,
      );
    });

    test('an old saved list gets the new criteria, keeping its answers', () {
      final read = DiagramState.decode(
        '{"stockQuestions":["minha"],"fiiQuestions":["x"],'
        '"answers":{"PETR4":{"minha":true}}}',
      );
      expect(read.stockQuestions.first, 'minha');
      expect(read.stockQuestions, hasLength(5));
      expect(read.fiiQuestions, hasLength(4));
      expect(read.answers['PETR4'], {'minha': true});
      // Once saved, it does not grow again.
      expect(DiagramState.decode(read.encode()).stockQuestions, hasLength(5));
    });

    test('what does not apply counts nothing', () {
      expect(
        questionnaireGrade(['a', 'b', 'c'], {'a': true, 'b': true}, skipped: {'c'}),
        2,
      );
      expect(questionnaireGrade(['a'], {}, skipped: {'a'}), isNull);
    });

    test('reviews on the 1st of February, May, August and November', () {
      expect(DiagramState.reviewStart(DateTime(2026, 11, 1)), DateTime(2026, 11));
      expect(DiagramState.reviewStart(DateTime(2026, 10, 31)), DateTime(2026, 8));
      expect(DiagramState.reviewStart(DateTime(2027, 1, 15)), DateTime(2026, 11));
      expect(DiagramState.nextReview(DateTime(2026, 11, 1)), DateTime(2027, 2));
      expect(DiagramState.nextReview(DateTime(2027, 4, 30)), DateTime(2027, 5));
    });

    test('what is pending review: graded before it began, or never', () {
      final state = DiagramState(
        gradedAt: {
          'PETR4': DateTime(2026, 10, 20),
          'WEGE3': DateTime(2026, 11, 1, 9),
        },
      );
      final pending = state.pendingReview([
        asset('PETR4', DiagramClass.nationalStock),
        asset('WEGE3', DiagramClass.nationalStock),
        asset('ITUB4', DiagramClass.nationalStock),
        asset('BTC', DiagramClass.crypto),
      ], DateTime(2026, 11, 2));
      expect(pending.map((a) => a.key), ['PETR4', 'ITUB4']);
    });

    test('status, notes and dates survive a round trip', () {
      final state = DiagramState(
        status: {'VALE3': HoldStatus.paused},
        statusNotes: {'VALE3': holdReasons.first},
        gradedAt: {'VALE3': DateTime(2026, 1, 2)},
        skipped: {'ITUB4': {'q'}},
        watchedEtfs: {'IVVB11'},
        emergencyTarget: 30000,
      );
      final read = DiagramState.decode(state.encode());
      expect(read.statusOf('VALE3'), HoldStatus.paused);
      expect(read.statusOf('PETR4'), HoldStatus.buying);
      expect(read.statusNotes['VALE3'], holdReasons.first);
      expect(read.gradedAt['VALE3'], DateTime(2026, 1, 2));
      expect(read.isStale('VALE3', DateTime(2026, 6, 1)), isTrue);
      expect(read.isStale('VALE3', DateTime(2026, 1, 31)), isFalse);
      expect(read.skipped['ITUB4'], {'q'});
      expect(read.watchedEtfs, {'IVVB11'});
      expect(read.emergencyTarget, 30000);
      expect(DiagramState().emergencyTarget, 20000);
    });
  });

  group('Buy and Hold', () {
    test('a paused or unwinding asset gets no money, whatever its grade', () {
      for (final status in [HoldStatus.paused, HoldStatus.unwinding]) {
        final held = DiagramAsset(
          key: 'VALE3',
          label: 'VALE3',
          cls: DiagramClass.nationalStock,
          grade: 10,
          price: 10,
          status: status,
        );
        expect(held.isEligible, isFalse);
        final plan = planContribution(
          assets: [held],
          targetPercent: {DiagramClass.nationalStock: 100},
          amount: 1000,
        );
        expect(plan.suggestions, isEmpty);
      }
    });

    test('the ideal share in the class follows the grades', () {
      final assets = [
        asset('A', DiagramClass.nationalStock, price: 1, grade: 6),
        asset('B', DiagramClass.nationalStock, price: 1, grade: 2),
        asset('C', DiagramClass.nationalStock, price: 1, grade: -3),
      ];
      expect(idealShareInClass(assets[0], assets), 75);
      expect(idealShareInClass(assets[1], assets), 25);
      expect(idealShareInClass(assets[2], assets), 0);
    });

    test('the emergency reserve is filled before the portfolio', () {
      var split = splitForReserve(amount: 3000, reserve: 18000, target: 20000);
      expect(split.toReserve, 2000);
      expect(split.toPortfolio, 1000);
      split = splitForReserve(amount: 1000, reserve: 5000, target: 20000);
      expect(split.toReserve, 1000);
      expect(split.toPortfolio, 0);
      split = splitForReserve(amount: 1000, reserve: 25000, target: 20000);
      expect(split.toReserve, 0);
      expect(split.toPortfolio, 1000);
    });
  });

  group('triangle, profiles and gold', () {
    test('the top of the triangle stops at 10% of wealth', () {
      final assets = [
        DiagramAsset(key: 'WEGE3', label: 'WEGE3', cls: DiagramClass.nationalStock, value: 900),
        DiagramAsset(key: 'OIBR3', label: 'OIBR3', cls: DiagramClass.nationalStock, value: 100),
      ];
      final tiers = {'WEGE3': PortfolioTier.base, 'OIBR3': PortfolioTier.top};
      expect(topOfTriangle(assets, tiers, wealth: 2000).full, isFalse);
      final top = topOfTriangle(assets, tiers, wealth: 1000);
      expect(top.share, 10);
      expect(top.full, isTrue);
      final blocked = assets.last.withData(grade: 5, price: 1, blockedReason: 'topo');
      expect(blocked.ineligibleReason, 'topo');
    });

    test('each PIAR range is a valid band', () {
      for (final profile in PiarProfile.values) {
        for (final (low, high) in profile.ranges.values) {
          expect(low, lessThanOrEqualTo(high));
        }
        expect(profile.ranges.keys, contains(PiarGroup.fixedIncome));
      }
    });

    test('a gold fund is a reserve of value bought in whole shares', () {
      final gold = DiagramAsset(
        key: 'GOLD11',
        label: 'GOLD11',
        cls: DiagramClass.crypto,
        isEtf: true,
        grade: 5,
        price: 20,
      );
      final coin = asset('BTC', DiagramClass.crypto, price: 300000, grade: 5);
      expect(gold.step, 1);
      expect(coin.step, 0.0001);
      final plan = planContribution(
        assets: [gold, coin],
        targetPercent: {DiagramClass.crypto: 100},
        amount: 1000,
      );
      final bought = {for (final s in plan.suggestions) s.asset.key: s.units};
      expect(bought['GOLD11']! % 1, 0);
    });

    test('tiers, sectors, profile and monthly sum survive a round trip', () {
      final read = DiagramState.decode(
        DiagramState(
          tiers: {'WEGE3': PortfolioTier.base},
          sectors: {'WEGE3': 'Bens Industriais'},
          monthlyContribution: 2000,
          piarProfile: PiarProfile.balanced,
        ).encode(),
      );
      expect(read.tiers['WEGE3'], PortfolioTier.base);
      expect(read.sectors['WEGE3'], 'Bens Industriais');
      expect(read.monthlyContribution, 2000);
      expect(read.piarProfile, PiarProfile.balanced);
    });
  });

  test('quantities abroad survive a round trip and go with the asset', () {
    final state = DiagramState(abroad: {'VOO': 2.5}, watched: {'VOO': DiagramClass.intlStock});
    final read = DiagramState.decode(state.encode());
    expect(read.abroad['VOO'], 2.5);
    read.forget('VOO');
    expect(read.abroad, isEmpty);
  });

  test('stocks and ETFs abroad paint their own roots', () {
    final roots = cerradoRoots(
      assets: [
        DiagramAsset(key: 'VOO', label: 'VOO', cls: DiagramClass.intlStock, value: 10, isEtf: true),
      ],
      emergencyReserve: 0,
      fixedIncomeHeld: 0,
    );
    expect(roots[CerradoRoot.etfsAbroad], isTrue);
    expect(roots[CerradoRoot.stocksAbroad], isFalse);
  });

  group('Cerrado tree', () {
    test('paints what is held', () {
      final roots = cerradoRoots(
        assets: [
          DiagramAsset(key: 'PETR4', label: 'PETR4', cls: DiagramClass.nationalStock, value: 10),
          DiagramAsset(key: 'IVVB11', label: 'IVVB11', cls: DiagramClass.nationalStock, value: 10, isEtf: true),
          DiagramAsset(key: 'MXRF11', label: 'MXRF11', cls: DiagramClass.fii),
          DiagramAsset(key: 'BTC', label: 'BTC', cls: DiagramClass.crypto, value: 5),
        ],
        emergencyReserve: 100,
        fixedIncomeHeld: 0,
      );
      expect(
        [for (final e in roots.entries) if (e.value) e.key],
        [
          CerradoRoot.emergency,
          CerradoRoot.stocks,
          CerradoRoot.etfs,
          CerradoRoot.digital,
        ],
      );
      expect(CerradoRoot.values, hasLength(11));
    });
  });

  group('classes', () {
    test('funds and pension plans stay out of the method', () {
      expect(diagramClassOf('CDB'), DiagramClass.fixedIncome);
      expect(diagramClassOf('Cofrinho'), DiagramClass.fixedIncome);
      expect(diagramClassOf('Tesouro'), DiagramClass.fixedIncome);
      expect(diagramClassOf('Ações'), DiagramClass.nationalStock);
      expect(diagramClassOf('ETF'), DiagramClass.nationalStock);
      expect(diagramClassOf('FII'), DiagramClass.fii);
      expect(diagramClassOf('Cripto'), DiagramClass.crypto);
      expect(diagramClassOf('Fundo'), isNull);
      expect(diagramClassOf('Previdência'), isNull);
      expect(diagramClassOf('COE'), isNull);
    });
  });
}
