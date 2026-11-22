import 'package:aupp/helpers/title-case.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a title all in capitals (as banks send) is fully converted', () {
    expect(titleCasePtBr('PAÇOCA DE GOIABA'), 'Paçoca de Goiaba');
    expect(titleCasePtBr('IR SOBRE RESGATE CDB - NU FINANCEIRA S.A.'),
        'IR Sobre Resgate CDB - Nu Financeira S.A.');
  });

  test('lowercase words get their first letter up, connectors stay', () {
    expect(titleCasePtBr('mae ajud tenis'), 'Mae Ajud Tenis');
    expect(titleCasePtBr('Pre e intra treino'), 'Pre e Intra Treino');
    expect(titleCasePtBr('Cpap 10/12'), 'CPAP 10/12');
    expect(titleCasePtBr('guarda-chuva'), 'Guarda-Chuva');
  });

  test('what was written with capitals on purpose stays', () {
    expect(titleCasePtBr('Encerramento Caixinha NX2'),
        'Encerramento Caixinha NX2');
    expect(titleCasePtBr('AliExpress'), 'AliExpress');
    expect(titleCasePtBr('NickXbox'), 'NickXbox');
    expect(titleCasePtBr('Truthear RED'), 'Truthear RED');
    expect(titleCasePtBr('RD'), 'RD');
    expect(titleCasePtBr('iPhone novo'), 'iPhone Novo');
    expect(titleCasePtBr('Xteink X4 Pro'), 'Xteink X4 Pro');
    expect(titleCasePtBr('IPTV Bras'), 'IPTV Bras');
  });

  test('a long word in capitals inside a title is a name the bank shouted', () {
    expect(titleCasePtBr('Pix recebido de FULANO DE TAL'),
        'Pix Recebido de Fulano de Tal');
  });

  test('running it again changes nothing', () {
    for (final t in ['PAÇOCA DE GOIABA', 'mae ajud tenis', 'AliExpress x']) {
      expect(titleCasePtBr(titleCasePtBr(t)), titleCasePtBr(t));
    }
  });
}
