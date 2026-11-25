# Evidência de Execução — Dicionário e Runbook Operacional (DB-020)

**Work ID:** DB-020 · Issue `#20`  
**Responsável:** Nicolas Pureza · **Revisora:** Isabelly  
**Commit avaliado:** `41abfa766073e8b1643c6f0bdc27b212b300b696` (`41abfa7`, branch `feat/DB-020-dictionary-and-runbook`)  
**Data da execução (UTC):** `2026-11-25T20:00:30Z` (duração: `45s`)  
**Workflow / Run ID:** `CI Database` (`.github/workflows/ci.yml`) · Run [`45690733353`](https://github.com/UniSENAI-Sorocaba/plataforma-database/actions/runs/45690733353)  
**Versão do banco:** PostgreSQL 16 (`postgres:16-alpine` conforme `compose.yaml`)  
**Log completo verbatim:** [`evidence/DB-020-ci-output.txt`](DB-020-ci-output.txt)

---

## 1. Resumo da Evidência Reproduzível

A execução da esteira `CI Database` sobre o commit `41abfa7` comprova os procedimentos descritos no [Runbook Operacional (DB-020)](../docs/DB-020-runbook.md) e a correspondência exata com os objetos descritos no [Dicionário de Dados (DB-020)](../docs/DB-020-data-dictionary.md):

| Etapa da CI | Comando Executado | Resultado Observado no Log (`DB-020-ci-output.txt`) |
| :--- | :--- | :--- |
| Provisionamento | `make up` (`docker compose up -d --wait`) | Container `plataforma-database-postgres-1` (`postgres:16-alpine`) atingiu estado `Healthy`. |
| Instalação Limpa — Migrations | `make migrate` (`./scripts/migrate.sh`) | Aplicou `V0001`, `V0002`, `V0003`, `V0004`, `V0006`, `V0007`, `V0008`, `V0009`, `V0011`, `V0013` e `V0017` com `COMMIT`. |
| Instalação Limpa — Seeds | `make seed` (`./scripts/seed.sh`) | Aplicou os 7 arquivos (`0001` a `0013`: `[seed] 7 arquivo(s) de seed aplicado(s) com sucesso em plataforma.`). |
| Validação Estrutural e Funcional | `make validate` (`./scripts/validate.sh`) | Concluiu os 46 passos (`[validate] 1` a `46`) sem falhas (`Todas as validacoes de compatibilidade, integridade, constraints e seeds concluidas com sucesso!`). |
| Upgrade Incremental, Idempotência e Drift | `make validate-upgrade` (`./scripts/validate_upgrade.sh`) | Subiu `plataforma_upgrade_test` na `V0001`, aplicou upgrade até `V0017`, confirmou idempotência de `migrate.sh` e `seed.sh`, rodou os 46 passos de `validate.sh` e confirmou zero drift via `detect_drift.sh` (`schemas=5,tables=19,constraints=108,indexes=73` em ambos). |
| Encerramento | `make down` (`docker compose down`) | Parou e removeu container e rede Docker do ambiente de teste. |

---

## 2. Como Reproduzir a Evidência

Em um ambiente com Docker e Docker Compose ativos, a partir do commit `41abfa7` (ou equivalente em `develop`):

```bash
git checkout 41abfa7
make up
make migrate
make seed
make validate
make validate-upgrade
make down
```

Para consultar a saída verbatim da CI neste mesmo commit via GitHub CLI:

```bash
gh run view 45690733353 --log
```

---

## 3. Procedimentos Exercitados Localmente vs. Pendentes

- **Exercitado localmente com evidência prévia (`DB-019`):** `make monitor-pool` e `make test-pool` documentados e comprovados em [`evidence/DB-019-postgresql-pool-and-load.md`](DB-019-postgresql-pool-and-load.md) e [`evidence/DB-019-test-output.txt`](DB-019-test-output.txt).
- **Ainda não exercitado / Pendente:**
  - **Backup, restauração e PITR com RPO/RTO medidos (`DB-018`):** Issue `#18` aberta; não existe script de backup/restore no repositório.
  - **Carga integrada conjunta com Backend + k6 (`QA-024`):** Issue `#24` aberta (`plataforma-quality`).
  - **Rollback automatizado por script (`down` migrations):** inexistente por decisão arquitetural; mudanças seguem **roll-forward** e **Expand and Contract**.
