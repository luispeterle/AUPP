#!/usr/bin/env python3
"""Checks that the APIs in docs/APIS.md still answer what the app reads.

Run monthly by scripts/install-api-check.sh. Writes only statuses and missing
fields to the report, never values: some answers hold financial data.
Keys come from private/chave_api_dinzo and private/chave_api_brapi; a service
without its key is reported as skipped.
"""
import hashlib
import json
import shutil
import subprocess
import urllib.error
import urllib.request
from datetime import datetime, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STATE_DIR = Path.home() / ".local/state/aupp"
REPORT = STATE_DIR / "apis-report.txt"
STATE = STATE_DIR / "apis-state.json"
AGENT = {"User-Agent": "Mozilla/5.0 (aupp api check)"}

DOCS = [
    "https://dinzo.com.br/docs",
    "https://brapi.dev/docs",
    "https://brapi.dev/versioning.md",
    "https://docs.coingecko.com",
    "https://docs.kraken.com/api/",
    "https://mempool.space/docs/api/rest",
    "https://dadosabertos.bcb.gov.br",
    "https://site.financialmodelingprep.com/developer/docs",
    "https://dados.cvm.gov.br/dataset/cia_aberta-doc-dfp",
    "https://olinda.bcb.gov.br/olinda/servico/IFDATA/versao/v1/aplicacao#!/recursos",
    "https://www.sec.gov/search-filings/edgar-application-programming-interfaces",
    "https://www.openfigi.com/api",
]

CVM = "https://dados.cvm.gov.br"

# Columns the app reads from the CVM's CSVs (lib/investments/cvm-statements.dart),
# by zip and by part of the file name.
CVM_COLUMNS = {
    "DFP": {
        "_DRE_con_": ["CNPJ_CIA", "DT_REFER", "VERSAO", "DENOM_CIA", "CD_CVM", "ESCALA_MOEDA", "DT_INI_EXERC", "DT_FIM_EXERC", "CD_CONTA", "DS_CONTA", "VL_CONTA"],
        "_BPP_con_": ["CNPJ_CIA", "DT_REFER", "VERSAO", "CD_CVM", "ESCALA_MOEDA", "DT_FIM_EXERC", "CD_CONTA", "DS_CONTA", "VL_CONTA"],
        "_composicao_capital_": ["CNPJ_CIA", "DT_REFER", "QT_ACAO_ORDIN_CAP_INTEGR", "QT_ACAO_PREF_CAP_INTEGR", "QT_ACAO_ORDIN_TESOURO", "QT_ACAO_PREF_TESOURO"],
    },
    "FCA": {
        "_geral_": ["CNPJ_Companhia", "Data_Referencia", "Versao", "Data_Constituicao", "Setor_Atividade", "Especie_Controle_Acionario"],
        "_valor_mobiliario_": ["CNPJ_Companhia", "Valor_Mobiliario", "Codigo_Negociacao", "Composicao_BDR_Unit", "Segmento", "Data_Inicio_Listagem", "Data_Fim_Listagem"],
    },
    "FRE": {
        "_distribuicao_capital_2": ["CNPJ_Companhia", "Data_Referencia", "Versao", "Percentual_Total_Acoes_Circulacao"],
    },
    "IPE": {
        "ipe_cia_aberta_": ["Codigo_CVM", "Categoria", "Tipo", "Assunto", "Data_Entrega", "Link_Download"],
    },
}


def last_bank_quarter(today):
    """The last quarter IF.data has: about three months after it ends."""
    back = today - timedelta(days=100)
    month = (back.month - 1) // 3 * 3
    return f"{back.year - 1}12" if month == 0 else f"{back.year}{month:02d}"



def key(name):
    path = ROOT / "private" / name
    return path.read_text().strip() if path.exists() else None


def fetch(url, token=None, limit=None, body=None):
    headers = dict(AGENT)
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if url.startswith(("https://www.sec.gov", "https://data.sec.gov")):
        # The SEC asks for a contact; private/sec_contact holds it.
        headers["User-Agent"] = f"AUPP {key('sec_contact') or ''}".strip()
    if body is not None:
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(url, headers=headers, data=body)
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return response.status, response.read(limit)
    except urllib.error.HTTPError as error:
        return error.code, b""


