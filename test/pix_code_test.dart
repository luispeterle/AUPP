import 'dart:convert';

import 'package:aupp/dinzo/pix-charge.dart';
import 'package:aupp/dinzo/pix-code.dart';
import 'package:aupp/models/category.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/models/recurrent-period.dart';
import 'package:aupp/models/recurrent-record-pattern.dart';
import 'package:aupp/services/recurrent-record-service.dart';
import 'package:aupp/services/service-config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz;

void main() {
  test('CRC matches the Banco Central manual example', () {
    const payload = '00020126580014br.gov.bcb.pix0136123e4567-e12b-12d1-a456-'
        '4266554400005204000053039865802BR5913Fulano de Tal6008BRASILIA'
        '62070503***6304';
    expect(PixCode.crc16(payload), '1D3D');
  });

  test('a key becomes a copia-e-cola with the amount', () {
    final code = PixCode.build(
      key: '(11) 98765-4321',
      name: 'José da Silva',
      amount: 150,
    );
    expect(code, startsWith('000201'));
    expect(code, contains('0114+5511987654321'));
    expect(code, contains('5406150.00'));
    expect(code, contains('5913JOSE DA SILVA'));
    expect(PixCode.crc16(code.substring(0, code.length - 4)),
        code.substring(code.length - 4));
    expect(Record.paymentCodeKind(code), 'Pix');
  });

  test('keys are normalized', () {
    expect(PixCode.normalizeKey('123.456.789-09'), '12345678909');
    expect(PixCode.normalizeKey(' Fulano@Mail.com '), 'fulano@mail.com');
    expect(PixCode.normalizeKey('+55 (11) 98765-4321'), '+5511987654321');
  });

  test('a bank boleto barcode becomes its 47-digit line', () {
    const barcode = '23791843400000100003381260000000000000004000';
    final line = PixCode.boletoLine(barcode);
    expect(line, hasLength(47));
    // Bank and currency, general check digit, due factor and amount.
    expect(line.substring(0, 4), barcode.substring(0, 4));
    expect(line[32], barcode[4]);
    expect(line.substring(33), barcode.substring(5, 19));
    // The free field, without the three check digits.
    expect(
      line.substring(4, 9) + line.substring(10, 20) + line.substring(21, 31),
      barcode.substring(19),
    );
    expect(Record.paymentCodeKind(line), 'Boleto');
  });

  test('a utility barcode becomes four blocks of 12', () {
    const barcode = '83640000001123401380000000000000000000000000';
    final line = PixCode.boletoLine(barcode);
    expect(line, hasLength(48));
    for (var i = 0; i < 4; i++) {
      expect(line.substring(i * 12, i * 12 + 11),
          barcode.substring(i * 11, i * 11 + 11));
    }
    expect(Record.paymentCodeKind(line), 'Boleto');
  });

  test('the amount comes out of the Pix and of both boletos', () {
    expect(PixCode.amountOf(PixCode.build(key: 'a@b.com', amount: 87.4)), 87.4);
    expect(PixCode.amountOf(PixCode.build(key: 'a@b.com')), isNull);
    const bank = '23791843400000100003381260000000000000004000';
    expect(PixCode.amountOf(bank), 100.0);
    expect(PixCode.amountOf(PixCode.boletoLine(bank)), 100.0);
    const utility = '83640000001123401380000000000000000000000000';
    expect(PixCode.amountOf(PixCode.boletoLine(utility)), 112.34);
    // Third digit 7: a reference, not an amount.
    expect(PixCode.amountOf('83740000001123401380000000000000000000000000'),
        isNull);
  });

  group('an occurrence\'s code sets only its amount', () {
    setUpAll(() {
      tz.initializeTimeZones();
      ServiceConfig.localTimezone = 'UTC';
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    test('water: R\$ 100 a month, this month\'s boleto is R\$ 112,34', () {
      final pattern = RecurrentRecordPattern(-100, 'Água', Category('Água'),
          DateTime.utc(2026, 10, 5), RecurrentPeriod.EveryMonth)
        ..paymentCodes['2026-11-05'] = PixCode.boletoLine(
            '83640000001123401380000000000000000000000000');

      final records = RecurrentRecordService()
          .generateRecurrentRecordsFromDateTime(
              pattern, DateTime.utc(2026, 12, 31));

      expect(records.map((r) => r.value), [-100, -112.34, -100]);
      expect(pattern.value, -100);
    });
  });

  group('Pix charge (cobrança)', () {
    // Made up: a charge whose copia-e-cola only has the bank's address.
    String field(String id, String v) =>
        '$id${v.length.toString().padLeft(2, '0')}$v';
    final payload = field('00', '01') +
        field('01', '12') +
        field(
          '26',
          field('00', 'br.gov.bcb.pix') +
              field('25', 'pix.banco-exemplo.com.br/qr/v2/cobv/abc-123'),
        ) +
        field('52', '0000') +
        field('53', '986') +
        field('58', 'BR') +
        field('59', 'Nao_informado') +
        field('60', 'Nao_informado') +
        field('62', field('05', '***')) +
        '6304';

    test('the address comes out of the copia-e-cola, not an amount', () {
      expect(PixCharge.urlOf(payload),
          'https://pix.banco-exemplo.com.br/qr/v2/cobv/abc-123');
      expect(PixCode.amountOf(payload), isNull);
      expect(PixCharge.urlOf(PixCode.build(key: 'a@b.com')), isNull);
    });

    test('the bank answer gives amount, due date and receiver', () {
      String part(Map<String, dynamic> m) =>
          base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
      final jws = '${part({'alg': 'RS256'})}.${part({
            'calendario': {'dataDeVencimento': '2030-01-15'},
            'valor': {'original': '200.00', 'final': '187.65'},
            'recebedor': {'nome': 'ENERGIA EXEMPLO'},
            'status': 'ATIVA',
          })}.assinatura';

      final charge = PixCharge.parse(jws)!;

      expect(charge.amount, 187.65);
      expect(charge.dueDate, DateTime(2030, 1, 15));
      expect(charge.receiver, 'ENERGIA EXEMPLO');
      expect(charge.isOpen, isTrue);
      expect(PixCharge.parse('not a jws'), isNull);
    });

    test('the saved amount is that occurrence\'s', () {
      tz.initializeTimeZones();
      ServiceConfig.localTimezone = 'UTC';
      final day = DateTime(2030, 1, 15);
      final pattern = RecurrentRecordPattern(-300, 'Energia',
          Category('Energia'), DateTime.utc(2029, 12, 15), RecurrentPeriod.EveryMonth)
        ..paymentCodes[RecurrentRecordPattern.occurrenceKey(day)] = payload
        ..paymentCodes[RecurrentRecordPattern.chargeValueKey(day)] = '187.65';
      expect(pattern.valueFor(day), -187.65);
      expect(pattern.valueFor(DateTime(2030, 2, 15)), -300);
    });
  });

  test('a bank boleto carries its due date', () {
    // Factor 1000 is 2025-02-22; 1268 is 268 days later.
    const barcode = '23791126800000100003381260000000000000004000';
    expect(PixCode.dueDateOf(barcode), DateTime(2025, 11, 17));
    expect(PixCode.dueDateOf(PixCode.boletoLine(barcode)), DateTime(2025, 11, 17));
    expect(PixCode.dueDateOf('83640000001123401380000000000000000000000000'),
        isNull);
  });

  test('a due date moves only that occurrence, which keeps its identity', () {
    tz.initializeTimeZones();
    ServiceConfig.localTimezone = 'UTC';
    final pattern = RecurrentRecordPattern(-300, 'Energia', Category('Energia'),
        DateTime.utc(2030, 1, 20, 10), RecurrentPeriod.EveryMonth)
      ..setDueDate(DateTime(2030, 2, 20), DateTime(2030, 2, 16));

    final records = RecurrentRecordService()
        .generateRecurrentRecordsFromDateTime(
            pattern, DateTime.utc(2030, 3, 31));

    expect(records.map((r) => r.localDateTime.day), [20, 16, 20]);
    expect(records[1].localDateTime.month, 2);
    // Codes and marks still go by the recurrence's day.
    expect(pattern.occurrenceDayOf(records[1]).day, 20);
    final stored = Record(-300, 'Energia', null, DateTime.utc(2030, 2, 16, 10),
        recurrencePatternId: 'x');
    expect(pattern.occurrenceDayOf(stored), DateTime(2030, 2, 20));
  });

  test('a code without a due date leaves the day unchecked', () {
    final day = DateTime(2030, 3, 10);
    final pattern = RecurrentRecordPattern(-100, 'Água', Category('Água'),
        DateTime.utc(2030, 1, 10), RecurrentPeriod.EveryMonth);
    expect(pattern.dueDateMissing(day), isFalse);
    pattern.paymentCodes[RecurrentRecordPattern.occurrenceKey(day)] =
        '83640000001123401380000000000000000000000000';
    expect(pattern.dueDateMissing(day), isTrue);
    // Checked by hand, even on the same day.
    pattern.setDueDate(day, day);
    expect(pattern.dueDateMissing(day), isFalse);
    expect(pattern.dueDateFor(day), day);
  });
}
