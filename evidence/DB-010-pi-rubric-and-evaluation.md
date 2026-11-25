# Evidência de Validação e Conformidade — Rubricas e Notas de PI (DB-010)

**Identificador de Trabalho (Work ID):** DB-010  
**Título:** Rubricas e notas aguardam validação das regras de cálculo  
**Responsável:** Nicolas Pureza da Silva  
**Revisora:** Isabelly Caroline Martins Pardim  
**Dependências:** DB-008 (`academic_pi.project`, `academic_pi.project_instructor`, `academic_pi.project_participation`), DB-009 (`V0009__create_project_evaluation.sql`: `academic_pi.project_evaluation`)  
**Autoridade Normativa:** ADR-002, ADR-011, DB-001, SPEC-PI-002, SPEC-PI-003 e Caderno de Validações de Escopo  
**Rastreabilidade:** Issue #10 · Migration `migrations/V0010__create_pi_rubric_and_evaluation.sql`

---

## 1. Resumo Executivo da Entrega

A entrega **DB-010** implementa e valida a persistência relacional dos critérios e pesos da rubrica de Projetos Integradores (PI), evolui `academic_pi.project_evaluation` (`V0009` / DB-009) com os controles de finalização, reabertura e correção docente, e persiste o valor vigente das notas por critério **sem cristalizar regras de nota** que ainda aguardam validação formal do André (PO):

1. **Migration Incremental e Repetível (`V0010`):** [`migrations/V0010__create_pi_rubric_and_evaluation.sql`](../migrations/V0010__create_pi_rubric_and_evaluation.sql) cria `academic_pi.evaluation_criterion` e `academic_pi.evaluation_criterion_score`, adiciona as colunas e constraints de finalização/reabertura/correção em `academic_pi.project_evaluation` de forma idempotente, e registra `'V0010'` em `public.schema_migration`.
2. **Critérios e Pesos Definidos pelo Docente Responsável:** `evaluation_criterion_instructor_fk (project_id, defined_by_instructor_id) -> academic_pi.project_instructor (project_id, instructor_id)` impede que usuários não responsáveis pelo projeto definam critérios ou pesos.
3. **Finalização, Reabertura e Correção Restritas ao Docente Responsável:** As FKs compostas `project_evaluation_finalized_by_instructor_fk`, `project_evaluation_reopened_by_instructor_fk`, `project_evaluation_corrected_by_instructor_fk` e `evaluation_criterion_score_corrected_by_instructor_fk` garantem no banco que apenas docentes responsáveis pelo projeto finalizem, reabram ou corrijam uma avaliação.
4. **Substituição de Valor Vigente sem Histórico:** `academic_pi.evaluation_criterion_score` impõe `UNIQUE (evaluation_id, criterion_id)` (`evaluation_criterion_score_eval_criterion_unq`) e não possui colunas de valor anterior nem tabela de histórico. Correções substituem `score` *in-place* via `UPDATE` (`AC-PI-003-05`, `DB-007`).
5. **Não Cristalização do Bloqueio de Produto (André):** `weight` e `score` usam `numeric` sem `(precision, scale)` e sem `CHECK` de escala (`0..100`), sem soma fixa de pesos, sem fórmula de cálculo e sem máquina de estados (`status`) ou `final_score`.

---

## 2. Matriz de Objetos e Restrições Verificados (`V0009` + `V0010`)

### 2.1 Tabelas Criadas / Estendidas
| Schema | Tabela | Origem | Finalidade |
| :--- | :--- | :--- | :--- |
| `academic_pi` | `evaluation_criterion` | Criada na `V0010` | Critérios e pesos da rubrica do PI definidos pelo docente responsável |
| `academic_pi` | `project_evaluation` | Base na `V0009`, estendida na `V0010` | Avaliação individual vinculada a projeto, avaliador e aluno avaliado + finalização/reabertura/correção docente |
| `academic_pi` | `evaluation_criterion_score` | Criada na `V0010` | Valor vigente da nota atribuída a cada critério na avaliação |

