#!/usr/bin/env python3
"""Gera o que cada ticker da B3 é, pelo cadastro de instrumentos da própria
B3: ação, unit, FII, Fiagro, fundo de infraestrutura, FIDC, outro fundo, ETF,
BDR de empresa ou BDR de ETF. Para o BDR de empresa, também o ticker dela na
SEC, que dá a Análise e o Comparar da empresa de fora.

Fontes:
  B3, cadastro de instrumentos listados (arquivo público do dia):
    arquivos.b3.com.br/api/download/requestname?fileName=InstrumentsConsolidated
  SEC, lista de empresas listadas nos EUA e de séries de fundos (ETFs), com o
  contato de private/sec_contact:
    www.sec.gov/files/company_tickers_exchange.json
    www.sec.gov/files/investment/data/other/.../investment_company_series_class.csv
  CVM, para o CNPJ de cada fundo listado (os informes são por CNPJ):
    FIAGRO/DOC/INF_MENSAL (ISIN → CNPJ), FI/DOC/CDA (carteiras: o código de
    negociação e o CNPJ que os fundos informam das cotas que têm), FI/CAD
    (nome → CNPJ, só nome idêntico e único) e FI/DOC/INF_DIARIO (confere que
    o CNPJ tem informe).

O BDR de ETF ganha a série da SEC (para o N-PORT, a carteira do ETF) quando o
nome bate ou quando o ticker é a raiz do BDR (com ou sem o B da frente:
BAGG39 → AGG) e os nomes têm uma palavra em comum além da gestora.

O BDR só ganha o ticker da SEC quando o nome bate (normalizado) ou quando o
ticker da SEC é a raiz do BDR (D1HI34 → DHI) e os nomes têm uma palavra em
comum. Nada de aproximação além disso: ticker errado é análise de outra
empresa.

Saída:
  lib/investments/b3-instruments.dart

Uso: python3 scripts/b3_instruments.py   (repetir de tempos em tempos)
"""

import collections
import csv
import datetime
import io
import json
import re
import sys
import unicodedata
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DART = ROOT / 'lib/investments/b3-instruments.dart'
B3 = 'https://arquivos.b3.com.br/api/download'
SEC = 'https://www.sec.gov/files/company_tickers_exchange.json'
SEC_SERIES = ('https://www.sec.gov/files/investment/data/other/'
              'investment-company-series-and-class-information/'
              'investment_company_series_class.csv')
CVM = 'https://dados.cvm.gov.br/dados'
UA = {'User-Agent': 'aupp-b3-instruments/1.0'}


def get(url, headers=UA):
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=180) as response:
        return response.read()


def b3_file():
    """The newest register the B3 has, from today back a week."""
    day = datetime.date.today()
    for _ in range(8):
        try:
            token = json.loads(get(
                f'{B3}/requestname?fileName=InstrumentsConsolidated'
                f'&date={day.isoformat()}'))['token']
            body = get(f'{B3}/?token={token}')
            if body.count(b'\n') > 1000:
                return day, body.decode('latin1')
        except Exception as e:  # no file that day (weekend, holiday)
            print(f'  {day}: {e}', file=sys.stderr)
        day -= datetime.timedelta(days=1)
    sys.exit('Cadastro da B3 não encontrado na última semana')


def fund_type(name):
    n = unicodedata.normalize('NFKD', name).encode('ascii', 'ignore').decode()
    n = n.upper()
    if 'FIAGRO' in n:
        return 'G'
    if 'INFRA' in n or re.search(r'\bINC(\.|ENTIVAD)', n):
        return 'I'
    if 'DIREITOS CRED' in n or 'FIDC' in n:
        return 'D'
    if 'IMOB' in n or re.search(r'\bFII\b|\bFUII\b', n):
        return 'F'
    return 'P'


SUFFIX = (r'\b(inc|incorporated|corp|corporation|co|cos|company|companies|'
          r'ltd|limited|plc|public limited company|sa|sab de cv|sab|de cv|'
          r's a|ag|nv|n v|se|spa|holdings?|group|the|ads|adr|lp|llc|new|'
          r'public joint stock|pjsc|asa|ab|oyj|kk|bhd|tbk)\b')


