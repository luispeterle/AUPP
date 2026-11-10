import 'dart:convert';

import 'package:sqflite/sqflite.dart';

/// Joins another device's data into this one's, row by row, against the last
/// data both had ([base]). Only what the other device changed since then is
/// applied; what changed here stays. Nothing changed on one side is ever lost
/// because the other side did not touch it:
/// - changed on one side only: that side's version;
/// - changed on both: field by field, and a field changed on both to different
///   values goes to the most recent edit ([remoteWins]), reported;
/// - deleted on one side and edited on the other: the edit stays, reported;
/// - created on both: kept apart (a new id here when they collide), except the
///   same row created by the app on each device (a Dinzo transaction, a
///   recurring occurrence), which becomes one.

/// What a merge did.
class MergeReport {
  /// Rows changed in this device's data.
  int applied = 0;

  /// What could not join both sides, in words, for the change log.
  final List<String> conflicts = [];

  bool get changed => applied > 0;
}

class _Table {
  final String name;

  /// Primary key columns.
  final List<String> key;

  /// The key is an INTEGER `id` that each device numbers on its own.
  final bool autoId;

  /// Kept up by the database itself (triggers): never compared nor copied.
  final Set<String> derived;

  /// How a field changed on both sides is decided, instead of the most recent
  /// edit.
  final Map<String, Object? Function(Object? local, Object? remote)> resolve;

  /// Identity of a row the app creates on each device by itself.
  final String? Function(Map<String, Object?> row)? natural;

  /// Columns elsewhere holding this table's id.
  final List<(String, String)> references;
  final String titleColumn;

  const _Table(
    this.name, {
    required this.key,
    this.autoId = false,
    this.derived = const {},
    this.resolve = const {},
    this.natural,
    this.references = const [],
    this.titleColumn = 'name',
  });
}

/// The record's tags, as one more field of it.
const _tagsColumn = '_tags';

Object? _later(Object? a, Object? b) {
  if (a is num && b is num) return a >= b ? a : b;
  return a ?? b;
}

String? _recordIdentity(Map<String, Object?> row) {
  final dinzo = row['dinzo_id'];
  if (dinzo != null) return 'dinzo:$dinzo';
  final recurrence = row['recurrence_id'];
  if (recurrence != null) return 'rec:$recurrence:${row['datetime']}';
  return null;
}

/// In this order: what is referenced comes before what references it.
const _tables = [
  _Table(
    'wallets',
    key: ['id'],
    autoId: true,
    natural: _walletIdentity,
    references: [
      ('records', 'wallet_id'),
      ('records', 'transfer_wallet_id'),
      ('recurrent_record_patterns', 'wallet_id'),
      ('recurrent_record_patterns', 'transfer_wallet_id'),
    ],
  ),
  _Table(
    'categories',
    key: ['name', 'category_type'],
    derived: {'last_used', 'record_count'},
  ),
  _Table(
    'recurrent_record_patterns',
    key: ['id'],
    // What each device already generated: the later one, so that neither
    // generates again what arrived from the other.
    resolve: {'last_update': _later},
    titleColumn: 'title',
  ),
  _Table(
    'records',
    key: ['id'],
    autoId: true,
    natural: _recordIdentity,
    references: [('records_tags', 'record_id')],
    titleColumn: 'title',
  ),
  _Table('fork_tags', key: ['name']),
];

String? _walletIdentity(Map<String, Object?> row) =>
    '${row['name']}|${row['kind']}';

/// Tables with no rows of their own to join.
const _skipped = {
  'sqlite_sequence',
  'android_metadata',
  'records_tags',
  'change_log',
};

/// Joins [remote] into [local] in one transaction. [base], [local] and
/// [remote] must have the same schema.
Future<MergeReport> mergeDatabases({
  required Database local,
  required DatabaseExecutor base,
  required DatabaseExecutor remote,
  required bool remoteWins,
}) async {
  final report = MergeReport();
  final tables = [..._tables];
  final known = {for (final t in tables) t.name, ..._skipped};
  // A table this code does not know yet (a newer schema adds one): by its key.
  for (final row in await local.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' "
    "AND name NOT LIKE 'sqlite_%'",
  )) {
    final name = row['name'] as String;
    if (known.contains(name)) continue;
    final info = await local.rawQuery('PRAGMA table_info("$name")');
    final key = [
      for (final column in info.where((c) => (c['pk'] as int) > 0))
        column['name'] as String,
    ];
    if (key.isNotEmpty) tables.add(_Table(name, key: key));
  }
  await local.transaction((tx) async {
    for (final table in tables) {
      await _mergeTable(tx, table, base, remote, remoteWins, report);
    }
    await _mergeChangeLog(tx, base, remote, report);
    await _repairReferences(tx, base, remote, report);
    // A row moved to a new id does not raise the counter by itself.
    for (final table in tables.where((t) => t.autoId)) {
      await tx.rawUpdate(
        'UPDATE sqlite_sequence SET seq = (SELECT MAX(id) FROM ${table.name}) '
        'WHERE name = ? AND seq < (SELECT MAX(id) FROM ${table.name})',
        [table.name],
      );
    }
  });
  return report;
}

