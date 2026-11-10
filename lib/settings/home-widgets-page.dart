import 'dart:async';

import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:aupp/services/home-widget-service.dart';
import 'package:aupp/services/logger.dart';

/// Settings > Home screen widgets: pin widgets.
class HomeWidgetsPage extends StatefulWidget {
  const HomeWidgetsPage({super.key});

  @override
  HomeWidgetsPageState createState() => HomeWidgetsPageState();
}

class HomeWidgetsPageState extends State<HomeWidgetsPage> {
  static final _logger = Logger.withClass(HomeWidgetsPage);
  bool _pinSupported = false;
  bool _refreshing = false;
  Timer? _postPinRefresh;

  @override
  void dispose() {
    _postPinRefresh?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    bool pinSupported = false;
    try {
      pinSupported = await HomeWidget.isRequestPinWidgetSupported() ?? false;
    } catch (e, st) {
      _logger.handle(e, st, 'Failed to check pin support');
    }
    if (!mounted) return;
    setState(() {
      _pinSupported = pinSupported;
    });
  }

  Future<void> _pin(String qualifiedName) async {
    try {
      await HomeWidget.requestPinWidget(qualifiedAndroidName: qualifiedName);
    } catch (e, st) {
      _logger.handle(e, st, 'Failed to request widget pin');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível adicionar o widget')),
        );
      }
    }
    await _load();
    // The system draws the placeholder until the first update lands;
    // render immediately so a just-pinned widget fills in within seconds.
    await HomeWidgetService.refreshAll();
    // The OS may not have registered the new widget instance yet, so the
    // first refresh above can miss it (the widget would stay empty until
    // the next refresh). Re-run shortly after to catch it.
    _postPinRefresh?.cancel();
    _postPinRefresh = Timer(const Duration(milliseconds: 900), () async {
      if (!mounted) return;
      await HomeWidgetService.refreshAll();
      await _load();
    });
  }

  Future<void> _refreshNow() async {
    setState(() => _refreshing = true);
    await HomeWidgetService.refreshAll();
    await _load();
    if (mounted) setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Widgets da tela inicial')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Fixe widgets que mostram seus totais. Eles seguem o intervalo de tempo da página inicial e são atualizados ao abrir o app.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (_pinSupported) ...[
            _PinRow(
              title: 'Visão geral',
              onPin: () => _pin(HomeWidgetService.overviewProvider),
            ),
            _PinRow(
              title: 'Rendas',
              onPin: () => _pin(HomeWidgetService.incomeProvider),
            ),
            _PinRow(
              title: 'Despesas',
              onPin: () => _pin(HomeWidgetService.expensesProvider),
            ),
            _PinRow(
              title: 'Saldo',
              onPin: () => _pin(HomeWidgetService.balanceProvider),
            ),
            // Looks like a plain calendar; the colored days are the
            // ones something is due (HomeWidgetService.saveDueDays).
            _PinRow(
              title: 'Calendário de vencimentos',
              onPin: () => _pin(HomeWidgetService.calendarProvider),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                'Adicione widgets pelo seletor de widgets do seu launcher.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: _refreshing ? null : _refreshNow,
              icon: _refreshing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: Text('Atualizar widgets'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PinRow extends StatelessWidget {
  final String title;
  final VoidCallback onPin;

  const _PinRow({required this.title, required this.onPin});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      trailing: IconButton(
        icon: const Icon(Icons.add_to_home_screen),
        tooltip: 'Adicionar à tela inicial',
        onPressed: onPin,
      ),
    );
  }
}
