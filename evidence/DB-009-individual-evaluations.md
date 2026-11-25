# Evidência de Validação e Conformidade — Avaliações Individuais sem Banca (DB-009)

- **Identificador de Trabalho (Work ID):** DB-009
- **Título:** Persistência de avaliações individuais sem banca
- **Responsável:** Enzo Gabriel
- **Revisor:** Henrique
- **Dependências:** DB-008 (`academic_pi.project`, `academic_pi.project_instructor`, `academic_pi.project_participation`)
- **Autoridade Normativa:** ADR-011, DB-001, SPEC-PI-002, SPEC-PI-003 e Caderno de Validações de Escopo
- **Rastreabilidade:** Issue #9 · Branch `feat/DB-009-individual-evaluations` · Migration `migrations/V0009__create_project_evaluation.sql`

---

## 1. Resumo Executivo

A entrega **DB-009** implementa e valida em PostgreSQL 16 (`PostgreSQL 16.16 on x86_64-pc-linux-musl, compiled by gcc (Alpine 15.2.0) 15.2.0, 64-bit` via `compose.yaml`) a persistência relacional de avaliações individuais no schema `academic_pi`:

1. **Migration Incremental e Repetível (`V0009`):** `migrations/V0009__create_project_evaluation.sql` cria `academic_pi.project_evaluation` dentro de transação explícita (`BEGIN; ... COMMIT;`), com `CREATE TABLE IF NOT EXISTS`, quatro índices `CREATE INDEX IF NOT EXISTS` e registro idempotente em `public.schema_migration`.
2. **Integridade Referencial e Sem Órfãos:** todas as cinco FKs (`project_id`, `evaluator_user_id`, `evaluated_student_id`, `(project_id, evaluated_student_id)` em `academic_pi.project_participation` e `assigned_by_user_id`) utilizam `ON DELETE RESTRICT`.
3. **Sem Banca, Agenda ou Cristalização Prematura:** nenhuma tabela ou coluna de banca, comitê, sala, link, agenda, conflito ou status especulativo foi criada; não foram impostas `UNIQUE (project_id, evaluator_user_id, evaluated_student_id)` nem proibição de autoavaliação sem validação formal do André (PO).
4. **Compatibilidade com DB-010:** incluída a restrição `project_evaluation_id_project_unq UNIQUE (id, project_id)` para suportar FK composta de notas por critério na DB-010.
5. **Seeds Determinísticos e Anti-PII (`0006_project_evaluation.sql`):** 6 avaliações determinísticas (`d4000000-0000-4000-8000-000000000001` a `...0006`) cobrindo PI, Extensão, avaliação entre alunos, docente não responsável avaliando na Extensão, atribuições pela coordenação com data e múltiplas avaliações por projeto.

---

## 2. Catálogo Estrutural Verificado no Banco (`pg_constraint` e `pg_indexes`)

### 2.1 Constraints de `academic_pi.project_evaluation`

```text
                conname                 | contype | confdeltype |                                                               definition
----------------------------------------+---------+-------------+----------------------------------------------------------------------------------------------------------------------------------------
 project_evaluation_assignment_ck       | c       |             | CHECK (((assigned_by_user_id IS NULL) = (evaluation_date IS NULL)))
 project_evaluation_assigned_by_user_fk | f       | r           | FOREIGN KEY (assigned_by_user_id) REFERENCES auth."user"(id) ON DELETE RESTRICT
 project_evaluation_evaluated_user_fk   | f       | r           | FOREIGN KEY (evaluated_student_id) REFERENCES auth."user"(id) ON DELETE RESTRICT
 project_evaluation_evaluator_user_fk   | f       | r           | FOREIGN KEY (evaluator_user_id) REFERENCES auth."user"(id) ON DELETE RESTRICT
 project_evaluation_participation_fk    | f       | r           | FOREIGN KEY (project_id, evaluated_student_id) REFERENCES academic_pi.project_participation(project_id, student_id) ON DELETE RESTRICT
 project_evaluation_project_fk          | f       | r           | FOREIGN KEY (project_id) REFERENCES academic_pi.project(id) ON DELETE RESTRICT
 project_evaluation_pkey                | p       |             | PRIMARY KEY (id)
 project_evaluation_id_project_unq      | u       |             | UNIQUE (id, project_id)
(8 rows)
```

