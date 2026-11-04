// Reading the CVM's statements: the latest version of each document,
// consolidated over individual, values in thousands, the last twelve months
// from the quarters, and share counts filed in thousands. Petrobras's figures
// (millions of reais) as filed for 2025 and 2026.
import 'package:flutter_test/flutter_test.dart';
import 'package:aupp/investments/cvm-statements.dart';

const _flowHeader =
    'CNPJ_CIA;DT_REFER;VERSAO;DENOM_CIA;CD_CVM;GRUPO_DFP;MOEDA;ESCALA_MOEDA;'
    'ORDEM_EXERC;DT_INI_EXERC;DT_FIM_EXERC;CD_CONTA;DS_CONTA;VL_CONTA;'
    'ST_CONTA_FIXA';
const _balanceHeader =
    'CNPJ_CIA;DT_REFER;VERSAO;DENOM_CIA;CD_CVM;GRUPO_DFP;MOEDA;ESCALA_MOEDA;'
    'ORDEM_EXERC;DT_FIM_EXERC;CD_CONTA;DS_CONTA;VL_CONTA;ST_CONTA_FIXA';
const _cnpj = '33.000.167/0001-01';

/// A row in millions, written in thousands as the CVM does.
String _flow(
  String refer,
  String start,
  String end,
  String code,
  String name,
  num millions, {
  int version = 1,
  String company = '009512',
}) =>
    '$_cnpj;$refer;$version;PETROBRAS;$company;DF;REAL;MIL;ÚLTIMO;$start;$end;'
    '$code;$name;${millions * 1000};S';

String _balance(String refer, String code, String name, num millions) =>
    '$_cnpj;$refer;1;PETROBRAS;009512;DF;REAL;MIL;ÚLTIMO;$refer;$code;$name;'
    '${millions * 1000};S';

List<String> _income(String refer, String start, String end, List<num> v) => [
  _flow(refer, start, end, '3.01', 'Receita de Venda de Bens e/ou Serviços', v[0]),
  _flow(refer, start, end, '3.02', 'Custo dos Bens e/ou Serviços Vendidos', v[1] - v[0]),
  _flow(refer, start, end, '3.04', 'Despesas/Receitas Operacionais', v[2] - v[1]),
  _flow(refer, start, end, '3.03', 'Resultado Bruto', v[1]),
  _flow(
    refer,
    start,
    end,
    '3.05',
    'Resultado Antes do Resultado Financeiro e dos Tributos',
    v[2],
  ),
  _flow(
    refer,
    start,
    end,
    '3.08',
    'Imposto de Renda e Contribuição Social sobre o Lucro',
    v[3],
  ),
  _flow(refer, start, end, '3.11', 'Lucro/Prejuízo Consolidado do Período', v[4]),
  _flow(
    refer,
    start,
    end,
    '3.11.01',
    'Atribuído a Sócios da Empresa Controladora',
    v[4],
  ),
];

