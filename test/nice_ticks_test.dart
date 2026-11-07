import 'package:aupp/desktop/analysis-widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  void expectTicks(double low, double high, List<double> expected) {
    final ticks = niceTicks(low, high);
    expect(ticks.length, expected.length, reason: '$ticks');
    for (final (i, t) in ticks.indexed) {
      expect(t, closeTo(expected[i], 1e-9));
    }
  }

  test('round steps that cover the values', () {
    expectTicks(0, 37, [0, 10, 20, 30, 40]);
    expectTicks(0, 0.8, [0, 0.2, 0.4, 0.6, 0.8]);
    expectTicks(0, 2300000000, [
      0,
      500000000,
      1000000000,
      1500000000,
      2000000000,
      2500000000,
    ]);
  });

  test('zero is a tick when the values cross it', () {
    expectTicks(-3, 12, [-5, 0, 5, 10, 15]);
  });

  test('a flat series still gets a scale', () {
    expect(niceTicks(0, 0).length, greaterThan(1));
  });
}