def has(data, *path):
    """Whether the keys exist; an int goes into a list."""
    for step in path:
        try:
            data = data[step]
        except (KeyError, IndexError, TypeError):
            return False
    return True


def fields(*paths):
    def check(body):
        data = json.loads(body)
        return [".".join(map(str, p)) for p in paths if not has(data, *p)]

    return check


def is_number(body):
    return [] if body.strip().isdigit() else ["altura do bloco"]


def is_svg(body):
    return [] if b"<svg" in body else ["SVG"]


def is_png(body):
    return [] if body.startswith(b"\x89PNG") else ["PNG"]


def pix_charge_spec(body):
    """The Pix charge an app reads by its QR (lib/dinzo/pix-charge.dart)."""
    wanted = (b"/cobv/{pixUrlAccessToken}", b"dataDeVencimento", b"application/jose")
    return [w.decode() for w in wanted if w not in body]


def checks():
    dinzo = key("chave_api_dinzo")
    brapi = key("chave_api_brapi")
    quote = ("results", 0, "data")
    history = (*quote, "historicalDataPrice", 0)
    # A month back: on the 1st, "this month" would be a single, maybe closed, day.
    today = datetime.now()
    start = (today - timedelta(days=31)).strftime("%d/%m/%Y")
    end = today.strftime("%d/%m/%Y")
    sgs = fields((0, "data"), (0, "valor"))
    bcb = (
        "https://api.bcb.gov.br/dados/serie/bcdata.sgs.{}/dados"
        f"?formato=json&dataInicial={start}&dataFinal={end}"
    )
    return [
        ("Dinzo: conta", "https://api.dinzo.com.br/v1/accounts", dinzo, "needs", fields(("data", 0, "id"))),
        ("Dinzo: investimentos", "https://api.dinzo.com.br/v1/investments/summary", dinzo, "needs", fields(("total_invested",))),
        (
            "brapi: cotação",
            "https://brapi.dev/api/v2/stocks/quote?symbols=PETR4",
            brapi,
            "needs",
            fields((*quote, "regularMarketPrice"), (*quote, "regularMarketChangePercent"), (*quote, "regularMarketTime"), (*quote, "longName"), (*quote, "shortName")),
        ),
        (
            "brapi: histórico",
            "https://brapi.dev/api/v2/stocks/historical?symbols=PETR4&range=3mo&interval=1d&sortOrder=asc",
            brapi,
            "needs",
            fields((*history, "date"), (*history, "close")),
        ),
        (
            "brapi: perfil",
            "https://brapi.dev/api/v2/stocks/profile?symbols=PETR4",
            brapi,
            "needs",
            fields((*quote, "sectorDisp"), (*quote, "industryDisp"), (*quote, "longBusinessSummary"), (*quote, "website")),
        ),
        (
            "brapi: lista da B3",
            "https://brapi.dev/api/quote/list?type=stock&limit=1",
            brapi,
            "needs",
            fields(*[("stocks", 0, k) for k in ("stock", "name", "close", "change", "volume", "market_cap", "sector", "subsector")]),
        ),
        *[
            (f"CVM: {name}", f"{CVM}/api/3/action/package_show?id=cia_aberta-doc-{name.lower()}", None, "", fields(("result", "resources", 0, "url")))
            for name in ("DFP", "ITR", "FCA", "FRE", "IPE")
        ],
        (
            "Banco Central: IF.data (Basileia)",
            "https://olinda.bcb.gov.br/olinda/servico/IFDATA/versao/v1/odata/"
            f"IfDataCadastro(AnoMes=@AnoMes)?@AnoMes={last_bank_quarter(today)}"
            "&$filter=CnpjInstituicaoLider%20eq%20%2760872504%27&$format=json",
            None,
            "",
            fields(("value", 0, "CodConglomeradoPrudencial")),
        ),
        (
            "SEC: lista de tickers",
            "https://www.sec.gov/files/company_tickers_exchange.json",
            key("sec_contact"),
            "needs",
            fields(("fields", 3), ("data", 0, 3)),
        ),
        (
            "SEC: balanços (Apple)",
            "https://data.sec.gov/api/xbrl/companyfacts/CIK0000320193.json",
            key("sec_contact"),
            "needs",
            fields(("facts", "us-gaap", "NetIncomeLoss", "units", "USD", 0, "end"), ("facts", "dei", "EntityCommonStockSharesOutstanding")),
        ),
        (
            "SEC: relatórios (Apple)",
            "https://data.sec.gov/submissions/CIK0000320193.json",
            key("sec_contact"),
            "needs",
            fields(("sic",), ("filings", "recent", "form"), ("filings", "recent", "items"), ("filings", "recent", "primaryDocument")),
        ),
        (
            "OpenFIGI: busca",
            ("https://api.openfigi.com/v3/search", json.dumps({"query": "TOYOTA MOTOR", "securityType2": "Common Stock", "exchCode": "JT"}).encode()),
            None,
            "",
            fields(("data", 0, "ticker"), ("data", 0, "exchCode"), ("data", 0, "name")),
        ),
        (
            "brapi: cotação fora (7203.T)",
            "https://brapi.dev/api/v2/stocks/quote?symbols=7203.T",
            brapi,
            "needs",
            fields((*quote, "regularMarketPrice"), (*quote, "currency")),
        ),
        (
            "Banco Central: PTAX (euro)",
            "https://olinda.bcb.gov.br/olinda/servico/PTAX/versao/v1/odata/CotacaoMoedaPeriodo(moeda=@moeda,dataInicial=@dataInicial,dataFinalCotacao=@dataFinalCotacao)"
            f"?@moeda=%27EUR%27&@dataInicial=%27{(today - timedelta(days=10)):%m-%d-%Y}%27&@dataFinalCotacao=%27{today:%m-%d-%Y}%27&$format=json",
            None,
            "",
            fields(("value", 0, "cotacaoVenda"), ("value", 0, "tipoBoletim")),
        ),
        # Each bank has its own address and a charge needs a real bill: the
        # Banco Central's specification stands for them.
        (
            "Pix: cobrança (especificação do Banco Central)",
            "https://raw.githubusercontent.com/bacen/pix-api/master/openapi.yaml",
            None,
            "",
            pix_charge_spec,
        ),
        ("CoinGecko: cotação", "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=brl,usd", None, "", fields(("bitcoin", "brl"), ("bitcoin", "usd"))),
        ("CoinGecko: histórico", "https://api.coingecko.com/api/v3/coins/bitcoin/market_chart?vs_currency=brl&days=30&interval=daily", None, "", fields(("prices", 0, 1))),
        ("Kraken: histórico", "https://api.kraken.com/0/public/OHLC?pair=XBTUSD&interval=1440", None, "", fields(("result", "last"))),
        ("mempool.space: bloco", "https://mempool.space/api/blocks/tip/height", None, "", is_number),
        ("brapi: logo", "https://icons.brapi.dev/icons/AAPL.svg", None, "limit", is_svg),
        ("FMP: logo", "https://financialmodelingprep.com/image-stock/NVDA.png", None, "limit", is_png),
        ("Banco Central: Selic", bcb.format(11), None, "", sgs),
        ("Banco Central: CDI", bcb.format(12), None, "", sgs),
        ("Banco Central: dólar", bcb.format(1), None, "", sgs),
        # Monthly and published around the 10th: a longer window.
        (
            "Banco Central: IPCA",
            "https://api.bcb.gov.br/dados/serie/bcdata.sgs.433/dados?formato=json"
            f"&dataInicial={(today - timedelta(days=120)):%d/%m/%Y}&dataFinal={end}",
            None,
            "",
            sgs,
        ),
    ]


