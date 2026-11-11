**Identificador de Trabalho (Work ID):** DB-012  
**Título:** Períodos de inscrição e inscrições mantêm janela e unicidade  
**Responsável:** Diogo Lopes  
**Revisora:** Isabelly-Caroline  
**Dependências:** DB-004 (`auth."user"`)  
**Autoridade Normativa:** Caderno de Validações de Escopo (AUTH, PI e Extensão), itens 28, 31, 32, 34, 36, 37, 61 e 62  
**Rastreabilidade:** Issue #12 · Estrutura entregue na DB-008 (PR #33, `V0008`)  

---

## 1. Resumo da Entrega

Esta issue é uma **reconciliação de escopo**: não cria estrutura nova. A entrega confere, com evidência executada, que a estrutura já existente (`academic_pi.enrollment_period` e `academic_pi.project_participation`, criadas na `V0008`) mantém **janela**, **status** e **unicidade** conforme o Caderno de Validações, e registra como pontos em aberto o que o banco não garante hoje.

Terminologia adotada, conforme o Caderno:

- **período de inscrição** (`enrollment_period`): janela de datas em que o aluno pode solicitar participação em um projeto;
- **inscrição/participação** (`project_participation`): a solicitação do aluno e a decisão do docente (aprovar ou negar);
- **aviso** não é tratado como edital: o Caderno (item 34) define avisos como comunicados, gerais ou de um projeto.

Pontos principais:

- **Janela:** `opens_at` e `closes_at` em `timestamptz` (UTC), com `enrollment_period_window_ck` (`closes_at >= opens_at`). A interpretação em UTC-3 (Brasília, item 36) é feita na apresentação: o banco guarda o instante e o converte sem perda (cenário J01).
- **Status:** a inscrição tem status restrito a `requested`, `approved`, `denied`, `withdrawn` e `removed`, sem status de convite. O status do período (futuro, aberto ou encerrado) **não é uma coluna**: é derivado das datas (cenário S01).
- **Unicidade:** um registro por aluno em cada projeto, e no máximo um PI e uma Extensão ativos por aluno (itens 31 e 32), decididos por índices únicos parciais.
- **Conflito entre os itens 61 e 62 do Caderno:** o item 61 define prazos não prorrogáveis, e o item 62 permite que o docente responsável ajuste o prazo. **Este trabalho não escolhe uma interpretação e não afirma que o conflito foi resolvido.** O banco apenas guarda datas coerentes e aceita a alteração delas (cenários J04 e J05); quem pode alterar o prazo fica para a aplicação, depois que o conflito for resolvido pelo PO.

---

## 2. Estrutura Existente Conferida (V0008)

### 2.1 `academic_pi.enrollment_period` (período de inscrição)

| Coluna | Tipo | Nulo | Padrão |
| :--- | :--- | :--- | :--- |
| `id` | `uuid` | não | |
| `project_id` | `uuid` | não | |
| `opens_at` | `timestamp with time zone` | não | |
| `closes_at` | `timestamp with time zone` | não | |
| `created_at` | `timestamp with time zone` | não | `now()` |
| `updated_at` | `timestamp with time zone` | não | `now()` |

- Índices: `enrollment_period_pkey` (`id`) e `idx_enrollment_period_project_id` (`project_id`).
- Check: `enrollment_period_window_ck` (`closes_at >= opens_at`).
- FK: `enrollment_period_project_fk` para `academic_pi.project (id)`, `ON DELETE RESTRICT`.

### 2.2 `academic_pi.project_participation` (inscrição/participação)

| Coluna | Tipo | Nulo | Padrão |
| :--- | :--- | :--- | :--- |
| `id` | `uuid` | não | |
| `project_id` | `uuid` | não | |
| `is_pi` | `boolean` | não | |
| `is_extension` | `boolean` | não | |
| `student_id` | `uuid` | não | |
| `status` | `character varying(20)` | não | `'requested'` |
| `justification` | `text` | sim | |
| `requested_at` | `timestamp with time zone` | não | `now()` |
| `decided_at` | `timestamp with time zone` | sim | |
| `created_at` | `timestamp with time zone` | não | `now()` |
| `updated_at` | `timestamp with time zone` | não | `now()` |

- Unicidade: `project_participation_project_student_unq` (`project_id`, `student_id`).
- Índices únicos parciais: `idx_project_participation_student_active_pi` (`student_id` onde `is_pi` e status `requested` ou `approved`) e `idx_project_participation_student_active_extension` (idem para `is_extension`).
- Checks: `project_participation_status_ck`, `project_participation_category_ck` (`is_pi OR is_extension`) e `project_participation_justification_ck` (remoção exige justificativa).
- FK: `project_participation_project_fk` composta, `(project_id, is_pi, is_extension)` para `academic_pi.project`, `ON DELETE RESTRICT`.

Observação: esta conferência foi feita no banco da branch desta issue, criada a partir da `develop`. As FKs de `student_id` e `instructor_id` para `auth."user"` fazem parte do PR de correção da DB-008 e não estão nesta base.

---

## 3. Matriz de Cenários Validados

Script: `evidence/DB-012-evidence-tests.sql`, executado em uma única transação que termina em `ROLLBACK` (nenhum dado permanece no banco). Os dados de apoio são sintéticos.

### 3.1 Janela

| # | Cenário | Comportamento Esperado | Resultado Obtido |
| :--- | :--- | :--- | :--- |
| **J01** | Período válido com datas em UTC-3 | Aceito; guardado em UTC e exibido em Brasília sem perda | Sucesso: `2026-03-01 11:00:00` UTC = `2026-03-01 08:00:00` Brasília |
| **J02** | Fechamento anterior à abertura | Rejeição por `enrollment_period_window_ck` | Sucesso (bloqueado) |
| **J03** | Janela de duração zero (`closes_at = opens_at`) | Informativo: o check usa `>=` | Aceita |
| **J04** | Alteração da data de fechamento | O banco aceita a alteração (não impõe prazo não prorrogável nem regra de ajuste) | Aceita |
| **J05** | Alteração que inverte a janela | Rejeição por `enrollment_period_window_ck` | Sucesso (bloqueado) |