def norm(name):
    s = unicodedata.normalize('NFKD', name).encode('ascii', 'ignore').decode()
    s = s.lower().split(' - ')[0]
    s = re.sub(r'\s*/.*$', '', s).replace('&', ' and ')
    s = re.sub(r'[^a-z0-9 ]', ' ', s)
    return ' '.join(re.sub(SUFFIX, ' ', s).split())


def sec_index():
    contact = (ROOT / 'private/sec_contact')
    if not contact.exists():
        print('Sem private/sec_contact: BDRs ficam sem o ticker da SEC',
              file=sys.stderr)
        return {}, {}
    data = json.loads(get(SEC, {
        'User-Agent': f'AUPP {contact.read_text().strip()}'}))
    fields = data['fields']
    cik, name, ticker = (fields.index(f) for f in ('cik', 'name', 'ticker'))
    main, by_name, by_ticker = {}, {}, {}
    # The first row of a company is its main listing.
    for row in data['data']:
        main.setdefault(row[cik], row[ticker])
        by_name.setdefault(norm(row[name]), (main[row[cik]], row[name]))
        by_ticker.setdefault(row[ticker], (row[ticker], row[name]))
    return by_name, by_ticker


def sec_of(name, root, by_name, by_ticker):
    found = by_name.get(norm(name))
    if found:
        return found
    root = re.sub(r'\d', '', root)
    words = set(norm(name).split())
    for ticker in {root, root[:3]}:
        candidate = by_ticker.get(ticker)
        if (candidate and len(ticker) >= 3
                and words & set(norm(candidate[1]).split())):
            return candidate
    return None


SMALL = {'ETF', 'ETP', 'MSCI', 'S&P', 'USD', 'US', 'U.S.', 'AI', 'ESG', 'REIT',
         'ARK', 'SPDR', 'II', 'III', 'ACWI', 'EAFE', 'EM', 'UK', 'JPM'}
SPELLED = {'ISHARES': 'iShares', 'VANECK': 'VanEck', 'WISDOMTREE': 'WisdomTree',
           '21SHARES': '21Shares', 'JPMORGAN': 'JPMorgan',
           'PROSHARES': 'ProShares', 'INVESCO': 'Invesco'}


def readable(name):
    """B3 names are upper case: "ISHARES CORE S&P 500 ETF" → "iShares Core
    S&P 500 ETF"."""
    words = []
    for word in name.split():
        upper = word.upper()
        if upper in SPELLED:
            words.append(SPELLED[upper])
        elif upper in SMALL or any(c.isdigit() for c in word):
            words.append(upper)
        else:
            words.append(word[:1].upper() + word[1:].lower())
    return ' '.join(words)


def sec_name(name):
    """"Apple Inc." as is; "TESLA, INC." → "Tesla, Inc."."""
    plain = re.sub(r'\s*/[A-Z]{2,}/?$|/$', '', name).strip()
    return plain if plain != plain.upper() else readable(plain)


def zip_csvs(url, prefix=''):
    """The CSVs inside a CVM zip, as lists of dicts."""
    with zipfile.ZipFile(io.BytesIO(get(url))) as z:
        for name in z.namelist():
            if name.endswith('.csv') and name.startswith(prefix):
                text = z.read(name).decode('latin1')
                yield name, list(csv.DictReader(io.StringIO(text),
                                                delimiter=';'))


def months_back(count, skip=0):
    day = datetime.date.today().replace(day=1)
    for _ in range(skip):
        day = (day - datetime.timedelta(days=1)).replace(day=1)
    for _ in range(count):
        yield day.strftime('%Y%m')
        day = (day - datetime.timedelta(days=1)).replace(day=1)


def digits(cnpj):
    return re.sub(r'\D', '', cnpj or '')


def fiagro_by_isin():
    """Fiagros report their ISIN: exact. Also every Fiagro that reports."""
    out, reporting = {}, set()
    for month in months_back(6):
        try:
            for _, rows in zip_csvs(f'{CVM}/FIAGRO/DOC/INF_MENSAL/DADOS/'
                                    f'inf_mensal_fiagro_{month}.zip',
                                    'inf_mensal_fiagro_2'):
                for r in rows:
                    reporting.add(digits(r['CNPJ_Classe']))
                    if r.get('Codigo_ISIN'):
                        out.setdefault(r['Codigo_ISIN'].strip(),
                                       digits(r['CNPJ_Classe']))
        except Exception as e:
            print(f'  Fiagro {month}: {e}', file=sys.stderr)
    return out, reporting


