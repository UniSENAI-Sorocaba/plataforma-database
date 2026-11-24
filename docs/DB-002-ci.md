# Integração Contínua e Validação de Compatibilidade (DB-002)

Este documento descreve a especificação, arquitetura e execução da pipeline de Integração Contínua (CI) e das validações automatizadas de compatibilidade para o repositório `plataforma-database`, alinhado com as diretrizes da *ADR-011*, convenções da *DB-001* e as normas de governança da plataforma.

---

## 1. Contexto e Objetivos

A entrega **DB-002** implementa a automação de CI responsável por garantir a integridade, compatibilidade e reprodutibilidade do banco de dados relacional (PostgreSQL 16).

Os objetivos centrais incluem:
1. **Subida de banco limpo:** Provisionamento determinístico de uma instância PostgreSQL 16 isolada via Docker Compose.
2. **Instalação limpa (Clean Install):** Execução sequencial de todas as migrations ativas a partir do zero, aplicação de seeds sintéticos e verificação estrutural completa.
3. **Validação de upgrade incremental:** Simulação de um ambiente existente em versão anterior (baseline V0001) e aplicação das migrations subsequentes (V0002+), garantindo retrocompatibilidade sem perda de dados.
4. **Garantia de idempotência:** Reexecução de scripts de migração e seeds sem gerar erros ou duplicações em bancos já migrados.
5. **Validação de integridade e segurança:** Verificação de esquemas de domínio, integridade de tabelas, índices, check constraints e ausência de privilégios públicos indevidos (`PUBLIC`).

---

## 2. Arquitetura da Pipeline de CI

