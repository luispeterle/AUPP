import 'package:aupp/components/known-tags.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('connector names written together still find the bank', () {
    expect(KnownTag.of('BTGPactual')?.name, 'BTG');
    expect(KnownTag.bankIn('BTGPactual')?.name, 'BTG');
    expect(KnownTag.of('MercadoPago')?.name, 'Mercado Pago');
    expect(KnownTag.of('NubankEmpresas')?.name, 'Nubank PJ');
    expect(KnownTag.of('BTG Pactual')?.name, 'BTG');
    expect(KnownTag.of('Pix')?.name, 'Pix');
    expect(KnownTag.of('Uma tag qualquer'), isNull);
  });
}