Future<Map<String, Map<String, Object?>>> _rows(
  DatabaseExecutor db,
  _Table table,
) async {
  final rows = await db.query(table.name);
  final tags = <Object?, List<String>>{};
  if (table.name == 'records') {
    for (final tag in await db.query('records_tags')) {
      tags.putIfAbsent(tag['record_id'], () => []).add(tag['tag_name'] as String);
    }
  }
  return {
    for (final row in rows)
      _keyOf(table, row): {
        for (final e in row.entries)
          if (!table.derived.contains(e.key)) e.key: e.value,
        if (table.name == 'records')
          _tagsColumn: ((tags[row['id']] ?? [])..sort()).join('\u0001'),
      },
  };
}

String _keyOf(_Table table, Map<String, Object?> row) => table.key.length == 1
    ? '${row[table.key.first]}'
    : jsonEncode([for (final k in table.key) row[k]]);

bool _sameRow(Map<String, Object?>? a, Map<String, Object?>? b) {
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (!b.containsKey(e.key) || b[e.key] != e.value) return false;
  }
  return true;
}

/// Content apart from the id: the same row created on both devices.
String _content(Map<String, Object?> row) => jsonEncode([
  for (final e in row.entries)
    if (e.key != 'id') [e.key, e.value],
]);

Future<void> _mergeTable(
  Transaction tx,
  _Table table,
  DatabaseExecutor base,
  DatabaseExecutor remote,
  bool remoteWins,
  MergeReport report,
) async {
  final b = await _rows(base, table);
  final r = await _rows(remote, table);
  if (table.autoId) await _alignIds(tx, table, b, r);
  final l = await _rows(tx, table);
  for (final key in {...b.keys, ...r.keys}) {
    final baseRow = b[key], remoteRow = r[key], localRow = l[key];
    if (_sameRow(remoteRow, baseRow)) continue;
    if (_sameRow(localRow, baseRow)) {
      await _put(tx, table, localRow, remoteRow);
      report.applied++;
      continue;
    }
    if (_sameRow(localRow, remoteRow)) continue;
    if (remoteRow == null) {
      report.conflicts.add(
        '${_title(table, localRow!)}: excluído no outro aparelho e alterado '
        'aqui, ficou',
      );
      continue;
    }
    if (localRow == null) {
      await _put(tx, table, null, remoteRow);
      report.applied++;
      report.conflicts.add(
        '${_title(table, remoteRow)}: excluído aqui e alterado no outro '
        'aparelho, voltou',
      );
      continue;
    }
    final merged = Map.of(localRow);
    final clashes = <String>[];
    for (final column in remoteRow.keys) {
      final was = baseRow?[column];
      final mine = localRow[column], theirs = remoteRow[column];
      if (theirs == was || mine == theirs) continue;
      if (mine == was) {
        merged[column] = theirs;
        continue;
      }
      final resolve = table.resolve[column];
      if (resolve != null) {
        merged[column] = resolve(mine, theirs);
        continue;
      }
      if (remoteWins) merged[column] = theirs;
      clashes.add(column == _tagsColumn ? 'tags' : column);
    }
    if (!_sameRow(merged, localRow)) {
      await _put(tx, table, localRow, merged);
      report.applied++;
    }
    if (clashes.isNotEmpty) {
      report.conflicts.add(
        '${_title(table, merged)}: ${clashes.join(', ')} mudou nos dois, '
        'ficou o ${remoteWins ? 'do outro aparelho' : 'daqui'}',
      );
    }
  }
}

String _title(_Table table, Map<String, Object?> row) {
  final title = row[table.titleColumn];
  return title is String && title.isNotEmpty
      ? '"$title"'
      : '${table.name} ${_keyOf(table, row)}';
}

