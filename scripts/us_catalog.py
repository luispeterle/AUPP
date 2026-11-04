#!/usr/bin/env python3
"""Gera o catálogo dos ativos de fora mais comuns (ações, ETFs e REITs dos
EUA) usado em Investimentos: nome legível e logo por ticker.

O brapi.dev não lista os tickers de fora, então a lista é escrita aqui. Os
ícones vêm de icons.brapi.dev, a mesma fonte do catálogo da B3 (SVG, convertido
com rsvg-convert); o que falta lá vem da Financial Modeling Prep (PNG, reduzido
com o ImageMagick). Tudo em 128 px. Ticker sem ícone nos dois fica só com o nome.

Saída:
  assets/images/stocks_us/<ticker>.png
  lib/investments/us-catalog.dart

Uso: python3 scripts/us_catalog.py   (repetir ao mudar a lista)
"""

import hashlib
import subprocess
import sys
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / 'assets/images/stocks_us'
DART = ROOT / 'lib/investments/us-catalog.dart'
CACHE = ROOT / 'build/us_cache'
UA = {'User-Agent': 'aupp-us-catalog/1.0'}

TICKERS = {
    # Ações
    'AAPL': 'Apple', 'MSFT': 'Microsoft', 'NVDA': 'NVIDIA', 'GOOGL': 'Alphabet',
    'GOOG': 'Alphabet', 'AMZN': 'Amazon', 'META': 'Meta', 'TSLA': 'Tesla',
    'BRK.B': 'Berkshire Hathaway', 'AVGO': 'Broadcom', 'TSM': 'TSMC',
    'ASML': 'ASML', 'AMD': 'AMD', 'INTC': 'Intel', 'QCOM': 'Qualcomm',
    'TXN': 'Texas Instruments', 'ORCL': 'Oracle', 'CRM': 'Salesforce',
    'ADBE': 'Adobe', 'IBM': 'IBM', 'CSCO': 'Cisco', 'NFLX': 'Netflix',
    'DIS': 'Disney', 'PYPL': 'PayPal', 'V': 'Visa', 'MA': 'Mastercard',
    'JPM': 'JPMorgan', 'BAC': 'Bank of America', 'WFC': 'Wells Fargo',
    'GS': 'Goldman Sachs', 'MS': 'Morgan Stanley', 'C': 'Citigroup',
    'BLK': 'BlackRock', 'AXP': 'American Express', 'KO': 'Coca-Cola',
    'PEP': 'PepsiCo', 'MCD': "McDonald's", 'SBUX': 'Starbucks', 'NKE': 'Nike',
    'WMT': 'Walmart', 'COST': 'Costco', 'HD': 'Home Depot', 'PG': 'Procter & Gamble',
    'JNJ': 'Johnson & Johnson', 'PFE': 'Pfizer', 'MRK': 'Merck', 'ABBV': 'AbbVie',
    'LLY': 'Eli Lilly', 'UNH': 'UnitedHealth', 'NVO': 'Novo Nordisk',
    'XOM': 'ExxonMobil', 'CVX': 'Chevron', 'BA': 'Boeing', 'CAT': 'Caterpillar',
    'DE': 'Deere', 'GE': 'GE Aerospace', 'MMM': '3M', 'UPS': 'UPS',
    'T': 'AT&T', 'VZ': 'Verizon', 'PM': 'Philip Morris', 'MO': 'Altria',
    'ABNB': 'Airbnb', 'UBER': 'Uber', 'SHOP': 'Shopify', 'SPOT': 'Spotify',
    'BABA': 'Alibaba', 'MELI': 'Mercado Livre', 'NU': 'Nu Holdings',
    'PLTR': 'Palantir', 'COIN': 'Coinbase', 'MSTR': 'Strategy',
    # ETFs
    'VOO': 'Vanguard S&P 500', 'IVV': 'iShares Core S&P 500',
    'SPY': 'SPDR S&P 500', 'VTI': 'Vanguard Total Stock Market',
    'QQQ': 'Invesco QQQ', 'VT': 'Vanguard Total World', 'VXUS': 'Vanguard Total International',
    'VEA': 'Vanguard Developed Markets', 'VWO': 'Vanguard Emerging Markets',
    'SCHD': 'Schwab US Dividend', 'VIG': 'Vanguard Dividend Appreciation',
    'VYM': 'Vanguard High Dividend', 'DGRO': 'iShares Dividend Growth',
    'VNQ': 'Vanguard Real Estate', 'BND': 'Vanguard Total Bond',
    'AGG': 'iShares Core US Aggregate Bond', 'TLT': 'iShares 20+ Year Treasury',
    'SHV': 'iShares Short Treasury', 'BIL': 'SPDR 1-3 Month T-Bill',
    'TIP': 'iShares TIPS Bond', 'GLD': 'SPDR Gold', 'IAU': 'iShares Gold',
    'SLV': 'iShares Silver', 'IBIT': 'iShares Bitcoin Trust',
    # REITs
    'O': 'Realty Income', 'PLD': 'Prologis', 'AMT': 'American Tower',
    'CCI': 'Crown Castle', 'EQIX': 'Equinix', 'SPG': 'Simon Property',
    'PSA': 'Public Storage', 'WPC': 'W. P. Carey', 'VICI': 'VICI Properties',
    'STAG': 'STAG Industrial', 'MAIN': 'Main Street Capital',
    'ARE': 'Alexandria Real Estate', 'AVB': 'AvalonBay', 'EQR': 'Equity Residential',
    'DLR': 'Digital Realty', 'WELL': 'Welltower', 'NNN': 'NNN REIT',
    'ADC': 'Agree Realty', 'MPW': 'Medical Properties Trust',
}


