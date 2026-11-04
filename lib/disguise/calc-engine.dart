import 'package:intl/intl.dart';

/// Pure logic of the disguise calculator (fork, 2026-10-14): typing,
/// evaluation (with phone-calculator percent rules) and pt-BR formatting.
/// The expression is kept as typed: digits, ',' and the operators below.
class CalcEngine {
  static const plus = '+';
  static const minus = '−';
  static const times = '×';
  static const divide = '÷';
  static const percent = '%';
  static const operators = [plus, minus, times, divide];

  static final _grouped = NumberFormat('#,##0.##########', 'pt_BR');
  static final _plain = NumberFormat('0.##########', 'en_US');

  /// Applies one key to [expr]. [lastResult] is used when an operator starts
  /// an empty expression (continue from the last "=").
  static String press(String expr, String key, {double? lastResult}) {
    final last = expr.isEmpty ? '' : expr[expr.length - 1];
    final isDigit = RegExp(r'[0-9]').hasMatch(key);
    if (isDigit || key == '00') {
      if (last == percent) return expr;
      final number = currentNumber(expr);
      if (key == '00' && (number.isEmpty || number == '0')) return expr;
      if (number == '0') return expr.substring(0, expr.length - 1) + key;
      if (number.replaceAll(',', '').length >= 15) return expr;
      return expr + key;
    }
    if (key == ',') {
      final number = currentNumber(expr);
      if (number.contains(',') || last == percent) return expr;
      return expr + (number.isEmpty ? '0,' : ',');
    }
    if (key == percent) {
      return RegExp(r'[0-9]').hasMatch(last) ? expr + percent : expr;
    }
    if (operators.contains(key)) {
      if (expr.isEmpty) {
        if (lastResult != null) return toInput(lastResult) + key;
        return key == minus ? minus : expr;
      }
      if (expr == minus) return key == minus ? expr : '';
      if (operators.contains(last)) {
        return expr.substring(0, expr.length - 1) + key;
      }
      if (last == ',') return expr.substring(0, expr.length - 1) + key;
      return expr + key;
    }
    return expr;
  }

  static String backspace(String expr) =>
      expr.isEmpty ? expr : expr.substring(0, expr.length - 1);

  /// The number being typed at the end of [expr] ('' after an operator).
  static String currentNumber(String expr) =>
      RegExp(r'[0-9,]*$').firstMatch(expr)!.group(0)!;

  /// Value of [expr], ignoring a trailing operator or comma. Null when there
  /// is nothing to compute or on division by zero.
  static double? evaluate(String expr) {
    var e = expr;
    while (e.isNotEmpty &&
        (operators.contains(e[e.length - 1]) || e.endsWith(','))) {
      e = e.substring(0, e.length - 1);
    }
    if (e.isEmpty) return null;

    final tokens =
        RegExp(r'[0-9]+(?:,[0-9]*)?%?|[+−×÷]').allMatches(e).map((m) => m[0]!);
    var total = 0.0;
    var sign = 1.0;
    double? term;
    var pendingOp = '';
    var termStart = true;
    for (final t in tokens) {
      if (t == plus || t == minus) {
        if (term == null) {
          if (t == minus) sign = -sign;
          continue;
        }
        total += sign * term;
        sign = t == plus ? 1 : -1;
        term = null;
        termStart = true;
        continue;
      }
      if (t == times || t == divide) {
        pendingOp = t;
        continue;
      }
      final isPercent = t.endsWith(percent);
      var v = double.parse(
          (isPercent ? t.substring(0, t.length - 1) : t).replaceAll(',', '.'));
      if (isPercent) {
        // "200 + 10%" = 220; "50%" = 0,5; "200 × 10%" = 20.
        v = termStart && total != 0 ? total * v / 100 : v / 100;
      }
      if (term == null) {
        term = v;
      } else if (pendingOp == divide) {
        if (v == 0) return null;
        term = term / v;
      } else {
        term = term * v;
      }
      pendingOp = '';
      termStart = false;
    }
    if (term != null) total += sign * term;
    return _round(total);
  }

  static double _round(double v) => double.parse(v.toStringAsFixed(10));

  /// "1.250,5" (grouped, comma decimals).
  static String format(double v) => _grouped.format(v == 0 ? 0 : v);

  /// Typable form of a result: "1250,5", "−3".
  static String toInput(double v) {
    final s = _plain.format(v.abs()).replaceAll('.', ',');
    return v < 0 ? '$minus$s' : s;
  }

  /// [expr] with thousands grouping in each number, for display.
  static String display(String expr) => expr.replaceAllMapped(
        RegExp(r'[0-9]+'),
        (m) {
          // Only the integer part of a number gets grouped.
          final before = m.start > 0 ? expr[m.start - 1] : '';
          if (before == ',') return m[0]!;
          return _grouped.format(int.parse(m[0]!));
        },
      );
}

/// Split-the-bill math ("racha conta"). Service applies to everything;
/// drinks are split only among those who drank.
class SplitBill {
  final double total;
  final double servicePercent;
  final int people;
  final double drinks;
  final int drinkers;

  const SplitBill({
    required this.total,
    this.servicePercent = 10,
    required this.people,
    this.drinks = 0,
    this.drinkers = 0,
  });

  double get _factor => 1 + servicePercent / 100;
  double get totalWithService => total * _factor;

  bool get splitsDrinks =>
      drinks > 0 && drinkers > 0 && drinkers < people && drinks <= total;

  /// What each one who did not drink pays (everyone, without drinks).
  double get perPerson {
    if (people <= 0) return 0;
    if (!splitsDrinks) return totalWithService / people;
    return (total - drinks) * _factor / people;
  }

  /// What each one who drank pays.
  double get perDrinker =>
      splitsDrinks ? perPerson + drinks * _factor / drinkers : perPerson;
}
