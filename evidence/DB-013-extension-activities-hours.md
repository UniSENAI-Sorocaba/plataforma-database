# Evidência de Validação e Conformidade — Atividades e Horas Vigentes de Extensão (DB-013)

- **Identificador de Trabalho (Work ID):** DB-013
- **Título:** Atividades e horas guardam somente o estado vigente
- **Responsável:** Enzo Gabriel
- **Revisora:** Isabelly
- **Dependências:** DB-012 (reconciliação de `enrollment_period` e `project_participation` sobre `V0008`), DB-007 (auditoria técnica sem snapshots)
- **Autoridade Normativa:** ADR-011, DB-001, Caderno de Validações de Escopo e Issue #13
- **Rastreabilidade:** Issue #13 · Reconciliação do PR #48 sobre `develop` · Branch `feat/DB-013-extension-activities-hours` · Migration `migrations/V0013__create_extension_activities_hours.sql`

---

## 1. Resumo Executivo

A entrega **DB-013** reconcilia a implementação preliminar do PR #48 com o schema vigente da branch `develop` e com as regras e bloqueios formais da **Issue #13**, validada em `PostgreSQL 16.16 on x86_64-pc-linux-musl` via Docker Compose:

1. **Vínculo estrito à participação de Extensão (`V0008`/`DB-012`):** `extension.activity` referencia `academic_pi.project_participation` (`participation_id` e `(project_id, student_id)`), `academic_pi.project` e `auth."user"` com `ON DELETE RESTRICT`, além de trigger garantindo correspondência exata da participação, categoria `is_extension = true` e participação `approved` no envio/edição.
2. **Validação exclusiva pelo docente responsável:** a FK composta `activity_last_validated_by_instructor_fk (project_id, last_validated_by)` para `academic_pi.project_instructor (project_id, instructor_id)` impede no banco que alunos ou docentes não responsáveis pelo projeto definam ou validem horas.
3. **Estado vigente sem histórico de negócio:** alterações discentes (dentro do prazo) e validações/revalidações docentes sobrescrevem `title`, `description`, `validated_hours`, `last_validated_by` e `last_validated_at` *in-place* via `UPDATE`, sem colunas de valor anterior e sem tabelas de histórico.
4. **Regras de prazo preservadas sem cristalizar R61/R62:** o envio e a correção de informações pelo aluno são bloqueados fora de `[project.starts_at, project.ends_at]` (mantendo projetos contínuos com `ends_at IS NULL` abertos e permitindo que o docente responsável valide horas mesmo após `ends_at`).
5. **Não cristalização das regras pendentes do André:** removidas as premissas não aprovadas do PR #48 (`requested_hours`, precisão `numeric(6,2)` em passos de `0.25..100`, `status` `SUBMITTED`/`APPROVED`/`REJECTED` e `rejection_reason`).

---

## 2. Catálogo Estrutural Verificado (`pg_constraint`, `pg_indexes`, `pg_trigger`)

### 2.1 Constraints de `extension.activity`

