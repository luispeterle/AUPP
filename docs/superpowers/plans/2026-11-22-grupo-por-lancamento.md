# Grupo do Orçamento por lançamento e ícone da categoria mãe: plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** desfazer a lista plana de categorias (já revertida no código) e, sobre a árvore da Dinzo de sempre, (1) deixar cada lançamento escolher o seu grupo do Orçamento, com o da categoria como padrão, e (2) mostrar no extrato sempre o ícone da categoria mãe.

**Architecture:** uma coluna nova `records.budget_group` (esquema 36), lida por `BudgetPlan` antes do grupo da categoria; escolha pelo rótulo do grupo na edição do lançamento. O extrato pega ícone/cor pela `CategoryHierarchy`. Os dados do computador voltam do backup de antes da migração.

**Tech Stack:** Flutter/Dart, sqflite (testes com `sqflite_common_ffi`), shared_preferences.

**Spec:** não há documento à parte; o pedido do usuário (2026-11-22) é a fonte:
- "Continua igual": árvore de categorias e subcategorias como antes da lista plana; nada muda na Dinzo nem no sync.
- "conforto, fixo etc pode ser alterado, por padrão segue aquele padrão, mas se quiser pode alterar": grupo por lançamento, padrão = grupo da categoria.
- "no extrato, nunca aparece o ícone das subcategorias, SEMPRE ícone da categoria mãe".
- Trava de categoria manual (`category_manual`): **não** volta ("Isso nunca nem precisou existir").

## Global Constraints

- `SqliteDatabase.version` = 36; `SqliteMigrationService.oldestSupported` continua 35; `onUpgrade` 35→36 só adiciona a coluna, sem mexer em dados.
- `budget_group` nulo = segue a categoria. A migração nunca grava `budget_group`.
- Grupo "Fora do orçamento" continua sendo a tag `outOfBudgetTag`, não um valor de `budget_group`.
- Textos de interface em pt-BR e sem frase explicativa; identificadores e comentários em inglês.
- Testes só com dados inventados. Rodar só os testes ligados ao que mudou; `scripts/check-data.sh` uma vez, na Task 4.
- Commits só quando o usuário pedir (Conventional Commits, pt-BR, sem assinatura de IA). Os passos "Commit" são pontos de parada.
- Banco à mão (Task 4): app fechado, backup antes na pasta `~/Documents/aupp`, mudança registrada em `change_log`.

## Review Focus

1. **Sync da Dinzo atualizando um lançamento com grupo próprio:** o grupo continua o escolhido (o sync só escreve campos da Dinzo). Teste na Task 1.
2. **Backup antigo (esquema 35) restaurado:** entra, e `budget_group` fica nulo. Teste na Task 1.
3. **Compra paga com caixinha:** a parte da caixinha sai do grupo do lançamento da compra, inclusive quando ele tem grupo próprio. Teste na Task 1.
4. **Lançamento sem categoria, transferência ou entrada:** o rótulo de grupo não aparece para eles, e a caixa "Não considerar no orçamento" continua para entradas. Conferido no passo manual da Task 2.
5. **Subcategoria cuja mãe não existe mais no banco:** o extrato mostra o ícone da própria subcategoria, nunca um ícone vazio. Teste na Task 3.

---

### Task 1: Grupo por lançamento no modelo, no esquema e no Orçamento

**Files:**
- Modify: `lib/models/record.dart` (campo, `fromMap`, `toMap`, cópia)
- Modify: `lib/services/database/sqlite-database.dart` (`version`, `_insertColumns`, `_insertValues`)
- Modify: `lib/services/database/sqlite-migration-service.dart` (DDL de `records`, `onUpgrade`)
- Modify: `lib/budget_plan/budget-plan.dart` (`groupOfRecord`, uso no cálculo)
- Test: `test/budget_plan/budget_plan_test.dart`, `test/dinzo/batch_identical_records_test.dart`, `test/backup/restore_recurrent_transfer_wallet_test.dart`, novo `test/database/budget_group_migration_test.dart`

**Interfaces:**
- Produces: `Record.budgetGroup` (`String?`), coluna `budget_group TEXT`; `BudgetPlan.groupOfRecord(Record r) → String?` = `r.budgetGroup ?? groupOfCategory(r.category?.name)`.