TICKER_IN = re.compile(r'\b([A-Z0-9]{4}1[1-5])\b')


def cda_pairs():
    """Ticker → CNPJ as the funds holding it write them in their portfolios
    (the block of other assets). Kept when the funds agree."""
    seen = collections.defaultdict(collections.Counter)
    found = 0
    for month in months_back(6, skip=1):
        try:
            for _, rows in zip_csvs(f'{CVM}/FI/DOC/CDA/DADOS/'
                                    f'cda_fi_{month}.zip', 'cda_fi_BLC_8'):
                for r in rows:
                    m = TICKER_IN.search((r.get('DS_ATIVO') or '').upper())
                    cnpj = digits(r.get('CPF_CNPJ_EMISSOR'))
                    if m and len(cnpj) == 14:
                        seen[m.group(1)][cnpj] += 1
            found += 1
        except Exception as e:
            print(f'  CDA {month}: {e}', file=sys.stderr)
        if found == 2:
            break
    out = {}
    for ticker, counts in seen.items():
        (cnpj, n), = counts.most_common(1)
        if n >= 2 and n >= 0.9 * sum(counts.values()):
            out[ticker] = cnpj
    return out


FUND_WORDS = (r'\b(fundo|fdo|fd|de|do|da|dos|das|em|investimento|invest|inv|'
              r'cotas|cota|classe|indice|ind|responsabilidade|resp|limitada|'
              r'lim|ltda|rl|fi|fic|fif|sa|e|ie)\b')


def fund_key(name):
    s = unicodedata.normalize('NFKD', name).encode('ascii', 'ignore').decode()
    s = re.sub(r'[^a-z0-9 ]', ' ', s.lower())
    return ' '.join(re.sub(FUND_WORDS, ' ', s).split())


GENERIC = set(
    'fundo fdo fd invest inv cotas cota fic fi fif infra inf infraestrutura '
    'incentivado incentivados inc renda fixa rf cp credito cred privado priv '
    'fiagro agro agronegocio cadeias produtivas prod nas dc rl '
    'responsabilidade limitada lim ie direitos creditorios fidc imobiliario '
    'imob'.split())


STRUCTURE = set(
    'fdo fundo fd fi fic fif fii fiagro fidc fip fia fiim cic resp '
    'responsabilidade rl ltda limitada classe cl'.split())


def brand(name):
    """What names the fund, before the words of its structure:
    "KINEA INFRA - FDO INV COTAS..." and "KINEA INFRA FIF CIC..." are both
    ("kinea", "infra"); "FII BTG PACTUAL CRÉDITO IMOBILIÁRIO RESP LIM" and
    "BTG PACTUAL CRÉDITO IMOBILIÁRIO - FUNDO DE CRI" both ("btg", "pactual",
    "credito", "imobiliario")."""
    s = unicodedata.normalize('NFKD', name).encode('ascii', 'ignore').decode()
    s = re.split(r'\s[-\u2013\x96]\s', s.lower())[0]
    words = re.sub(r'[^a-z0-9 ]', ' ', s).split()
    while words and words[0] in STRUCTURE:
        words.pop(0)
    out = []
    for word in words:
        if word in STRUCTURE:
            break
        out.append(word)
    return tuple(out)


def leading(key, count):
    return tuple(
        [w for w in key.split() if w not in GENERIC and w not in STRUCTURE][:count]
    )


def cvm_names():
    """Name → CNPJ of the funds in operation, only names that are unique;
    every CNPJ in operation; and the closed ones (all listed funds are) by
    their first two words that say which fund it is, when only one has
    them."""
    names = collections.defaultdict(set)
    operating = {}
    closed = collections.defaultdict(set)
    brands = collections.defaultdict(set)
    for name, rows in zip_csvs(f'{CVM}/FI/CAD/DADOS/registro_fundo_classe.zip'):
        cnpj_col = 'CNPJ_Classe' if 'classe' in name else 'CNPJ_Fundo'
        if 'subclasse' in name:
            continue
        for r in rows:
            if r.get('Situacao') == 'Em Funcionamento Normal':
                cnpj = digits(r[cnpj_col])
                key = fund_key(r['Denominacao_Social'])
                operating[cnpj] = r['Denominacao_Social']
                names[key].add(cnpj)
                if r.get('Forma_Condominio') == 'Fechado':
                    for n in (2, 3):
                        if len(leading(key, n)) == n:
                            closed[leading(key, n)].add(cnpj)
                    if len(brand(r['Denominacao_Social'])) >= 2:
                        brands[brand(r['Denominacao_Social'])].add(cnpj)
    unique = {k: next(iter(v)) for k, v in names.items() if len(v) == 1 and k}
    return unique, operating, closed, brands