### 2.2 Índices de `academic_pi.project_evaluation`

```text
                  indexname                  |                                                                              indexdef
---------------------------------------------+---------------------------------------------------------------------------------------------------------------------------------------------------------------------
 idx_project_evaluation_assigned_by_user_id  | CREATE INDEX idx_project_evaluation_assigned_by_user_id ON academic_pi.project_evaluation USING btree (assigned_by_user_id) WHERE (assigned_by_user_id IS NOT NULL)
 idx_project_evaluation_evaluated_student_id | CREATE INDEX idx_project_evaluation_evaluated_student_id ON academic_pi.project_evaluation USING btree (evaluated_student_id)
 idx_project_evaluation_evaluator_user_id    | CREATE INDEX idx_project_evaluation_evaluator_user_id ON academic_pi.project_evaluation USING btree (evaluator_user_id)
 idx_project_evaluation_project_id           | CREATE INDEX idx_project_evaluation_project_id ON academic_pi.project_evaluation USING btree (project_id)
 project_evaluation_id_project_unq           | CREATE UNIQUE INDEX project_evaluation_id_project_unq ON academic_pi.project_evaluation USING btree (id, project_id)
 project_evaluation_pkey                     | CREATE UNIQUE INDEX project_evaluation_pkey ON academic_pi.project_evaluation USING btree (id)
(6 rows)
```

### 2.3 Registros Determinísticos Carregados (`seeds/0006_project_evaluation.sql`)

```text
                  id                  | categoria |             evaluator             | is_resp_instructor |        evaluated_student        |             assigned_by             | evaluation_date
--------------------------------------+-----------+-----------------------------------+--------------------+---------------------------------+-------------------------------------+-----------------
 d4000000-0000-4000-8000-000000000001 | PI        | mock.professor.01@synthetic.local | t                  | mock.student.01@synthetic.local | -                                   | -
 d4000000-0000-4000-8000-000000000002 | PI        | mock.student.02@synthetic.local   | f                  | mock.student.01@synthetic.local | mock.coordinator.01@synthetic.local | 2026-06-15
 d4000000-0000-4000-8000-000000000003 | PI        | mock.student.01@synthetic.local   | f                  | mock.student.02@synthetic.local | mock.coordinator.01@synthetic.local | 2026-06-16
 d4000000-0000-4000-8000-000000000004 | Extensao  | mock.professor.01@synthetic.local | t                  | mock.student.01@synthetic.local | -                                   | -
 d4000000-0000-4000-8000-000000000005 | Extensao  | mock.professor.02@synthetic.local | f                  | mock.student.01@synthetic.local | -                                   | -
 d4000000-0000-4000-8000-000000000006 | Extensao  | mock.student.02@synthetic.local   | f                  | mock.student.01@synthetic.local | -                                   | -
(6 rows)
```

---

## 3. Matriz de Cenários Testados (`scripts/validate.sh` — Passos 38 a 41)