def run_check(name, url, token, mode, validate):
    if mode == "needs" and not token:
        return f"PULADA  {name}: sem chave em private/", False
    try:
        post = None
        if isinstance(url, tuple):
            url, post = url
        status, body = fetch(url, token, 4096 if mode == "limit" else None, post)
        if status != 200:
            return f"FALHOU  {name}: HTTP {status}", True
        missing = validate(body)
    except Exception as error:  # A changed answer must end up in the report.
        return f"FALHOU  {name}: {type(error).__name__}", True
    if missing:
        return f"MUDOU   {name}: faltam {', '.join(missing)}", True
    return f"OK      {name}", False


def brapi_extras(state):
    """Used paths in the contract, the prices page and the quota in use."""
    lines = []
    try:
        _, body = fetch("https://brapi.dev/openapi.json")
        paths = json.loads(body)["paths"]
        for path in ["/api/v2/stocks/quote", "/api/v2/stocks/historical", "/api/v2/stocks/profile", "/api/quote/list"]:
            if path not in paths:
                lines.append(f"MUDOU   brapi: {path} saiu do contrato")
            elif paths[path].get("get", {}).get("deprecated"):
                lines.append(f"MUDOU   brapi: {path} está descontinuado")
        _, pricing = fetch("https://brapi.dev/pricing.md")
        digest = hashlib.sha256(pricing).hexdigest()
        if state.get("brapiPricing") not in (None, digest):
            lines.append("MUDOU   brapi: a página de preços e limites mudou (https://brapi.dev/pricing.md)")
        state["brapiPricing"] = digest
    except Exception as error:
        lines.append(f"FALHOU  brapi: contrato ou preços, {type(error).__name__}")
    token = key("chave_api_brapi")
    if token:
        try:
            status, body = fetch("https://brapi.dev/api/v2/user/usage", token)
            if status == 200:
                usage = json.loads(body)["usage"]
                lines.append(f"INFO    brapi: plano {usage['planName']}, {usage['currentUsage']} de {usage['planLimit']} chamadas")
        except Exception:
            pass
    return lines