A pipeline é implementada através do GitHub Actions no arquivo [ci.yml](file:///.github/workflows/ci.yml).

### Disparadores (Triggers)
- **Push:** Todos os commits em qualquer branch (`'**'`) e na branch `main`.
- **Pull Request:** Validação automática para PRs com destino à branch `main`.
- **Workflow Dispatch:** Execução manual sob demanda.

### Etapas da Execução
```mermaid
flowchart TD
    A[Início do Job CI] --> B[Checkout do Repositório]
    B --> C[make up: Sobe PostgreSQL 16 isolado]
    C --> D[make migrate: Aplica todas as migrations no banco limpo]
    D --> E[make seed: Aplica dados sintéticos determinísticos]
    E --> F[make validate: Valida schemas, tabelas, índices e constraints]
    F --> G[make validate-upgrade: Executa teste de upgrade incremental]
    G --> H[make down: Encerra containers e desaloca recursos]
    H --> I[Sucesso do Job]
```

1. **Provisionamento do Banco:** Executa `make up` (`docker compose up -d --wait`), aguardando o healthcheck oficial do PostgreSQL.
2. **Instalação Limpa:**
   - Executa `make migrate` (`./scripts/migrate.sh`).
   - Executa `make seed` (`./scripts/seed.sh`).
   - Executa `make validate` (`./scripts/validate.sh`).
3. **Validação de Upgrade Incremental:** Executa `make validate-upgrade` (`./scripts/validate_upgrade.sh`).
4. **Desalocação Limpa:** Executa `make down` (`docker compose down`) garantindo a finalização dos containers mesmo em caso de falha (`if: always()`).

---

## 3. Mecanismo de Migrations e Idempotência (`migrate.sh`)

O script [migrate.sh](file:///scripts/migrate.sh) foi aprimorado para garantir atomicidade, rastreabilidade e idempotência:
- Suporta as variáveis de ambiente `PGDATABASE` e `PGUSER` (com valor padrão `plataforma`).
- Consulta a tabela `public.schema_migration` antes de executar cada arquivo `migrations/*.sql`.
- Se a migration já foi registrada como aplicada, ela é ignorada com registro explicativo (`Migration VNNNN ja aplicada em <banco>, ignorando.`).
- Caso ainda não tenha sido aplicada, é executada com a opção `ON_ERROR_STOP=1`.

---

## 4. Validação de Upgrade Incremental (`validate_upgrade.sh`)

O script [validate_upgrade.sh](file:///scripts/validate_upgrade.sh) automatiza o ciclo completo de verificação de atualização:
1. Cria dinamicamente um banco isolado temporário (`plataforma_upgrade_test`).
2. Aplica apenas a migration baseline inicial (`V0001__create_domain_schemas.sql`).
3. Valida que o estado intermediário reflete exclusivamente a versão baseline.
4. Executa o `migrate.sh` padrão sobre o banco temporário, confirmando que a versão `V0001` é ignorada e todas as migrations subsequentes da branch (`migrations/*.sql`) são aplicadas e registradas em `public.schema_migration` (com verificação explícita de `V0006`, `V0008` e `V0010`).
5. Valida a idempotência executando o `migrate.sh` uma segunda vez, confirmando que não ocorrem erros nem alterações na lista de versões.
6. Aplica os seeds determinísticos (`seed.sh`) duas vezes para validar idempotência de sementes.
7. Executa a suíte de validação completa (`validate.sh`) sobre o banco atualizado.
8. Executa `scripts/detect_drift.sh` comparando o schema normalizado e as contagens de catálogo entre a instalação limpa e o banco atualizado.
9. Remove com segurança o banco temporário de teste.

---

## 5. Verificações de Integridade e Postura de Segurança (`validate.sh`)

> [!NOTE]
> Na entrega inicial da DB-002, `validate.sh` possuía 8 etapas focadas em `V0001` e `V0002`. Conforme as entregas subsequentes, o script evoluiu e atualmente executa **42 blocos de verificação** (`[validate] 1` a `42`), detalhados no [Runbook Operacional (DB-020)](DB-020-runbook.md).

Resumo das verificações atuais em [validate.sh](file:///scripts/validate.sh):
1. **Schemas, controle e segurança base (passos 1–9.3):** existência dos 5 schemas de domínio, `public.schema_migration` com todas as migrations da branch, `public.audit_event`, índices, check constraints, restrição de `old_data`/`new_data` (`DB-007`), ausência de privilégios para `PUBLIC` e cobertura de seeds em `audit_event`.
2. **Identidade, vínculo e sessões (passos 10–22):** `auth.user`, `auth.user_identity`, `institutional.academic_class`, `institutional.academic_link` (`DB-004`), `auth.user_session` (`DB-005`), constraints, índices, seeds e conformidade Anti-PII.
3. **Projetos, artefatos, RBAC e avaliações (passos 23–42):** `academic_pi.*` (`DB-008`, `DB-016`), `assets.project_file` e `assets.file_lifecycle_state` (`DB-011`), `roles`/`permissions`/`role_permissions`/`user_roles` (`DB-006`) e `evaluation_criterion`/`project_evaluation`/`evaluation_criterion_score` (`DB-010`).

---

## 6. Estratégia de Rollback e Segurança Operacional

Conforme definido na DB-001 e alinhado ao [Runbook Operacional (DB-020)](DB-020-runbook.md):
1. **Imutabilidade:** Arquivos de migrations já publicados em branches compartilhadas são imutáveis e jamais devem ser editados. Não existe script de rollback (`down` migration) no repositório.
2. **Roll-forward por padrão:** Qualquer correção ou ajuste em schema em ambientes integrados e produção deve ser realizado através de uma nova migração sequencial incremental (ex.: `V0018__...`).
3. **Padrão Expand and Contract:** Operações que alteram estruturas existentes sem downtime seguem as três etapas:
   - *Expand:* Criação da nova estrutura coexistindo com a anterior (ex.: `V0007`).
   - *Transition:* Adaptação do código da aplicação e backfill dos dados.
   - *Contract:* Remoção segura dos artefatos legados após descontinuação do uso.
4. **Recuperação de Desastres (PITR — pendente de DB-018):** A estratégia de backup e *Point-in-Time Recovery* (PITR) é prevista como norma de governança, porém **ainda não foi exercitada** neste repositório (aguarda execução e evidência da issue **DB-018**).

---

## 7. Como Executar Localmente

Com o Docker e Docker Compose instalados e em execução:

```bash
# 1. Sobe o banco PostgreSQL 16
make up

# 2. Aplica as migrations incrementais
make migrate

# 3. Aplica os seeds determinísticos sintéticos
make seed

# 4. Executa as validações estruturais e de segurança
make validate

# 5. Executa a validação de upgrade incremental e idempotência
make validate-upgrade

# 6. Ou executa todos os testes conjuntamente
make test

# 7. Finaliza e limpa os containers locais
make down
```