| # | Categoria | Cenário Verificado | Resultado |
| :--- | :--- | :--- | :--- |
| **01** | Estrutura e versão | Tabela `academic_pi.project_evaluation` criada e versão `V0009` registrada em `public.schema_migration` | Passou |
| **02** | Ausência de banca/agenda | Zero tabelas ou colunas de banca, comitê, agenda, sala, link, conflito ou status especulativo | Passou |
| **03** | Constraints e índices | 1 `CHECK`, 1 `UNIQUE (id, project_id)`, 5 `FOREIGN KEY` com `ON DELETE RESTRICT` e 4 índices `idx_project_evaluation_*` | Passou |
| **04** | FK de projeto | Inserção com `project_id` inexistente rejeitada (`foreign_key_violation`) | Passou |
| **05** | FK de avaliador e atribuidor | Inserção com `evaluator_user_id` ou `assigned_by_user_id` inexistente em `auth."user"` rejeitada (`foreign_key_violation`) | Passou |
| **06** | Participação do avaliado | Usuário inexistente, usuário sem participação e aluno participante apenas de outro projeto rejeitados por `project_evaluation_participation_fk` | Passou |
| **07** | Restrições de atribuição | `assigned_by_user_id` sem `evaluation_date` e `evaluation_date` sem `assigned_by_user_id` rejeitados por `project_evaluation_assignment_ck` | Passou |
| **08** | Cardinalidade variável | Projeto com 0 avaliações válido; projeto PI com 5 avaliações e projeto de Extensão com múltiplas avaliações aceitos | Passou |
| **09** | Regras pendentes não cristalizadas | Repetição de tripla `(project_id, evaluator_user_id, evaluated_student_id)` e registro com `evaluator_user_id = evaluated_student_id` não sofrem bloqueio prematuro no schema | Passou |
| **10** | Proteção contra órfãos | `DELETE` bloqueado por `ON DELETE RESTRICT` em `project`, `project_participation`, avaliador e atribuidor; limpeza final restaura exatamente a contagem original | Passou |
| **11** | Cobertura de seeds | 6 avaliações determinísticas (`d4000000-...`), cobrindo PI, Extensão, pares, docente não responsável na Extensão e múltiplas avaliações por projeto | Passou |

---

## 4. Saídas Reais de Execução

### 4.1 Instalação Limpa (`./scripts/migrate.sh` e `./scripts/seed.sh`)

