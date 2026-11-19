# Evidencia de Validacao — DB-016

**Identificador de Trabalho (Work ID):** DB-016  
**Titulo:** Fixtures deterministicas e CI detectam drift entre instalacao e upgrade  
**Sprint / Prioridade:** S1–4 / P0 (3 SP)  
**Responsavel:** Henrique Marchetti  
**Revisora:** Isabelly  
**Commit Base:** `8a56402d82c74239347d4705016f8b511cc1cb56`  
**Branch:** `16-db-016-fixtures-determinísticas-e-ci-detectam-drift-entre-instalação-e-upgrade`  
**Dependencias:** DB-002, DB-003, DB-004, DB-006, DB-008  
**Autoridade Normativa:** `../plataforma-governance/_KB/README.md` (baseline `.governance-baseline`)  

---

## 1. Resumo Executivo da Entrega

A entrega **DB-016** fecha a lacuna de integridade estrutural entre uma instalacao do banco a partir do zero (*clean install*) e um banco atualizado incrementalmente atraves de migrations (*upgrade*), garantindo a ausencia de *schema drift* e fornecendo fixtures sinteticas deterministicas para as entidades aprovadas na branch:

1. **Deteccao de Drift Estrutural na CI (`scripts/detect_drift.sh`):** Desenvolvido mecanismo automatizado que extrai e normaliza o DDL de ambos os bancos (`plataforma` e `plataforma_upgrade_test`) via `pg_dump --schema-only` e executa um `diff -u`. Caso haja qualquer divergencia de tabelas, colunas, tipos, constraints ou indices, a CI falha imediatamente exibindo o diff unificado legivel.
2. **Upgrade Dinamico para Todas as Migrations (`scripts/validate_upgrade.sh`):** O teste de upgrade foi estendido para listar dinamicamente todas as migrations existentes no diretorio `migrations/` (`V0001`, `V0002`, `V0003`, `V0004`, `V0006`, `V0007`, `V0008`, `V0011`). A presenca de `V0006` e `V0008` e explicitamente assegurada, e a idempotencia de `migrate.sh` e `seed.sh` e testada e validada.
3. **Fixtures Deterministicas de Projetos (`seeds/0005_project_tables.sql`):** Criacao de dados sinteticos deterministas cobrindo `academic_pi.project`, `enrollment_period`, `project_instructor` e `project_participation`. As fixtures respeitam rigorosamente todas as regras de negocio do banco (incluindo o limite de 1 PI + 1 Extensao ativos simultaneos por aluno, e justificativa obrigatoria para status `removed`).
4. **Validacao Anti-PII e Integridade Expandida (`scripts/validate.sh`):** Implementados passos 36 e 37 no validador oficial, cobrindo contagem de registros, conformidade de identificadores UUID deterministicos e ausencia total de dados pessoais sensiveis (LGPD).

---

## 2. Matriz de Criterios de Aceite

| Criterio Especifico de Aceite | Status | Evidencia de Cumprimento |
| :--- | :--- | :--- |
| **1. CI cobre todas as migrations presentes, inclusive V0006/V0008 quando estiverem na linha de migrations integrada.** | **ATENDIDO** | `validate_upgrade.sh` e `validate.sh` calculam dinamicamente a lista de migrations via `migrations/*.sql` e validam correspondencia exata em `public.schema_migration`. Assegurada presenca de `V0001,V0002,V0003,V0004,V0006,V0007,V0008,V0011`. |
| **2. Instalacao limpa e upgrade produzem schemas equivalentes; divergencia causa falha legivel.** | **ATENDIDO** | Script `scripts/detect_drift.sh` integrado ao `validate_upgrade.sh` e `Makefile`. Extracao canonica via `pg_dump --schema-only` normalizada (sem comentarios/setvals) e comparada com `diff -u`. Divergencia gera falha imediata com diff detalhado. |
| **3. Fixtures passam pelas constraints reais e nao contem dados pessoais.** | **ATENDIDO** | `seeds/0005_project_tables.sql` implementa 4 projetos, 3 janelas de inscricao, 3 vinculos de docentes e 5 participacoes de alunos. Atendem a todas as FKs compostas, check constraints e indices parciais unicos. Anti-PII validado no passo 37 do `validate.sh`. |
| **4. Evidencia informa commit, comandos e resultado da comparacao.** | **ATENDIDO** | Registrado commit base `8a56402`, comandos executados, procedimentos e logs de execucao comprovando equivalencia estrutural completa. |

---

## 3. Especificacao dos Componentes Desenvolvidos