def get(url, dest):
    """True when [url] was saved to [dest]; a 404 is just a missing logo."""
    if dest.exists():
        return True
    try:
        req = urllib.request.Request(url, headers=UA)
        with urllib.request.urlopen(req, timeout=30) as r:
            dest.write_bytes(r.read())
        return True
    except urllib.error.HTTPError as e:
        if e.code != 404:
            print(f'  falhou {url}: {e}', file=sys.stderr)
    except Exception as e:  # noqa: BLE001
        print(f'  falhou {url}: {e}', file=sys.stderr)
    return False


def fetch(ticker):
    png = CACHE / f'{ticker}.png'
    if png.exists():
        return ticker, png
    svg = CACHE / f'{ticker}.svg'
    if get(f'https://icons.brapi.dev/icons/{ticker}.svg', svg):
        cmd = ['rsvg-convert', '-w', '128', '-h', '128', '-o', str(png), str(svg)]
    else:
        raw = CACHE / f'{ticker}.fmp.png'
        fmp = ticker.replace('.', '-')
        if not get(f'https://financialmodelingprep.com/image-stock/{fmp}.png', raw):
            return ticker, None
        cmd = ['magick', str(raw), '-resize', '128x128', str(png)]
    if subprocess.run(cmd, capture_output=True).returncode != 0:
        print(f'  conversão falhou em {ticker}', file=sys.stderr)
        return ticker, None
    return ticker, png


def main():
    CACHE.mkdir(parents=True, exist_ok=True)
    ASSETS.mkdir(parents=True, exist_ok=True)
    with ThreadPoolExecutor(3) as pool:
        pngs = dict(pool.map(fetch, sorted(TICKERS)))

    for old in ASSETS.glob('*.png'):
        old.unlink()
    by_hash = {}
    catalog = {}
    for ticker in sorted(TICKERS):
        file = None
        if pngs.get(ticker):
            data = pngs[ticker].read_bytes()
            digest = hashlib.sha1(data).hexdigest()
            file = by_hash.get(digest)
            if file is None:
                file = by_hash[digest] = ticker.lower().replace('.', '_')
                (ASSETS / f'{file}.png').write_bytes(data)
        catalog[ticker] = (TICKERS[ticker], file)

    def lit(v):
        return 'null' if v is None else "'" + v.replace('\\', '\\\\').replace("'", "\\'") + "'"

    lines = [
        '// Gerado por scripts/us_catalog.py (icons.brapi.dev e FMP). Não editar à mão.',
        '',
        '/// Ticker abroad → (name, logo file in assets/images/stocks_us/).',
        'const Map<String, (String, String?)> usCatalog = {',
    ]
    lines += [f"  {lit(t)}: ({lit(name)}, {lit(file)})," for t, (name, file) in catalog.items()]
    lines.append('};')
    DART.write_text('\n'.join(lines) + '\n', encoding='utf-8')
    size = sum(p.stat().st_size for p in ASSETS.glob('*.png'))
    print(f'{len(catalog)} tickers, {len(by_hash)} logos ({size / 1e6:.2f} MB)')
    print('sem logo:', ' '.join(t for t, (_, f) in catalog.items() if f is None))


if __name__ == '__main__':
    main()