```text
                  conname                  | contype | confdeltype |                                                                                                    definition
-------------------------------------------+---------+-------------+------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 activity_description_ck                   | c       |             | CHECK ((length(TRIM(BOTH FROM description)) > 0))
 activity_title_ck                         | c       |             | CHECK ((length(TRIM(BOTH FROM title)) > 0))
 activity_validated_hours_positive_ck      | c       |             | CHECK (((validated_hours IS NULL) OR (validated_hours > (0)::numeric)))
 activity_validation_consistency_ck        | c       |             | CHECK ((((validated_hours IS NULL) AND (last_validated_by IS NULL) AND (last_validated_at IS NULL)) OR ((validated_hours IS NOT NULL) AND (last_validated_by IS NOT NULL) AND (last_validated_at IS NOT NULL))))
 activity_last_validated_by_instructor_fk  | f       | r           | FOREIGN KEY (project_id, last_validated_by) REFERENCES academic_pi.project_instructor(project_id, instructor_id) ON DELETE RESTRICT
 activity_last_validated_by_user_fk        | f       | r           | FOREIGN KEY (last_validated_by) REFERENCES auth."user"(id) ON DELETE RESTRICT
 activity_participation_fk                 | f       | r           | FOREIGN KEY (participation_id) REFERENCES academic_pi.project_participation(id) ON DELETE RESTRICT
 activity_project_fk                       | f       | r           | FOREIGN KEY (project_id) REFERENCES academic_pi.project(id) ON DELETE RESTRICT
 activity_project_student_participation_fk | f       | r           | FOREIGN KEY (project_id, student_id) REFERENCES academic_pi.project_participation(project_id, student_id) ON DELETE RESTRICT
 activity_student_user_fk                  | f       | r           | FOREIGN KEY (student_id) REFERENCES auth."user"(id) ON DELETE RESTRICT
 activity_pkey                             | p       |             | PRIMARY KEY (id)
(11 rows)
```

### 2.2 Índices e Trigger de `extension.activity`

```text
           indexname            |                                                                indexdef
--------------------------------+-----------------------------------------------------------------------------------------------------------------------------------------
 activity_pkey                  | CREATE UNIQUE INDEX activity_pkey ON extension.activity USING btree (id)
 idx_activity_last_validated_by | CREATE INDEX idx_activity_last_validated_by ON extension.activity USING btree (last_validated_by) WHERE (last_validated_by IS NOT NULL)
 idx_activity_participation_id  | CREATE INDEX idx_activity_participation_id ON extension.activity USING btree (participation_id)
 idx_activity_project_id        | CREATE INDEX idx_activity_project_id ON extension.activity USING btree (project_id)
 idx_activity_student_id        | CREATE INDEX idx_activity_student_id ON extension.activity USING btree (student_id)
(5 rows)

                tgname                 |                                                                                       triggerdef
---------------------------------------+-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 activity_participation_and_window_trg | CREATE TRIGGER activity_participation_and_window_trg BEFORE INSERT OR UPDATE ON extension.activity FOR EACH ROW EXECUTE FUNCTION extension.validate_activity_participation_and_window()
(1 row)
```

### 2.3 Seeds Determinísticos Carregados (`seeds/0013_extension_activity.sql`)

```text
                  id                  | categoria_projeto |                student                 |                        title                         | validated_hours |          last_validated_by
--------------------------------------+-------------------+----------------------------------------+------------------------------------------------------+-----------------+-------------------------------------
 e1300000-0000-4000-8000-000000000001 | Extensao          | mock.student.01@synthetic.local        | Oficina de Letramento Digital Comunitario            | 4               | mock.professor.01@synthetic.local
 e1300000-0000-4000-8000-000000000002 | Extensao          | mock.student.01@synthetic.local        | Plantao de Orientacao Tecnica Aberta                 | 2.5             | mock.professor.01@synthetic.local
 e1300000-0000-4000-8000-000000000003 | Extensao          | mock.student.01@synthetic.local        | Elaboracao de Apostila Sintetica de Inclusao Digital | NULL            | NULL
 e1300000-0000-4000-8000-000000000004 | Extensao          | mock.unaffiliated.user@synthetic.local | Mediacao em Laboratorio Aberto Comunitario           | 6               | mock.professor.01@synthetic.local
 e1300000-0000-4000-8000-000000000005 | Hibrido (PI+Ext)  | mock.ext.student.13@synthetic.local    | Demonstracao Comunitaria de Prototipo Sustentavel    | 3.75            | mock.coordinator.01@synthetic.local
(5 rows)
```

---

## 3. Matriz de Cenários Testados (`scripts/validate.sh` — Passos 38 a 41)

