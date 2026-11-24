# Evidência de Execução — Dicionário e Runbook Operacional (DB-020)

**Work ID:** DB-020 · Issue `#20`  
**Responsável:** Nicolas Pureza · **Revisora:** Isabelly  
**Commit avaliado:** `628a4aaa5bfa8999e25e70e5233b2e7e09027ca1` (`628a4aa`, branch `feat/DB-020-dictionary-and-runbook`)  
**Data da execução (UTC):** `2026-11-24T15:31:36Z` (duração: `47s`)  
**Workflow / Run ID:** `CI Database` (`.github/workflows/ci.yml`) · Run [`45426523151`](https://github.com/UniSENAI-Sorocaba/plataforma-database/actions/runs/45426523151)  
**Versão do banco:** PostgreSQL 16 (`postgres:16-alpine` conforme `compose.yaml`)  
**Log completo verbatim:** [`evidence/DB-020-ci-output.txt`](DB-020-ci-output.txt)

---

## 1. Resumo da Evidência Reproduzível

A execução da esteira `CI Database` sobre o commit `628a4aa` comprova os procedimentos descritos no [Runbook Operacional (DB-020)](../docs/DB-020-runbook.md) e a correspondência exata com os objetos descritos no [Dicionário de Dados (DB-020)](../docs/DB-020-data-dictionary.md):

| Etapa da CI | Comando Executado | Resultado Observado no Log (`DB-020-ci-output.txt`) |
| :--- | :--- | :--- |
| Provisionamento | `make up` (`docker compose up -d --wait`) | Container `plataforma-database-postgres-1` (`postgres:16-alpine`) atingiu estado `Healthy`. |
| Instalação Limpa — Migrations | `make migrate` (`./scripts/migrate.sh`) | Aplicou sequencialmente `V0001`, `V0002`, `V0003`, `V0004`, `V0006`, `V0007`, `V0008`, `V0010`, `V0011` e `V0017` com `COMMIT`. |
| Instalação Limpa — Seeds | `make seed` (`./scripts/seed.sh`) | Aplicou `0001_audit_event.sql` a `0005_project_tables.sql` (`[seed] 5 arquivo(s) de seed aplicado(s) com sucesso em plataforma.`). |
| Validação Estrutural e Funcional | `make validate` (`./scripts/validate.sh`) | Concluiu os 42 passos (`[validate] 1` a `42`) sem falhas (`Todas as validacoes de compatibilidade, integridade, constraints e seeds concluidas com sucesso!`). |
| Upgrade Incremental, Idempotência e Drift | `make validate-upgrade` (`./scripts/validate_upgrade.sh`) | Subiu `plataforma_upgrade_test` na `V0001`, aplicou upgrade até `V0017`, confirmou idempotência de `migrate.sh` e `seed.sh`, rodou os 42 passos de `validate.sh` e confirmou zero drift via `detect_drift.sh` (`schemas=5,tables=20,constraints=119,indexes=79` em ambos). |
| Encerramento | `make down` (`docker compose down`) | Parou e removeu container e rede Docker do ambiente de teste. |

---

## 2. Como Reproduzir a Evidência

Em um ambiente com Docker e Docker Compose ativos, a partir do commit `628a4aa` (ou equivalente em `develop`):

```bash
git checkout 628a4aa
make up
make migrate
make seed
make validate
make validate-upgrade
make down
```

Para consultar a saída verbatim da CI neste mesmo commit via GitHub CLI:

```bash
gh run view 45426523151 --log
```

---

## 3. Procedimentos Explicitamente Pendentes (Não Exercitados)

Conforme critério de aceite da **DB-020**, os procedimentos abaixo **não foram exercitados** nesta entrega e permanecem pendentes de suas respectivas issues:

- **Backup, restauração e PITR com RPO/RTO medidos:** pendente da **DB-018** (Issue `#18` aberta); não existe script de backup/restore no repositório.
- **Pool de conexões e operação sob carga integrada:** pendente da **DB-019** (Issue `#19` aberta).
- **Rollback automatizado por script (`down` migrations):** inexistente por decisão arquitetural; mudanças seguem **roll-forward** e **Expand and Contract**.
- **Execução local nesta estação Windows:** não realizada por ausência de Docker/PostgreSQL instalados localmente; toda comprovação desta entrega decorre da execução reproduzível na CI em `postgres:16-alpine`.
