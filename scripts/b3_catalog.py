#!/usr/bin/env python3
"""Gera o catálogo de ativos da B3 (ações, units, FIIs, ETFs) usado na aba
Investimentos: nome legível e logo por raiz do ticker (PETR3/PETR4 → PETR).

Fonte: lista pública do brapi.dev (sem token) e os ícones SVG de
icons.brapi.dev, convertidos para PNG 128 px com rsvg-convert (o app não
renderiza SVG). Logos idênticos viram um arquivo só.

Saída:
  assets/images/stocks/<raiz>.png
  lib/investments/b3-catalog.dart

Uso: python3 scripts/b3_catalog.py   (repetir de tempos em tempos)
"""

import hashlib
import json
import re
import subprocess
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / 'assets/images/stocks'
DART = ROOT / 'lib/investments/b3-catalog.dart'
CACHE = ROOT / 'build/b3_cache'
PLACEHOLDER = 'BRAPI.svg'
UA = {'User-Agent': 'aupp-b3-catalog/1.0'}

# Nomes oficiais da B3 são longos e sem acento; os mais negociados ganham
# o nome pelo qual são conhecidos.
NAMES = {
    'ABEV': 'Ambev', 'ALOS': 'Allos', 'ALPA': 'Alpargatas', 'AMER': 'Americanas',
    'ASAI': 'Assaí', 'AURE': 'Auren', 'AZUL': 'Azul', 'AZZA': 'Azzas 2154',
    'B3SA': 'B3', 'BBAS': 'Banco do Brasil', 'BBDC': 'Bradesco',
    'BBSE': 'BB Seguridade', 'BEEF': 'Minerva', 'BHIA': 'Casas Bahia',
    'BPAC': 'BTG Pactual', 'BRAP': 'Bradespar', 'BRAV': 'Brava Energia',
    'BRFS': 'BRF', 'BRKM': 'Braskem', 'CASH': 'Méliuz', 'CMIG': 'Cemig',
    'CMIN': 'CSN Mineração', 'COGN': 'Cogna', 'CPFE': 'CPFL Energia',
    'CPLE': 'Copel', 'CRFB': 'Carrefour Brasil', 'CSAN': 'Cosan',
    'CSMG': 'Copasa', 'CSNA': 'CSN', 'CURY': 'Cury', 'CVCB': 'CVC',
    'CXSE': 'Caixa Seguridade', 'CYRE': 'Cyrela', 'DIRR': 'Direcional',
    'DXCO': 'Dexco', 'ECOR': 'EcoRodovias', 'EGIE': 'Engie Brasil',
    'ELET': 'Eletrobras', 'EMBR': 'Embraer', 'ENEV': 'Eneva',
    'ENGI': 'Energisa', 'EQTL': 'Equatorial', 'EZTC': 'EZTec',
    'FLRY': 'Fleury', 'GGBR': 'Gerdau', 'GOAU': 'Metalúrgica Gerdau',
    'GOLL': 'Gol', 'GRND': 'Grendene', 'HAPV': 'Hapvida', 'HYPE': 'Hypera',
    'IGTI': 'Iguatemi', 'INTB': 'Intelbras', 'IRBR': 'IRB Re',
    'ITSA': 'Itaúsa', 'ITUB': 'Itaú Unibanco', 'JBSS': 'JBS',
    'JHSF': 'JHSF', 'KLBN': 'Klabin', 'LREN': 'Lojas Renner',
    'MDIA': 'M. Dias Branco', 'MGLU': 'Magazine Luiza', 'MOVI': 'Movida',
    'MRFG': 'Marfrig', 'MRVE': 'MRV', 'MULT': 'Multiplan', 'NTCO': 'Natura',
    'PETR': 'Petrobras', 'PETZ': 'Petz', 'POMO': 'Marcopolo', 'PRIO': 'PRIO',
    'PSSA': 'Porto Seguro', 'RADL': 'Raia Drogasil', 'RAIL': 'Rumo',
    'RAIZ': 'Raízen', 'RDOR': "Rede D'Or", 'RECV': 'PetroReconcavo',
    'RENT': 'Localiza', 'SANB': 'Santander', 'SAPR': 'Sanepar',
    'SBSP': 'Sabesp', 'SLCE': 'SLC Agrícola', 'SMTO': 'São Martinho',
    'SUZB': 'Suzano', 'TAEE': 'Taesa', 'TIMS': 'TIM', 'TOTS': 'Totvs',
    'UGPA': 'Ultrapar', 'USIM': 'Usiminas', 'VALE': 'Vale', 'VAMO': 'Vamos',
    'VBBR': 'Vibra Energia', 'VIVA': 'Vivara', 'VIVT': 'Vivo',
    'WEGE': 'WEG', 'YDUQ': 'Yduqs', 'BOVA': 'iShares Ibovespa',
    'IVVB': 'iShares S&P 500', 'SMAL': 'iShares Small Cap',
    'HASH': 'Hashdex Nasdaq Crypto', 'MXRF': 'Maxi Renda',
    'HGLG': 'CSHG Logística', 'KNRI': 'Kinea Renda Imobiliária',
    'XPML': 'XP Malls', 'VISC': 'Vinci Shopping Centers',
    'BTLG': 'BTG Pactual Logística', 'XPLG': 'XP Log',
    'KNCR': 'Kinea Rendimentos Imobiliários', 'HGRU': 'CSHG Renda Urbana',
    'BRSR': 'Banrisul', 'PCAR': 'GPA', 'NATU': 'Natura', 'CEAB': 'C&A',
    'SMFT': 'Smart Fit', 'PGMN': 'Pague Menos', 'MOTV': 'Motiva',
    'QUAL': 'Qualicorp', 'ONCO': 'Oncoclínicas', 'DASA': 'Dasa',
    'MBRF': 'MBRF', 'TEND': 'Tenda', 'LWSA': 'LWSA', 'RIAA': 'Riachuelo',
    'CBAV': 'CBA', 'PASS': 'Compass', 'EMBJ': 'Embraer', 'AXIA': 'Axia Energia',
    'MCCI': 'Mauá Capital Recebíveis', 'PVBI': 'VBI Prime Properties',
    'RECR': 'REC Recebíveis', 'RZTR': 'Riza Terrax', 'TGAR': 'TG Ativo Real',
    'HCTR': 'Hectare CE',
}