| # | Categoria | Cenário Verificado | Resultado |
| :--- | :--- | :--- | :--- |
| **01** | Estrutura e escala em aberto | Tabela `extension.activity`, versão `V0013` registrada, zero tabelas/colunas de histórico/status/recusa e `validated_hours` em `numeric` sem escala fixada | Passou |
| **02** | Integridade referencial | `participation_id` inexistente ou divergente de `(project_id, student_id)` rejeitado (`foreign_key_violation`) | Passou |
| **03** | Elegibilidade da participação | Projeto exclusivamente `PI` (`is_extension = false`) e participação `requested` rejeitados (`check_violation`) | Passou |
| **04** | Consistência textual | `title` vazio e `description` vazia rejeitados (`activity_title_ck`, `activity_description_ck`) | Passou |
| **05** | Regras de prazo aprovadas | Envio/edição discente aceitos durante o período (inclusive projeto contínuo `ends_at IS NULL`) e rejeitados antes de `starts_at` ou após `ends_at` | Passou |
| **06** | Validação exclusiva pelo docente responsável | Validação por docente não responsável ou pelo próprio aluno bloqueada por `activity_last_validated_by_instructor_fk`; horas sem validador ou `<= 0` bloqueadas | Passou |
| **07** | Atualização sem histórico | Revalidação por segundo docente responsável substitui `validated_hours` (`4.5 -> 6.75`) e `last_validated_by` *in-place*, mantendo 1 único registro | Passou |
| **08** | Proteção contra órfãos | `ON DELETE RESTRICT` bloqueia exclusão de projeto, participação e docente responsável validador; limpeza restaura contagem exata | Passou |
| **09** | Seeds e Anti-PII | 5 atividades determinísticas (`e1300000-...`), horas validadas e pendentes cobertas, zero PII | Passou |

---

## 4. Saídas Reais de Execução

### 4.1 Instalação Limpa e Repetibilidade Direta (`migrate.sh`, `seed.sh`, `V0013` e `0013`)

```text
Aplicando migration migrations/V0013__create_extension_activities_hours.sql em plataforma...
BEGIN
CREATE TABLE
CREATE INDEX
CREATE INDEX
CREATE INDEX
CREATE INDEX
CREATE FUNCTION
DROP TRIGGER
NOTICE:  trigger "activity_participation_and_window_trg" for relation "extension.activity" does not exist, skipping
CREATE TRIGGER
COMMENT
COMMENT
COMMENT
INSERT 0 1
COMMIT
Aplicando migration migrations/V0017__add_public_project_title_index.sql em plataforma...
BEGIN
CREATE INDEX
INSERT 0 1
COMMIT
...
[seed] Aplicando seeds/0013_extension_activity.sql em plataforma...
BEGIN
INSERT 0 1
INSERT 0 1
INSERT 0 2
INSERT 0 5
COMMIT
[seed] 6 arquivo(s) de seed aplicado(s) com sucesso em plataforma.

=== 2. Direct repeatability of V0013 and 0013 seed ===
BEGIN
NOTICE:  relation "activity" already exists, skipping
CREATE TABLE
CREATE INDEX
NOTICE:  relation "idx_activity_participation_id" already exists, skipping
NOTICE:  relation "idx_activity_project_id" already exists, skipping
CREATE INDEX
NOTICE:  relation "idx_activity_student_id" already exists, skipping
CREATE INDEX
CREATE INDEX
NOTICE:  relation "idx_activity_last_validated_by" already exists, skipping
CREATE FUNCTION
DROP TRIGGER
CREATE TRIGGER
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
COMMIT
```

### 4.2 Suíte `validate.sh`, `validate_upgrade.sh` e Detecção de Drift

