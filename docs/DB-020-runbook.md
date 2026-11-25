# Runbook Operacional — Instalação, Atualização, Seeds e Validação (DB-020)

Este runbook descreve como qualquer pessoa do time instala, migra, popula com dados sintéticos, valida, monitora pool/carga controlada e encerra o banco PostgreSQL do repositório `plataforma-database`, distinguindo **o que já foi exercitado** do que **ainda está pendente / não exercitado**.

---

## 1. Pré-requisitos e Ambiente Local

- **Container engine:** Docker com plugin Docker Compose (`docker compose`) ativo.
- **Shell POSIX:** `sh` (Linux/macOS, WSL ou Git Bash no Windows) e `make` (ou execução direta de `./scripts/*.sh`).
- **Configuração definida em `compose.yaml`:**
  - Imagem: `postgres:16-alpine` (serviço `postgres`).
  - Banco padrão (`PGDATABASE`): `plataforma`.
  - Usuário padrão (`PGUSER`): `plataforma` (senha local de desenvolvimento definida em `compose.yaml`).
  - Parâmetros de conexão e timeouts (DB-019): `max_connections=100` (`PG_MAX_CONNECTIONS`), `superuser_reserved_connections=3`, `reserved_connections=2`, `idle_in_transaction_session_timeout=60s`, `lock_timeout=10s`, `statement_timeout=0`, `log_lock_waits=on`.
  - Persistência local: volume Docker `database-data` (observação: o serviço não expõe porta no host por padrão; os scripts acessam via `docker compose exec -T postgres psql ...`).

---

## 2. Catálogo de Comandos (`Makefile` e `scripts/`)

Todos os scripts aceitam `PGDATABASE` (padrão `plataforma`) e `PGUSER` (padrão `plataforma`) e usam `set -eu` com `psql -v ON_ERROR_STOP=1`.

| Comando `make` | Script subjacente | Efeito real no banco / ambiente | Status de exercício |
| :--- | :--- | :--- | :--- |
| `make up` | `docker compose up -d --wait` | Sobe `postgres:16-alpine` com parâmetros de conexões/timeouts da DB-019 e aguarda `pg_isready -U plataforma -d plataforma`. | **Exercitado na CI** |
| `make migrate` | `./scripts/migrate.sh` | Percorre `migrations/*.sql` em ordem alfabética (`V0001` a `V0017`), consulta `public.schema_migration` e aplica apenas versões ainda não registradas. | **Exercitado na CI** |
| `make seed` | `./scripts/seed.sh` | Executa `seeds/*.sql` em ordem alfabética (`0001` a `0013` — 7 arquivos), inserindo dados sintéticos idempotentes (`ON CONFLICT DO NOTHING`). | **Exercitado na CI** |
| `make validate` | `./scripts/validate.sh` | Executa os **46 blocos de verificação** (`[validate] 1` a `46`) sobre schemas, migrations, `audit_event` (DB-007), segurança `PUBLIC`, DB-004, DB-005, DB-008, DB-011, DB-006 (RBAC), DB-016 (seeds), DB-009 (`project_evaluation`), DB-013 (`extension.activity`) e parâmetros da DB-019. | **Exercitado na CI** |
| `make validate-upgrade` | `./scripts/validate_upgrade.sh` | Cria `plataforma_upgrade_test`, aplica `V0001`, executa `migrate.sh`, confere todas as migrations da branch (`expected_versions == applied_versions` + presença explícita de `V0006`, `V0008`, `V0009` e `V0013`), testa idempotência de `migrate.sh` e `seed.sh`, roda `validate.sh`, chama `detect_drift.sh` e remove o banco temporário. | **Exercitado na CI** |
| `make detect-drift` | `./scripts/detect_drift.sh` | Compara `pg_dump --schema-only --no-owner` normalizado e contagens de catálogo entre `<CLEAN_DB>` e `<UPGRADE_DB>`. Exige que ambos os bancos existam previamente. | **Exercitado na CI** (invocado por `validate_upgrade.sh`) |
| `make monitor-pool` | `./scripts/monitor_pool.sh` | Coleta snapshots de `pg_stat_activity`, `pg_stat_database`, locks e uso de conexões frente ao orçamento configurado (DB-019). | **Exercitado localmente com evidência** (`evidence/DB-019-postgresql-pool-and-load.md`) |
| `make test-pool` | `./scripts/run_pool_load_test.sh` | Executa carga controlada sintética de leitura/escrita concorrente (`evidence/DB-019-workload-*.sql`) e valida guardrails `idle_in_transaction_session_timeout` e `lock_timeout` (DB-019). | **Exercitado localmente com evidência** (`evidence/DB-019-test-output.txt`) |
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

# 3. Popular com os seeds sintéticos determinísticos (0001 .. 0013)
make seed

# 4. Validar estrutura, constraints, triggers, índices, segurança, RBAC, avaliações, extensão e parâmetros de pool
make validate