```text
Aplicando migration migrations/V0001__create_domain_schemas.sql em plataforma...
BEGIN
CREATE SCHEMA
CREATE SCHEMA
CREATE SCHEMA
CREATE SCHEMA
CREATE SCHEMA
CREATE TABLE
INSERT 0 1
COMMIT
Aplicando migration migrations/V0002__create_audit_event.sql em plataforma...
BEGIN
CREATE TABLE
CREATE INDEX
CREATE INDEX
CREATE INDEX
INSERT 0 1
COMMIT
Aplicando migration migrations/V0003__create_identity_user_and_academic_link.sql em plataforma...
BEGIN
CREATE TABLE
CREATE INDEX
CREATE INDEX
CREATE INDEX
CREATE TABLE
CREATE INDEX
CREATE INDEX
CREATE TABLE
CREATE INDEX
CREATE INDEX
CREATE INDEX
CREATE TABLE
CREATE INDEX
CREATE INDEX
CREATE INDEX
INSERT 0 1
COMMIT
Aplicando migration migrations/V0004__create_user_session.sql em plataforma...
BEGIN
CREATE TABLE
CREATE INDEX
CREATE INDEX
CREATE INDEX
INSERT 0 1
COMMIT
Aplicando migration migrations/V0006__create_rbac_schema.sql em plataforma...
BEGIN
CREATE TABLE
CREATE TABLE
CREATE TABLE
CREATE TABLE
DO
DO
CREATE INDEX
CREATE INDEX
CREATE INDEX
CREATE INDEX
INSERT 0 1
COMMIT
Aplicando migration migrations/V0007__restrict_audit_event_to_technical_records.sql em plataforma...
BEGIN
UPDATE 0
ALTER TABLE
NOTICE:  constraint "audit_event_no_snapshot_ck" of relation "audit_event" does not exist, skipping
ALTER TABLE
COMMENT
COMMENT
COMMENT
INSERT 0 1
COMMIT
Aplicando migration migrations/V0008__create_project_tables.sql em plataforma...
BEGIN
CREATE TABLE
CREATE TABLE
CREATE INDEX
CREATE TABLE
CREATE INDEX
CREATE TABLE
CREATE INDEX
CREATE INDEX
CREATE INDEX
DO
DO
INSERT 0 1
COMMIT
Aplicando migration migrations/V0009__create_project_evaluation.sql em plataforma...
BEGIN
CREATE TABLE
CREATE INDEX
CREATE INDEX
CREATE INDEX
CREATE INDEX
COMMENT
COMMENT
COMMENT
INSERT 0 1
COMMIT
Aplicando migration migrations/V0011__create_project_file_metadata.sql em plataforma...
BEGIN
CREATE TABLE
COMMENT
CREATE TABLE
CREATE INDEX
CREATE INDEX
CREATE INDEX
CREATE INDEX
CREATE INDEX
COMMENT
COMMENT
INSERT 0 1
COMMIT
Aplicando migration migrations/V0017__add_public_project_title_index.sql em plataforma...
BEGIN
CREATE INDEX
INSERT 0 1
COMMIT

[seed] Aplicando seeds deterministicos em plataforma...
[seed] Aplicando seeds/0001_audit_event.sql em plataforma...
INSERT 0 15
[seed] Aplicando seeds/0002_identity_user_link.sql em plataforma...
INSERT 0 5
INSERT 0 2
INSERT 0 2
INSERT 0 5
[seed] Aplicando seeds/0003_user_session.sql em plataforma...
INSERT 0 1
INSERT 0 4
[seed] Aplicando seeds/0004_rbac_roles_and_scopes.sql em plataforma...
BEGIN
INSERT 0 3
INSERT 0 7
INSERT 0 2
INSERT 0 4
INSERT 0 1
INSERT 0 1
INSERT 0 1
INSERT 0 1
INSERT 0 1
INSERT 0 1
INSERT 0 1
INSERT 0 1
COMMIT
[seed] Aplicando seeds/0005_project_tables.sql em plataforma...
BEGIN
INSERT 0 4
INSERT 0 3
INSERT 0 3
INSERT 0 5
COMMIT
[seed] Aplicando seeds/0006_project_evaluation.sql em plataforma...
BEGIN
INSERT 0 2
INSERT 0 2
INSERT 0 1
INSERT 0 1
INSERT 0 1
INSERT 0 1
INSERT 0 6
COMMIT
[seed] 6 arquivo(s) de seed aplicado(s) com sucesso em plataforma.
```

### 4.2 Repetibilidade Direta da `V0009` e do Seed `0006`

```text
BEGIN
CREATE TABLE
NOTICE:  relation "project_evaluation" already exists, skipping
NOTICE:  relation "idx_project_evaluation_project_id" already exists, skipping
CREATE INDEX
NOTICE:  relation "idx_project_evaluation_evaluator_user_id" already exists, skipping
CREATE INDEX
CREATE INDEX
NOTICE:  relation "idx_project_evaluation_evaluated_student_id" already exists, skipping
NOTICE:  relation "idx_project_evaluation_assigned_by_user_id" already exists, skipping
CREATE INDEX
COMMENT
COMMENT
COMMENT
INSERT 0 0
COMMIT
BEGIN
INSERT 0 0
INSERT 0 0
INSERT 0 0
INSERT 0 0
INSERT 0 0
INSERT 0 0
INSERT 0 0
COMMIT
```

### 4.3 Suíte Completa de Validação (`./scripts/validate.sh`)

```text
[validate] 1. Validando schemas de dominio em plataforma...
[validate] 2. Validando tabela public.schema_migration...
[validate] 3. Validando registro de todas as migrations aplicadas...
   Todas as migrations da branch registradas com sucesso em plataforma: V0001,V0002,V0003,V0004,V0006,V0007,V0008,V0009,V0011,V0017
...
[validate] 38. Validando tabela academic_pi.project_evaluation, migration V0009 e ausencia de banca/agenda (DB-009)...
[validate] 39. Validando check, unique, foreign keys e indices de academic_pi.project_evaluation (DB-009)...
[validate] 40. Validando regras funcionais e de integridade de academic_pi.project_evaluation (DO block)...
DO
[validate] 41. Validando presenca, cobertura de cenarios e determinismo dos seeds em academic_pi.project_evaluation (DB-009)...
[validate] Todas as validacoes de compatibilidade, integridade, constraints e seeds concluidas com sucesso!
```

