# APIs usadas pelo app

O app só busca dados por API. Sites de pesquisa, como Fundamentus e AUVP Analítica, são apenas links que a pessoa abre: o app não lê nada deles. O Fundamentus recusa clientes que não sejam navegador (HTTP 403), e o app não se disfarça de navegador.

Serviço novo só entra no app depois de entrar nesta lista e em `scripts/check_apis.py`.

| Serviço | Para quê | Chamadas | Onde no código | Chave | Documentação |
|---|---|---|---|---|---|
| Dinzo | Contas, lançamentos e investimentos | `/v1/...` | `lib/dinzo/dinzo-api.dart` | Sim | https://dinzo.com.br/docs |
| brapi.dev | Cotação, histórico, setor e descrição da empresa (B3), e cotação em dólar do que está no exterior (o usuário digita ticker e quantidade) | `/api/v2/stocks/quote`, `/api/v2/stocks/historical`, `/api/v2/stocks/profile` | `lib/investments/brapi-api.dart`, `lib/investments/asset-sheet.dart` | Sim | https://brapi.dev/docs |
| brapi.dev | Catálogo de ativos da B3 (só ao gerar o catálogo) | `/api/quote/list` | `scripts/b3_catalog.py` | Não | https://brapi.dev/docs |
| brapi.dev | Preço, volume, valor de mercado e setor de todas as ações da B3 numa chamada só, para a Análise e o Comparar (o plano free cota um ticker por chamada) | `/api/quote/list?type=stock&limit=10000` | `lib/investments/b3-market.dart` | Sim | https://brapi.dev/docs |
| CVM (Dados Abertos) | Balanços de todas as empresas da B3 para a Análise e o Comparar (computador): DFP anual (cinco arquivos dão dez anos), ITR do ano (últimos 12 meses), FCA (tickers, fundação, controle, segmento), FRE (free float) e IPE (fatos relevantes, comunicados e avisos dos últimos 12 meses). Zips CSV publicados pela API CKAN; baixados de novo só quando o `Last-Modified` muda | `/dados/CIA_ABERTA/DOC/{DFP,ITR,FCA,FRE,IPE}/DADOS/*.zip`, `/api/3/action/package_show` | `lib/investments/cvm-store.dart`, `lib/investments/cvm-statements.dart` | Não | https://dados.cvm.gov.br/dataset/cia_aberta-doc-dfp |
| brapi.dev | Logos dos ativos da B3 e de fora (só ao gerar os catálogos; vão junto com o app) | `icons.brapi.dev/icons/{ticker}.svg` | `scripts/b3_catalog.py`, `scripts/us_catalog.py` | Não | https://brapi.dev/docs |
| Financial Modeling Prep | Logos dos ativos de fora que o brapi não tem (só ao gerar o catálogo; vão junto com o app) | `/image-stock/{ticker}.png` | `scripts/us_catalog.py` | Não | https://site.financialmodelingprep.com/developer/docs |
| CoinGecko | Cotação de cripto e histórico de 1 ano | `/api/v3/simple/price`, `/api/v3/coins/{id}/market_chart` | `lib/services/crypto-quote-service.dart`, `lib/investments/asset-sheet.dart` | Não | https://docs.coingecko.com |
| Kraken | Histórico longo de cripto | `/0/public/OHLC` | `lib/investments/crypto-history.dart` | Não | https://docs.kraken.com/api/ |
| mempool.space | Altura do bloco do Bitcoin, para o halving | `/api/blocks/tip/height` | `lib/investments/crypto-view.dart` | Não | https://mempool.space/docs/api/rest |
| SEC (EDGAR) | Lista de todas as empresas listadas nos EUA, inclusive ADRs de estrangeiras (busca), e balanços e relatórios de cada uma para a Análise e o Comparar (computador). A SEC exige um contato no User-Agent: vem de `private/sec_contact`, passado na compilação (`SEC_CONTACT`) | `www.sec.gov/files/company_tickers_exchange.json`, `data.sec.gov/api/xbrl/companyfacts/CIK{cik}.json`, `data.sec.gov/submissions/CIK{cik}.json` | `lib/investments/sec-data.dart` | Não (contato) | https://www.sec.gov/search-filings/edgar-application-programming-interfaces |
| OpenFIGI | Busca por nome em bolsas fora da B3 e dos EUA, e a bolsa de origem das estrangeiras (o preço que vai com o balanço). Sem chave: poucas buscas por minuto | `POST api.openfigi.com/v3/search` | `lib/investments/home-listing.dart`, `lib/investments/asset-sheet-page.dart` | Não | https://www.openfigi.com/api |
| brapi.dev | Cotação de ações de outras bolsas pelo sufixo (SIE.DE, 7203.T, 2330.TW) | `/api/v2/stocks/quote` | `lib/investments/home-listing.dart` | Sim | https://brapi.dev/docs |
| Banco Central (PTAX) | Câmbio de dez moedas para converter balanço e preço de fora e comparar empresas de países diferentes | Olinda: `PTAX/versao/v1/odata/CotacaoMoedaPeriodo` | `lib/investments/home-listing.dart` | Não | https://olinda.bcb.gov.br/olinda/servico/PTAX/versao/v1/aplicacao#!/recursos |
| Banco Central (IF.data) | Índice de Basileia e de imobilização dos bancos, na Análise (computador) | Olinda: `IFDATA/versao/v1/odata/IfDataCadastro`, `IfDataValores` (relatório 1, conglomerado prudencial) | `lib/investments/bank-capital.dart` | Não | https://olinda.bcb.gov.br/olinda/servico/IFDATA/versao/v1/aplicacao#!/recursos |
| Pix: cobrança do banco recebedor | Valor, vencimento e recebedor de um Pix de cobrança (conta de luz, por exemplo), cujo copia-e-cola não traz o valor, só o endereço no banco de quem recebe. Só quando a pessoa cola ou escaneia o código; o valor fica salvo na ocorrência. A assinatura (JWS) não é conferida: o app do banco confere ao pagar | `GET {endereço do QR}` (API Pix do Banco Central: `/{pixUrlAccessToken}`, `/cobv/{pixUrlAccessToken}`), em qualquer banco | `lib/dinzo/pix-charge.dart` | Não | https://bacen.github.io/pix-api/ |
| Banco Central (SGS) | Selic (11), CDI (12), IPCA (433) e dólar (1, também converte o exterior para reais) | `/dados/serie/bcdata.sgs.{série}/dados` | `lib/investments/benchmark.dart`, `lib/investments/crypto-history.dart` | Não | https://dadosabertos.bcb.gov.br |

## Verificação mensal

`scripts/check_apis.py` chama cada serviço e confere se a resposta ainda tem os campos que o app lê. Na brapi, também avisa se a página de preços mudou. O resultado vai para `~/.local/state/aupp/apis-report.txt`, sem nenhum valor financeiro.

Para rodar todo mês no Linux, uma vez só:

```sh
scripts/install-api-check.sh
```

Para rodar na hora:

```sh
python3 scripts/check_apis.py
```

O script pega API fora do ar e formato alterado. A cobrança Pix muda de endereço a cada banco e só existe com uma conta de verdade: o script confere a especificação do Banco Central, e o formato lido fica coberto por `test/pix_code_test.dart`, com dados inventados. Mudança de preço, limite ou termos de uso nos outros serviços só aparece na documentação de cada um, cujos links saem no relatório.
