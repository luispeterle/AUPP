import 'dart:convert';
import 'dart:io';

import 'package:aupp/demo/demo-mode.dart';
import 'package:aupp/services/logger.dart';

/// One sync, as written to the history file.
class DinzoSyncLogEntry {
  final DateTime at;

  /// "auto" (on app open) or "manual" (sync screen).
  final String trigger;

  /// "rápido" or "completo".
  final String mode;

  /// What happened: "aplicado", "revisar" (auto sync left it to the user)
  /// or "erro".
  final String outcome;
  final String summary;
  final List<String> warnings;

  /// One line per record touched: "+ novo", "~ atualizado", "− removido".
  final List<String> items;

  DinzoSyncLogEntry({
    required this.at,
    required this.trigger,
    required this.mode,
    required this.outcome,
    required this.summary,
    this.warnings = const [],
    this.items = const [],
  });

  Map<String, dynamic> toJson() => {
    'at': at.toIso8601String(),
    'trigger': trigger,
    'mode': mode,
    'outcome': outcome,
    'summary': summary,
    if (warnings.isNotEmpty) 'warnings': warnings,
    if (items.isNotEmpty) 'items': items,
  };

  factory DinzoSyncLogEntry.fromJson(Map<String, dynamic> json) =>
      DinzoSyncLogEntry(
        at: DateTime.parse(json['at'] as String),
        trigger: json['trigger'] as String? ?? '',
        mode: json['mode'] as String? ?? '',
        outcome: json['outcome'] as String? ?? '',
        summary: json['summary'] as String? ?? '',
        warnings: (json['warnings'] as List?)?.cast<String>() ?? const [],
        items: (json['items'] as List?)?.cast<String>() ?? const [],
      );
}

/// History of Dinzo syncs in a JSON-lines file that survives restarts
/// (the in-app Talker log is memory only), so a wrong import can be traced
/// back. Lives outside the backup.
class DinzoSyncLog {
  static final _logger = Logger.withClass(DinzoSyncLog);

  /// Oldest entries are dropped beyond this size.
  static const int maxBytes = 2 * 1024 * 1024;

  static Future<File> _file() async => File(
    '${(await DemoMode.supportDirectory()).path}/dinzo_sync_log.jsonl',
  );

  static Future<void> add(DinzoSyncLogEntry entry) async {
    _logger.info(
      'Sync ${entry.trigger}/${entry.mode} ${entry.outcome}: ${entry.summary}',
    );
    for (final w in entry.warnings) {
      _logger.warning(w);
    }
    for (final item in entry.items) {
      _logger.info(item);
    }
    try {
      final file = await _file();
      await file.writeAsString(
        '${jsonEncode(entry.toJson())}\n',
        mode: FileMode.append,
        flush: true,
      );
      if (await file.length() > maxBytes) {
        final lines = await file.readAsLines();
        final kept = <String>[];
        var size = 0;
        for (final line in lines.reversed) {
          size += line.length + 1;
          if (size > maxBytes ~/ 2) break;
          kept.add(line);
        }
        await file.writeAsString('${kept.reversed.join('\n')}\n', flush: true);
      }
    } catch (e, st) {
      _logger.handle(e, st, 'Could not write the sync history');
    }
  }

  /// Newest first.
  static Future<List<DinzoSyncLogEntry>> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return [];
      final entries = <DinzoSyncLogEntry>[];
      for (final line in await file.readAsLines()) {
        if (line.trim().isEmpty) continue;
        try {
          entries.add(
            DinzoSyncLogEntry.fromJson(
              jsonDecode(line) as Map<String, dynamic>,
            ),
          );
        } catch (_) {
          // A torn line from a crash mid-write: skip it.
        }
      }
      return entries.reversed.toList();
    } catch (e, st) {
      _logger.handle(e, st, 'Could not read the sync history');
      return [];
    }
  }

  static Future<String> rawText() async {
    final file = await _file();
    return await file.exists() ? file.readAsString() : '';
  }
}