### 3.1 Script de Deteccao de Drift (`scripts/detect_drift.sh`)
- Executavel de forma independente ou orquestrado pelo `validate_upgrade.sh`.
- Aceita parametros opcionais para banco limpo (padrao: `plataforma`) e banco de upgrade (padrao: `plataforma_upgrade_test`).
- Normaliza DDL via `pg_dump --schema-only --no-owner`:
  - Remove linhas de cabecalho, metadados e comentarios iniciados em `--`.
  - Remove linhas vazias e normaliza quebras de linha (`\r`).
  - Descarta comandos `SELECT pg_catalog.setval(...)`, garantindo que contadores de sequence (dados) nao afetem a comparacao da estrutura (schema).
- Realiza verificacao cruzada de objetos no catalogo (`pg_catalog`).
- Executa `diff -u` entre os arquivos SQL normalizados. Emite saida legivel e encerra com codigo de retorno nao-nulo em caso de divergencia.

### 3.2 Atualizacao do Runner de Upgrade (`scripts/validate_upgrade.sh`)
- Substituicao de lista estatica `('V0002', 'V0003', 'V0004', 'V0006')` por extracao dinamica via `migrations/*.sql`.
- Cobertura de todas as 8 migrations atuais da branch: `V0001`, `V0002`, `V0003`, `V0004`, `V0006`, `V0007`, `V0008`, `V0011`.
- Checagem explicita de presenca de `V0006` e `V0008`.
- Teste de idempotencia de migrations (reexecucao de `migrate.sh` e confirmacao de lista de versoes inalterada).
- Aplicacao e teste de idempotencia de seeds (`seed.sh`).
- Execucao da suite de validacao integral (`validate.sh`).
- Chamada automatica de `./scripts/detect_drift.sh "$CLEAN_DB" "$UPGRADE_DB"`.
- Limpeza segura do banco temporario.

### 3.3 Fixtures Deterministicas de Projetos (`seeds/0005_project_tables.sql`)
- Provisiona 4 projetos:
  - `b0000000-0000-4000-8000-000000000101`: PI publicado e publico (alinhado ao escopo atribuido em `seeds/0004_rbac_roles_and_scopes.sql`).
  - `b0000000-0000-4000-8000-000000000102`: Extensao publicada e publica.
  - `b0000000-0000-4000-8000-000000000103`: Hibrido (PI + Extensao) em rascunho.
  - `b0000000-0000-4000-8000-000000000104`: PI arquivado de ciclo anterior.
- Provisiona 3 periodos de inscricao em `academic_pi.enrollment_period` com datas coerentes (`closes_at >= opens_at`).
- Provisiona 3 responsaveis em `academic_pi.project_instructor` vinculados aos usuarios docentes de `auth.user`.
- Provisiona 5 participacoes em `academic_pi.project_participation`:
  - Aluno 1 com 1 PI aprovado no Projeto 1 e 1 Extensao aprovada no Projeto 2 (valida suporte e conformidade com `idx_project_participation_student_active_pi` e `idx_project_participation_student_active_extension`).
  - Aluno 1 com status `withdrawn` no Projeto 4 (nao consome vaga de PI ativo).
  - Aluno 2 com status `removed` no Projeto 4 acompanhado de justificativa formal valida (`project_participation_justification_ck`).
  - Aluno 2 com solicitacao `requested` no Projeto 3.
- Idempotencia total garantida com clausula `ON CONFLICT (id) DO NOTHING`.

---

## 4. Evidencia de Execucao e Comparacao Estrutural

### 4.1 Comandos Executados na Pipeline de CI
```bash
# 1. Clean Install
make up
make migrate
make seed
make validate

# 2. Upgrade Validation e Deteccao de Drift
make validate-upgrade
```

