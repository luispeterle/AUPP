import 'dart:convert';
import 'dart:io';

import 'package:aupp/services/automatic-writes.dart';
import 'package:aupp/services/logger.dart';
import 'package:sqflite/sqflite.dart';

/// One change made by hand, or a sync decision by the user.
class ChangeLogEntry {
  final DateTime at;
  final String device;

  /// "Criou", "Editou", "Excluiu" or "Sincronização".
  final String action;

  /// The table the change was in. Empty for a sync decision.
  final String target;
  final String title;

  /// Only the fields that changed; each side is null when the row did not
  /// exist on it.
  final Map<String, dynamic>? before;
  final Map<String, dynamic>? after;

  const ChangeLogEntry({
    required this.at,
    required this.device,
    required this.action,
    required this.target,
    required this.title,
    this.before,
    this.after,
  });

  factory ChangeLogEntry.fromMap(Map<String, Object?> row) => ChangeLogEntry(
    at: DateTime.fromMillisecondsSinceEpoch(row['at'] as int),
    device: row['device'] as String,
    action: row['action'] as String,
    target: row['target'] as String,
    title: row['title'] as String,
    before: _decode(row['before_values']),
    after: _decode(row['after_values']),
  );

  static Map<String, dynamic>? _decode(Object? text) =>
      text == null ? null : jsonDecode(text as String) as Map<String, dynamic>;
}

/// What a change that the app did not make by itself looked like, kept in the
/// database so that it follows the data to the other devices.
/// "By itself" is [AutomaticWrites], the same line the sync draws.
class ChangeLog {
  static final _logger = Logger.withClass(ChangeLog);

  static const table = 'change_log';
  static const createTable =
      'CREATE TABLE IF NOT EXISTS $table ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, at INTEGER NOT NULL, '
      'device TEXT NOT NULL, action TEXT NOT NULL, target TEXT NOT NULL, '
      'title TEXT NOT NULL, before_values TEXT, after_values TEXT)';

  /// An entry goes after a year, but the latest ones always stay: an app left
  /// unused for a long time still has them.
  static const maxAgeDays = 365;
  static const keepAtLeast = 500;

  /// Beyond this, a change in many rows at once is logged as a count.
  static const _maxDetailedRows = 20;

  /// Too big, and rebuilt by every sync: never useful to compare.
  static const _ignored = {'_rowid', 'dinzo_snapshot'};

  static String get device =>
      Platform.isAndroid ? 'Celular' : 'Computador (${Platform.localHostname})';

  /// Reads the rows a write is about to touch. Null for what the app does by
  /// itself. A failure here never stops the write.
  static Future<ChangeLogSnapshot?> before(
    Database db,
    String target,
    String where,
    List<Object?> args,
  ) async {
    if (AutomaticWrites.active) return null;
    try {
      return ChangeLogSnapshot._(
        target,
        await _rows(db, target, where, args),
      );
    } catch (e, st) {
      _logger.handle(e, st, 'Could not read $target for the change log');
      return null;
    }
  }

  /// A row just created, known by its id.
  static Future<void> created(
    Database db,
    String target,
    String where,
    List<Object?> args,
  ) async {
    if (AutomaticWrites.active) return;
    try {
      for (final row in await _rows(db, target, where, args)) {
        await _insert(db, 'Criou', target, _titleOf(row), null, _clean(row));
      }
    } catch (e, st) {
      _logger.handle(e, st, 'Could not log a new row in $target');
    }
  }

  /// [count] rows created at once, like an import.
  static Future<void> createdMany(Database db, String target, int count) async {
    if (AutomaticWrites.active || count == 0) return;
    try {
      await _insert(db, 'Criou', target, '$count itens', null, null);
    } catch (e, st) {
      _logger.handle(e, st, 'Could not log new rows in $target');
    }
  }

  /// A tag has no row of its own to compare.
  static Future<void> tagChanged(Database db, String action, String title) async {
    if (AutomaticWrites.active) return;
    try {
      await _insert(db, action, 'tags', title, null, null);
    } catch (e, st) {
      _logger.handle(e, st, 'Could not log a tag change');
    }
  }

  /// A sync decision: it counts even though the swap itself is automatic.
  static Future<void> syncDecision(Database db, String what) async {
    try {
      await _insert(db, 'Sincronização', '', what, null, null);
    } catch (e, st) {
      _logger.handle(e, st, 'Could not log a sync decision');
    }
  }

