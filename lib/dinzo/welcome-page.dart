import 'dart:async';

import 'package:flutter/material.dart';
import 'package:aupp/services/service-config.dart';
import 'package:aupp/settings/constants/preferences-keys.dart';

/// How the app works and how it is meant to be used, on the first opening,
/// when it stays up for [readingSeconds]. Reopened freely from the settings.
class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key, this.mustRead = false});

  final bool mustRead;

  static const readingSeconds = 20;

  /// On this device, once: closing the app before the time shows it again.
  static Future<void> showOnFirstOpening(BuildContext context) async {
    final prefs = ServiceConfig.sharedPreferences;
    if (prefs == null || prefs.getBool(PreferencesKeys.welcomeSeen) == true) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const WelcomePage(mustRead: true),
      ),
    );
    await prefs.setBool(PreferencesKeys.welcomeSeen, true);
  }

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  late int _left = widget.mustRead ? WelcomePage.readingSeconds : 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (_left == 0) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() => _left--);
      if (_left == 0) timer.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static const _steps = [
    (
      Icons.sync,
      'Os lançamentos vêm sozinhos',
      'Conecte seus bancos pela Dinzo e só revise. Sem ela, você lança à mão.',
    ),
    (
      Icons.credit_card,
      'Compra entra inteira, no dia',
      'R\$ 1.200 em 12x são R\$ 1.200 hoje: esse dinheiro já está comprometido.',
    ),
    (
      Icons.account_balance,
      'Escolha os bancos do dia a dia',
      'O dinheiro deles é repartido nas carteiras, mesmo aplicado em RDB ou '
          'CDB. Reserva e caixinhas ficam aqui. O que está na corretora é '
          'investimento.',
    ),
    (
      Icons.account_balance_wallet,
      'Carteiras dizem para que serve',
      'Elas não são contas de banco. A Conta corrente é o que dá para gastar '
          'e nunca recebe rendimento.',
    ),
    (
      Icons.savings,
      'Separe antes de investir',
      'Transfira para a carteira Investir, envie para a corretora e registre '
          'o aporte. Os juros caem na Investir sozinhos.',
    ),
    (
      Icons.tune,
      'Olhe o Ajuste do mês',
      'Fica na Investir: são os juros e o que faltou lançar. Valor estranho, '
          'ou Investir negativa, pede uma conferida.',
    ),
    (
      Icons.pie_chart,
      'Siga o plano do mês',
      'A receita é o 100%, dividido em grupos no Orçamento. Em Carteira e '
          'aporte, você dá notas aos ativos e o app calcula o próximo aporte.',
    ),
    (
      Icons.edit_note,
      'Cripto e exterior são à mão',
      'Registre cada compra. A cotação de nenhum investimento mexe nas '
          'carteiras.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: _left == 0,
      child: Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                    children: [
                      Text('Bem-vindo', style: theme.textTheme.headlineMedium),
                      const SizedBox(height: 8),
                      Text(
                        'Este app segue o jeito que o autor gosta de cuidar do '
                        'dinheiro. Ele funciona melhor usado assim:',
                        style: theme.textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 16),
                      for (final (icon, title, text) in _steps)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(icon, color: theme.colorScheme.primary),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: theme.textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      text,
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: FilledButton(
                    onPressed: _left > 0 ? null : () => Navigator.pop(context),
                    child: Text(_left > 0 ? 'Começar ($_left)' : 'Começar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}
