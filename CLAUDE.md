# AUPP

Finanças pessoais em Flutter, para Android e Linux. Interface em pt-BR; textos novos direto em português.

Leia só quando a tarefa pedir:
- `private/DINZO.md`: histórico de decisões da integração e do modelo do dinheiro.
- `private/AUVP.md`: conceitos de investimento, antes de mexer em Investimentos, Orçamento ou Carteira e aporte.

## Regras

- **Dados pessoais** ficam em `private/`, ignorada pelo git. Testes e exemplos usam dados inventados.
- **Dados entre versões:** mudança que faria um app antigo ler ou escrever errado sobe `HybridSync.dataCompat` no mesmo commit. Esquema novo (`SqliteDatabase.version`) já faz isso sozinho.
- **Banco à mão:** app fechado, backup antes, mudança registrada em `change_log`.
- **APIs:** o app só busca dados por API, nunca lendo sites. Serviço novo entra em `docs/APIS.md` e `scripts/check_apis.py`.
- **Testes:** rode só os ligados ao que mudou. `scripts/check-data.sh` confere o banco real numa cópia: use depois de mudar migração ou código que grava dados, não a cada alteração.
- **Commits:** só quando pedido, em Conventional Commits, sem assinatura de IA.
