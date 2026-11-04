import 'package:flutter/material.dart';
import 'package:aupp/helpers/amount-input-utils.dart';
import 'package:aupp/helpers/records-utility-functions.dart';

/// A text field for amounts, with math-aware formatters.
class AmountInputField extends StatefulWidget {
  const AmountInputField({
    super.key,
    required this.controller,
    this.labelText,
    this.suffixText,
    this.enabled = true,
    this.allowNegative = false,
    this.validator,
    this.onChanged,
    this.autofocus = false,
    this.autovalidateMode = AutovalidateMode.disabled,
    this.decimalDigits,
    this.unlimitedDecimals = false,
  });

  final TextEditingController controller;
  final String? labelText;
  final String? suffixText;
  final bool enabled;

  /// Allow negative values: accepts a leading minus.
  final bool allowNegative;

  /// Override the default validator. The default rejects empty input and
  /// values that cannot be parsed as locale-aware currency strings.
  final FormFieldValidator<String>? validator;

  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final AutovalidateMode autovalidateMode;

  /// Overrides the global [getNumberDecimalDigits] when non-null.
  /// Ignored when [unlimitedDecimals] is true.
  final int? decimalDigits;

  /// When true, no cap is placed on the number of decimal digits the user
  /// can type. Used for fields like the currency conversion ratio, where
  /// truncating precision would defeat the purpose of the field.
  final bool unlimitedDecimals;

  @override
  State<AmountInputField> createState() => _AmountInputFieldState();
}

class _AmountInputFieldState extends State<AmountInputField> {
  int get _resolvedDecimalDigits =>
      widget.decimalDigits ?? getNumberDecimalDigits();

  String? _defaultValidator(String? value) {
    if (value == null || value.isEmpty) return 'Por favor, insira um valor';
    final parsed = widget.allowNegative
        ? tryParseSignedCurrencyString(value)
        : tryParseCurrencyString(value);
    if (parsed == null) {
      return amountFormatErrorMessage(
        decimalDigits: widget.unlimitedDecimals ? null : _resolvedDecimalDigits,
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final validator = widget.validator ?? _defaultValidator;
    final decDigits = _resolvedDecimalDigits;
    // Non-breaking space so the number and currency never wrap apart.
    final suffixText = widget.suffixText == null
        ? null
        : '\u00A0${widget.suffixText}';

    return TextFormField(
      controller: widget.controller,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      autovalidateMode: widget.autovalidateMode,
      inputFormatters: buildAmountInputFormatters(
        decimalSep: getDecimalSeparator(),
        groupSep: getGroupingSeparator(),
        autoDec: getAmountInputAutoDecimalShift(),
        decDigits: decDigits,
        unlimitedDecimals: widget.unlimitedDecimals,
      ),
      validator: validator,
      onChanged: widget.onChanged,
      textAlign: TextAlign.end,
      style: TextStyle(
        fontSize: 32.0,
        color: widget.enabled
            ? Theme.of(context).colorScheme.onSurface
            : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38),
      ),
      keyboardType: getAmountInputKeyboardType(signed: widget.allowNegative),
      decoration: InputDecoration(
        floatingLabelBehavior: FloatingLabelBehavior.always,
        labelText: widget.labelText,
        hintText:
            widget.unlimitedDecimals ? '0' : buildZeroAmountText(decimalDigits: decDigits),
        suffixText: suffixText,
      ),
    );
  }
}