# 5. Validar upgrade incremental a partir da V0001, idempotência e ausência de drift
make validate-upgrade

# 6. (Opcional, para testes de pool/carga local da DB-019)
make test-pool

# 7. Encerrar os containers ao finalizar
make down
```

### Observações importantes sobre os scripts atuais
1. **`scripts/validate.sh` exige seeds aplicados previamente:** os passos `9`, `16`, `22`, `35`, `36`, `37`, `41` e `45` verificam quantidades mínimas e conformidade Anti-PII dos registros inseridos por `make seed`. Rodar `make validate` sem `make seed` falhará nesses passos.
2. **`scripts/validate.sh` insere e limpa dados temporários de teste:** os blocos `DO $$ ... $$` (`8`, `9.3`, `15`, `21`, `26`, `29`, `34`, `40`, `44`) testam constraints, FKs e triggers em tempo real e removem os registros temporários ao final; o passo `30` confirma que não restou resíduo em `assets`.
3. **Limpeza completa do volume local:** `make down` não apaga o volume `database-data`. Para reiniciar o banco local completamente do zero após experimentos manuais, utilize `docker compose down -v` antes de `make up`.
4. **Scripts de evidência avulsos (`evidence/*.sql`) não rodam na CI:** arquivos como [`evidence/DB-012-evidence-tests.sql`](../evidence/DB-012-evidence-tests.sql) e [`evidence/DB-017-queries.sql`](../evidence/DB-017-queries.sql) são executados manualmente com `psql` e **não fazem parte** de `.github/workflows/ci.yml`.

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
| Subir PostgreSQL 16 via Compose (`make up`) | **Exercitado na CI** | `.github/workflows/ci.yml` (`make up`) | Não expõe porta no host por padrão; parâmetros de pool podem ser sobrescritos via env (`PG_MAX_CONNECTIONS`, etc.). |
| Instalação limpa de migrations (`make migrate`) | **Exercitado na CI** | `.github/workflows/ci.yml` (`make migrate`) | Cobre `V0001`–`V0004`, `V0006`–`V0009`, `V0011`, `V0013`, `V0017`. |
| Aplicação idempotente de seeds (`make seed`) | **Exercitado na CI** | `.github/workflows/ci.yml` e `validate_upgrade.sh` (passos 7–8) | Cobre `0001`–`0006` e `0013`; `assets.file_lifecycle_state` permanece vazia por decisão (`DB-011`). |
| Suite de validação estrutural e funcional (`make validate`) | **Exercitado na CI** | `.github/workflows/ci.yml` (`scripts/validate.sh`, passos 1–46) | Requer seeds prévios. |
| Upgrade incremental, idempotência e detecção de drift (`make validate-upgrade` + `detect_drift.sh`) | **Exercitado na CI** | `.github/workflows/ci.yml` (`scripts/validate_upgrade.sh`) | Testa upgrade a partir de `V0001` até o conjunto atual de migrations e compara DDL via `pg_dump`. |
| Encerramento de container (`make down`) | **Exercitado na CI** | `.github/workflows/ci.yml` (`if: always()`) | Mantém volume local quando executado localmente; não remove `database-data` sem `-v`. |
| Monitoramento de pool e teste de carga controlada local (`make monitor-pool`, `make test-pool` — **DB-019**) | **Exercitado localmente com evidência** | [`evidence/DB-019-postgresql-pool-and-load.md`](../evidence/DB-019-postgresql-pool-and-load.md) e [`evidence/DB-019-test-output.txt`](../evidence/DB-019-test-output.txt) | Carga local sintética em Docker; operação integrada completa com Backend + k6 (`QA-024`) permanece pendente. |
| Execução avulsa de `make detect-drift` fora de `validate_upgrade.sh` | **Ainda não exercitado isoladamente** | — | A lógica de `detect_drift.sh` é exercitada dentro de `validate_upgrade.sh`; invocação direta via `make detect-drift` exige os bancos `plataforma` e `plataforma_upgrade_test` ativos simultaneamente. |
| Execução isolada de `make test` | **Ainda não exercitado como target único** | — | Equivalente a `make validate` + `make validate-upgrade` após `make up && make migrate && make seed`, que são executados na CI. |
| Execução conjunta sob carga integrada (**QA-024** + `monitor_pool.sh`) | **Ainda não exercitado (Pendente)** | Issue `#24` aberta (`plataforma-quality`) | Depende de disparo conjunto com Backend e k6 (`200 RPS`, `p95 <= 500 ms`). |
| Backup, restauração e PITR com RPO/RTO medidos (**DB-018**) | **Ainda não exercitado (Pendente)** | Issue `#18` aberta | Não existem scripts nem evidências de backup/restore/PITR no repositório. |
| Rollback automatizado por script (`down` migrations) | **Inexistente (Não aplicável)** | Convenção DB-001 / DB-002 | Política oficial é **roll-forward** e **Expand and Contract**. |