- [ ] **Step 1: testes que falham**
  - `budget_plan_test`: "per-record group wins over the category's": duas despesas na mesma categoria (grupo `conforto` no plano), uma com `budgetGroup = 'fixos'` → uso de `fixos` e `conforto` com um valor cada; `groupOfRecord` sem grupo próprio = grupo da categoria.
  - `budget_plan_test`: "caixinha part of a purchase follows the purchase's own group": compra com `budgetGroup = 'metas'` e parte paga pela caixinha → abate de `metas`.
  - `budget_group_migration_test`: banco criado no esquema 35 (DDL atual do `onCreate` sem a coluna, um lançamento) aberto com versão 36 e `SqliteMigrationService.onUpgrade` → a coluna existe, o lançamento continua igual, `budget_group` nulo.
  - `batch_identical_records_test`: restaurar/gravar mantém `budgetGroup`.
  - `restore_recurrent_transfer_wallet_test`: versão do backup `'36'`.
  - Teste de sync (no arquivo de testes do apply da Dinzo que já atualiza lançamentos): um lançamento com `budgetGroup = 'fixos'` atualizado pela Dinzo continua `'fixos'`.
- [ ] **Step 2:** `flutter test test/budget_plan/ test/database/budget_group_migration_test.dart test/dinzo/batch_identical_records_test.dart test/backup/restore_recurrent_transfer_wallet_test.dart`. Esperado: FAIL (campo/coluna inexistentes).
- [ ] **Step 3: implementar.** A referência da tentativa anterior está em `private/categorias-enxutas.patch` (trechos de `budgetGroup`, sem `categoryManual`). Em `budget-plan.dart` trocar `groupOfCategory(r.category?.name)` e `groupOfCategory(purchase.category?.name)` do cálculo de uso por `groupOfRecord(...)`. `onUpgrade`: `if (oldVersion == 35) ALTER TABLE records ADD COLUMN budget_group TEXT`, senão o `StateError` de hoje.
- [ ] **Step 4:** o mesmo comando. Esperado: PASS.
- [ ] **Step 5: Commit** `feat(orçamento): grupo do orçamento por lançamento`

### Task 2: Escolher o grupo na edição do lançamento

**Files:**
- Modify: `lib/budget_plan/budget-plan-groups.dart` (recebe `showBudgetGroupPicker` público)
- Modify: `lib/budget_plan/budget-plan-page.dart` (`_pickGroup` passa a chamar `showBudgetGroupPicker`)
- Modify: `lib/budget_plan/budget-plan.dart` (`recordGroupChoice`)
- Modify: `lib/records/edit-record-page.dart` (rótulo tocável, caixa "Não considerar no orçamento" só para não-despesa)
- Test: `test/budget_plan/budget_plan_test.dart`

**Interfaces:**
- Consumes: `Record.budgetGroup`, `BudgetPlan.groupOfCategory`.
- Produces: `Future<({String group, bool applyToChildren})?> showBudgetGroupPicker(BuildContext context, {required String title, String? current, int childrenCount = 0})`; `static ({String? budgetGroup, bool outOfBudget}) BudgetPlan.recordGroupChoice(String picked, String? categoryGroup)`.

- [ ] **Step 1: teste que falha** "recordGroupChoice": `('fora', 'conforto')` → `(budgetGroup: null, outOfBudget: true)`; `('conforto', 'conforto')` → `(null, false)`; `('fixos', 'conforto')` → `('fixos', false)`; `('fixos', null)` → `('fixos', false)`.
- [ ] **Step 2:** `flutter test test/budget_plan/`. Esperado: FAIL.
- [ ] **Step 3: implementar.** Mover o diálogo de `_pickGroup` para `showBudgetGroupPicker` sem mudar o visual. Na edição, o `BudgetGroupLabel` (só despesa com categoria) vira `InkWell` que abre o seletor com `current` = fora (tag) ou `budgetGroup ?? grupo da categoria`, e aplica `recordGroupChoice`: põe/tira `outOfBudgetTag` e grava `budgetGroup`. Trocar a categoria não apaga um grupo próprio. Para despesas, a caixa `_createOutOfBudgetCard` some, porque o seletor já tem "Fora"; ela continua para entradas.
- [ ] **Step 4:** `flutter test test/budget_plan/ && flutter analyze lib`. Esperado: PASS, sem issues.
- [ ] **Step 5: conferência manual** no desktop de debug com banco de demonstração: despesa → tocar no grupo → Fixos → salvar → reabrir mostra Fixos; voltar para o grupo da categoria limpa; entrada e transferência sem rótulo; entrada com a caixa.
- [ ] **Step 6: Commit** `feat(lançamentos): escolher o grupo do orçamento na edição`

