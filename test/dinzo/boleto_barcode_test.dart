import 'package:flutter_test/flutter_test.dart';
import 'package:aupp/dinzo/payment-launcher.dart';

void main() {
  test('bank boleto: digitable line (47) back to its barcode (44)', () {
    // Barcode: bank 237, currency 9, DV 1, factor 9123, value 0000012345,
    // free field 2500000000000000000012345.
    const barcode = '2379191230000012345' '2500000000000000000012345';
    final line = '${barcode.substring(0, 4)}${barcode.substring(19, 24)}0'
        '${barcode.substring(24, 34)}0'
        '${barcode.substring(34, 44)}0'
        '${barcode[4]}${barcode.substring(5, 19)}';
    expect(line.length, 47);
    expect(PaymentLauncher.boletoBarcode(line), barcode);
    // Punctuation and spaces as printed on the boleto.
    final printed = '${line.substring(0, 5)}.${line.substring(5, 10)} '
        '${line.substring(10, 21)} ${line.substring(21, 32)} '
        '${line[32]} ${line.substring(33)}';
    expect(PaymentLauncher.boletoBarcode(printed), barcode);
  });

  test('utility boleto: drops the check digit of each 12-digit block', () {
    final blocks = ['8366000000-1', '23450001000-2', '00000000000-3', '12345678901-4'];
    final line = blocks.map((b) => b.replaceAll('-', '').padLeft(12, '8')).join();
    expect(line.length, 48);
    expect(PaymentLauncher.boletoBarcode(line),
        [for (var i = 0; i < 4; i++) line.substring(i * 12, i * 12 + 11)].join());
  });

  test('anything else has no barcode', () {
    expect(PaymentLauncher.boletoBarcode('00020126580014br.gov.bcb.pix'), isNull);
    expect(PaymentLauncher.boletoBarcode('123'), isNull);
  });
}