  static Future<List<Map<String, Object?>>> _rows(
    Database db,
    String target,
    String where,
    List<Object?> args,
  ) {
    final tags = target == 'records'
        ? ", (SELECT group_concat(tag_name, ', ') FROM records_tags "
              "WHERE record_id = records.id) AS tags"
        : '';
    return db.rawQuery(
      'SELECT rowid AS _rowid, *$tags FROM $target WHERE $where',
      args,
    );
  }

  static Map<String, Object?> _clean(Map<String, Object?> row) => {
    for (final entry in row.entries)
      if (!_ignored.contains(entry.key) && entry.value != null)
        entry.key: entry.value,
  };

  static String _titleOf(Map<String, Object?> row) {
    for (final key in ['title', 'name', 'category_name', 'id']) {
      final value = row[key];
      if (value != null && '$value'.isNotEmpty) return '$value';
    }
    return '';
  }

  static Future<void> _insert(
    Database db,
    String action,
    String target,
    String title,
    Map<String, Object?>? before,
    Map<String, Object?>? after,
  ) => db.insert(table, {
    'at': DateTime.now().millisecondsSinceEpoch,
    'device': device,
    'action': action,
    'target': target,
    'title': title,
    'before_values': before == null ? null : jsonEncode(before),
    'after_values': after == null ? null : jsonEncode(after),
  });

  /// Newest first. Empty when the table is not there yet (a read-only database
  /// from before it existed).
  static Future<List<ChangeLogEntry>> read(Database db, {int? limit}) async {
    try {
      final rows = await db.query(table, orderBy: 'id DESC', limit: limit);
      return rows.map(ChangeLogEntry.fromMap).toList();
    } catch (e, st) {
      _logger.handle(e, st, 'Could not read the change log');
      return const [];
    }
  }

  /// Called when the database opens.
  static Future<void> prune(Database db, {DateTime? now}) async {
    final limit = (now ?? DateTime.now())
        .subtract(const Duration(days: maxAgeDays))
        .millisecondsSinceEpoch;
    await db.delete(
      table,
      where:
          'at < ? AND id NOT IN '
          '(SELECT id FROM $table ORDER BY id DESC LIMIT ?)',
      whereArgs: [limit, keepAtLeast],
    );
  }
}

/// The rows before a write; [commit] compares them with how they ended up.
class ChangeLogSnapshot {
  final String _target;
  final List<Map<String, Object?>> _rows;

  ChangeLogSnapshot._(this._target, this._rows);

  Future<void> commit(Database db) async {
    if (_rows.isEmpty) return;
    try {
      final ids = _rows.map((row) => row['_rowid']).toList();
      final marks = List.filled(ids.length, '?').join(',');
      final now = {
        for (final row in await ChangeLog._rows(
          db,
          _target,
          'rowid IN ($marks)',
          ids,
        ))
          row['_rowid']: row,
      };
      final changes = <_Change>[];
      for (final row in _rows) {
        final after = now[row['_rowid']];
        if (after == null) {
          changes.add(_Change('Excluiu', ChangeLog._titleOf(row), row, null));
          continue;
        }
        final old = ChangeLog._clean(row);
        final current = ChangeLog._clean(after);
        final keys = {...old.keys, ...current.keys}.where(
          (key) => old[key] != current[key],
        );
        if (keys.isEmpty) continue;
        changes.add(
          _Change(
            'Editou',
            ChangeLog._titleOf(after),
            {for (final key in keys) key: old[key]},
            {for (final key in keys) key: current[key]},
          ),
        );
      }
      if (changes.length > ChangeLog._maxDetailedRows) {
        await ChangeLog._insert(
          db,
          changes.first.action,
          _target,
          '${changes.length} itens',
          null,
          null,
        );
        return;
      }
      for (final change in changes) {
        await ChangeLog._insert(
          db,
          change.action,
          _target,
          change.title,
          change.action == 'Excluiu'
              ? ChangeLog._clean(change.before!)
              : change.before,
          change.after,
        );
      }
    } catch (e, st) {
      ChangeLog._logger.handle(e, st, 'Could not log a change in $_target');
    }
  }
}

class _Change {
  final String action;
  final String title;
  final Map<String, Object?>? before;
  final Map<String, Object?>? after;

  const _Change(this.action, this.title, this.before, this.after);
}