### 4.2 Log de Execucao da Deteccao de Drift
```
=== [validate_upgrade] Iniciando validacao de upgrade incremental ===
1. Provisionando banco isolado para upgrade: plataforma_upgrade_test...
DROP DATABASE
CREATE DATABASE
2. Aplicando migration baseline (V0001)...
Aplicando migration migrations/V0001__create_domain_schemas.sql em plataforma_upgrade_test...
3. Validando estado pos-V0001...
V0001
4. Executando upgrade com migrate.sh...
Migration V0001 ja aplicada em plataforma_upgrade_test, ignorando.
Aplicando migration migrations/V0002__create_audit_event.sql em plataforma_upgrade_test...
Aplicando migration migrations/V0003__create_identity_user_and_academic_link.sql em plataforma_upgrade_test...
Aplicando migration migrations/V0004__create_user_session.sql em plataforma_upgrade_test...
Aplicando migration migrations/V0006__create_rbac_schema.sql em plataforma_upgrade_test...
Aplicando migration migrations/V0007__restrict_audit_event_to_technical_records.sql em plataforma_upgrade_test...
Aplicando migration migrations/V0008__create_project_tables.sql em plataforma_upgrade_test...
Aplicando migration migrations/V0011__create_project_file_metadata.sql em plataforma_upgrade_test...
5. Verificando que todas as migrations da branch foram aplicadas no upgrade...
   Migrations esperadas: V0001,V0002,V0003,V0004,V0006,V0007,V0008,V0011
   Migrations aplicadas: V0001,V0002,V0003,V0004,V0006,V0007,V0008,V0011
6. Testando idempotencia de migrations (reexecutando migrate.sh no banco atualizado)...
Migration V0001 ja aplicada em plataforma_upgrade_test, ignorando.
Migration V0002 ja aplicada em plataforma_upgrade_test, ignorando.
Migration V0003 ja aplicada em plataforma_upgrade_test, ignorando.
Migration V0004 ja aplicada em plataforma_upgrade_test, ignorando.
Migration V0006 ja aplicada em plataforma_upgrade_test, ignorando.
Migration V0007 ja aplicada em plataforma_upgrade_test, ignorando.
Migration V0008 ja aplicada em plataforma_upgrade_test, ignorando.
Migration V0011 ja aplicada em plataforma_upgrade_test, ignorando.
7. Aplicando seeds deterministicos no banco atualizado...
[seed] Aplicando seeds deterministicos em plataforma_upgrade_test...
[seed] Aplicando seeds/0001_audit_event.sql em plataforma_upgrade_test...
[seed] Aplicando seeds/0002_identity_user_link.sql em plataforma_upgrade_test...
[seed] Aplicando seeds/0003_user_session.sql em plataforma_upgrade_test...
[seed] Aplicando seeds/0004_rbac_roles_and_scopes.sql em plataforma_upgrade_test...
[seed] Aplicando seeds/0005_project_tables.sql em plataforma_upgrade_test...
[seed] 5 arquivo(s) de seed aplicado(s) com sucesso em plataforma_upgrade_test.
8. Testando idempotencia de seeds (reexecutando seed.sh no banco atualizado)...
[seed] Aplicando seeds deterministicos em plataforma_upgrade_test...
[seed] 5 arquivo(s) de seed aplicado(s) com sucesso em plataforma_upgrade_test.
9. Executando suite completa de validacao no banco atualizado...
[validate] Passos 1 a 37 concluidos com sucesso em plataforma_upgrade_test!
10. Detectando drift estrutural entre instalacao limpa (plataforma) e upgrade (plataforma_upgrade_test)...
=== [detect_drift] Iniciando deteccao de drift estrutural de schemas ===
   Banco de instalacao limpa (referencia): plataforma
   Banco de upgrade incremental:          plataforma_upgrade_test
1. Extraindo DDL normalizado da instalacao limpa (plataforma)...
2. Extraindo DDL normalizado do banco atualizado (plataforma_upgrade_test)...
3. Comparando contagem de objetos estruturais via catalogo...
   Clean install: schemas=5,tables=11,constraints=35,indexes=22
   Upgrade:       schemas=5,tables=11,constraints=35,indexes=22
4. Executando diff estrutural entre schemas DDL...
=== [detect_drift] SUCESSO: Nenhum drift detectado! Schemas de instalacao limpa e upgrade sao equivalentes. ===
11. Limpando banco temporario de upgrade...
DROP DATABASE
=== [validate_upgrade] Validacao de upgrade, compatibilidade, idempotencia e ausencia de drift concluida com sucesso! ===
```

### 4.3 Comportamento em Caso de Falha de Drift (Demonstracao)
Se uma alteracao estrutural for omitida ou divergir entre a instalacao limpa e o upgrade (por exemplo, um indice ou coluna faltando em uma migracao incremental), o script interrompe o pipeline e emite a diferenca no padrao unified diff:

```diff
================================================================================
FALHA [detect_drift]: DRIFT ESTRUTURAL DETECTADO ENTRE INSTALACAO LIMPA E UPGRADE!
Divergencias encontradas (clean_schema.sql -> upgrade_schema.sql):
================================================================================
--- /tmp/schema_drift_xxxxxx/clean_schema.sql
+++ /tmp/schema_drift_xxxxxx/upgrade_schema.sql
@@ -142,6 +142,5 @@
 CREATE TABLE academic_pi.project (
     id uuid NOT NULL,
     title character varying(200) NOT NULL,
-    description text,
     is_pi boolean DEFAULT false NOT NULL,
================================================================================
```

---

## 5. Conclusao

A entrega **DB-016** alcanca 100% dos criterios de aceite estabelecidos:
- A esteira de CI cobre todas as migrations vigentes na branch de forma dinamica, auditando inclusive `V0006` e `V0008`.
- A equivalencia estrutural entre clean install e upgrade e garantida matematicamente pela comparacao DDL de zero drift via `detect_drift.sh`.
- Fixtures deterministicas foram criadas para o schema de projetos em total aderencia as restricoes relacionais e a postura Anti-PII da instituicao.
- A evidencia completa encontra-se versionada e pronta para homologacao pela revisora Isabelly.
