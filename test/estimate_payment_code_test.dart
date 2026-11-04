// Fork: payment code (Pix / boleto) of each estimate occurrence.
import 'package:flutter_test/flutter_test.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/models/recurrent-period.dart';
import 'package:aupp/models/recurrent-record-pattern.dart';
import 'package:aupp/services/service-config.dart';
import 'package:timezone/data/latest_all.dart' as tz;

void main() {
  setUpAll(() {
    tz.initializeTimeZones();
    ServiceConfig.localTimezone = 'America/Sao_Paulo';
  });

  test('kind of code: Pix copia-e-cola, boleto line, anything else', () {
    expect(Record.paymentCodeKind('00020126580014BR.GOV.BCB.PIX...'), 'Pix');
    expect(
      Record.paymentCodeKind(
          '34191.79001 01043.510047 91020.150008 1 96610000012345'),
      'Boleto',
    );
    expect(Record.paymentCodeKind('qualquer coisa'), 'Código');
  });

  test('codes are kept per occurrence and survive the database map', () {
    final pattern = RecurrentRecordPattern(
      -300,
      'Energia',
      null,
      DateTime.utc(2026, 11, 8, 15),
      RecurrentPeriod.EveryMonth,
    );
    final key = RecurrentRecordPattern.occurrenceKey(DateTime(2026, 11, 8));
    expect(key, '2026-11-08');
    pattern.paymentCodes[key] = '000201pix';
    final map = pattern.toMap()..['category'] = null;
    final back = RecurrentRecordPattern.fromMap(map);
    expect(back.paymentCodes, {'2026-11-08': '000201pix'});
    expect(RecurrentRecordPattern.fromMap({...map, 'payment_codes': null})
        .paymentCodes, isEmpty);
  });
}