def fii_cnpjs():
    """FIIs with a monthly report this year or the last."""
    out = set()
    year = datetime.date.today().year
    for y in (year, year - 1):
        try:
            for name, rows in zip_csvs(f'{CVM}/FII/DOC/INF_MENSAL/DADOS/'
                                       f'inf_mensal_fii_{y}.zip',
                                       'inf_mensal_fii_geral'):
                out |= {digits(r['CNPJ_Fundo_Classe']) for r in rows}
        except Exception as e:
            print(f'  FII {y}: {e}', file=sys.stderr)
    return out


def daily_cnpjs():
    """Funds with a daily report (where the numbers of an ETF come from)."""
    for month in months_back(2):
        try:
            for _, rows in zip_csvs(f'{CVM}/FI/DOC/INF_DIARIO/DADOS/'
                                    f'inf_diario_fi_{month}.zip'):
                return {digits(r['CNPJ_FUNDO_CLASSE']) for r in rows}
        except Exception as e:
            print(f'  informe diário {month}: {e}', file=sys.stderr)
    return set()


SPONSORS = {'ishares', 'vanguard', 'spdr', 'invesco', 'global', 'x', 'jpmorgan',
            'betabuilders', 'wisdomtree', 'vaneck', 'xtrackers', 'first',
            'schwab', 'core', 'msci', 'us', 'ark', 'proshares', 'franklin',
            'pimco', 'fidelity', 'select', 'sector', 'and', 'of'}


def etf_key(name):
    s = unicodedata.normalize('NFKD', name).encode('ascii', 'ignore').decode()
    s = s.lower().replace('u.s.', 'us').replace('&', ' and ').replace('/', ' ')
    s = re.sub(r'[^a-z0-9 ]', ' ', s)
    s = re.sub(r'\b(the|fund|trust|shares|etf|etp|index|ucits|exch tf)\b',
               ' ', s)
    return ' '.join(s.split())


def sec_series(contact):
    """ETF series: name and ticker → (ticker, "series:class", name). The class
    is the one of that ticker: a series with several classes reports the
    return of each."""
    text = get(SEC_SERIES, {'User-Agent': f'AUPP {contact}'}).decode('latin1')
    by_name, by_ticker = {}, {}
    for r in csv.DictReader(io.StringIO(text)):
        ticker = r['class_ticker_symbol']
        if ticker in ('', '[NULL]') or not r['series_id'].startswith('S'):
            continue
        value = (ticker, f"{r['series_id']}:{r['class_id']}", r['series_name'])
        by_name.setdefault(etf_key(r['series_name']), value)
        by_ticker.setdefault(ticker, value)
    return by_name, by_ticker


def etf_of(name, root, by_name, by_ticker):
    found = by_name.get(etf_key(name))
    if found:
        return found
    words = set(etf_key(name).split()) - SPONSORS
    for ticker in (root, root[1:]):
        candidate = by_ticker.get(ticker)
        if candidate and words & set(etf_key(candidate[2]).split()):
            return candidate
    return None


def dart(text):
    return "'" + text.replace('\\', '\\\\').replace("'", "\\'") + "'"


