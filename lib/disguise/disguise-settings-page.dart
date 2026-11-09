import 'package:flutter/material.dart';
import 'package:aupp/demo/demo-mode.dart';
import 'package:aupp/disguise/calculator-gate.dart';
import 'package:aupp/services/service-config.dart';
import 'package:aupp/settings/constants/preferences-keys.dart';

/// Fork: Configurações → "Disfarce e demonstração". The calculator disguise
/// is optional (off on a fresh install); the demo can be opened from here
/// too, so it doesn't depend on the calculator.
class DisguiseSettingsPage extends StatefulWidget {
  const DisguiseSettingsPage({Key? key}) : super(key: key);

  @override
  State<DisguiseSettingsPage> createState() => _DisguiseSettingsPageState();
}

class _DisguiseSettingsPageState extends State<DisguiseSettingsPage> {
  bool _enabled = CalculatorGate.enabled;

  Future<void> _setEnabled(bool on) async {
    await ServiceConfig.sharedPreferences?.setBool(
      PreferencesKeys.disguiseEnabled,
      on,
    );
    CalculatorGate.settingChanged();
    setState(() => _enabled = on);
  }

  Future<void> _toggleDemo() async {
    final leaving = DemoMode.active;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(leaving ? 'Sair da demonstração?' : 'Abrir a demonstração?'),
        content: Text(
          leaving
              ? 'O app reinicia com os seus dados.'
              : 'O app reinicia com dados fictícios. Seus dados não são '
                    'tocados; para voltar, use "Sair da demonstração" ou feche '
                    'o app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(leaving ? 'Sair' : 'Abrir'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (leaving) {
      await DemoMode.leaveAndRestart();
    } else {
      await DemoMode.enterAndRestart();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Disfarce e demonstração')),
      body: ListView(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.calculate),
            title: const Text('Disfarce de calculadora'),
            subtitle: Text(
              'O app abre como uma calculadora. Digite ${CalculatorGate.code} '
              'e C para entrar; ${DemoMode.code} e C abre a demonstração. '
              'Vale a partir da próxima abertura.',
            ),
            value: _enabled,
            onChanged: _setEnabled,
          ),
          ListTile(
            leading: const Icon(Icons.slideshow),
            title: Text(
              DemoMode.active ? 'Sair da demonstração' : 'Modo demonstração',
            ),
            subtitle: const Text(
              'Dados fictícios para mostrar o app a alguém. Reinicia o app.',
            ),
            onTap: _toggleDemo,
          ),
        ],
      ),
    );
  }
}
