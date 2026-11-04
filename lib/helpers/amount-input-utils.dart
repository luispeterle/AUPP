import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:function_tree/function_tree.dart';
import 'package:aupp/desktop/desktop-layout.dart';
import 'package:aupp/records/formatter/auto_decimal_shift_formatter.dart';
import 'package:aupp/records/formatter/calculator-normalizer.dart';
import 'package:aupp/records/formatter/group-separator-formatter.dart';
import 'package:aupp/records/formatter/max_decimal_digits_formatter.dart';

import 'records-utility-functions.dart';

bool isMathExpression(String text) {
  return RegExp(r'[+\-*/%]').hasMatch(text);
}

/// Strips grouping/decimal separators and returns the expression ready to be
/// evaluated by [function_tree], or null if [text] is not a math expression.
String? tryParseMathExpr(String text) {
  if (!isMathExpression(text)) return null;
  try {
    text = text.replaceAll(getGroupingSeparator(), "");
    text = text.replaceAll(getDecimalSeparator(), ".");
    return text;
  } catch (_) {
    return null;
  }
}

/// Evaluates a math expression in [controller] and replaces the text with the
/// formatted result. Calls [onSolved] with the new text if provided.
void solveMathExpressionAndUpdateController(
  TextEditingController controller, {
  void Function(String)? onSolved,
}) {
  final text = controller.text.toLowerCase();
  final mathExpr = tryParseMathExpr(text);
  if (mathExpr == null) return;
  try {
    final result = mathExpr.interpret();
    final formatted =
        getCurrencyValueString(result.toDouble(), turnOffGrouping: false);
    controller.value = controller.value.copyWith(
      text: formatted,
      selection:
          TextSelection(baseOffset: formatted.length, extentOffset: formatted.length),
      composing: TextRange.empty,
    );
    onSolved?.call(controller.text.toLowerCase());
  } catch (e) {
    stderr.writeln("Can't parse the expression: $text");
  }
}

/// The system keyboard for amounts: the computer's physical one accepts any
/// character, the phone's is numeric.
TextInputType getAmountInputKeyboardType({bool signed = false}) => isComputer
    ? TextInputType.phone
    : TextInputType.numberWithOptions(decimal: true, signed: signed);

/// Returns the zero placeholder text for amount fields.
/// Returns `"0.00"` (locale-appropriate) when auto-decimal is on, `"0"` otherwise.
///
/// If [decimalDigits] is provided, it overrides the global [getNumberDecimalDigits]
/// so hint text matches the expected decimal count for the specific field.
String buildZeroAmountText({int? decimalDigits}) {
  if (!getAmountInputAutoDecimalShift()) return '0';
  final decDigits = decimalDigits ?? getNumberDecimalDigits();
  if (decDigits <= 0) return '0';
  final decSep = getDecimalSeparator();
  return '0$decSep${List.filled(decDigits, '0').join()}';
}

/// Shared validation error message for unparseable amount strings.
///
/// The example shown reflects the field's actual expected precision: pass
/// [decimalDigits] to match a field's override, or leave it null to use the
/// global [getNumberDecimalDigits] preference.
String amountFormatErrorMessage({int? decimalDigits}) {
  final exampleFormat = getNumberFormatWithCustomizations(
    turnOffGrouping: true,
    decimalDigits: decimalDigits,
  );
  return 'Não é um formato válido (use por exemplo: ${exampleFormat.format(1234.20)})';
}

/// Returns the [RegExp] used to deny characters not valid in an amount field.
RegExp buildAmountAllowedRegex() {
  return RegExp(
      '[^0-9\\+\\-\\*/%${RegExp.escape(getDecimalSeparator())}${RegExp.escape(getGroupingSeparator())}]');
}

/// Builds the list of [TextInputFormatter]s used by amount input fields.
///
/// If [unlimitedDecimals] is true, no cap is placed on the number of decimal
/// digits the user can type: [MaxDecimalDigitsFormatter] is omitted and
/// [AutoDecimalShiftFormatter] is forced off, since shifting digits into
/// place from the right only makes sense for a fixed decimal-digit count.
/// Used for fields like the currency conversion ratio, where truncating
/// precision would defeat the purpose of the field.
List<TextInputFormatter> buildAmountInputFormatters({
  required String decimalSep,
  required String groupSep,
  required bool autoDec,
  required int decDigits,
  bool unlimitedDecimals = false,
}) {
  final effectiveAutoDec = autoDec && !unlimitedDecimals;
  return [
    CalculatorNormalizer(
      overwriteDot: getOverwriteDotValue(),
      overwriteComma: getOverwriteCommaValue(),
      decimalSep: decimalSep,
      groupSep: groupSep,
    ),
    FilteringTextInputFormatter.deny(buildAmountAllowedRegex()),
    LeadingZeroIntegerTrimmerFormatter(
      decimalSep: decimalSep,
      groupSep: groupSep,
    ),
    if (effectiveAutoDec)
      AutoDecimalShiftFormatter(
        decimalDigits: decDigits,
        decimalSep: decimalSep,
        groupSep: groupSep,
      ),
    if (!effectiveAutoDec)
      GroupSeparatorFormatter(
        groupSep: groupSep,
        decimalSep: decimalSep,
      ),
    if (!effectiveAutoDec && !unlimitedDecimals)
      MaxDecimalDigitsFormatter(
        decimalDigits: decDigits,
        decimalSep: decimalSep,
      ),
  ];
}
