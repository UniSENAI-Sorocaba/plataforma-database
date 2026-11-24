# Runbook Operacional — Instalação, Atualização, Seeds e Validação (DB-020)

Este runbook descreve como qualquer pessoa do time instala, migra, popula com dados sintéticos, valida e encerra o banco PostgreSQL do repositório `plataforma-database`, distinguindo **o que já foi exercitado** do que **ainda está pendente / não exercitado**.

---

## 1. Pré-requisitos e Ambiente Local

- **Container engine:** Docker com plugin Docker Compose (`docker compose`) ativo.
- **Shell POSIX:** `sh` (Linux/macOS, WSL ou Git Bash no Windows) e `make` (ou execução direta de `./scripts/*.sh`).
- **Configuração definida em `compose.yaml`:**
  - Imagem: `postgres:16-alpine` (serviço `postgres`).
  - Banco padrão (`PGDATABASE`): `plataforma`.
  - Usuário padrão (`PGUSER`): `plataforma` (senha local de desenvolvimento definida em `compose.yaml`).
  - Persistência local: volume Docker `database-data` (observação: o serviço não expõe porta no host por padrão; os scripts acessam via `docker compose exec -T postgres psql ...`).

---

## 2. Catálogo de Comandos (`Makefile` e `scripts/`)

Todos os scripts aceitam `PGDATABASE` (padrão `plataforma`) e `PGUSER` (padrão `plataforma`) e usam `set -eu` com `psql -v ON_ERROR_STOP=1`.

| Comando `make` | Script subjacente | Efeito real no banco / ambiente | Status de exercício |
| :--- | :--- | :--- | :--- |
| `make up` | `docker compose up -d --wait` | Sobe o container `postgres:16-alpine` e aguarda `pg_isready -U plataforma -d plataforma` passar no healthcheck. | **Exercitado na CI** |
| `make migrate` | `./scripts/migrate.sh` | Percorre `migrations/*.sql` em ordem alfabética (`V0001` a `V0017`), consulta `public.schema_migration` e aplica apenas versões ainda não registradas. | **Exercitado na CI** |
| `make seed` | `./scripts/seed.sh` | Executa `seeds/*.sql` em ordem alfabética (`0001` a `0005`), inserindo dados sintéticos idempotentes (`ON CONFLICT DO NOTHING`). | **Exercitado na CI** |
| `make validate` | `./scripts/validate.sh` | Executa os **42 blocos de verificação** (`[validate] 1` a `42`) sobre schemas, migrations, `audit_event` (DB-007), segurança `PUBLIC`, DB-004, DB-005, DB-008, DB-011, DB-006 (RBAC), DB-016 (seeds) e DB-010 (rubricas/avaliações). | **Exercitado na CI** |
| `make validate-upgrade` | `./scripts/validate_upgrade.sh` | Cria `plataforma_upgrade_test`, aplica `V0001`, executa `migrate.sh`, confere todas as migrations da branch (`expected_versions == applied_versions` + presença explícita de `V0006`, `V0008`, `V0010`), testa idempotência de `migrate.sh` e `seed.sh`, roda `validate.sh`, chama `detect_drift.sh` e remove o banco temporário. | **Exercitado na CI** |
| `make detect-drift` | `./scripts/detect_drift.sh` | Compara `pg_dump --schema-only --no-owner` normalizado e contagens de catálogo entre `<CLEAN_DB>` e `<UPGRADE_DB>`. Exige que ambos os bancos existam previamente. | **Exercitado na CI** (invocado por `validate_upgrade.sh`) |
| `make test` | `validate` + `validate-upgrade` | Encadeia `make validate` e `make validate-upgrade` em sequência (pressupõe `make up`, `make migrate` e `make seed` já executados). | **Equivalente exercitado na CI** (etapas separadas em `ci.yml`) |
| `make down` | `docker compose down` | Para e remove os containers da stack mantendo o volume `database-data` (use `docker compose down -v` apenas se quiser apagar os dados locais do volume). | **Exercitado na CI** |

---

## 3. Passo a Passo para Instalação Limpa, Seeds e Validação Local

Execute os comandos a partir da raiz do repositório:

```bash
# 1. Subir o PostgreSQL 16 em container limpo
make up

# 2. Aplicar todas as migrations incrementais (V0001 .. V0017)
make migrate

# 3. Popular com os seeds sintéticos determinísticos (0001 .. 0005)
make seed

# 4. Validar estrutura, constraints, triggers, índices, segurança, RBAC, seeds e DB-010
make validate

# 5. Validar upgrade incremental a partir da V0001, idempotência e ausência de drift
make validate-upgrade

# 6. Encerrar os containers ao finalizar
make down
```

### Observações importantes sobre os scripts atuais
1. **`scripts/validate.sh` exige seeds aplicados previamente:** os passos `9`, `16`, `22`, `35`, `36` e `37` verificam quantidades mínimas e conformidade Anti-PII dos registros inseridos por `make seed`. Rodar `make validate` sem `make seed` falhará nesses passos.
2. **`scripts/validate.sh` insere e limpa dados temporários de teste:** os blocos `DO $$ ... $$` (`8`, `9.3`, `15`, `21`, `26`, `29`, `34`, `41`) testam constraints e FKs em tempo real e removem os registros temporários ao final; os passos `30` e `42` confirmam que não restou resíduo em `assets` nem nas tabelas de avaliação da `DB-010`.
3. **Limpeza completa do volume local:** `make down` não apaga o volume `database-data`. Para reiniciar o banco local completamente do zero após experimentos manuais, utilize `docker compose down -v` antes de `make up`.
4. **Scripts de evidência avulsos (`evidence/*.sql`) não rodam na CI:** arquivos como [`evidence/DB-010-evidence-tests.sql`](../evidence/DB-010-evidence-tests.sql) e [`evidence/DB-012-evidence-tests.sql`](../evidence/DB-012-evidence-tests.sql) são executados manualmente com `psql` dentro de transação com `ROLLBACK` e **não fazem parte** de `.github/workflows/ci.yml`.

