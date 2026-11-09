import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aupp/investments/asset-sheet.dart';
import 'package:aupp/investments/cvm-funds.dart';
import 'package:aupp/investments/fund-compare-page.dart';
import 'package:aupp/investments/sec-fund.dart';

String nport({
  required String date,
  required List<String> returns,
  String holdings = '',
}) =>
    '''
<edgarSubmission><formData><genInfo><seriesName>Exemplo Total Market &amp; Bond ETF</seriesName>
<repPdEnd>2027-03-31</repPdEnd><repPdDate>$date</repPdDate></genInfo>
<fundInfo><totAssets>1100.5</totAssets><netAssets>1000.25</netAssets>
<returnInfo><monthlyTotReturns><monthlyTotReturn classId="C1" rtn1="${returns[0]}" rtn2="${returns[1]}" rtn3="${returns[2]}"/></monthlyTotReturns></returnInfo></fundInfo>
<invstOrSecs>$holdings</invstOrSecs></formData></edgarSubmission>''';

String holding(String name, double pct, String cat, String country) =>
    '<invstOrSec><name>$name</name><title>$name A</title>'
    '<pctVal>$pct</pctVal><assetCat>$cat</assetCat>'
    '<invCountry>$country</invCountry></invstOrSec>';

File zipOf(Directory dir, String name, Map<String, String> csvs) {
  final archive = Archive();
  for (final e in csvs.entries) {
    final bytes = latin1.encode(e.value);
    archive.addFile(ArchiveFile(e.key, bytes.length, bytes));
  }
  final file = File('${dir.path}/$name');
  file.writeAsBytesSync(ZipEncoder().encode(archive));
  return file;
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('fund_data'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('SEC: N-PORT of an ETF', () {
    test('net assets, months of the quarter and positions', () {
      final f = readNport(
        nport(
          date: '2026-06-30',
          returns: ['1.5', '-2', '3'],
          holdings: [
            holding('Empresa Um', 6, 'EC', 'US'),
            holding('Empresa Dois', 4, 'EC', 'IE'),
            holding('Empresa Um', 1, 'EC', 'US'),
            holding('Caixa', 0.5, 'STIV', 'US'),
            holding('Futuro', 0.1, 'DE', 'US'),
          ].join(),
        ),
      )!;
      expect(f.name, 'Exemplo Total Market & Bond ETF');
      expect(f.netAssets, 1000.25);
      expect(f.positions, 5);
      expect(f.months.map((m) => m.$1), [
        DateTime(2026, 4, 30),
        DateTime(2026, 5, 31),
        DateTime(2026, 6, 30),
      ]);
      expect(f.months.map((m) => m.$2), [0.015, -0.02, 0.03]);
      expect(f.holdings['Empresa Um'], closeTo(0.07, 1e-9));
      expect(f.byKind['Ações'], closeTo(0.11, 1e-9));
      expect(f.byKind['Caixa e aplicações curtas'], closeTo(0.005, 1e-9));
      expect(f.byKind['Derivativos'], closeTo(0.001, 1e-9));
      expect(f.byCountry['Irlanda'], closeTo(0.04, 1e-9));
    });

    test('a year of months from four reports, positions from the newest', () {
      NportFiling quarter(String date, String r, String top) => readNport(
        nport(
          date: date,
          returns: [r, r, r],
          holdings: holding(top, 10, 'EC', 'US'),
        ),
      )!;
      final report = reportOf('S1', [
        quarter('2026-06-30', '1', 'Nova'),
        quarter('2026-03-31', '1', 'Velha'),
        quarter('2025-12-31', '1', 'Velha'),
        quarter('2025-09-30', '1', 'Velha'),
      ], DateTime(2026, 9, 1));
      expect(report.months, hasLength(12));
      expect(report.months.first.$1, DateTime(2025, 7, 31));
      expect(report.top.single.name, 'Nova');
      expect(report.returnOver(3), closeTo(1.01 * 1.01 * 1.01 - 1, 1e-9));
      expect(report.returnOver(12), isNotNull);
      expect(report.returnOver(13), isNull);
      final again = EtfReport.fromJson(
        jsonDecode(jsonEncode(report.toJson())) as Map<String, dynamic>,
      );
      expect(again.months, report.months);
      expect(again.byKind, report.byKind);
    });

    test('the returns are those of the class of the ticker', () {
      const xml = '''
<seriesName>Fundo Exemplo</seriesName><repPdDate>2026-06-30</repPdDate><netAssets>10</netAssets>
<monthlyTotReturn classId="C1" rtn1="1" rtn2="1" rtn3="1"/>
<monthlyTotReturn classId="C2" rtn1="2" rtn2="2" rtn3="2"/>''';
      expect(readNport(xml)!.months.first.$2, 0.01);
      expect(readNport(xml, share: 'C2')!.months.first.$2, 0.02);
      expect(readNport(xml, share: 'C9')!.months.first.$2, 0.01);
      expect(readNport(xml)!.classes, 2);
    });

    test('the feed lists the original filings, not the amendments', () {
      const atom = '''
<feed><entry><filing-href>https://www.sec.gov/Archives/edgar/data/1/0001/0001-index.htm</filing-href><filing-type>NPORT-P</filing-type></entry>
<entry><filing-href>https://www.sec.gov/Archives/edgar/data/1/0002/0002-index.htm</filing-href><filing-type>NPORT-P/A</filing-type></entry></feed>''';
      expect(nportFilings(atom).map((u) => u.toString()), [
        'https://www.sec.gov/Archives/edgar/data/1/0001/primary_doc.xml',
      ]);
    });

    test('fund tickers give the series', () {
      final series = parseFundTickers(
        jsonEncode({
          'fields': ['cik', 'seriesId', 'classId', 'symbol'],
          'data': [
            [1, 'S0001', 'C0001', 'XMPL'],
            [2, 'S0002', 'C0002', null],
          ],
        }),
      );
      expect(series, {'XMPL': 'S0001:C0001'});
    });
  });

  group('CVM: listed funds', () {
    const cnpj = '11222333000144';
    test('register: the class, its fund and the fund start', () {
      final zip = zipOf(dir, 'registro.zip', {
        'registro_fundo.csv':
            'ID_Registro_Fundo;CNPJ_Fundo;Denominacao_Social;Data_Constituicao;'
            'Gestor;Administrador\n'
            '7;99888777000166;FUNDO EXEMPLO;2010-05-01;GESTORA EXEMPLO;ADM EXEMPLO\n',
        'registro_classe.csv':
            'ID_Registro_Fundo;CNPJ_Classe;Denominacao_Social;Data_Constituicao;'
            'Patrimonio_Liquido;Data_Patrimonio_Liquido\n'
            '7;$cnpj;CLASSE EXEMPLO;2025-04-01;1500000.50;2026-11-03\n'
            '8;55444333000122;OUTRA;2025-04-01;1;2026-11-03\n',
        'registro_subclasse.csv': 'x\n',
      });
      final funds = readRegister(zip.readAsBytesSync(), {cnpj});
      expect(funds.keys, [cnpj]);
      final f = funds[cnpj]!;
      expect(f.name, 'CLASSE EXEMPLO');
      expect(f.manager, 'GESTORA EXEMPLO');
      expect(f.since, DateTime(2010, 5, 1));
      expect(f.equity, 1500000.50);
    });

    test('daily report: quota, holders and flows; subclasses left out', () {
      final zip = zipOf(dir, 'inf_diario.zip', {
        'inf_diario_fi_202611.csv':
            'TP_FUNDO_CLASSE;CNPJ_FUNDO_CLASSE;ID_SUBCLASSE;DT_COMPTC;VL_TOTAL;'
            'VL_QUOTA;VL_PATRIM_LIQ;CAPTC_DIA;RESG_DIA;NR_COTST\n'
            'CLASSES - FIF;11.222.333/0001-44;;2026-11-04;0;101.5;2000;50;20;300\n'
            'CLASSES - FIF;11.222.333/0001-44;;2026-11-03;0;101.0;1990;0;0;299\n'
            'CLASSES - FIF;11.222.333/0001-44;SUB1;2026-11-04;0;9;9;0;0;1\n',
      });
      final days = readDaily(zip.readAsBytesSync(), {cnpj})[cnpj]!;
      expect(days.map((d) => d.date), [
        DateTime(2026, 11, 3),
        DateTime(2026, 11, 4),
      ]);
      expect(days.last.quota, 101.5);
      expect(days.last.holders, 300);
      expect(days.last.flow, 30);
    });

    test('Fiagro: income per quota from reais, not the reported yield', () {
      final zip = zipOf(dir, 'fiagro.zip', {
        'inf_mensal_fiagro_202609.csv':
            'CNPJ_Classe;Data_Referencia;Numero_Cotistas;Patrimonio_Liquido;'
            'Cotas_Emitidas;Valor_Patrimonial_Cotas;Dividend_Yield_Mes;'
            'Rendimentos_Distribuir\n'
            '$cnpj;2026-09-01;1200;5000000;50000;100;0.01;50000\n'
            '55444333000122;2026-09-01;1;1;1;1;1;0\n',
        'inf_mensal_fiagro_subclasse_202609.csv': 'CNPJ_Classe\n$cnpj\n',
      });
      final m = readFiagro(zip.readAsBytesSync(), {cnpj})[cnpj]!.single;
      expect(m.date, DateTime(2026, 9));
      expect(m.holders, 1200);
      expect(m.bookPerShare, 100);
      expect(m.dividendPerShare, 1);
      expect(m.dividendYield, closeTo(0.01, 1e-12));
    });

    test('months of separate files in one list, a later file winning', () {
      final merged = mergeParts(FundReports.daily, [
        {
          'a': [
            ['2026-10-02', 2],
            ['2026-10-01', 1],
          ],
        },
        {
          'a': [
            ['2026-10-02', 3],
          ],
          'b': [
            ['2026-11-01', 9],
          ],
        },
      ]);
      expect(merged['a'], [
        ['2026-10-01', 1],
        ['2026-10-02', 3],
      ]);
      expect(merged['b'], hasLength(1));
    });

    test('quota change, flows and the year of yields', () {
      final days = [
        for (var i = 0; i <= 400; i += 10)
          FundDay(
            DateTime(2025, 10, 1).add(Duration(days: i)),
            100 + i / 10,
            1000,
            10,
            1,
          ),
      ];
      final fund = CvmFund('1', days: days);
      final last = days.last;
      final yearAgo = days.firstWhere(
        (d) => !d.date.isBefore(last.date.subtract(const Duration(days: 365))),
      );
      expect(fund.quotaChange(365), closeTo(last.quota / yearAgo.quota - 1, 1e-12));
      expect(fund.quotaChange(800), isNull);
      expect(fund.flowOver(30), 3);
      final months = [
        for (var m = 1; m <= 12; m++)
          FundMonth(DateTime(2026, m), bookPerShare: 100, dividendPerShare: 1),
      ];
      expect(CvmFund('1', months: months).yearYield, closeTo(0.12, 1e-12));
      expect(CvmFund('1', months: months.sublist(1)).yearYield, isNull);
    });
  });

  test('Comparar groups each fund with its peers', () {
    expect(peersOf(B3Type.infra), {B3Type.infra, B3Type.fidc, B3Type.fund});
    expect(peersOf(B3Type.etfAbroad), {B3Type.etf, B3Type.etfAbroad});
    final fiagros = listedOf({B3Type.fiagro});
    expect(fiagros, isNotEmpty);
    expect(fiagros.every((f) => f.$2.cnpj != null), isTrue);
    expect(
      listedOf({B3Type.bdrEtf}).every((f) => f.$2.secSeries != null),
      isTrue,
    );
  });
}