### 4.4 Upgrade Incremental, Idempotência e Detecção de Drift (`./scripts/validate_upgrade.sh`)

```text
=== [validate_upgrade] Iniciando validacao de upgrade incremental ===
1. Provisionando banco isolado para upgrade: plataforma_upgrade_test...
2. Aplicando migration baseline (V0001)...
3. Validando estado pos-V0001...
4. Executando upgrade com migrate.sh...
   ...
   Aplicando migration migrations/V0009__create_project_evaluation.sql em plataforma_upgrade_test...
   BEGIN / CREATE TABLE / CREATE INDEX (x4) / COMMENT (x3) / INSERT 0 1 / COMMIT
5. Verificando que todas as migrations da branch foram aplicadas no upgrade...
   Migrations esperadas: V0001,V0002,V0003,V0004,V0006,V0007,V0008,V0009,V0011,V0017
   Migrations aplicadas: V0001,V0002,V0003,V0004,V0006,V0007,V0008,V0009,V0011,V0017
6. Testando idempotencia de migrations (reexecutando migrate.sh no banco atualizado)...
   Migration V0001..V0017 ja aplicada em plataforma_upgrade_test, ignorando.
7. Aplicando seeds deterministicos no banco atualizado...
   [seed] 6 arquivo(s) de seed aplicado(s) com sucesso em plataforma_upgrade_test.
8. Testando idempotencia de seeds (reexecutando seed.sh no banco atualizado)...
   INSERT 0 0 em todos os comandos dos 6 arquivos de seed.
9. Executando suite completa de validacao no banco atualizado...
   [validate] Todas as validacoes de compatibilidade, integridade, constraints e seeds concluidas com sucesso!
10. Detectando drift estrutural entre instalacao limpa (plataforma) e upgrade (plataforma_upgrade_test)...
=== [detect_drift] Iniciando deteccao de drift estrutural de schemas ===
   Banco de instalacao limpa (referencia): plataforma
   Banco de upgrade incremental:          plataforma_upgrade_test
1. Extraindo DDL normalizado da instalacao limpa (plataforma)...
2. Extraindo DDL normalizado do banco atualizado (plataforma_upgrade_test)...
3. Comparando contagem de objetos estruturais via catalogo...
   Clean install: schemas=5,tables=18,constraints=97,indexes=68
   Upgrade:       schemas=5,tables=18,constraints=97,indexes=68
4. Executando diff estrutural entre schemas DDL...
=== [detect_drift] SUCESSO: Nenhum drift detectado! Schemas de instalacao limpa e upgrade sao equivalentes. ===
11. Limpando banco temporario de upgrade...
DROP DATABASE
=== [validate_upgrade] Validacao de upgrade, compatibilidade, idempotencia e ausencia de drift concluida com sucesso! ===
```

---

## 5. Regras Pendentes de Validação pelo André e Limitações Conhecidas

- **Pendentes do PO (não inferidas no schema):** autorização detalhada de avaliadores na Extensão, relação entre atribuições discentes e avaliações docentes, eventual unicidade por tripla `(project_id, evaluator_user_id, evaluated_student_id)`, regra formal sobre autoavaliação, estados/prazos de avaliação e matriz de visibilidade de dados individuais por papel.
- **Execução de validação:** executada localmente em container PostgreSQL 16.16 via scripts oficiais do repositório (`migrate.sh`, `seed.sh`, `validate.sh`, `validate_upgrade.sh`, `detect_drift.sh`), preservando volumes e containers do ambiente.
