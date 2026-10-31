**Identificador de Trabalho (Work ID):** DB-008  
**Título:** Propostas, equipes e solicitações de participação com integridade garantida pelo banco  
**Responsável:** Diogo Lopes  
**Revisora:** Isabelly-Caroline  
**Dependências:** DB-004 (`auth."user"`)  
**Autoridade Normativa:** Caderno de Validações de Escopo (AUTH, PI e Extensão), itens 28 a 37; SPEC-PI-001 (em Draft; o caderno prevalece onde divergem)  
**Rastreabilidade:** Issue #8 · PR do ciclo 1: #33 (mergeado na `develop`) · Branch do ciclo 2: `DB-008-fks-e-validacao`  

---

## 1. Resumo Executivo da Entrega

A entrega **DB-008** implementa a modelagem relacional, a migration incremental, as restrições de integridade, os índices e as validações automatizadas para projetos, equipes e participação de alunos no schema `academic_pi`.

A entrega foi feita em dois ciclos:

- **Ciclo 1 (PR #33, mergeado):** criação da `V0008` com quatro tabelas e testes manuais de integridade.
- **Ciclo 2 (esta branch):** correção das pendências apontadas pelo time: chaves estrangeiras de `student_id` e `instructor_id` para `auth."user"`, passos da DB-008 no `validate.sh` e evidência real.

Pontos principais:

- **Fluxo de solicitação, não de convite:** o Caderno de Validações (item 31) define que não há convites individuais. O aluno solicita participação durante o período de inscrição e o docente aprova ou nega.
- **Modelagem Relacional:** quatro tabelas (`project`, `enrollment_period`, `project_instructor`, `project_participation`), com `ON DELETE RESTRICT` em todas as FKs, porque a participação é histórico acadêmico.
- **Categorias por flags:** `is_pi` e `is_extension` em vez de enum, permitindo projeto nas duas categorias sem valor `HYBRID`.
- **Limite de 1 PI + 1 Extensão por aluno no banco:** FK composta `(project_id, is_pi, is_extension)` e dois índices únicos parciais sobre participações `requested`/`approved`. Projeto nas duas categorias ocupa as duas vagas. Solicitações concorrentes são decididas pelo próprio banco.
- **Justificativa obrigatória na remoção:** `project_participation_justification_ck`.
- **FKs para usuários (ciclo 2):** `project_instructor_user_fk` e `project_participation_user_fk` apontam para `auth."user" (id)`, criadas por bloco `DO $$` repetível, com checagem em `pg_constraint` e diagnóstico prévio de órfãos (resultado: 0 aluno e 0 docente sem usuário).
- **Migration atômica (`V0008`):** `migrations/V0008__create_project_tables.sql`, protegida por transação e registrada em `public.schema_migration`.
- **Automação de validação:** `scripts/validate.sh` com os passos 23 a 26 da DB-008. O `scripts/validate_upgrade.sh` não foi alterado.

---

## 2. Especificação Estrutural e Matriz de Objetos Criados

### 2.1 Tabelas

| Schema | Tabela | Finalidade | Chave Primária |
| :--- | :--- | :--- | :--- |
| `academic_pi` | `project` | Projeto, com flags `is_pi` e `is_extension`, status (`draft`/`published`/`archived`), `is_public` e datas | UUID (aplicação) |
| `academic_pi` | `enrollment_period` | Período de inscrição por projeto (`opens_at`, `closes_at`) | UUID (aplicação) |
| `academic_pi` | `project_instructor` | Docentes responsáveis (vários por projeto) | UUID (aplicação) |
| `academic_pi` | `project_participation` | Solicitação do aluno, com status (`requested`/`approved`/`denied`/`withdrawn`/`removed`), justificativa e datas | UUID (aplicação) |

### 2.2 Restrições de Integridade (Constraints)

**CHECK**

| Tabela | Restrição | Regra |
| :--- | :--- | :--- |
| `project` | `project_category_ck` | Projeto precisa ter ao menos uma categoria (`is_pi` ou `is_extension`) |
| `project` | `project_title_ck` | Título não pode ser vazio |
| `project` | `project_status_ck` | Status restrito a `draft`, `published`, `archived` |
| `project` | `project_period_ck` | Coerência entre as datas do projeto |
| `enrollment_period` | `enrollment_period_window_ck` | Fechamento posterior à abertura |
| `project_participation` | `project_participation_status_ck` | Status restrito a `requested`, `approved`, `denied`, `withdrawn`, `removed` |
| `project_participation` | `project_participation_category_ck` | Participação precisa ter ao menos uma categoria |
| `project_participation` | `project_participation_justification_ck` | Remoção exige justificativa |

**UNIQUE**

| Tabela | Restrição | Regra |
| :--- | :--- | :--- |
| `project` | `project_id_category_unq` | `(id, is_pi, is_extension)`, base da FK composta |
| `project_instructor` | `project_instructor_project_instructor_unq` | Um docente por projeto, sem repetição |
| `project_participation` | `project_participation_project_student_unq` | Um registro por aluno em cada projeto |

**FOREIGN KEY** (todas com `ON DELETE RESTRICT`)

| Tabela | Restrição | Referência |
| :--- | :--- | :--- |
| `enrollment_period` | `enrollment_period_project_fk` | `academic_pi.project` |
| `project_instructor` | `project_instructor_project_fk` | `academic_pi.project` |
| `project_instructor` | `project_instructor_user_fk` | `auth."user" (id)` (ciclo 2) |
| `project_participation` | `project_participation_project_fk` | `academic_pi.project (id, is_pi, is_extension)` (FK composta) |
| `project_participation` | `project_participation_user_fk` | `auth."user" (id)` (ciclo 2) |

### 2.3 Índices

- `idx_enrollment_period_project_id`
- `idx_project_instructor_instructor_id`
- `idx_project_participation_student_id`
- `idx_project_participation_student_active_pi` (único parcial: um PI ativo por aluno)
- `idx_project_participation_student_active_extension` (único parcial: uma Extensão ativa por aluno)

---

## 3. Mapeamento com o Caderno de Validações

| Item | Regra | Como o banco atende |
| :--- | :--- | :--- |
| 28 | Projeto contínuo ou com data de fim | Datas do projeto com `project_period_ck` |
| 29 | Rascunho ou publicado | `project_status_ck` |
| 30 | Docente responsável; remoção exige justificativa | `project_instructor`; `project_participation_justification_ck` |
| 31 | Períodos de inscrição; aluno solicita, docente aprova ou nega | `enrollment_period`; status `requested`/`approved`/`denied` |
| 32 | Um PI e uma Extensão por vez; projeto nas duas categorias conta nos dois | FK composta e índices únicos parciais |
| 35 | Docente marca se o projeto aparece no site público | `project.is_public` |
| 37 | Depois de aprovado, só o docente altera a participação | Regra de aplicação; o banco guarda o status |

---

## 4. Matriz de Cenários de Testes Funcionais Validados

Os cenários abaixo estão no passo 26 do [scripts/validate.sh](scripts/validate.sh), em bloco transacional `DO $$ ... $$` com usuários sintéticos reais em `auth."user"` e limpeza ao final:

| # | Cenário Testado | Comportamento Esperado | Resultado Obtido |
| :--- | :--- | :--- | :--- |
| **01** | Projeto sem nenhuma categoria | Rejeição por `project_category_ck` | Sucesso (bloqueado) |
| **02** | Projeto com título vazio | Rejeição por `project_title_ck` | Sucesso (bloqueado) |
| **03** | Período de inscrição com fechamento anterior à abertura | Rejeição por `enrollment_period_window_ck` | Sucesso (bloqueado) |
| **04** | Participação com aluno inexistente | Rejeição por `project_participation_user_fk` | Sucesso (bloqueado) |
| **05** | Docente inexistente em `project_instructor` | Rejeição por `project_instructor_user_fk` | Sucesso (bloqueado) |
| **06** | Docente válido e repetição no mesmo projeto | Primeiro aceito; repetido rejeitado por `project_instructor_project_instructor_unq` | Sucesso |
| **07** | Participação com categorias divergentes das do projeto | Rejeição pela FK composta | Sucesso (bloqueado) |
| **08** | Segundo PI ativo para o mesmo aluno | Rejeição por `idx_project_participation_student_active_pi` | Sucesso (bloqueado) |
| **09** | 1 PI + 1 Extensão para o mesmo aluno | Ambos aceitos | Sucesso (inseridos) |
| **10** | Projeto PI+Extensão com as duas vagas já ocupadas | Rejeição pelos índices parciais | Sucesso (bloqueado) |
| **11** | Remoção sem justificativa | Rejeição por `project_participation_justification_ck` | Sucesso (bloqueado) |
| **12** | Remoção com justificativa | Inserção aceita | Sucesso (inserido) |
| **13** | Exclusão de projeto com participação | Bloqueio por `ON DELETE RESTRICT` | Sucesso (bloqueado) |
| **14** | Exclusão de usuário com participação | Bloqueio por `ON DELETE RESTRICT` | Sucesso (bloqueado) |

Além desses, o script de testes de integridade local (17 cenários, T00 a T16, usado no ciclo 2) teve todos os cenários com o resultado esperado.

---

## 5. Evidência de Validação Local

Validação executada localmente (PostgreSQL 16, Docker Compose), em banco recriado do zero a partir da `develop` atualizada (HEAD `557de69`):

```
1. Migrations aplicadas: V0001, V0002, V0003, V0004, V0006, V0008
2. ./scripts/seed.sh
   - seeds/0001_audit_event.sql
   - seeds/0002_identity_user_link.sql
   - seeds/0003_user_session.sql
3. ./scripts/validate.sh
   - [validate] 1 a 22 ... OK (passos existentes, sem alteração)
   - [validate] 23. Validando tabelas e registro da migration de projetos (DB-008)... OK
   - [validate] 24. Validando check, unique e foreign keys das tabelas de projeto... OK
   - [validate] 25. Validando indices das tabelas de projeto... OK
   - [validate] 26. Validando regras funcionais e de integridade das tabelas de projeto (DO block)... OK
   - [validate] Todas as validacoes de compatibilidade, integridade, constraints e seeds concluidas com sucesso!
4. ./scripts/validate_upgrade.sh
   - V0002, V0003, V0004, V0006 e V0008 aplicadas em sequência pelo migrate.sh sobre a V0001... OK
   - Reexecução do migrate.sh: V0008 ignorada por já estar registrada... OK
   - Seeds aplicadas e reexecutadas (INSERT 0 0)... OK
   - Suíte completa (passos 1 a 26) no banco atualizado... OK
   - === [validate_upgrade] Validacao de upgrade, compatibilidade e idempotencia de seeds concluida com sucesso! ===
```

Nota: na primeira execução do `validate.sh` no banco recriado, o script parou no passo 9 porque as seeds ainda não tinham sido carregadas (`audit_event` com 0 registros). Após o `./scripts/seed.sh`, a suíte passou do passo 1 ao 26.

A saída completa dos dois scripts está em `evidence/DB-008-integrity.txt`.

### 5.1 Repetibilidade da V0008 (arquivo executado uma segunda vez)

A V0008 foi executada diretamente, uma segunda vez, sobre o banco que já a tinha aplicada. Os `NOTICE ... already exists, skipping` são esperados. Os dois blocos `DO` (FKs de usuário) rodaram sem erro, o registro em `schema_migration` deu `INSERT 0 0` e a transação terminou em `COMMIT`, sem nenhum `ERROR`.

Comando:

```
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U plataforma -d plataforma < migrations/V0008__create_project_tables.sql
```

Saída (trecho final):

```
CREATE TABLE
NOTICE:  relation "project" already exists, skipping
NOTICE:  relation "enrollment_period" already exists, skipping
CREATE TABLE
CREATE INDEX
NOTICE:  relation "idx_enrollment_period_project_id" already exists, skipping
NOTICE:  relation "project_instructor" already exists, skipping
CREATE TABLE
NOTICE:  relation "idx_project_instructor_instructor_id" already exists, skipping
CREATE INDEX
CREATE TABLE
NOTICE:  relation "project_participation" already exists, skipping
NOTICE:  relation "idx_project_participation_student_id" already exists, skipping
CREATE INDEX
NOTICE:  relation "idx_project_participation_student_active_pi" already exists, skipping
CREATE INDEX
CREATE INDEX
NOTICE:  relation "idx_project_participation_student_active_extension" already exists, skipping
DO
DO
INSERT 0 0
COMMIT
```

### 5.2 Banco limpo após os testes

Comando:

```
docker compose exec -T postgres psql -U plataforma -d plataforma -c "SELECT (SELECT count(*) FROM academic_pi.project) AS projetos, (SELECT count(*) FROM auth.user WHERE email LIKE 'db008.%') AS usuarios_teste;"
```

Saída:

```
 projetos | usuarios_teste
----------+----------------
        0 |              0
(1 row)
```

---

## 6. Observações e Pendências

- **Fora do escopo da DB-008 (RBAC/DB-006):** `V0006` não registra versão em `schema_migration`; seed RBAC em `seeds/seeds/` é ignorado pelo `seed.sh`; `user_roles` sem FK para `auth.user`; evidência da DB-006.
- Não existem `V0005` e `V0007` na `develop`.
- "Pelo menos um docente por projeto" fica na aplicação.
- Teste manual de concorrência com duas sessões: pendente.
- **Perguntas em aberto para o PO:** `requested` ocupa a vaga do limite ou só `approved`; alcance de `withdrawn` (item 37); schema `academic_pi`; reaproveitamento da linha no `UNIQUE (project_id, student_id)` quando o aluno desiste e volta; redundância entre `status` e `is_public`; limite de vagas e notificações.

---

## 7. Rastreabilidade e Conclusão

- **Issue:** #8 (Propostas, Equipes e Solicitações)
- **PR do ciclo 1:** #33
- **Branch do ciclo 2:** `DB-008-fks-e-validacao`
- **Status:** implementado e validado localmente; aguardando revisão.