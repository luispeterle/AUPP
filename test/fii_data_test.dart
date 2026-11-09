import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aupp/desktop/fii-compare-page.dart';
import 'package:aupp/investments/b3-market.dart';
import 'package:aupp/investments/fii-data.dart';
import 'package:aupp/investments/fii-store.dart';
import 'package:aupp/investments/fii-view.dart';

// Invented funds, in the CVM's layout (only the columns the app reads).
const _cnpj = '11.111.111/0001-11';
const _other = '22.222.222/0001-22';

const _register =
    'Tipo_Fundo_Classe;CNPJ_Fundo_Classe;Data_Referencia;Versao;Nome_Fundo_Classe;Data_Funcionamento;Codigo_ISIN;Segmento_Atuacao;Tipo_Gestao;Nome_Administrador\n'
    'Classe;$_cnpj;2026-01-01;1;FUNDO TESTE RENDA FII;2015-03-02;BRTSTRCTF001;Logística;Ativa;ADMINISTRADORA EXEMPLO\n'
    'Classe;$_cnpj;2026-02-01;1;FUNDO TESTE RENDA FII RESPONSABILIDADE LIMITADA;2015-03-02;BRTSTRCTF001;Logística;Ativa;ADMINISTRADORA EXEMPLO\n'
    // A fund whose ISIN is the CVM's code: found by brapi's name.
    'Classe;$_other;2026-02-01;1;OUTRO EXEMPLO FII;2020-01-01;BR0XYZCTF000;Logística;Passiva;OUTRA ADM\n';

String _months() {
  final lines = StringBuffer(
    'CNPJ_Fundo_Classe;Data_Referencia;Versao;Total_Numero_Cotistas;Patrimonio_Liquido;Cotas_Emitidas;Valor_Patrimonial_Cotas;Percentual_Despesas_Taxa_Administracao;Percentual_Dividend_Yield_Mes\n',
  );
  for (var m = 1; m <= 12; m++) {
    final date = '2025-${m.toString().padLeft(2, '0')}-01';
    // 0.01 of a book of 100: R$ 1,00 a share; March written as a percentage.
    final yieldOnBook = m == 3 ? '1' : '0.01';
    lines.writeln('$_cnpj;$date;1;1000;1000000;10000;100;0.001;$yieldOnBook');
  }
  lines
    // A second version of December wins.
    ..writeln('$_cnpj;2025-12-01;2;1200;1100000;10000;110;0.001;0.02')
    ..writeln('$_cnpj;2026-01-01;1;1200;1100000;10000;110;0.001;')
    ..writeln('$_other;2026-01-01;1;50;500000;5000;100;0.002;0.008');
  return lines.toString();
}

const _assets =
    'CNPJ_Fundo_Classe;Data_Referencia;Versao;Total_Necessidades_Liquidez;Total_Investido;Direitos_Bens_Imoveis;CRI;FII\n'
    '$_cnpj;2026-01-01;1;100;900;700;150;50\n'
    '$_other;2026-01-01;1;50;950;0;900;0\n';

const _properties =
    'CNPJ_Fundo_Classe;Data_Referencia;Versao;Classe;Nome_Imovel;Area;Percentual_Vacancia;Percentual_Inadimplencia;Percentual_Receitas_FII\n'
    '$_cnpj;2025-09-30;1;Imóveis para renda acabados;Galpão Velho;100;1;0;0.5\n'
    '$_cnpj;2025-12-31;1;Imóveis para renda acabados;Galpão A;3000;0;0;0.6\n'
    '$_cnpj;2025-12-31;1;Imóveis para renda acabados;Galpão B;1000;0.4;0.01;0.4\n'
    '$_cnpj;2025-12-31;1;Terrenos;Terreno C;5000;;;0\n';

const _tenants =
    'CNPJ_Fundo_Classe;Data_Referencia;Versao;Nome_Imovel;Setor_Atuacao;Percentual_Receita_Imovel;Percentual_Receitas_FII\n'
    '$_cnpj;2025-12-31;1;Galpão A;Varejo;1;0.6\n'
    '$_cnpj;2025-12-31;1;Galpão B;Varejo;0.5;0.2\n'
    '$_cnpj;2025-12-31;1;Galpão B;Indústria;0.5;0.2\n'
    '$_cnpj;2025-12-31;1;Galpão B;-;0;0\n';

const _leases =
    'CNPJ_Fundo_Classe;Data_Referencia;Versao;Percentual_Vencimento_Receita_FII_Faixa_Ate_3Meses;Percentual_Vencimento_Receita_FII_Faixa_9a12Meses;Percentual_Vencimento_Receita_FII_Faixa_Acima_36Meses;Percentual_Indexador_Receita_FII_IPCA;Percentual_Indexador_Receita_FII_IGPM\n'
    '$_cnpj;2025-12-31;1;0.1;0.2;0.7;0.75;0.25\n';

Map<String, FiiFund> _parse() {
  final parser = FiiParser()
    ..addRegister(_register)
    ..addMonths(_months())
    ..addAssets(_assets)
    ..addProperties(_properties)
    ..addTenants(_tenants)
    ..addLeases(_leases);
  return parser.build();
}