SMALL = {'de', 'da', 'do', 'das', 'dos', 'e', 'em', 'para', 'com', 'a', 'o', 'no', 'na'}
UPPER = {
    'B3', 'BB', 'BTG', 'XP', 'WEG', 'TIM', 'MRV', 'CSN', 'IRB', 'CVC', 'ETF',
    'S&P', 'CRI', 'CDI', 'IPCA', 'FII', 'IT', 'HBC', 'RBR', 'VBI', 'JHSF', 'BR',
    'TRX', 'BM&FBOVESPA', 'AD', 'HSI', 'TG', 'GGR', 'BRF', 'JBS', 'CPFL', 'SLC',
    'CSHG', 'XPML', 'ESG', 'USD', 'MSCI', 'BDR', 'II', 'III', 'IV', 'VI', 'VII',
}
SPECIAL = {'ISHARES': 'iShares', 'BCO': 'Banco', 'CIA': 'Cia'}


def title(name):
    words = []
    for i, w in enumerate(name.split()):
        if w in SPECIAL:
            words.append(SPECIAL[w])
        elif w in UPPER or re.search(r'\d', w) or not re.search(r'[AEIOUÁÉÍÓÚÂÊÔÃÕ]', w):
            words.append(w)
        elif i > 0 and w.lower() in SMALL:
            words.append(w.lower())
        else:
            words.append(w[0] + w[1:].lower())
    return ' '.join(words)


def clean_stock(name):
    n = re.sub(r'\s*-?\s*EM RECUPERA[CÇ][AÃ]O JUDICIAL.*', '', name.upper())
    n = re.sub(r'\bS\.?\s?/?\s?A\b\.?', ' ', n)
    full = re.sub(r'\s+', ' ', n).strip()
    n = re.sub(r'\b(E )?(PARTICIPA[CÇ](OES|ÕES)|PARTICIP|PART|HOLDING|EMPREEND)\b.*', '', n)
    n = re.sub(r'(\s+(DE|DA|DO|DAS|DOS|E))+\s*$', '', n.strip())
    if n.strip() in ('', 'CIA', 'COMPANHIA'):
        n = full
    # "CIA PARANAENSE DE ENERGIA - COPEL": the brand after the dash.
    m = re.search(r' - ([A-Z0-9&]+)$', n.strip())
    if m:
        n = m.group(1)
    n = re.sub(r'[\s.\-]+$', '', re.sub(r'\s+', ' ', n)).strip()
    return title(n) if n else None