/// Rows created here since [base] whose id the other device also used: the
/// same row created by the app on both takes the other's id; a different one
/// moves to a new id. Afterwards the ids that both know mean the same row.
Future<void> _alignIds(
  Transaction tx,
  _Table table,
  Map<String, Map<String, Object?>> b,
  Map<String, Map<String, Object?>> r,
) async {
  final l = await _rows(tx, table);
  final createdHere = {
    for (final e in l.entries)
      if (!b.containsKey(e.key)) e.key: e.value,
  };
  if (createdHere.isEmpty) return;
  final createdThere = [
    for (final e in r.entries)
      if (!b.containsKey(e.key)) e.key,
  ];
  final byIdentity = <String, String>{};
  final byContent = <String, String>{};
  for (final e in createdHere.entries) {
    final identity = table.natural?.call(e.value);
    if (identity != null) byIdentity.putIfAbsent(identity, () => e.key);
    byContent.putIfAbsent(_content(e.value), () => e.key);
  }
  final moves = <int, int>{};
  final matched = <String>{};
  for (final key in createdThere) {
    final row = r[key]!;
    final identity = table.natural?.call(row);
    var mine = identity == null ? null : byIdentity[identity];
    if (mine != null && matched.contains(mine)) mine = null;
    mine ??= byContent[_content(row)];
    if (mine == null || matched.contains(mine)) continue;
    matched.add(mine);
    if (mine != key) moves[int.parse(mine)] = int.parse(key);
  }
  var next = 1;
  for (final source in [b, r, l]) {
    for (final key in source.keys) {
      final id = int.parse(key);
      if (id >= next) next = id + 1;
    }
  }
  final sequence = await tx.rawQuery(
    'SELECT seq FROM sqlite_sequence WHERE name = ?',
    [table.name],
  );
  if (sequence.isNotEmpty) {
    final seq = (sequence.first['seq'] as int?) ?? 0;
    if (seq >= next) next = seq + 1;
  }
  for (final key in createdThere) {
    final id = int.parse(key);
    // Something created here sits where the other device's row goes, is not
    // that row and is not moving to its own: it moves away.
    if (!createdHere.containsKey(key) || moves.containsKey(id)) continue;
    if (matched.contains(key)) continue;
    moves[id] = next++;
  }
  if (moves.isEmpty) return;
  // Through negative ids, so that no move lands on a row still to move.
  var temporary = 0;
  final staged = <int, int>{};
  for (final e in moves.entries) {
    temporary--;
    await _renumber(tx, table, e.key, temporary);
    staged[temporary] = e.value;
  }
  for (final e in staged.entries) {
    await _renumber(tx, table, e.key, e.value);
  }
}

Future<void> _renumber(Transaction tx, _Table table, int from, int to) async {
  await tx.rawUpdate('UPDATE ${table.name} SET id = ? WHERE id = ?', [to, from]);
  for (final (other, column) in table.references) {
    await tx.rawUpdate(
      'UPDATE $other SET $column = ? WHERE $column = ?',
      [to, from],
    );
  }
}

/// Puts [row] where [current] is (null: there is none). Null [row] deletes.
Future<void> _put(
  Transaction tx,
  _Table table,
  Map<String, Object?>? current,
  Map<String, Object?>? row,
) async {
  final source = row ?? current!;
  final where = table.key.map((k) => '$k = ?').join(' AND ');
  final args = [for (final k in table.key) source[k]];
  if (row == null) {
    await tx.delete(table.name, where: where, whereArgs: args);
    return;
  }
  final values = {
    for (final e in row.entries)
      if (e.key != _tagsColumn) e.key: e.value,
  };
  if (current == null) {
    await tx.insert(table.name, values);
  } else {
    await tx.update(table.name, values, where: where, whereArgs: args);
  }
  if (table.name == 'records') {
    final tags = row[_tagsColumn] as String? ?? '';
    if (current != null && current[_tagsColumn] == tags) return;
    await tx.delete('records_tags', where: 'record_id = ?', whereArgs: [row['id']]);
    for (final tag in tags.isEmpty ? const <String>[] : tags.split('\u0001')) {
      await tx.insert('records_tags', {'record_id': row['id'], 'tag_name': tag});
    }
  }
}

/// The history only grows: what the other device logged arrives.
Future<void> _mergeChangeLog(
  Transaction tx,
  DatabaseExecutor base,
  DatabaseExecutor remote,
  MergeReport report,
) async {
  String signature(Map<String, Object?> row) => jsonEncode([
    row['at'],
    row['device'],
    row['action'],
    row['target'],
    row['title'],
    row['before_values'],
    row['after_values'],
  ]);
  final known = {
    for (final db in [base, tx])
      for (final row in await db.query('change_log')) signature(row),
  };
  for (final row in await remote.query('change_log', orderBy: 'at')) {
    if (known.contains(signature(row))) continue;
    await tx.insert('change_log', {
      for (final e in row.entries)
        if (e.key != 'id') e.key: e.value,
    });
  }
}