### 2.2 Restrições Verificadas no Catálogo (`scripts/validate.sh` passos 47–51)
- **CHECK (7):** `evaluation_criterion_name_ck`, `evaluation_criterion_score_correction_ck`, `evaluation_criterion_weight_positive_ck`, `project_evaluation_assignment_ck`, `project_evaluation_correction_ck`, `project_evaluation_finalization_ck`, `project_evaluation_reopen_ck`.
- **UNIQUE (4):** `evaluation_criterion_id_project_unq`, `evaluation_criterion_project_name_unq`, `evaluation_criterion_score_eval_criterion_unq`, `project_evaluation_id_project_unq`.
- **FOREIGN KEY (14):** `evaluation_criterion_defined_by_user_fk`, `evaluation_criterion_instructor_fk`, `evaluation_criterion_project_fk`, `evaluation_criterion_score_corrected_by_instructor_fk`, `evaluation_criterion_score_criterion_fk`, `evaluation_criterion_score_evaluation_fk`, `project_evaluation_assigned_by_user_fk`, `project_evaluation_corrected_by_instructor_fk`, `project_evaluation_evaluated_user_fk`, `project_evaluation_evaluator_user_fk`, `project_evaluation_finalized_by_instructor_fk`, `project_evaluation_participation_fk`, `project_evaluation_project_fk`, `project_evaluation_reopened_by_instructor_fk`.
- **Índices `idx_%` (9):** `idx_evaluation_criterion_defined_by_instructor_id`, `idx_evaluation_criterion_project_id`, `idx_evaluation_criterion_score_criterion_id`, `idx_evaluation_criterion_score_evaluation_id`, `idx_evaluation_criterion_score_project_id`, `idx_project_evaluation_assigned_by_user_id`, `idx_project_evaluation_evaluated_student_id`, `idx_project_evaluation_evaluator_user_id`, `idx_project_evaluation_project_id`.

---

## 3. Matriz de Cenários Validados (`scripts/validate.sh` passos 47–51 e `evidence/DB-010-evidence-tests.sql`)

| # | Cenário Testado | Comportamento Esperado |
| :---: | :--- | :--- |
| **01** | Docente responsável salva critérios e pesos (incluindo decimais e soma diferente de 100) | Aceito, preservando valores exatos em `numeric` sem escala cristalizada |
| **02** | Usuário que não é docente responsável pelo projeto tenta cadastrar critério | Rejeição por `evaluation_criterion_instructor_fk` (`foreign_key_violation`) |
| **03** | Critério com nome em branco, nome duplicado no projeto ou `weight <= 0` | Rejeição por `evaluation_criterion_name_ck`, `evaluation_criterion_project_name_unq` e `evaluation_criterion_weight_positive_ck` |
| **04** | Coordenação atribui múltiplos alunos avaliadores, projeto e data (`evaluation_date`) | Inserções aceitas (sem tabela de banca/agenda) |
| **05** | Atribuição pela coordenação sem informar `evaluation_date` | Rejeição por `project_evaluation_assignment_ck` (`check_violation`) |
| **06** | Avaliação de aluno que não participa do projeto | Rejeição por `project_evaluation_participation_fk` (`foreign_key_violation`) |
| **07** | Lançamento de nota vinculada a critério de outro projeto | Rejeição pela FK composta `evaluation_criterion_score_criterion_fk` |
| **08** | Tentativa de finalizar, reabrir ou corrigir avaliação por usuário não responsável pelo projeto | Rejeição pelas FKs compostas para `academic_pi.project_instructor` |
| **09** | Tentativa de inserir segunda linha de nota para o mesmo `(evaluation_id, criterion_id)` | Rejeição por `evaluation_criterion_score_eval_criterion_unq` (`unique_violation`) |
| **10** | Correção da nota pelo docente responsável via `UPDATE` | Valor vigente substituído *in-place* (`85.75` → `91.25`), mantendo 1 único registro e sem histórico anterior |

---

## 4. Registro de Bloqueios e Limitações Conhecidas

- **Aguardando validação formal do André (PO):** escala e precisão numérica (incluindo proposta de `0–100` inteiro), regra de arredondamento, agregação ponderada dos critérios, tratamento de avaliação ausente, estados/prazos da avaliação e definição sobre se a nota consolidada representa o aluno, o projeto ou ambos.
- **Testes de cálculo e limites de escala:** conforme o quarto critério de aceite da Issue #10 (*"Testes cobrem limites, precisão, cálculo e ausência de avaliação somente após aprovação das regras"*), esses testes serão adicionados em migration/validação complementar após o registro formal da decisão pelo PO.
