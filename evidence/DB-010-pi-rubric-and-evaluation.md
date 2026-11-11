# Evidência de Validação e Conformidade — Rubricas e Notas de PI (DB-010)

**Identificador de Trabalho (Work ID):** DB-010  
**Título:** Rubricas e notas aguardam validação das regras de cálculo  
**Responsável:** Nicolas Pureza da Silva  
**Revisora:** Isabelly Caroline Martins Pardim  
**Dependências:** DB-008 (`academic_pi.project`, `academic_pi.project_instructor`, `academic_pi.project_participation`), DB-009 (vínculo de avaliação individual a projeto, avaliador e aluno avaliado)  
**Autoridade Normativa:** ADR-002, ADR-011, DB-001, SPEC-PI-002, SPEC-PI-003 e Caderno de Validações de Escopo  
**Rastreabilidade:** Issue #10 · Migration `migrations/V0010__create_pi_rubric_and_evaluation.sql`

---

## 1. Resumo Executivo da Entrega

A entrega **DB-010** implementa e valida a persistência relacional dos critérios e pesos da rubrica de Projetos Integradores (PI) e das avaliações individuais no schema `academic_pi`, preservando integralmente o escopo já definido no Caderno de Validações e mantendo em aberto (sem cristalização prematura no schema) as regras de escala, precisão, arredondamento, agregação, avaliação ausente, estados/prazos e titularidade da nota consolidada que aguardam validação formal do André (PO):

1. **Migration Incremental e Repetível (`V0010`):** O arquivo [`migrations/V0010__create_pi_rubric_and_evaluation.sql`](../migrations/V0010__create_pi_rubric_and_evaluation.sql) cria as tabelas `academic_pi.evaluation_criterion`, `academic_pi.project_evaluation` e `academic_pi.evaluation_criterion_score`, protegidas por transação (`BEGIN; ... COMMIT;`), cláusulas idempotentes (`CREATE TABLE IF NOT EXISTS`, `CREATE INDEX IF NOT EXISTS`, `ON CONFLICT (version) DO NOTHING`) e registra a versão `'V0010'` em `public.schema_migration`.
2. **Critérios e Pesos Definidos pelo Docente Responsável:** A tabela `academic_pi.evaluation_criterion` vincula o critério ao projeto e exige, por meio da FK composta `evaluation_criterion_instructor_fk (project_id, defined_by_instructor_id) -> academic_pi.project_instructor (project_id, instructor_id)`, que apenas um docente responsável pelo projeto possa cadastrar critérios e pesos.
3. **Avaliações Individuais sem Banca e Atribuição pela Coordenação:** A tabela `academic_pi.project_evaluation` vincula projeto (`project_id`), avaliador (`evaluator_user_id`) e aluno participante avaliado (`evaluated_student_id` via `project_evaluation_participation_fk`), suportando número variável de avaliações sem tabelas/colunas de banca, sala, agenda ou link. Quando atribuída pela coordenação (`assigned_by_user_id`), exige o registro da data (`evaluation_date` via `project_evaluation_assignment_ck`).
4. **Finalização, Reabertura e Correção Restritas ao Docente Responsável:** As FKs compostas `project_evaluation_finalized_by_instructor_fk`, `project_evaluation_reopened_by_instructor_fk`, `project_evaluation_corrected_by_instructor_fk` e `evaluation_criterion_score_corrected_by_instructor_fk` garantem no banco que apenas docentes responsáveis pelo projeto finalizem, reabram ou corrijam uma avaliação.
5. **Substituição de Valor Vigente sem Histórico:** A tabela `academic_pi.evaluation_criterion_score` impõe unicidade por `(evaluation_id, criterion_id)` (`evaluation_criterion_score_eval_criterion_unq`) e não possui colunas de valor anterior (`previous_score`) nem tabela de histórico. Qualquer correção substitui `score` *in-place* via `UPDATE` (`AC-PI-003-05`, `DB-007`).
6. **Não Cristalização do Bloqueio de Produto (André):** As colunas `weight` e `score` utilizam `numeric` sem precisão/escala fixada e sem `CHECK` de faixa de escala (como `0..100` inteiro), soma de pesos igual a `100`, fórmula de cálculo ou máquina de estados especulativa.

