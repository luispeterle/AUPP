import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'dinzo-sync-log.dart';

/// Every Dinzo sync (automatic or manual) with what it imported, updated or
/// removed, newest first, to trace a wrong import back.
class DinzoSyncHistoryPage extends StatefulWidget {
  const DinzoSyncHistoryPage({Key? key}) : super(key: key);

  @override
  State<DinzoSyncHistoryPage> createState() => _DinzoSyncHistoryPageState();
}

class _DinzoSyncHistoryPageState extends State<DinzoSyncHistoryPage> {
  List<DinzoSyncLogEntry>? _entries;

  @override
  void initState() {
    super.initState();
    DinzoSyncLog.read().then((e) {
      if (mounted) setState(() => _entries = e);
    });
  }

  Future<void> _copy() async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: await DinzoSyncLog.rawText()));
    messenger.showSnackBar(
      const SnackBar(content: Text('Histórico copiado (JSON por linha)')),
    );
  }

  static const _icons = {
    'aplicado': (Icons.check_circle, Colors.green),
    'revisar': (Icons.rule, Colors.orange),
    'erro': (Icons.error, Colors.red),
  };

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    final format = DateFormat('dd/MM HH:mm');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Histórico de sincronizações'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copiar tudo',
            onPressed: entries == null || entries.isEmpty ? null : _copy,
          ),
        ],
      ),
      body: entries == null
          ? const Center(child: CircularProgressIndicator())
          : entries.isEmpty
          ? const Center(child: Text('Nenhuma sincronização registrada.'))
          : ListView.builder(
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final e = entries[index];
                final (icon, color) =
                    _icons[e.outcome] ?? (Icons.sync, Colors.grey);
                final details = [...e.warnings.map((w) => '⚠️ $w'), ...e.items];
                final header = Text(
                  '${format.format(e.at)} · ${e.trigger} · ${e.mode}',
                  style: Theme.of(context).textTheme.labelMedium,
                );
                if (details.isEmpty) {
                  return ListTile(
                    leading: Icon(icon, color: color),
                    title: header,
                    subtitle: Text(e.summary),
                  );
                }
                return ExpansionTile(
                  leading: Icon(icon, color: color),
                  title: header,
                  subtitle: Text(e.summary),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in details)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: SelectableText(
                          line,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }
}
