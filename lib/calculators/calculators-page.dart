import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// A calculator of the Investidor Sardinha site, opened in the browser.
class Calculator {
  final String name;
  final IconData icon;
  final Color color;
  final String path;

  const Calculator(this.name, this.icon, this.color, this.path);

  Uri get uri =>
      Uri.parse('https://investidorsardinha.r7.com/calculadoras/$path');
}

/// Launcher of the Investidor Sardinha calculators, laid out like an Android home screen: a 3×3 grid of app
/// icons.
class CalculatorsPage extends StatelessWidget {
  const CalculatorsPage({super.key, this.onOpen});

  /// On the computer the sites open inside the app, in [CalculatorsArea].
  final void Function(Calculator)? onOpen;

  // Icons are the ones the site itself uses for each calculator.
  static const calculators = [
    Calculator('Juros compostos', Icons.calculate, Color(0xFF1E88E5),
        'calculadora-de-juros-compostos/'),
    Calculator('Viver de renda', Icons.price_change, Color(0xFF43A047),
        'calculadora-de-renda/'),
    Calculator('À vista ou parcelado', Icons.account_balance_wallet,
        Color(0xFFFB8C00), 'vista-prazo'),
    Calculator('Alugar x financiar', Icons.home_work, Color(0xFF8E24AA),
        'calculadora-alugar-x-financiar/'),
    Calculator('CLT x PJ', Icons.difference, Color(0xFF6D4C41),
        'calculadora-comparativa/'),
    Calculator('Calculadora PJ', Icons.business, Color(0xFF3949AB),
        'calculadora-pj/'),
    Calculator('Renda fixa', Icons.bar_chart, Color(0xFF00897B),
        'comparador-de-renda-fixa/'),
    Calculator('Reserva de emergência', Icons.savings, Color(0xFFE53935),
        'reserva-emergencia'),
    Calculator('Primeiro milhão', Icons.filter_1, Color(0xFFFDD835),
        'primeiro-milhao/'),
  ];

  Future<void> _open(BuildContext context, Calculator c) async {
    var ok = false;
    try {
      ok = await launchUrl(c.uri, mode: LaunchMode.inAppBrowserView);
    } catch (_) {}
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível abrir "${c.name}".')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: onOpen != null ? null : AppBar(title: const Text('Calculadoras')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.82,
              children: [
                for (final c in calculators)
                  _AppIcon(calculator: c, onTap: () => onOpen != null ? onOpen!(c) : _open(context, c)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AppIcon extends StatelessWidget {
  final Calculator calculator;
  final VoidCallback onTap;

  const _AppIcon({required this.calculator, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = calculator;
    final onColor =
        ThemeData.estimateBrightnessForColor(c.color) == Brightness.dark
            ? Colors.white
            : Colors.black87;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: c.color,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(
                    blurRadius: 6,
                    offset: Offset(0, 2),
                    color: Color(0x33000000),
                  ),
                ],
              ),
              child: Icon(c.icon, color: onColor, size: 32),
            ),
            const SizedBox(height: 8),
            Text(
              c.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
