// Joining two devices' data row by row: what each side changed stays, and
// the rows the app creates on both become one.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:aupp/hybrid_sync/hybrid-sync-merge.dart';
import 'package:aupp/services/database/sqlite-database.dart';
import 'package:aupp/services/database/sqlite-migration-service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tmp;
  late Database base, local, remote;

  Future<Database> open(String name) => databaseFactoryFfi.openDatabase(
    '${tmp.path}/$name.db',
    options: OpenDatabaseOptions(
      version: SqliteDatabase.version,
      onCreate: SqliteMigrationService.onCreate,
      singleInstance: false,
    ),
  );

  Future<int> addRecord(
    Database db,
    String title, {
    int? id,
    double value = -10,
    String? dinzoId,
    List<String> tags = const [],
  }) async {
    final recordId = await db.insert('records', {
      'id': ?id,
      'datetime': DateTime.utc(2026, 10, 1).millisecondsSinceEpoch,
      'value': value,
      'title': title,
      'category_name': 'Mercado',
      'category_type': 0,
      'wallet_id': 1,
      'dinzo_id': dinzoId,
    });
    for (final tag in tags) {
      await db.insert('records_tags', {'record_id': recordId, 'tag_name': tag});
    }
    return recordId;
  }

  /// Local and remote start as copies of [base].
  Future<void> split() async {
    await base.close();
    for (final name in ['local', 'remote']) {
      await File('${tmp.path}/base.db').copy('${tmp.path}/$name.db');
    }
    base = await open('base');
    local = await open('local');
    remote = await open('remote');
  }

  Future<MergeReport> merge({bool remoteWins = true}) => mergeDatabases(
    local: local,
    base: base,
    remote: remote,
    remoteWins: remoteWins,
  );

  Future<Map<String, Map<String, Object?>>> records() async => {
    for (final row in await local.query('records', orderBy: 'id'))
      row['title'] as String: row,
  };

  Future<List<String>> tagsOf(int id) async => [
    for (final row in await local.query(
      'records_tags',
      where: 'record_id = ?',
      whereArgs: [id],
      orderBy: 'tag_name',
    ))
      row['tag_name'] as String,
  ];

  setUp(() async {
    sqfliteFfiInit();
    tmp = await Directory.systemTemp.createTemp('hybrid_merge');
    base = await open('base');
    for (final table in ['wallets', 'categories', 'records', 'change_log']) {
      await base.delete(table);
    }
    await base.insert('categories', {'name': 'Mercado', 'category_type': 0});
    await base.insert('wallets', {'id': 1, 'name': 'Conta', 'kind': 'normal'});
    await addRecord(base, 'aluguel', id: 1, value: -1000);
    await addRecord(base, 'luz', id: 2, value: -100);
    await split();
  });

  tearDown(() async {
    for (final db in [base, local, remote]) {
      await db.close();
    }
    await tmp.delete(recursive: true);
  });

  test('a change on each side: both stay', () async {
    await remote.update('records', {'value': -1100}, where: 'id = 1');
    await local.update('records', {'value': -120}, where: 'id = 2');
    final report = await merge();
    final rows = await records();
    expect(rows['aluguel']!['value'], -1100);
    expect(rows['luz']!['value'], -120);
    expect(report.conflicts, isEmpty);
  });

  test('different fields of the same record on each side join', () async {
    await remote.update('records', {'value': -1100}, where: 'id = 1');
    await local.update('records', {'description': 'pago'}, where: 'id = 1');
    await merge(remoteWins: false);
    final row = (await records())['aluguel']!;
    expect((row['value'], row['description']), (-1100, 'pago'));
  });

  test('the same field on both: the most recent edit, and it is reported',
      () async {
    await remote.update('records', {'value': -1100}, where: 'id = 1');
    await local.update('records', {'value': -1200}, where: 'id = 1');
    var report = await merge(remoteWins: false);
    expect((await records())['aluguel']!['value'], -1200);
    expect(report.conflicts.single, contains('aluguel'));

    report = await merge(remoteWins: true);
    expect((await records())['aluguel']!['value'], -1100);
  });

  test('records created on both with the same id: both stay, tags follow',
      () async {
    final there = await addRecord(remote, 'feira', tags: ['Pix']);
    final here = await addRecord(local, 'padaria', tags: ['Débito']);
    expect(here, there);
    await merge();
    final rows = await records();
    expect(rows.keys, containsAll(['feira', 'padaria']));
    expect(rows['feira']!['id'], there);
    final moved = rows['padaria']!['id'] as int;
    expect(moved, isNot(there));
    expect(await tagsOf(there), ['Pix']);
    expect(await tagsOf(moved), ['Débito']);
    // The next record gets an id nobody has.
    expect(await addRecord(local, 'novo'), greaterThan(moved));
  });

  test('the same Dinzo transaction brought by both devices becomes one',
      () async {
    await addRecord(remote, 'outro', id: 3);
    final there = await addRecord(remote, 'mercado', id: 4, dinzoId: 'tx-1');
    await addRecord(local, 'mercado', id: 3, dinzoId: 'tx-1', tags: ['Crédito']);
    await merge(remoteWins: false);
    final rows = await records();
    expect(rows['mercado']!['id'], there);
    expect(rows.keys.where((t) => t == 'mercado'), hasLength(1));
    expect(rows['outro']!['id'], 3);
    expect(await tagsOf(there), ['Crédito']);
  });

  test('deleted there, untouched here: goes; edited here: stays', () async {
    await remote.delete('records', where: 'id IN (1, 2)');
    await local.update('records', {'value': -130}, where: 'id = 2');
    final report = await merge();
    final rows = await records();
    expect(rows.containsKey('aluguel'), isFalse);
    expect(rows['luz']!['value'], -130);
    expect(report.conflicts.single, contains('luz'));
  });

  test('deleted here, edited there: comes back', () async {
    await local.delete('records', where: 'id = 1');
    await remote.update('records', {'value': -1100}, where: 'id = 1');
    await merge();
    expect((await records())['aluguel']!['value'], -1100);
  });

  test('a wallet created on both with the same name becomes one', () async {
    await remote.insert('wallets', {'id': 2, 'name': 'Viagem', 'kind': 'normal'});
    await remote.insert('wallets', {'id': 3, 'name': 'Carro', 'kind': 'normal'});
    await local.insert('wallets', {'id': 2, 'name': 'Carro', 'kind': 'normal'});
    final id = await addRecord(local, 'gasolina');
    await local.update('records', {'wallet_id': 2}, where: 'id = ?', whereArgs: [id]);
    await merge();
    final wallets = {
      for (final row in await local.query('wallets')) row['name']: row['id'],
    };
    expect(wallets, {'Conta': 1, 'Viagem': 2, 'Carro': 3});
    expect((await records())['gasolina']!['wallet_id'], 3);
  });

  test('a wallet deleted there but used here comes back', () async {
    await remote.delete('wallets', where: 'id = 1');
    await remote.delete('records');
    await addRecord(local, 'novo');
    final report = await merge();
    expect((await local.query('wallets')).map((w) => w['id']), [1]);
    expect(report.conflicts, contains(contains('Carteira 1')));
  });

  test('a recurring item keeps what was generated latest', () async {
    for (final db in [base, local, remote]) {
      await db.insert('recurrent_record_patterns', {
        'id': 'p1',
        'title': 'Internet',
        'last_update': 100,
      });
    }
    await local.update('recurrent_record_patterns', {'last_update': 300});
    await remote.update('recurrent_record_patterns', {'last_update': 200});
    await merge(remoteWins: true);
    final row = (await local.query('recurrent_record_patterns')).single;
    expect(row['last_update'], 300);
  });

  test("the other device's history arrives once", () async {
    final entry = {
      'at': 1,
      'device': 'Celular',
      'action': 'Criou',
      'target': 'records',
      'title': 'feira',
    };
    await remote.insert('change_log', entry);
    await merge();
    await merge();
    expect(await local.query('change_log'), hasLength(1));
  });

  test('nothing changed there: nothing changes here', () async {
    await local.update('records', {'value': -120}, where: 'id = 2');
    final report = await merge();
    expect(report.changed, isFalse);
    expect((await records())['luz']!['value'], -120);
  });

  group('preferences', () {
    String lots(Map<String, List<Map<String, Object>>> value) =>
        jsonEncode(value);

    test('a coin bought here and another there both stay', () {
      final btc = {'id': 'a', 'qty': 1};
      final result = mergePreferences(
        base: {'assetLots': lots({'BTC': [btc]})},
        local: {
          'assetLots': lots({
            'BTC': [btc, {'id': 'b', 'qty': 2}],
          }),
        },
        remote: {
          'assetLots': lots({
            'BTC': [btc],
            'XMR': [{'id': 'c', 'qty': 3}],
          }),
        },
        remoteWins: true,
      );
      final merged = jsonDecode(result.merged['assetLots']) as Map;
      expect((merged['BTC'] as List).map((l) => l['id']), ['a', 'b']);
      expect((merged['XMR'] as List).single['id'], 'c');
      expect(result.conflicts, isEmpty);
    });

    test('removed there, untouched here: goes', () {
      final result = mergePreferences(
        base: {'x': true, 'y': 1},
        local: {'x': true, 'y': 1},
        remote: {'y': 1},
        remoteWins: false,
      );
      expect(result.merged, {'y': 1});
    });

    test('the same value changed on both: the most recent', () {
      final result = mergePreferences(
        base: {'x': 1},
        local: {'x': 2},
        remote: {'x': 3},
        remoteWins: false,
      );
      expect(result.merged, {'x': 2});
      expect(result.conflicts, ['x']);
    });
  });
}