### Task 3: Extrato com o ícone da categoria mãe

**Files:**
- Modify: `lib/services/category-hierarchy.dart`
- Modify: `lib/records/components/records-per-day-card.dart` (`_buildLeading`)
- Test: novo `test/services/category_hierarchy_test.dart`

**Interfaces:**
- Produces: `static Category? CategoryHierarchy.topOf(Category? category)` (a mãe, ou a própria quando não tem mãe ou a mãe não existe); `@visibleForTesting static void load(Iterable<Category> all)`, que `refresh` passa a usar.

- [ ] **Step 1: teste que falha:** com `load([Alimentação, Cafeteria(parent: Alimentação), Órfã(parent: 'Sumiu')])`, `topOf(Cafeteria)` é Alimentação, `topOf(Alimentação)` é Alimentação, `topOf(Órfã)` é Órfã e `topOf(null)` é null.
- [ ] **Step 2:** `flutter test test/services/category_hierarchy_test.dart`. Esperado: FAIL.
- [ ] **Step 3: implementar.** Em `_buildLeading`, `final look = CategoryHierarchy.topOf(movement.category)`, usado para `iconEmoji`, `icon` e `color`. Decisão minha: a cor também vem da mãe, para o círculo ficar igual em toda a família. O nome mostrado continua o da subcategoria.
- [ ] **Step 4:** o mesmo comando. Esperado: PASS. Depois `flutter analyze lib`.
- [ ] **Step 5: Commit** `feat(extrato): ícone da categoria mãe nos lançamentos`

### Task 4: Dados de volta, conferência e instalação

Nada de código. Começa com o AUPP fechado no computador e **sem abrir o AUPP no celular** até o passo 6. O celular ainda não abriu a versão da lista plana: o último envio dele é de 20/11.

- [ ] **Step 1: guardar o estado atual** em `~/Documents/aupp`: `movements.db` → `movements.db.categorias-enxutas-2026-11-21`; `~/.local/share/app.aupp/shared_preferences.json` → `shared_preferences.json.categorias-enxutas-2026-11-21`.
- [ ] **Step 2: banco:** copiar `movements.db.antes-categorias-2026-11-21` (esquema 35, 94 subcategorias) para `movements.db`. Conferido em 2026-11-22, o que mudou depois dele foi só o que o app refaz sozinho: o lançamento Dinzo "Posto Romano" de 20/11 volta no próximo sync, os dois "Resgate para o Nubank" e o "Ajuste de 11/2026" são automáticos, e o resto são nomes de categoria. Inserir em `change_log` uma linha `Editou` / `records` / "Volta da lista plana de categorias: banco restaurado de antes da migração (movements.db.antes-categorias-2026-11-21)".
- [ ] **Step 3: preferências:** `flutter.budgetPlan` ← `budgetPlan` de `movements.db.old.prefs.json` (20/11). Só `categories` difere do atual, porque a conversão juntou os nomes. Também apagar `flutter.categoriesConsolidated` e pôr `flutter.hybridSyncDirty = true`, para o computador enviar esta versão antes de tudo. `dinzoConfig` não mudou e fica como está.
- [ ] **Step 4:** `scripts/check-data.sh`. Esperado: esquema 35→36 e saldos iguais.
- [ ] **Step 5:** `scripts/deploy-linux.sh`. Esperado: "Instalado em" e o `.desktop` escrito. O usuário abre o app; conferir que `~/Syncthing/AUPP/aupp_sync.enc` foi reescrito e que `hybrid_sync_base` ganhou uma base de esquema 36 com subcategorias.
- [ ] **Step 6:** build do APK e `adb install -r`. Só então o usuário abre o AUPP no celular, que junta pela última base em comum (anterior à lista plana).
- [ ] **Step 7:** `private/DINZO.md`: nota curta da volta e do grupo por lançamento.
