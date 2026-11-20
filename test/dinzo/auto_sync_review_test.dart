// What stops the automatic sync for the user to look at.
import 'package:flutter_test/flutter_test.dart';
import 'package:aupp/dinzo/dinzo-auto-sync.dart';
import 'package:aupp/dinzo/dinzo-models.dart';
import 'package:aupp/dinzo/dinzo-sync-engine.dart';
import 'package:aupp/models/record.dart';

void main() {
  final record = Record(
    489.29,
    'Resgate para o C6',
    null,
    DateTime.utc(2026, 11, 19, 12),
  )..dinzoId = 'tx';
  final tx = DinzoTransaction(
    id: 'tx',
    date: '2026-11-19',
    type: 'CREDIT',
    amount: 489.29,
    description: 'CDB C6 LIM. GARANT.',
    accountId: 'c6',
  );

  test('a record the app now skips by its own rule goes without asking', () {
    final plan = DinzoSyncPlan([
      DinzoPlanItem(
        kind: DinzoPlanKind.remove,
        transaction: tx,
        existing: record,
        skipReason: DinzoSkipReason.investment,
      ),
    ]);
    expect(DinzoAutoSync.reviewReasons(plan), isEmpty);
  });

  test('a transaction gone from the Dinzo is asked', () {
    final plan = DinzoSyncPlan([
      DinzoPlanItem(kind: DinzoPlanKind.remove, existing: record),
    ]);
    expect(DinzoAutoSync.reviewReasons(plan), ['1 removido na Dinzo']);
  });

  test('a record edited here is asked, whatever the reason', () {
    final plan = DinzoSyncPlan([
      DinzoPlanItem(
        kind: DinzoPlanKind.remove,
        transaction: tx,
        existing: record,
        skipReason: DinzoSkipReason.investment,
        selected: false,
      ),
    ]);
    expect(DinzoAutoSync.reviewReasons(plan), isNotEmpty);
  });
}