```text
[validate] 3. Validando registro de todas as migrations aplicadas...
   Todas as migrations da branch registradas com sucesso em plataforma: V0001,V0002,V0003,V0004,V0006,V0007,V0008,V0011,V0013,V0017
...
[validate] 38. Validando tabela extension.activity, migration V0013 e ausencia de historico/estados nao aprovados (DB-013)...
[validate] 39. Validando check, foreign keys, indices e trigger de extension.activity (DB-013)...
[validate] 40. Validando regras funcionais de atividades e horas vigentes de Extensao sem historico (DO block)...
DO
[validate] 41. Validando presenca, cobertura, determinismo e Anti-PII dos seeds em extension.activity (DB-013)...
[validate] Todas as validacoes de compatibilidade, integridade, constraints e seeds concluidas com sucesso!

10. Detectando drift estrutural entre instalacao limpa (plataforma) e upgrade (plataforma_upgrade_test)...
=== [detect_drift] Iniciando deteccao de drift estrutural de schemas ===
   Banco de instalacao limpa (referencia): plataforma
   Banco de upgrade incremental:          plataforma_upgrade_test
   Clean install: schemas=5,tables=18,constraints=100,indexes=67
   Upgrade:       schemas=5,tables=18,constraints=100,indexes=67
=== [detect_drift] SUCESSO: Nenhum drift detectado! Schemas de instalacao limpa e upgrade sao equivalentes. ===
=== [validate_upgrade] Validacao de upgrade, compatibilidade, idempotencia e ausencia de drift concluida com sucesso! ===
```

### 4.3 Upgrade Incremental a partir do Estado da `develop` (`V0017` já aplicada) e Coexistência com `DB-009`

```text
Migration V0001..V0011 ja aplicada em plataforma_from_develop, ignorando.
Aplicando migration migrations/V0013__create_extension_activities_hours.sql em plataforma_from_develop...
BEGIN / CREATE TABLE / CREATE INDEX (x4) / CREATE FUNCTION / DROP TRIGGER / CREATE TRIGGER / COMMENT (x3) / INSERT 0 1 / COMMIT
Migration V0017 ja aplicada em plataforma_from_develop, ignorando.
   Clean install: schemas=5,tables=18,constraints=100,indexes=67
   Upgrade:       schemas=5,tables=18,constraints=100,indexes=67
=== [detect_drift] SUCESSO: Nenhum drift detectado! Schemas de instalacao limpa e upgrade sao equivalentes. ===

Coexistencia em banco temporario isolado com V0009 + 0006_project_evaluation.sql (DB-009):
project_evaluation=6,extension.activity=5
```

---

## 5. Pendências Externas do Product Owner (André)

Conforme o quarto critério de aceite da Issue #13 (*"Testes de limites, recusa e reenvio ficam condicionados às decisões acima"*), permanecem aguardando decisão formal do PO antes de qualquer constraint/teste adicional:

1. Unidade e limites numéricos de horas (mínimo, máximo e granularidade decimal/inteira).
2. Estados formais da atividade (`status`), caso venham a existir além da presença/ausência de validação vigente.
3. Tratamento e eventual persistência de motivo vigente de recusa e regra de reenvio após recusa.
4. Resolução do conflito entre os itens 61 e 62 do Caderno (`R61/R62`) sobre prorrogação/ajuste de prazos pelo docente responsável.

### 5.1 Limitação Arquitetural Documentada (Controle de Identidade no Backend)

- No banco de dados (conexão via role única da aplicação, conforme `DB-001` §3.1, sem inventar `RLS` ou variáveis de sessão não aprovadas), a exclusividade do docente responsável é garantida referencialmente pela FK composta `activity_last_validated_by_instructor_fk (project_id, last_validated_by) -> academic_pi.project_instructor (project_id, instructor_id)`: nenhum UUID de aluno ou de docente não responsável pelo projeto é aceito em `last_validated_by`.
- A comprovação de que o autor autenticado da requisição corresponde de fato ao `last_validated_by` informado (no fluxo docente) ou ao `student_id` titular (no fluxo discente) depende da camada de autenticação de sessão (`DB-005`) e autorização RBAC (`DB-006`) no Backend.