---

## 4. Fluxo de Atualização em Banco Já Existente

1. Garanta que o container está ativo (`make up`).
2. Execute `make migrate` (ou `PGDATABASE=<alvo> ./scripts/migrate.sh`).
   - O script `migrate.sh` consulta `public.schema_migration` para cada arquivo `migrations/V*.sql`.
   - Versões já presentes exibem `Migration VNNNN ja aplicada em <banco>, ignorando.` e não são reaplicadas.
   - Versões novas são executadas em ordem alfabética com `ON_ERROR_STOP=1` dentro de transação explícita (`BEGIN; ... COMMIT;`).
3. Caso deseje reaplicar seeds idempotentes, execute `make seed`.
4. Valide o resultado com `make validate` e confira se não há drift frente a uma instalação limpa usando `make validate-upgrade`.

---

## 5. Política de Mudanças, Rollback e Recuperação

- **Não existe script de rollback (`down` migration) no repositório.** Nenhuma documentação ou procedimento deve instruir a execução de scripts de rollback inexistentes ou a edição de migrations já publicadas.
- **Estratégia padrão — Roll-forward:** correções e evoluções de schema após publicação devem ser feitas criando uma nova migration sequencial incremental (`migrations/VNNNN__descricao.sql`).
- **Alterações destrutivas — Expand and Contract:** mudanças que removam/renomeiem colunas ou alterem tipos incompatíveis seguem 3 fases em migrations distintas:
  1. **Expand:** adiciona novas estruturas preservando as antigas (ex.: `V0007__restrict_audit_event_to_technical_records.sql`, que bloqueou snapshots em `old_data`/`new_data` sem remover as colunas ainda).
  2. **Transition:** adapta consumidores da aplicação e migra dados.
  3. **Contract:** remove colunas ou estruturas legadas após confirmação de desuso.
- **Restauração e PITR (DB-018 — PENDENTE):** procedimentos formais de backup físico/lógico, restauração e *Point-in-Time Recovery* (PITR) com RPO/RTO medidos **ainda não foram exercitados** neste repositório e aguardam a entrega da issue **DB-018**.

---

## 6. Matriz de Status dos Procedimentos (Exercitado vs. Pendente)

| Procedimento / Capacidade | Status | Onde / Como foi comprovado | Limitações / Pendências |
| :--- | :--- | :--- | :--- |
| Subir PostgreSQL 16 via Compose (`make up`) | **Exercitado na CI** | `.github/workflows/ci.yml` (`make up`) | Não exercitado localmente nesta estação Windows por ausência de Docker/psql instalados; não expõe porta no host por padrão. |
| Instalação limpa de migrations (`make migrate`) | **Exercitado na CI** | `.github/workflows/ci.yml` (`make migrate`) | Cobre `V0001`–`V0004`, `V0006`–`V0008`, `V0010`, `V0011`, `V0017`. |
| Aplicação idempotente de seeds (`make seed`) | **Exercitado na CI** | `.github/workflows/ci.yml` e `validate_upgrade.sh` (passos 7–8) | Cobre `0001`–`0005`; `assets.file_lifecycle_state`, `extension` e notas/critérios de `DB-010` não possuem seeds globais por decisão de escopo. |
| Suite de validação estrutural e funcional (`make validate`) | **Exercitado na CI** | `.github/workflows/ci.yml` (`scripts/validate.sh`, passos 1–42) | Requer seeds prévios; não testa regras pendentes de PO da `DB-010` (escala, arredondamento, cálculo e avaliação ausente). |
| Upgrade incremental, idempotência e detecção de drift (`make validate-upgrade` + `detect_drift.sh`) | **Exercitado na CI** | `.github/workflows/ci.yml` (`scripts/validate_upgrade.sh`) | Testa upgrade a partir de `V0001` até o conjunto atual de migrations e compara DDL via `pg_dump`. |
| Encerramento de container (`make down`) | **Exercitado na CI** | `.github/workflows/ci.yml` (`if: always()`) | Mantém volume local quando executado localmente; não remove `database-data` sem `-v`. |
| Execução avulsa de `make detect-drift` fora de `validate_upgrade.sh` | **Ainda não exercitado isoladamente** | — | A lógica de `detect_drift.sh` é exercitada dentro de `validate_upgrade.sh`; invocação direta via `make detect-drift` exige os bancos `plataforma` e `plataforma_upgrade_test` ativos simultaneamente. |
| Execução isolada de `make test` | **Ainda não exercitado como target único** | — | Equivalente a `make validate` + `make validate-upgrade` após `make up && make migrate && make seed`, que são executados na CI. |
| Execução de `evidence/DB-010-evidence-tests.sql` e `evidence/DB-012-evidence-tests.sql` | **Exercitado em entregas anteriores (avulso)** | Evidências `DB-010` e `DB-012` | Não executados automaticamente pela esteira de CI atual. |
| Backup, restauração e PITR com RPO/RTO medidos (**DB-018**) | **Ainda não exercitado (Pendente)** | Issue `#18` aberta | Não existem scripts nem evidências de backup/restore/PITR no repositório. |
| Dimensionamento de pool e operação sob carga integrada (**DB-019**) | **Ainda não exercitado (Pendente)** | Issue `#19` aberta | Não existem evidências de pool/conexões sob carga integrada nesta branch. |
| Rollback automatizado por script (`down` migrations) | **Inexistente (Não aplicável)** | Convenção DB-001 / DB-002 | Política oficial é **roll-forward** e **Expand and Contract**. |