### 3.2 Status

| # | Cenário | Comportamento Esperado | Resultado Obtido |
| :--- | :--- | :--- | :--- |
| **S01** | Status do período | Derivado das datas, sem coluna própria | Período passado: `encerrado`; período em curso: `aberto` |
| **S02** | Criação de inscrição | Nasce como `requested` | Sucesso |
| **S03** | Aprovação com `decided_at` | Persistida como `approved` | Sucesso |
| **S04** | Recusa e desistência | `denied` e `withdrawn` persistidos | Sucesso |
| **S05** | Status fora do domínio (`invited`) | Rejeição por `project_participation_status_ck` | Sucesso (bloqueado) |

### 3.3 Unicidade

| # | Cenário | Comportamento Esperado | Resultado Obtido |
| :--- | :--- | :--- | :--- |
| **U01** | Mesma inscrição repetida (mesmo aluno e projeto) | Rejeição por `project_participation_project_student_unq` | Sucesso (bloqueado) |
| **U02** | Segundo PI ativo para o mesmo aluno | Rejeição por `idx_project_participation_student_active_pi` | Sucesso (bloqueado) |
| **U03** | 1 PI + 1 Extensão para o mesmo aluno | Permitido | Sucesso |
| **U04** | Projeto PI+Extensão com as duas vagas ocupadas | Rejeição pelos índices parciais | Sucesso (bloqueado por `idx_project_participation_student_active_pi`) |

---

## 4. Evidência de Execução

Ambiente: PostgreSQL 16, local, via Docker Compose, banco recriado do zero na branch `DB-012-periodos-inscricao-janela-unicidade` (a partir da `develop`), com as migrations V0001, V0002, V0003, V0004, V0006 e V0008 e as seeds aplicadas.

Comando:

```
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U plataforma -d plataforma < evidence/DB-012-evidence-tests.sql
```

Saída:

```
BEGIN
NOTICE:  J01 OK periodo valido aceito. opens_at em UTC: 2026-03-01 11:00:00 | em Brasilia (UTC-3): 2026-03-01 08:00:00
NOTICE:  J02 OK janela invertida rejeitada: new row for relation "enrollment_period" violates check constraint "enrollment_period_window_ck"
NOTICE:  J03 INFO janela de duracao zero aceita (check closes_at >= opens_at)
NOTICE:  J04 OK alteracao de data de fechamento aceita pelo banco (R61/R62 ficam fora do banco)
NOTICE:  J05 OK alteracao que inverte a janela rejeitada: new row for relation "enrollment_period" violates check constraint "enrollment_period_window_ck"
NOTICE:  S01 INFO status derivado das datas: encerrado
NOTICE:  S01 INFO status derivado das datas: aberto
NOTICE:  S02 OK inscricao criada com status padrao: requested
NOTICE:  S03 OK aprovacao persistida: approved
NOTICE:  S04 OK recusa (denied) e desistencia (withdrawn) persistidas
NOTICE:  S05 OK status fora do dominio rejeitado: new row for relation "project_participation" violates check constraint "project_participation_status_ck"
NOTICE:  U01 OK inscricao duplicada rejeitada: duplicate key value violates unique constraint "project_participation_project_student_unq"
NOTICE:  U02 OK segundo PI ativo rejeitado: duplicate key value violates unique constraint "idx_project_participation_student_active_pi"
NOTICE:  U03 OK 1 PI + 1 Extensao permitido
NOTICE:  U04 OK projeto PI+Extensao rejeitado com as duas vagas ocupadas: duplicate key value violates unique constraint "idx_project_participation_student_active_pi"
NOTICE:  DB-012: todos os cenarios concluidos
DO
ROLLBACK
```

---

## 5. Observações e Pontos em Aberto

Nada abaixo foi alterado ou decidido nesta entrega. São pontos para o PO e a revisão.

- **Conflito R61/R62 (itens 61 e 62 do Caderno):** prazos não prorrogáveis versus ajuste de prazo pelo docente. Não está resolvido. O banco aceita a alteração das datas e só exige que a janela seja coerente.
- **Inscrição sem vínculo com o período:** `project_participation` não referencia `enrollment_period`. O banco não garante que a inscrição tenha sido feita dentro da janela, e a unicidade atual é por projeto, não por período.
- **Períodos sobrepostos:** nada impede dois períodos de inscrição sobrepostos no mesmo projeto.
- **Janela de duração zero:** o check usa `>=`, então `closes_at = opens_at` é aceito. Trocar para `>` exigiria migration nova.
- **Status do período:** interpretado como derivado das datas (não persistido), porque uma constraint não pode depender de `now()`. A confirmação de que é isso que o escopo pede está pendente.
- **Fuso UTC-3:** o banco guarda o instante em `timestamptz`. A aplicação interpreta e exibe em UTC-3 (item 36).
- **Item 37 (depois de aprovado, só o docente altera a participação):** regra de aplicação e permissões (RBAC), fora do banco.
- **FKs para usuários:** estão no PR de correção da DB-008 e não fazem parte desta base.

---

## 6. Rastreabilidade e Conclusão

- **Issue:** #12 (Períodos de inscrição e inscrições mantêm janela e unicidade)
- **Estrutura conferida:** `V0008` (DB-008, PR #33)
- **Branch:** `DB-012-periodos-inscricao-janela-unicidade`
- **Status:** evidência executada; aguardando revisão.