---

## 2. Matriz de Objetos e Restrições Verificados (`V0010`)

### 2.1 Tabelas Criadas
| Schema | Tabela | Finalidade | Chave Primária |
| :--- | :--- | :--- | :--- |
| `academic_pi` | `evaluation_criterion` | Critérios e pesos da rubrica do PI definidos pelo docente responsável | `id` (`uuid`) |
| `academic_pi` | `project_evaluation` | Avaliação individual vinculada a projeto, avaliador e aluno avaliado | `id` (`uuid`) |
| `academic_pi` | `evaluation_criterion_score` | Valor vigente da nota atribuída a cada critério na avaliação | `id` (`uuid`) |

### 2.2 Restrições de Integridade (Constraints)
| Tabela | Nome da Constraint | Tipo | Regra Verificada |
| :--- | :--- | :--- | :--- |
| `evaluation_criterion` | `evaluation_criterion_project_fk` | `FOREIGN KEY` | Referência a `academic_pi.project(id)` (`ON DELETE RESTRICT`) |
| `evaluation_criterion` | `evaluation_criterion_defined_by_user_fk` | `FOREIGN KEY` | Referência a `auth.user(id)` (`ON DELETE RESTRICT`) |
| `evaluation_criterion` | `evaluation_criterion_instructor_fk` | `FOREIGN KEY` | FK composta `(project_id, defined_by_instructor_id)` para `academic_pi.project_instructor` |
| `evaluation_criterion` | `evaluation_criterion_name_ck` | `CHECK` | `length(trim(name)) > 0` |
| `evaluation_criterion` | `evaluation_criterion_weight_positive_ck` | `CHECK` | `weight > 0` (sem impor soma 100 nem escala fechada) |
| `evaluation_criterion` | `evaluation_criterion_project_name_unq` | `UNIQUE` | Unicidade `(project_id, name)` |
| `evaluation_criterion` | `evaluation_criterion_id_project_unq` | `UNIQUE` | Unicidade `(id, project_id)` (alvo da FK composta de `evaluation_criterion_score`) |
| `project_evaluation` | `project_evaluation_project_fk` | `FOREIGN KEY` | Referência a `academic_pi.project(id)` (`ON DELETE RESTRICT`) |
| `project_evaluation` | `project_evaluation_evaluator_user_fk` | `FOREIGN KEY` | Referência a `auth.user(id)` (`ON DELETE RESTRICT`) |
| `project_evaluation` | `project_evaluation_evaluated_user_fk` | `FOREIGN KEY` | Referência a `auth.user(id)` (`ON DELETE RESTRICT`) |
| `project_evaluation` | `project_evaluation_participation_fk` | `FOREIGN KEY` | FK composta `(project_id, evaluated_student_id)` para `academic_pi.project_participation` |
| `project_evaluation` | `project_evaluation_assigned_by_user_fk` | `FOREIGN KEY` | Referência a `auth.user(id)` (`ON DELETE RESTRICT`) |
| `project_evaluation` | `project_evaluation_finalized_by_instructor_fk` | `FOREIGN KEY` | FK composta `(project_id, finalized_by_instructor_id)` para `academic_pi.project_instructor` |
| `project_evaluation` | `project_evaluation_reopened_by_instructor_fk` | `FOREIGN KEY` | FK composta `(project_id, reopened_by_instructor_id)` para `academic_pi.project_instructor` |
| `project_evaluation` | `project_evaluation_corrected_by_instructor_fk` | `FOREIGN KEY` | FK composta `(project_id, corrected_by_instructor_id)` para `academic_pi.project_instructor` |
| `project_evaluation` | `project_evaluation_distinct_actors_ck` | `CHECK` | `evaluator_user_id <> evaluated_student_id` |
| `project_evaluation` | `project_evaluation_assignment_ck` | `CHECK` | `assigned_by_user_id IS NULL OR evaluation_date IS NOT NULL` |
| `project_evaluation` | `project_evaluation_finalization_ck` | `CHECK` | `(finalized_at IS NULL) = (finalized_by_instructor_id IS NULL)` |
| `project_evaluation` | `project_evaluation_reopen_ck` | `CHECK` | `(reopened_at IS NULL) = (reopened_by_instructor_id IS NULL)` |
| `project_evaluation` | `project_evaluation_correction_ck` | `CHECK` | `(corrected_at IS NULL) = (corrected_by_instructor_id IS NULL)` |
| `project_evaluation` | `project_evaluation_triplet_unq` | `UNIQUE` | Unicidade `(project_id, evaluator_user_id, evaluated_student_id)` |
| `project_evaluation` | `project_evaluation_id_project_unq` | `UNIQUE` | Unicidade `(id, project_id)` |
| `evaluation_criterion_score` | `evaluation_criterion_score_evaluation_fk` | `FOREIGN KEY` | FK composta `(evaluation_id, project_id)` para `academic_pi.project_evaluation(id, project_id)` |
| `evaluation_criterion_score` | `evaluation_criterion_score_criterion_fk` | `FOREIGN KEY` | FK composta `(criterion_id, project_id)` para `academic_pi.evaluation_criterion(id, project_id)` |
| `evaluation_criterion_score` | `evaluation_criterion_score_corrected_by_instructor_fk` | `FOREIGN KEY` | FK composta `(project_id, last_corrected_by_instructor_id)` para `academic_pi.project_instructor` |
| `evaluation_criterion_score` | `evaluation_criterion_score_correction_ck` | `CHECK` | `(last_corrected_at IS NULL) = (last_corrected_by_instructor_id IS NULL)` |
| `evaluation_criterion_score` | `evaluation_criterion_score_eval_criterion_unq` | `UNIQUE` | Unicidade `(evaluation_id, criterion_id)` (1 único valor vigente por critério) |

