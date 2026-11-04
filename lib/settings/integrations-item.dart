import 'package:flutter/material.dart';
import 'package:aupp/dinzo/dinzo-settings-page.dart';
import 'package:aupp/dinzo/dinzo-sync-service.dart';
import 'package:aupp/investments/brapi-api.dart';

import 'settings-item.dart';

/// The integrations in the settings. It blinks while a key is missing: without
/// them the app has no bank data or quotes.
class IntegrationsItem extends StatefulWidget {
  const IntegrationsItem({super.key});

  @override
  State<IntegrationsItem> createState() => _IntegrationsItemState();
}

class _IntegrationsItemState extends State<IntegrationsItem>
    with SingleTickerProviderStateMixin {
  late final _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
    lowerBound: 0.25,
  );

  bool get _missingKey =>
      DinzoSyncService.apiKey == null || BrapiApi.key == null;

  void _update() {
    if (_missingKey) {
      if (!_blink.isAnimating) _blink.repeat(reverse: true);
    } else {
      _blink.stop();
      _blink.value = 1;
    }
  }

  @override
  void initState() {
    super.initState();
    _update();
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _blink,
      child: SettingsItem(
        icon: const Icon(Icons.sync, color: Colors.white),
        iconBackgroundColor: Colors.teal.shade600,
        title: 'Integrações com API',
        subtitle: 'Dinzo e brapi.dev: chaves, categorias e importação',
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DinzoSettingsPage()),
          );
          if (mounted) setState(_update);
        },
      ),
    );
  }
}
