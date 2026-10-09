# Evidência de Validação — DB-002

**Identificador de Trabalho (Work ID):** DB-002  
**Título:** CI sobe banco limpo, aplica migrations e valida compatibilidade  
**Sprint / Prioridade:** S0 / P0  
**Responsável inicial:** Henrique Marchetti  
**Revisor:** Isabelly  
**Dependências:** DB-001  
**Autoridade Normativa:** `plataforma-governance/_KB/README.md` (baseline `.governance-baseline`)  

---

## 1. Resumo Executivo da Entrega

A entrega DB-002 estabelece a esteira de Integração Contínua (CI) e os testes de compatibilidade e integridade do banco de dados relacional (PostgreSQL 16). O fluxo foi concebido para atender a todos os critérios de aceitação:
- Execução automática em ambiente de CI (GitHub Actions) a partir de uma instância limpa de PostgreSQL.
- Aplicação das migrações incrementais (`migrations/V*.sql`).
- Aplicação de seeds sintéticos determinísticos (`seeds/*.sql`).
- Validação estrutural de compatibilidade e segurança (`scripts/validate.sh`).
- Teste de atualização incremental e retrocompatibilidade (`scripts/validate_upgrade.sh`).
- Garantia de idempotência de execução e política formal de rollback.

---

## 2. Evidência da Pipeline de CI (GitHub Actions)

A esteira de CI foi configurada no arquivo `.github/workflows/ci.yml` contendo os seguintes passos automatizados:

```yaml
name: CI Database

on:
  push:
    branches:
      - main
      - '**'
  pull_request:
    branches:
      - main
  workflow_dispatch:

jobs:
  validate-database:
    name: Sobe banco limpo, aplica migrations e valida compatibilidade
    runs-on: ubuntu-latest
    steps:
      - name: Checkout do repositorio
        uses: actions/checkout@v4
      - name: Sobe banco limpo (PostgreSQL 16)
        run: make up
      - name: Clean Install - Aplica migrations
        run: make migrate
      - name: Clean Install - Aplica seeds deterministicos
        run: make seed
      - name: Clean Install - Valida compatibilidade e integridade
        run: make validate
      - name: Upgrade Validation - Executa teste de upgrade e compatibilidade
        run: make validate-upgrade
      - name: Finaliza servico de banco de dados
        if: always()
        run: make down
```

---

## 3. Evidência de Instalação Limpa (Clean Install)

### 3.1 Procedimento Executado
1. Inicialização de um container PostgreSQL 16 limpo a partir da imagem `postgres:16-alpine` através do comando `make up`.
2. Execução das migrações incrementais via `make migrate` (`./scripts/migrate.sh`):
   - `V0001__create_domain_schemas.sql`: criação dos esquemas de domínio (`auth`, `academic_pi`, `extension`, `assets`, `institutional`) e da tabela `public.schema_migration`.
   - `V0002__create_audit_event.sql`: criação da tabela `public.audit_event`, restrições de verificação e índices correspondentes.
3. Execução das seeds determinísticas via `make seed` (`./scripts/seed.sh`):
   - Inserção do registro sintético em `public.audit_event` (`seeds/0001_audit_event.sql`).
4. Verificação de integridade via `make validate` (`./scripts/validate.sh`).

### 3.2 Resultado das Verificações da Instalação Limpa
- **Schemas de Domínio:** `academic_pi, assets, auth, extension, institutional` presentes e validados.
- **Tabela de Versionamento:** `public.schema_migration` presente com versões `V0001` e `V0002` registradas com seus respectivos timestamps UTC (`applied_at`).
- **Tabela de Auditoria:** `public.audit_event` criada com todas as colunas obrigatórias e tipos esperados (`uuid`, `timestamptz`, `varchar`, `jsonb`).
- **Índices de Performance:** `idx_audit_event_actor`, `idx_audit_event_occurred_at` e `idx_audit_event_record` verificados.
- **Restrições de Integridade (Check Constraints):** `audit_event_operation_ck`, `audit_event_schema_name_ck` e `audit_event_table_name_ck` validadas.
- **Segurança (Zero Trust / Least Privilege):** Ausência total de permissões `USAGE` ou `CREATE` para a role `PUBLIC` nos esquemas de domínio.
- **Teste Funcional de Constraint:** Inserção de registro inválido em `public.audit_event` rejeitada pelo PostgreSQL com código `check_violation`.

---

## 4. Evidência de Validação de Upgrade Incremental (Upgrade Validation)

### 4.1 Procedimento Executado (`scripts/validate_upgrade.sh`)
Para validar a compatibilidade e capacidade de atualização em ambientes com versões anteriores em produção:
1. Provisionamento de um banco isolado de teste (`plataforma_upgrade_test`).
2. Aplicação exclusiva da migração base (`V0001__create_domain_schemas.sql`).
3. Confirmação do estado intermediário contendo apenas a versão `V0001`.
4. Execução de `migrate.sh` no banco pré-existente:
   - O mecanismo inspeciona `public.schema_migration`.
   - Identifica que `V0001` já foi aplicada e salta sua execução sem erro (`Migration V0001 ja aplicada em plataforma_upgrade_test, ignorando.`).
   - Identifica que `V0002` é uma atualização pendente e a aplica com sucesso.
5. Verificação da conclusão do upgrade com ambas as versões registradas.
6. Teste de **idempotência**: Reexecução completa do `migrate.sh` sobre o banco atualizado; ambas as migrações são identificadas como concluídas e nenhuma alteração ou erro ocorre.
7. Aplicação das seeds determinísticas no banco atualizado.
8. Execução da suíte completa de validação (`validate.sh`) sobre o banco atualizado.
9. Desalocação e limpeza do banco de teste.

### 4.2 Resultado do Teste de Upgrade
- **Compatibilidade:** O banco em versão anterior é atualizado sem erros e sem interrupção de integridade.
- **Idempotência:** A reexecução dos scripts de migração não produz conflitos, falhas ou dados duplicados.
- **Integridade Final:** O estado após o upgrade é indistinguível da instalação limpa completa.

---

## 5. Estratégia de Rollback e Segurança Operacional

Conforme normas de governança e convenções estabelecidas:
1. **Roll-Forward como Padrão:** As migrações já publicadas em branches compartilhadas são estritamente imutáveis. Ajustes e correções são efetuados via novas migrações sequenciais (ex.: `V0003`).
2. **Padrão Expand and Contract:** Operações de alteração destrutiva (remoção de colunas ou tabelas, alteração de tipos de dados) devem seguir o ciclo Expand (nova estrutura criada em paralelo), Transition (aplicação adaptada e dados sincronizados) e Contract (remoção segura da estrutura legada).
3. **Plano de Contingência e PITR:** Antes de qualquer alteração de esquema estrutural em ambiente de produção, é obrigatória a existência de backup snapshot ativo para recuperação pontual via Point-in-Time Recovery (PITR).

---

## 6. Conclusão

Todos os critérios de aceitação da issue **DB-002** foram atendidos e comprovados:
- [x] CI sobe banco limpo, aplica migrations e valida compatibilidade.
- [x] Evidências de instalação limpa e upgrade registradas.
- [x] Validação executável via `make validate` e `make validate-upgrade`.
- [x] Rastreabilidade e documentação atualizadas.