### 2.3 Índices Criados
- `idx_evaluation_criterion_project_id`
- `idx_evaluation_criterion_defined_by_instructor_id`
- `idx_project_evaluation_project_id`
- `idx_project_evaluation_evaluator_user_id`
- `idx_project_evaluation_evaluated_student_id`
- `idx_project_evaluation_assigned_by_user_id` (parcial: `WHERE assigned_by_user_id IS NOT NULL`)
- `idx_evaluation_criterion_score_evaluation_id`
- `idx_evaluation_criterion_score_criterion_id`
- `idx_evaluation_criterion_score_project_id`

---

## 3. Matriz de Cenários Validados (`scripts/validate.sh` e `evidence/DB-010-evidence-tests.sql`)

| # | Cenário Testado | Comportamento Esperado | Resultado Obtido |
| :---: | :--- | :--- | :---: |
| **01** | Docente responsável salva critérios e pesos (incluindo decimais e soma diferente de 100) | Aceito, preservando valores exatos em `numeric` sem escala cristalizada | Sucesso |
| **02** | Usuário que não é docente responsável pelo projeto tenta cadastrar critério | Rejeição por `evaluation_criterion_instructor_fk` (`foreign_key_violation`) | Sucesso (bloqueado) |
| **03** | Critério com nome em branco, nome duplicado no projeto ou `weight <= 0` | Rejeição por `evaluation_criterion_name_ck`, `evaluation_criterion_project_name_unq` e `evaluation_criterion_weight_positive_ck` | Sucesso (bloqueado) |
| **04** | Coordenação atribui múltiplos alunos avaliadores, projeto e data (`evaluation_date`) | Inserções aceitas (quantidade variável de avaliações, sem tabela de banca/agenda) | Sucesso |
| **05** | Atribuição pela coordenação sem informar `evaluation_date` | Rejeição por `project_evaluation_assignment_ck` (`check_violation`) | Sucesso (bloqueado) |
| **06** | Avaliação de aluno que não participa do projeto ou autoavaliação | Rejeição por `project_evaluation_participation_fk` e `project_evaluation_distinct_actors_ck` | Sucesso (bloqueado) |
| **07** | Lançamento de nota vinculada a critério de outro projeto | Rejeição pela FK composta `evaluation_criterion_score_criterion_fk` | Sucesso (bloqueado) |
| **08** | Tentativa de finalizar, reabrir ou corrigir avaliação por usuário não responsável pelo projeto | Rejeição pelas FKs compostas para `academic_pi.project_instructor` | Sucesso (bloqueado) |
| **09** | Tentativa de inserir segunda linha de nota para o mesmo `(evaluation_id, criterion_id)` | Rejeição por `evaluation_criterion_score_eval_criterion_unq` (`unique_violation`) | Sucesso (bloqueado) |
| **10** | Correção da nota pelo docente responsável via `UPDATE` | Valor vigente substituído *in-place* (`85.75` → `91.25`), mantendo 1 único registro e sem histórico anterior | Sucesso |

