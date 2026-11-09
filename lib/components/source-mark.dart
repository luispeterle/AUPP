import 'package:flutter/material.dart';

/// Where a figure comes from when it is not an official source (the B3, the
/// CVM, the SEC, the Banco Central).
abstract final class Unofficial {
  static const brapi =
      'brapi.dev: repassa cotações da B3 com atraso; não é a fonte oficial.';
  static const brapiPrice =
      'Usa o preço da brapi.dev, que repassa as cotações da B3 com atraso; o '
      'resto da conta vem da fonte oficial.';
  static const yahoo =
      'Yahoo Finance: histórico de preços sem API oficial nem garantia.';
  static const coingecko =
      'CoinGecko: média de várias corretoras; cripto não tem fonte oficial.';
}

/// A small "!" beside a figure that does not come from an official source;
/// its tooltip says where it came from. On hover on the computer, on a tap on
/// the phone.
class SourceMark extends StatelessWidget {
  const SourceMark(this.source, {super.key, this.size = 13});

  final String source;
  final double size;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Fonte não oficial\n$source',
    triggerMode: TooltipTriggerMode.tap,
    showDuration: const Duration(seconds: 8),
    waitDuration: const Duration(milliseconds: 200),
    constraints: const BoxConstraints(maxWidth: 360),
    padding: const EdgeInsets.all(10),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Icon(
        Icons.error_outline,
        size: size,
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFFE5A50A)
            : const Color(0xFFB7791F),
      ),
    ),
  );
}