def clean_fund(name):
    n = re.split(
        r'\s*-?\s*\b(FUNDO|FDO|FII|FIAGRO|FI-INFRA|FIDC|CLASSE|RESPONSABILIDADE|RESP)\b',
        name.upper(),
    )[0]
    n = re.sub(r'[\s.\-]+$', '', re.sub(r'\s+', ' ', n)).strip()
    return title(n) if n else None


def get_json(url):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def download(url, dest):
    if dest.exists() and dest.stat().st_size > 0:
        return dest
    try:
        req = urllib.request.Request(url, headers=UA)
        with urllib.request.urlopen(req, timeout=30) as r:
            dest.write_bytes(r.read())
        return dest
    except Exception as e:  # noqa: BLE001
        print(f'  falhou {url}: {e}', file=sys.stderr)
        return None


def main():
    CACHE.mkdir(parents=True, exist_ok=True)
    ASSETS.mkdir(parents=True, exist_ok=True)
    entries = {}  # root -> {'name', 'logo_url', 'volume'}
    for kind, clean in (('stock', clean_stock), ('fund', clean_fund)):
        rows = get_json(f'https://brapi.dev/api/quote/list?type={kind}&limit=10000')['stocks']
        print(f'{kind}: {len(rows)} tickers')
        rows.sort(key=lambda r: -(r.get('volume') or 0))
        for r in rows:
            ticker = r['stock'].upper()
            if not re.match(r'^[A-Z0-9]{4}\d', ticker):
                continue
            root = ticker[:4]
            e = entries.get(root)
            if e is not None and e['kind'] != kind:
                continue  # stocks win over a fund with the same root
            if e is None:
                name = r.get('name') or ''
                e = entries[root] = {
                    'kind': kind,
                    'name': None if name.upper() == ticker else clean(name),
                    'logo_url': None,
                }
            logo = r.get('logo') or ''
            if e['logo_url'] is None and logo and not logo.endswith(PLACEHOLDER):
                e['logo_url'] = logo

    def fetch(item):
        root, e = item
        if not e['logo_url']:
            return root, None
        svg = download(e['logo_url'], CACHE / f'{root}.svg')
        if svg is None:
            return root, None
        png = CACHE / f'{root}.png'
        if not png.exists():
            res = subprocess.run(
                ['rsvg-convert', '-w', '128', '-h', '128', '-o', str(png), str(svg)],
                capture_output=True,
            )
            if res.returncode != 0:
                print(f'  rsvg falhou em {root}', file=sys.stderr)
                return root, None
        return root, png

    with ThreadPoolExecutor(3) as pool:
        pngs = dict(pool.map(fetch, sorted(entries.items())))

    for old in ASSETS.glob('*.png'):
        old.unlink()
    by_hash = {}
    catalog = {}
    for root in sorted(entries):
        e = entries[root]
        file = None
        if pngs.get(root):
            data = pngs[root].read_bytes()
            digest = hashlib.sha1(data).hexdigest()
            file = by_hash.get(digest)
            if file is None:
                file = by_hash[digest] = root.lower()
                (ASSETS / f'{file}.png').write_bytes(data)
        catalog[root] = (NAMES.get(root) or e['name'], file)

    def lit(v):
        return 'null' if v is None else "'" + v.replace('\\', '\\\\').replace("'", "\\'") + "'"

    lines = [
        '// Gerado por scripts/b3_catalog.py (brapi.dev). Não editar à mão.',
        '',
        '/// B3 ticker root → (name, logo file in assets/images/stocks/).',
        'const Map<String, (String?, String?)> b3Catalog = {',
    ]
    lines += [f"  '{root}': ({lit(name)}, {lit(file)})," for root, (name, file) in catalog.items()]
    lines.append('};')
    DART.write_text('\n'.join(lines) + '\n', encoding='utf-8')
    size = sum(p.stat().st_size for p in ASSETS.glob('*.png'))
    print(f'{len(catalog)} raízes, {len(by_hash)} logos ({size / 1e6:.1f} MB)')


if __name__ == '__main__':
    main()