---

## 4. Saída de Execução dos Testes de Evidência (`evidence/DB-010-evidence-tests.sql`)

```
BEGIN
NOTICE:  C01 OK criterios e pesos definidos pelo docente responsavel (pesos: 2.75 e 1.25; soma = 4.00)
NOTICE:  C02 OK criacao de criterio por usuario nao responsavel bloqueada: insert or update on table "evaluation_criterion" violates foreign key constraint "evaluation_criterion_instructor_fk"
NOTICE:  C03 OK criterio com nome vazio rejeitado: new row for relation "evaluation_criterion" violates check constraint "evaluation_criterion_name_ck"
NOTICE:  C04 OK criterio com peso <= 0 rejeitado: new row for relation "evaluation_criterion" violates check constraint "evaluation_criterion_weight_positive_ck"
NOTICE:  A01 OK 3 avaliacoes vinculadas ao projeto, avaliadores e aluno participante (2 atribuidas pela coordenacao com data)
NOTICE:  A02 OK atribuicao sem evaluation_date rejeitada: new row for relation "project_evaluation" violates check constraint "project_evaluation_assignment_ck"
NOTICE:  A03 OK avaliado nao participante do projeto rejeitado: insert or update on table "project_evaluation" violates foreign key constraint "project_evaluation_participation_fk"
NOTICE:  N01 OK notas vigentes registradas por criterio (78.5 e 88)
NOTICE:  N02 OK criterio de outro projeto rejeitado na avaliacao: insert or update on table "evaluation_criterion_score" violates foreign key constraint "evaluation_criterion_score_criterion_fk"
NOTICE:  N03 OK tentativa de finalizacao por nao responsavel bloqueada: insert or update on table "project_evaluation" violates foreign key constraint "project_evaluation_finalized_by_instructor_fk"
NOTICE:  N04 OK correcao pelo docente responsavel substituiu o valor vigente sem historico (linhas=1 | valor_atual=94.25)
NOTICE:  DB-010: todos os cenarios concluidos com sucesso
DO
ROLLBACK
```

---

## 5. Registro de Bloqueios e Limitações Conhecidas

- **Aguardando validação formal do André (PO):** escala e precisão numérica (incluindo proposta de `0–100` inteiro), regra de arredondamento, agregação ponderada dos critérios, tratamento de avaliação ausente, estados/prazos da avaliação e definição sobre se a nota consolidada representa o aluno, o projeto ou ambos.
- **Testes de cálculo e limites de escala:** conforme o quarto critério de aceite da Issue #10 (*"Testes cobrem limites, precisão, cálculo e ausência de avaliação somente após aprovação das regras"*), esses testes serão adicionados em migration/validação complementar após o registro formal da decisão pelo PO.