def main():
    day, text = b3_file()
    lines = text.splitlines()
    rows = list(csv.DictReader(io.StringIO('\n'.join(lines[1:])),
                               delimiter=';'))
    by_name, by_ticker = sec_index()
    contact = ROOT / 'private/sec_contact'
    etf_names, etf_tickers = (sec_series(contact.read_text().strip())
                              if contact.exists() else ({}, {}))
    print('CVM: Fiagros, carteiras, cadastro e informe diário…')
    (fiagros, fiagro_reports), pairs = fiagro_by_isin(), cda_pairs()
    daily, fiis = daily_cnpjs(), fii_cnpjs()
    names, operating, closed, brands = cvm_names()

    # An ETF has no daily report: only the register (equity, manager). A
    # fund matched by its first words must have its report.
    def cnpj_of(ticker, kind, name, isin):
        if kind == 'G' and isin in fiagros:
            return fiagros[isin]
        if kind not in 'EXIDPGF':
            return None
        reports = (operating if kind in 'EX'
                   else fiagro_reports if kind == 'G'
                   else fiis if kind == 'F' else daily)
        for cnpj in (pairs.get(ticker), names.get(fund_key(name))):
            if cnpj in reports:
                return cnpj
        if kind in 'EX':
            return None
        found = brands.get(brand(name), set()) & reports
        if len(found) == 1:
            return next(iter(found))
        key = fund_key(name)
        for n in (3, 2):
            words = leading(key, n)
            found = closed.get(words, set()) if len(words) == n else set()
            if len(found) == 1 and next(iter(found)) in reports:
                return next(iter(found))
        return None

    out = {}
    for r in rows:
        if r['SgmtNm'] != 'CASH' or r['MktNm'] != 'EQUITY-CASH':
            continue
        ticker, kind = r['TckrSymb'].strip(), r['SctyCtgyNm'].strip()
        name = r['CrpnNm'].strip()
        spec = r['SpcfctnCd'].split()[0] if r['SpcfctnCd'].strip() else ''
        isin = r['ISIN'].strip()
        if kind == 'SHARES':
            out[ticker] = ('A', None, None, None)
        elif kind == 'UNIT':
            out[ticker] = ('U', None, None, None)
        elif kind in ('FUNDS', 'ETF FOREIGN INDEX') or kind.startswith('ETF'):
            code = (fund_type(name) if kind == 'FUNDS'
                    else 'X' if kind == 'ETF FOREIGN INDEX' else 'E')
            cnpj = cnpj_of(ticker, code, name, isin)
            # The B3's name is short ("CAPITÂNIA FDO. INV. FINANCEIRO IE.
            # RF."); the CVM's says what it is.
            if code == 'P' and cnpj in operating:
                code = fund_type(operating[cnpj])
            out[ticker] = (code, None, None, cnpj)
        elif kind == 'BDR' and spec == 'DRE':
            found = etf_of(name, r['Asst'], etf_names, etf_tickers)
            out[ticker] = ('T', readable(name), found[0] if found else None,
                           found[1] if found else None)
        elif kind == 'BDR':
            found = sec_of(name, r['Asst'], by_name, by_ticker)
            out[ticker] = ('B', sec_name(found[1]) if found else readable(name),
                           found[0] if found else None, None)
    def count(codes, field):
        rows = [v for v in out.values() if v[0] in codes]
        return f'{sum(1 for v in rows if v[field])} de {len(rows)}'
    print(f'{day}: {len(out)} instrumentos')
    print(f'  BDR de empresa com ticker da SEC: {count("B", 2)}')
    print(f'  BDR de ETF com série da SEC: {count("T", 3)}')
    print(f'  FII com CNPJ: {count("F", 3)}')
    print(f'  Fiagro com CNPJ: {count("G", 3)}')
    print(f'  ETF com CNPJ: {count("EX", 3)}')
    print(f'  Outros fundos com CNPJ: {count("IDP", 3)}')
    with DART.open('w') as f:
        f.write('// Gerado por scripts/b3_instruments.py (cadastro de '
                f'instrumentos da B3 de {day.isoformat()}\n'
                '// e lista da SEC). Não editar à mão.\n\n'
                '/// What each ticker traded on the B3 is: A share, '
                'U unit, F FII, G Fiagro,\n'
                '/// I infrastructure fund, D FIDC, P other fund, E ETF, '
                'X ETF of an index abroad,\n'
                '/// B BDR of a company, T BDR of an ETF. Then the name abroad '
                '(BDRs), the ticker\n'
                '/// abroad (at the SEC) and an id: the SEC series of an ETF '
                'abroad, or the\n'
                '/// CNPJ of a fund here (its reports to the CVM). Null when '
                'not found for sure.\n'
                'const Map<String, (String, String?, String?, String?)> '
                'b3Instruments = {\n')
        for ticker in sorted(out):
            kind, name, abroad, ident = out[ticker]
            f.write(f"  {dart(ticker)}: ({dart(kind)}, "
                    f"{dart(name) if name else 'null'}, "
                    f"{dart(abroad) if abroad else 'null'}, "
                    f"{dart(ident) if ident else 'null'}),\n")
        f.write('};\n')


if __name__ == '__main__':
    main()