def cvm_columns():
    """The columns read from last year's DFP and this year's FCA, FRE and IPE (about 25 MB)."""
    import io
    import zipfile

    year = datetime.now().year
    lines = []
    for kind, zip_year in (("DFP", year - 1), ("FCA", year), ("FRE", year), ("IPE", year)):
        parts = CVM_COLUMNS[kind]
        url = f"{CVM}/dados/CIA_ABERTA/DOC/{kind}/DADOS/{kind.lower()}_cia_aberta_{zip_year}.zip"
        try:
            status, body = fetch(url)
            if status != 200:
                lines.append(f"FALHOU  CVM: {kind} {zip_year}, HTTP {status}")
                continue
            changed = len(lines)
            with zipfile.ZipFile(io.BytesIO(body)) as archive:
                for part, columns in parts.items():
                    names = [n for n in archive.namelist() if part in n]
                    if not names:
                        continue
                    header = archive.open(names[0]).readline().decode("latin-1").strip().lstrip("\ufeff").split(";")
                    missing = [c for c in columns if c not in header]
                    if missing:
                        lines.append(f"MUDOU   CVM: {names[0]} sem {', '.join(missing)}")
            if len(lines) == changed:
                lines.append(f"OK      CVM: colunas do {kind} {zip_year}")
        except Exception as error:
            lines.append(f"FALHOU  CVM: {kind}, {type(error).__name__}")
    return lines


def notify(text, urgent):
    if shutil.which("notify-send"):
        urgency = "critical" if urgent else "normal"
        subprocess.run(["notify-send", "-u", urgency, "AUPP: APIs", text], check=False)


def main():
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    state = json.loads(STATE.read_text()) if STATE.exists() else {}
    results = [run_check(*check) for check in checks()]
    lines = [line for line, _ in results]
    problems = sum(1 for _, bad in results if bad)
    extras = brapi_extras(state) + cvm_columns()
    lines += extras
    problems += sum(1 for line in extras if not line.startswith(("INFO", "OK")))
    header = f"Verificação de {datetime.now():%d/%m/%Y %H:%M}: "
    header += f"{problems} problema(s)" if problems else "tudo certo"
    report = [header, "", *lines, "", "Conferir mudanças de limite e termos:", *DOCS]
    REPORT.write_text("\n".join(report) + "\n")
    STATE.write_text(json.dumps(state))
    print("\n".join(report))
    notify(f"{header}\nRelatório: {REPORT}", problems > 0)
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