void main() {
  CvmParser petrobras({bool withQuarter = true, double shareScale = 1}) {
    final parser = CvmParser();
    parser.addStatement(
      [
        _flowHeader,
        ..._income('2025-12-31', '2025-01-01', '2025-12-31', [
          497549,
          236998,
          145628,
          -39994,
          110605,
        ]),
        _flow(
          '2025-12-31',
          '2025-01-01',
          '2025-12-31',
          '3.99.01.01',
          'ON',
          0,
        ).replaceFirst(';0;S', ';8.54;S'),
      ].join('\n'),
      Statement.dre,
      consolidated: true,
      yearly: true,
    );
    parser.addStatement(
      [
        _flowHeader,
        _flow('2025-12-31', '2025-01-01', '2025-12-31', '6.01', 'Caixa Líquido Atividades Operacionais', 200333),
        _flow('2025-12-31', '2025-01-01', '2025-12-31', '6.01.01.04', 'Depreciação, depleção e amortização', 84388),
        _flow('2025-12-31', '2025-01-01', '2025-12-31', '6.02.01', 'Aquisições de ativos imobilizados e intangíveis', -108714),
        _flow('2025-12-31', '2025-01-01', '2025-12-31', '6.03.05', 'Dividendos pagos a acionistas da Petrobras', -45205),
        _flow('2025-12-31', '2025-01-01', '2025-12-31', '6.03.06', 'Dividendos pagos a acionistas não controladores', -233),
        _flow('2025-12-31', '2025-01-01', '2025-12-31', '6.02', 'Caixa Líquido Atividades de Investimento', -86114),
        _flow('2025-12-31', '2025-01-01', '2025-12-31', '6.03', 'Caixa Líquido Atividades de Financiamento', -97122),
        _flow('2025-12-31', '2025-01-01', '2025-12-31', '6.04', 'Variação Cambial s/ Caixa e Equivalentes', -1743),
        _flow('2025-12-31', '2025-01-01', '2025-12-31', '6.05.02', 'Saldo Final de Caixa e Equivalentes', 35608),
      ].join('\n'),
      Statement.dfc,
      consolidated: true,
      yearly: true,
    );
    parser.addStatement(
      [
        _balanceHeader,
        _balance('2025-12-31', '1', 'Ativo Total', 1223389),
        _balance('2025-12-31', '1.01', 'Ativo Circulante', 140026),
        _balance('2025-12-31', '1.01.01', 'Caixa e Equivalentes de Caixa', 35608),
        _balance('2025-12-31', '1.01.02', 'Aplicações Financeiras', 15000),
        _balance('2025-12-31', '1.01.04', 'Estoques', 45173),
        _balance('2025-12-31', '1.02', 'Ativo Não Circulante', 1083363),
      ].join('\n'),
      Statement.bpa,
      consolidated: true,
      yearly: true,
    );
    parser.addStatement(
      [
        _balanceHeader,
        _balance('2025-12-31', '2.01', 'Passivo Circulante', 198368),
        _balance('2025-12-31', '2.01.04', 'Empréstimos e Financiamentos', 67253),
        _balance('2025-12-31', '2.02', 'Passivo Não Circulante', 607434),
        _balance('2025-12-31', '2.02.01', 'Empréstimos e Financiamentos', 316772),
        _balance('2025-12-31', '2.03', 'Patrimônio Líquido Consolidado', 417587),
      ].join('\n'),
      Statement.bpp,
      consolidated: true,
      yearly: true,
    );
    // The individual statement of the same document is ignored.
    parser.addStatement(
      [
        _flowHeader,
        _flow('2025-12-31', '2025-01-01', '2025-12-31', '3.01', 'Receita de Venda de Bens e/ou Serviços', 1),
      ].join('\n'),
      Statement.dre,
      consolidated: false,
      yearly: true,
    );
    if (withQuarter) {
      parser.addStatement(
        [
          _flowHeader,
          // Version 1 of the second quarter, replaced by version 2.
          _flow('2026-06-30', '2026-01-01', '2026-06-30', '3.01', 'Receita de Venda de Bens e/ou Serviços', 1),
          ..._income('2026-06-30', '2026-01-01', '2026-06-30', [
            293216,
            150000,
            110000,
            -27000,
            85256,
          ]).map((row) => row.replaceFirst(';1;PETROBRAS', ';2;PETROBRAS')),
          // The quarter alone: not the year so far.
          _flow('2026-06-30', '2026-04-01', '2026-06-30', '3.01', 'Receita de Venda de Bens e/ou Serviços', 169530, version: 2),
          ..._income('2026-06-30', '2025-01-01', '2025-06-30', [
            242272,
            109486,
            69882,
            -19860,
            62105,
          ]).map((row) => row.replaceFirst(';1;PETROBRAS', ';2;PETROBRAS')),
        ].join('\n'),
        Statement.dre,
        consolidated: true,
        yearly: false,
      );
      parser.addStatement(
        [
          _balanceHeader,
          _balance(
            '2026-06-30',
            '2.03',
            'Patrimônio Líquido Consolidado',
            480950,
          ).replaceFirst(';1;PETROBRAS', ';2;PETROBRAS'),
        ].join('\n'),
        Statement.bpp,
        consolidated: true,
        yearly: false,
      );
    }
    final on = 7442231382 / shareScale;
    final pn = 5446501379 / shareScale;
    parser.addCapital(
      'CNPJ_CIA;DT_REFER;VERSAO;DENOM_CIA;QT_ACAO_ORDIN_CAP_INTEGR;'
      'QT_ACAO_PREF_CAP_INTEGR;QT_ACAO_TOTAL_CAP_INTEGR;QT_ACAO_ORDIN_TESOURO;'
      'QT_ACAO_PREF_TESOURO;QT_ACAO_TOTAL_TESOURO\n'
      '$_cnpj;2025-12-31;1;PETROBRAS;${on.round()};${pn.round()};0;0;0;0',
    );
    parser.addFreeFloat(
      'CNPJ_Companhia;Data_Referencia;Versao;Percentual_Total_Acoes_Circulacao\n'
      '$_cnpj;2026-12-31;12;61.212000\n'
      '$_cnpj;2025-12-31;9;63.000000',
    );
    parser.addRegister(
      'CNPJ_Companhia;Data_Referencia;Versao;Data_Constituicao;'
      'Setor_Atividade;Especie_Controle_Acionario\n'
      '$_cnpj;2025-01-01;1;1953-10-01;Petróleo e Gás;Privado\n'
      '$_cnpj;2026-01-01;1;1953-10-03;Petróleo e Gás;Estatal Holding',
    );
    parser.addSecurities(
      'CNPJ_Companhia;Valor_Mobiliario;Codigo_Negociacao;Composicao_BDR_Unit;'
      'Data_Fim_Negociacao;Segmento;Data_Inicio_Listagem;Data_Fim_Listagem\n'
      '$_cnpj;Ações Ordinárias;PETR3;;;Nível 2 de Governança Corporativa;1977-07-20;\n'
      // The end of trading filled with its start, as some companies do.
      '$_cnpj;Ações Preferenciais;PETR4;;1977-07-20;Nível 2 de Governança Corporativa;1977-07-20;\n'
      '$_cnpj;Ações Preferenciais;PETR6;;;;2005-01-01;2010-01-01\n'
      '$_cnpj;Ações Ordinárias;9512;;;;;\n'
      '$_cnpj;Debêntures;PETR16;;;;;',
    );
    return parser;
  }

  test('reads the year in reais, consolidated, by the names of accounts', () {
    final company = petrobras(withQuarter: false).build()['009512']!;
    final year = company.years[2025]!;
    expect(year[Figure.revenue], 497549e6);
    expect(year[Figure.grossProfit], 236998e6);
    expect(year[Figure.ebit], 145628e6);
    expect(year[Figure.netIncome], 110605e6);
    expect(year[Figure.depreciation], 84388e6);
    expect(year.ebitda, 230016e6);
    expect(year[Figure.capex], -108714e6);
    expect(year[Figure.dividendsPaid], 45205e6, reason: 'minorities left out');
    expect(year[Figure.cash], 50608e6);
    expect(year[Figure.grossDebt], 384025e6);
    expect(year.netDebt, 333417e6);
    expect(year.freeCashFlow, closeTo(91619e6, 1));
    expect(year[Figure.costs], -260551e6);
    expect(year[Figure.operatingExpenses], -91370e6);
    expect(year[Figure.nonCurrentAssets], 1083363e6);
    expect(year.liabilities, 805802e6);
    expect(year[Figure.cfi], -86114e6);
    expect(year[Figure.cashEnd], 35608e6);
    expect(year.cashChange, closeTo(15354e6, 1));
    expect(company.financial, isFalse);
    expect(company.ttm, same(year));
  });

  test('the last twelve months: last year + this year so far − last year '
      'so far, with the quarter\'s balance', () {
    final company = petrobras().build()['009512']!;
    expect(company.ttmEnd, DateTime(2026, 6, 30));
    expect(company.ttm![Figure.revenue], closeTo(548493e6, 1));
    expect(company.ttm![Figure.netIncome], closeTo(133756e6, 1));
    expect(company.ttm![Figure.equity], 480950e6);
  });

  test('the register: tickers in trade, founding date and control', () {
    final company = petrobras().build()['009512']!;
    expect(
      company.tickers,
      {'PETR3': ShareClass.on, 'PETR4': ShareClass.pn},
      reason: 'a delisted class and a code that is no ticker are left out',
    );
    expect(company.founded, DateTime(1953, 10, 3));
    expect(company.stateControlled, isTrue);
    expect(company.segment, 'Nível 2 de Governança Corporativa');
    expect(company.listed, DateTime(1977, 7, 20));
    expect(company.freeFloat, closeTo(0.61212, 1e-9), reason: 'the newest');
  });

  test('notices: the categories kept, from a date on, by padded CVM code', () {
    const header =
        'CNPJ_Companhia;Nome_Companhia;Codigo_CVM;Data_Referencia;Categoria;'
        'Tipo;Especie;Assunto;Data_Entrega;Tipo_Apresentacao;Protocolo_Entrega;'
        'Versao;Link_Download';
    final found = CvmNotice.parse(
      [
        header,
        '$_cnpj;PETROBRAS;9512;2026-10-28;Fato Relevante;;;Relatório de Produção 3T26;2026-10-28;AP;1;1;https://x/1',
        '$_cnpj;PETROBRAS;9512;2026-10-13;Comunicado ao Mercado;Outros;;;2026-10-13;AP;2;1;https://x/2',
        '$_cnpj;PETROBRAS;9512;2026-10-01;Assembleia;Ata;;Ata;2026-10-01;AP;3;1;https://x/3',
        '$_cnpj;PETROBRAS;9512;2025-01-01;Fato Relevante;;;Antigo;2025-01-01;AP;4;1;https://x/4',
      ].join('\n'),
      DateTime(2025, 11, 1),
    );
    final notices = found['009512']!;
    expect(notices.map((n) => n.subject), ['Relatório de Produção 3T26', 'Outros']);
    expect(notices.first.url, 'https://x/1');
    expect(CvmNotice.fromJson(notices.first.toJson()).date, DateTime(2026, 10, 28));
  });

  test('share counts filed in thousands are found by the earnings per share', () {
    for (final scale in [1.0, 1000.0]) {
      final company = petrobras(shareScale: scale).build()['009512']!;
      expect(company.shares, closeTo(12888732761, 1000), reason: 'scale $scale');
    }
  });

  test('a bank has no EBIT, so no debt or margins', () {
    final parser = CvmParser()
      ..addStatement(
        [
          _flowHeader,
          _flow('2025-12-31', '2025-01-01', '2025-12-31', '3.01', 'Receitas da Intermediação Financeira', 387118, company: '019348'),
          _flow('2025-12-31', '2025-01-01', '2025-12-31', '3.11', 'Lucro ou Prejuízo Líquido Consolidado do Período', 45849, company: '019348'),
        ].join('\n'),
        Statement.dre,
        consolidated: true,
        yearly: true,
      );
    final bank = parser.build()['019348']!;
    expect(bank.financial, isTrue);
    expect(bank.years[2025]![Figure.netIncome], 45849e6);
    expect(bank.years[2025]![Figure.ebit], isNull);
  });

  test('unit compositions as companies write them', () {
    expect(CvmParser.unitComposition('1 ON / 2 PN'), (1, 2));
    expect(CvmParser.unitComposition('1 ON e 2PNs'), (1, 2));
    expect(
      CvmParser.unitComposition('2 ações preferenciais e 1 ação ordinária'),
      (1, 2),
    );
    expect(
      CvmParser.unitComposition('1 ação ordinária e 4 ações preferenciais'),
      (1, 4),
    );
    expect(CvmParser.unitComposition(''), isNull);
  });

  test('which files are read', () {
    expect(Statement.ofFile('dfp_cia_aberta_DRE_con_2025.csv'), (
      Statement.dre,
      true,
    ));
    expect(Statement.ofFile('itr_cia_aberta_DFC_MI_ind_2026.csv'), (
      Statement.dfc,
      false,
    ));
    expect(Statement.ofFile('dfp_cia_aberta_DMPL_con_2025.csv'), isNull);
  });

  test('survives the JSON it is saved in', () {
    final company = petrobras().build()['009512']!;
    final back = CvmCompany.fromJson(company.toJson());
    expect(back.years[2025]![Figure.revenue], 497549e6);
    expect(back.ttm![Figure.revenue], company.ttm![Figure.revenue]);
    expect(back.tickers, company.tickers);
    expect(back.shares, company.shares);
    expect(back.founded, company.founded);
  });
}