/// A wallet or category deleted on one side while the other still
/// used it comes back, so that nothing points at what is gone.
Future<void> _repairReferences(
  Transaction tx,
  DatabaseExecutor base,
  DatabaseExecutor remote,
  MergeReport report,
) async {
  Future<void> restore(
    String table,
    String where,
    List<Object?> args,
    String what,
  ) async {
    for (final source in [remote, base]) {
      final rows = await source.query(table, where: where, whereArgs: args);
      if (rows.isEmpty) continue;
      await tx.insert(table, rows.first);
      report.applied++;
      report.conflicts.add('$what: ainda usado, voltou');
      return;
    }
  }

  for (final (table, column) in [
    ('records', 'wallet_id'),
    ('records', 'transfer_wallet_id'),
    ('recurrent_record_patterns', 'wallet_id'),
    ('recurrent_record_patterns', 'transfer_wallet_id'),
  ]) {
    for (final row in await tx.rawQuery(
      'SELECT DISTINCT $column AS id FROM $table WHERE $column IS NOT NULL '
      'AND $column NOT IN (SELECT id FROM wallets)',
    )) {
      await restore('wallets', 'id = ?', [row['id']], 'Carteira ${row['id']}');
    }
  }
  for (final table in ['records', 'recurrent_record_patterns']) {
    for (final row in await tx.rawQuery(
      'SELECT DISTINCT category_name AS name, category_type AS type FROM $table '
      'WHERE category_name IS NOT NULL AND NOT EXISTS (SELECT 1 FROM categories '
      'c WHERE c.name = $table.category_name '
      'AND c.category_type = $table.category_type)',
    )) {
      await restore(
        'categories',
        'name = ? AND category_type = ?',
        [row['name'], row['type']],
        'Categoria "${row['name']}"',
      );
    }
  }
}

/// The same, for the portable preferences (JSON-safe values by key). A value
/// that is a JSON object is joined inside, so that a coin bought here and a
/// note written there both stay. Returns the preferences as they end up.
({Map<String, dynamic> merged, List<String> conflicts}) mergePreferences({
  required Map<String, dynamic> base,
  required Map<String, dynamic> local,
  required Map<String, dynamic> remote,
  required bool remoteWins,
}) {
  final conflicts = <String>[];
  final merged = _mergeMap(base, local, remote, remoteWins, conflicts, '');
  return (merged: merged, conflicts: conflicts);
}

const _absent = Object();

Map<String, dynamic> _mergeMap(
  Map<String, dynamic> base,
  Map<String, dynamic> local,
  Map<String, dynamic> remote,
  bool remoteWins,
  List<String> conflicts,
  String path,
) {
  final result = <String, dynamic>{};
  for (final key in {...local.keys, ...remote.keys, ...base.keys}) {
    final value = _mergeValue(
      base.containsKey(key) ? base[key] : _absent,
      local.containsKey(key) ? local[key] : _absent,
      remote.containsKey(key) ? remote[key] : _absent,
      remoteWins,
      conflicts,
      path.isEmpty ? key : '$path.$key',
    );
    if (!identical(value, _absent)) result[key] = value;
  }
  return result;
}

Object? _mergeValue(
  Object? was,
  Object? mine,
  Object? theirs,
  bool remoteWins,
  List<String> conflicts,
  String path,
) {
  String text(Object? v) => identical(v, _absent) ? '\u0000' : jsonEncode(v);
  if (text(theirs) == text(was) || text(mine) == text(theirs)) return mine;
  if (text(mine) == text(was)) return theirs;
  // Both changed. Inside: JSON objects, and lists of objects with an id.
  final objects = [was, mine, theirs].map(_asObject).toList();
  if (objects[1] != null && objects[2] != null) {
    final merged = _mergeMap(
      objects[0] ?? const {},
      objects[1]!,
      objects[2]!,
      remoteWins,
      conflicts,
      path,
    );
    return mine is String ? jsonEncode(merged) : merged;
  }
  final lists = [was, mine, theirs].map(_asIdList).toList();
  if (lists[1] != null && lists[2] != null) {
    final base = lists[0] ?? const <String, dynamic>{};
    final merged = _mergeMap(base, lists[1]!, lists[2]!, remoteWins, conflicts, path);
    // Their order, then what only this side has.
    final order = [
      ...lists[2]!.keys,
      ...lists[1]!.keys.where((k) => !lists[2]!.containsKey(k)),
    ];
    return [
      for (final id in order)
        if (merged.containsKey(id)) merged[id],
    ];
  }
  conflicts.add(path);
  return remoteWins ? theirs : mine;
}

/// A JSON object, also when saved as text (most preferences are).
Map<String, dynamic>? _asObject(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is String && value.startsWith('{')) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
  }
  return null;
}

Map<String, dynamic>? _asIdList(Object? value) {
  if (value is! List || value.isEmpty) return null;
  final result = <String, dynamic>{};
  for (final item in value) {
    if (item is! Map || item['id'] == null) return null;
    result['${item['id']}'] = item;
  }
  return result;
}