void main() {
  test('the reports of a fund: the newest version and month win', () {
    final fund = _parse()[_cnpj]!;
    expect(fund.name, 'FUNDO TESTE RENDA FII RESPONSABILIDADE LIMITADA');
    expect(fund.segment, 'Logística');
    expect(fund.since, DateTime(2015, 3, 2));
    expect(fund.months.length, 13);
    expect(fund.last!.date, DateTime(2026));
    expect(fund.bookPerShare, 110);
    expect(fund.last!.holders, 1200);
    // January is blank: the last payment is December's second version.
    expect(fund.lastPaid!.date, DateTime(2025, 12));
    expect(fund.lastDividend, closeTo(2.2, 1e-9));
    // March's "1" is 1%.
    expect(fund.months[2].dividendPerShare, closeTo(1, 1e-9));
  });

  test('payments of the last year, with a blank month', () {
    final fund = _parse()[_cnpj]!;
    // February to January: ten months of 1,00, December of 2,20, January
    // blank and counted as the average of the eleven.
    expect(fund.dividends12m, closeTo((10 + 2.2) / 11 * 12, 1e-9));
    expect(fund.dividendYield(100), closeTo((10 + 2.2) / 11 * 12 / 100, 1e-9));
    expect(fund.pvp(99), closeTo(0.9, 1e-9));
    expect(fund.paidMonths(24), (12, 12));
    expect(fund.adminFee12m, closeTo(0.012, 1e-9));
    expect(fund.marketCap(100), 1e6);
  });

  test('what the fund holds, its properties and leases', () {
    final funds = _parse();
    final fund = funds[_cnpj]!;
    expect(fund.mix!.realEstate, closeTo(0.7, 1e-9));
    expect(fund.mix!.cash, closeTo(0.1, 1e-9));
    expect(fund.kind, FiiKind.brick);
    expect(funds[_other]!.kind, FiiKind.paper);
    // Only the newest quarter, the most of the revenue first.
    expect(fund.quarter, DateTime(2025, 12, 31));
    expect(fund.properties.map((p) => p.name), ['Galpão A', 'Galpão B', 'Terreno C']);
    // By area, the land left out.
    expect(fund.vacancy, closeTo(400 / 4000, 1e-9));
    expect(fund.rentedCount, 2);
    expect(fund.tenants, {'Varejo': closeTo(0.8, 1e-9), 'Indústria': 0.2});
    expect(fund.leases.map((l) => l.$1), ['Até 1 ano', 'Mais de 3 anos']);
    expect(fund.leases.first.$2, closeTo(0.3, 1e-9));
    expect(fund.indexes, {'IPCA': 0.75, 'IGP-M': 0.25});
  });

  test('the JSON keeps everything', () {
    final fund = _parse()[_cnpj]!;
    final back = FiiFund.fromJson(fund.toJson());
    expect(back.toJson(), fund.toJson());
  });

  test('brapi\'s and the CVM\'s names meet', () {
    expect(
      plainFundName(
        'KINEA UNIQUE HY CDI FUNDO DE INVESTIMENTO IMOBILIÁRIO RESPONSABILIDADE LIMITADA',
      ),
      plainFundName('KINEA UNIQUE HY CDI FII RESPONSABILIDADE LIMITADA'),
    );
    expect(
      plainFundName('PATRIA SECURITIES FUNDO DE INVESTIMENTO IMOBILIÁRIO - RESPONSABILIDADE  LIMITADA'),
      'PATRIA SECURITIES',
    );
  });

  test('a fund that changed its name is found by the CNPJ of the B3', () {
    // BTCI11 still reports the ISIN and name of FEXC, before it was renamed.
    FiiStore.instance.setForTest([
      const FiiFund(
        cnpj: '09.552.812/0001-14',
        name: 'BTG CRÉDITO IMOB FII',
        isin: 'BRFEXCCTF007',
      ),
    ]);
    expect(FiiStore.instance.byTicker('BTCI11')?.cnpj, '09.552.812/0001-14');
  });

  test('a ticker finds its fund by the ISIN, or by brapi\'s name', () {
    FiiStore.instance.setForTest(_parse().values);
    B3Market.funds.setForTest([
      const MarketRow(ticker: 'TSTR11', name: 'FUNDO TESTE RENDA', price: 99, volume: 1000),
      const MarketRow(ticker: 'OUTR11', name: 'OUTRO EXEMPLO FUNDO DE INVESTIMENTO IMOBILIÁRIO', price: 9),
    ]);
    expect(FiiStore.instance.byTicker('TSTR11')!.cnpj, _cnpj);
    expect(FiiStore.instance.byTicker('OUTR11')!.cnpj, _other);
    expect(FiiStore.instance.byTicker('NADA11'), isNull);
    final quote = FiiQuote.of('TSTR11')!;
    expect(quote.traded, 99000);
    expect(FiiIndicator.pvp.format(quote), '0,90');
    expect(FiiIndicator.paid.format(quote), '12 de 12');
  });

  testWidgets('the Ficha and Comparar of a fund lay out', (tester) async {
    FiiStore.instance.setForTest(_parse().values);
    B3Market.funds.setForTest([
      const MarketRow(ticker: 'TSTR11', name: 'FUNDO TESTE RENDA', price: 99, volume: 1000),
      const MarketRow(ticker: 'OUTR11', name: 'OUTRO EXEMPLO', price: 9),
    ]);
    for (final size in const [Size(1400, 1000), Size(400, 900)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(children: const [FiiPanel(ticker: 'TSTR11')]),
          ),
        ),
      );
      expect(find.text('Dados do fundo'), findsOneWidget);
      expect(find.text('Galpão A'), findsOneWidget);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: FiiComparePage(ticker: 'TSTR11')),
        ),
      );
      await tester.pump();
      expect(find.text('P/VP'), findsWidgets);
    }
    tester.view.reset();
  });
}
