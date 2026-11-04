import 'package:flutter/material.dart';
import 'package:aupp/services/database/change-log.dart';
import 'package:aupp/services/database/sqlite-database.dart';

/// What was changed by hand, on any device, newest first.
class ChangeLogPage extends StatefulWidget {
  const ChangeLogPage({super.key});

  @override
  State<ChangeLogPage> createState() => _ChangeLogPageState();
}

class _ChangeLogPageState extends State<ChangeLogPage> {
  List<ChangeLogEntry>? _entries;

  static const _targets = {
    'records': 'Lançamento',
    'wallets': 'Carteira',
    'categories': 'Categoria',
    'recurrent_record_patterns': 'Recorrência',
    'profiles': 'Perfil',
    'tags': 'Tag',
  };

  static const _fields = {
    'value': 'Valor',
    'transfer_value': 'Valor recebido',
    'title': 'Título',
    'description': 'Descrição',
    'datetime': 'Data',
    'category_name': 'Categoria',
    'wallet_id': 'Carteira',
    'transfer_wallet_id': 'Carteira de destino',
    'tags': 'Tags',
    'name': 'Nome',
    'initial_amount': 'Saldo inicial',
    'is_archived': 'Arquivada',
  };

  static const _amounts = {'value', 'transfer_value', 'initial_amount'};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await SqliteDatabase.instance.database;
    final entries = db == null ? <ChangeLogEntry>[] : await ChangeLog.read(db);
    if (mounted) setState(() => _entries = entries);
  }

  String _show(String field, Object? value) {
    if (value == null) return '—';
    if (_amounts.contains(field)) {
      if (value is num) return value.toStringAsFixed(2);
    }
    if (field == 'datetime' && value is int) {
      final at = DateTime.fromMillisecondsSinceEpoch(value);
      return '${at.day.toString().padLeft(2, '0')}/'
          '${at.month.toString().padLeft(2, '0')}/${at.year}';
    }
    return '$value';
  }

  String _clock(DateTime at) =>
      '${at.day.toString().padLeft(2, '0')}/'
      '${at.month.toString().padLeft(2, '0')}/${at.year} '
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';

  /// "Valor: -8000.00 → -12000.00", one line per field.
  List<String> _details(ChangeLogEntry entry) {
    final before = entry.before ?? const {};
    final after = entry.after ?? const {};
    final both = entry.before != null && entry.after != null;
    return [
      for (final field in {...before.keys, ...after.keys})
        if (both || _fields.containsKey(field))
          '${_fields[field] ?? field}: '
              '${both ? '${_show(field, before[field])} → ${_show(field, after[field])}' : _show(field, entry.before == null ? after[field] : before[field])}',
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = _entries;
    return Scaffold(
      appBar: AppBar(title: const Text('Histórico de alterações')),
      body: entries == null
          ? const Center(child: CircularProgressIndicator())
          : entries.isEmpty
          ? const Center(child: Text('Nenhuma alteração ainda.'))
          : ListView.separated(
              itemCount: entries.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final entry = entries[index];
                final target = _targets[entry.target];
                return ListTile(
                  title: Text(
                    '${entry.action}${target == null ? '' : ' · $target'}: '
                    '${entry.title}',
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final line in _details(entry)) Text(line),
                      Text(
                        '${_clock(entry.at)} · ${entry.device}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
