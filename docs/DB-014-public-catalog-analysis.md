# Análise de Campos do Catálogo Público e Critérios de Indexação (DB-014)

**Work ID:** DB-014 · Issue `#14`  
**Fase atual:** Análise de campos (definição de Produto precede qualquer alteração de schema/índices)  
**Responsável:** Nicolas Pureza · **Revisor:** Henrique  
**Dependências técnicas:** DB-008 (`V0008__create_project_tables.sql`) e DB-012 (`docs/DB-012-enrollment-periods.md`)  
**Referência complementar já medida:** DB-017 (`V0017__add_public_project_title_index.sql`, listagem pública ordenada por título)

---

## 1. Regras Já Definidas (Invariantes de Visibilidade e Segurança)

Antes de avaliar qualquer campo candidato de filtro, ordenação ou exibição no catálogo público:

1. **Somente projeto publicado e marcado como público é visível a visitante anônimo:** na modelagem atual (`academic_pi.project`), isso corresponde a `status = 'published' AND is_public = true`.
2. **Rascunhos e arquivados nunca são públicos:** registros com `status IN ('draft', 'archived')` ou `is_public = false` não podem ser retornados nem incluídos em índices parciais públicos.
3. **Horas e notas individuais nunca são públicas:** dados de `academic_pi.evaluation_criterion_score`, `academic_pi.project_evaluation`, `academic_pi.project_participation` e futuras tabelas de horas (`extension`) são estritamente internos e **não devem ser expostos nem indexados para consulta pública**.
4. **Nota agregada do projeto depende de aprovação prévia (DB-010):** enquanto o PO (André) não formalizar se a nota consolidada representa o aluno, o projeto ou ambos (além de escala, arredondamento e cálculo), nenhuma coluna de nota consolidada é adicionada ou exposta em `academic_pi.project`.
5. **Artefatos exigem autorização explícita (`DB-011`):** em `assets.project_file`, acesso interno não implica publicação; somente objetos com `publication_authorized = true` (e `lifecycle_state` válido quando definido) podem ser vinculados a exibição pública.
6. **Não cristalizar decisões pendentes:** nenhuma coluna, filtro, ordenação, paginação ou índice novo é criado para `palavra-chave`, `curso`, `semestre` ou `ODS` antes do registro formal de aprovação por Produto.

---

## 2. Mapeamento dos Campos Candidatos contra o Schema Vigente (`develop`)

| Campo Candidato | Fonte Atual no Schema (`V0001`–`V0017`) | Situação Atual | Decisão Necessária (Produto / Negócio) | Impacto no Schema (Somente Após Aprovação) |
| :--- | :--- | :--- | :--- | :--- |
| **Palavra-chave (`keyword`)** | `academic_pi.project.title` (`varchar(200)`) e `academic_pi.project.description` (`text`). | **Existe parcialmente.** Há apenas o índice B-tree parcial `idx_project_public_title (title) WHERE is_public AND status = 'published'` (`V0017`), voltado à ordenação por título (`ORDER BY title LIMIT 20`), que não acelera busca por substring (`ILIKE '%termo%'`) nem busca em `description`. | Definir se a busca será apenas por prefixo em `title`, correspondência parcial (`ILIKE`) em `title`/`description`, busca *full-text* em português (`to_tsvector('portuguese', ...)`) ou se haverá campo específico de palavras-chave/resumo público. | Sem alteração no momento. Se busca textual/substring for aprovada, avaliar via `EXPLAIN (ANALYZE, BUFFERS)` criação de índice `GIN` (`pg_trgm` ou `tsvector`) restrito ao predicado público `WHERE is_public AND status = 'published'`. |
| **Curso (`course`)** | **Inexistente** em `academic_pi.project` e sem tabela `course` no schema `institutional` (existe apenas `institutional.academic_class` com `code`, `name`, `term` e `scope_type = 'CURSO'` em `public.user_roles`). | **Exige modelagem.** Não há vínculo entre `project` e curso ou turma. | Definir se o projeto possui um curso principal (`1:1`), múltiplos cursos para projetos interdisciplinares (`N:N`) ou derivação por turma vinculada, e qual catálogo oficial de cursos (`code`/`id`/`name`) será usado. | Nova migration com tabela de domínio/catálogo (`institutional.course`) e chave estrangeira direta ou tabela associativa `academic_pi.project_course`. Criar índice de filtro apenas se a medição justificar. |
| **Semestre (`semester` / `term`)** | **Sem coluna dedicada em `project`.** Existem: `institutional.academic_class.term` (`varchar(20)`, sem relação com `project`), `academic_pi.project.starts_at`/`ends_at` (`timestamptz`, opcionais) e `academic_pi.enrollment_period.opens_at`/`closes_at` (`timestamptz`). | **Exige definição e modelagem.** `starts_at`/`ends_at` podem ser `NULL`, e `enrollment_period` não possui coluna `academic_term`. | Definir se o filtro de semestre no catálogo público representa semestre letivo explícito (ex.: `2026.1`), ano/semestre derivado de `starts_at`, ou período de inscrição ativo/ofertado. | Se for semestre letivo explícito, adicionar coluna `academic_term` (com validação de formato) em `academic_pi.project` ou em entidade de oferta/período, avaliando índice parcial público por medição após aprovação. |
| **ODS (`ods`)** | **Inexistente** em toda a base da `develop`. | **Exige modelagem.** Não há coluna, tabela de domínio ou associação de Objetivos de Desenvolvimento Sustentável. | Definir cardinalidade (0..N ODS por projeto, faixa `1`–`17`), representação (tabela associativa normalizada vs. lista controlada) e semântica de filtro (qualquer ODS selecionado `OR` vs. todos `AND`). | Nova migration com tabela de referência (`ODS-1`..`ODS-17`) + tabela associativa `academic_pi.project_ods` (ou tipo validado por `CHECK`). Comparar plano com `EXPLAIN (ANALYZE, BUFFERS)` antes de definir B-tree vs. `GIN`. |

### Campos já disponíveis para resposta pública mínima (já existentes em `academic_pi.project`)

| Campo | Tipo | Regra de Exposição Pública |
| :--- | :--- | :--- |
| `id` | `uuid` | Permitido quando `status = 'published' AND is_public = true` |
| `title` | `varchar(200)` | Permitido; coberto por `idx_project_public_title` para ordenação paginada (`V0017`) |
| `description` | `text` | Permitido quando publicado e público (respeitando sanitização na camada de apresentação) |
| `is_pi` / `is_extension` | `boolean` | Permitido para identificar modalidade (PI, Extensão ou ambos) |
| `starts_at` / `ends_at` | `timestamptz` | Permitido quando preenchido em projeto publicado e público |

### Campos explicitamente proibidos na consulta e nos índices do catálogo público

- `auth.user`: `email`, `cpf`, `password_hash`, `full_name` (dados pessoais / autenticação).
- `auth.user_session` e `auth.user_identity`: tokens, IPs e identidades federadas.
- `academic_pi.project_participation`: solicitações, recusas, justificativas de remoção e vínculos de alunos.
- `academic_pi.evaluation_criterion`, `academic_pi.project_evaluation`, `academic_pi.evaluation_criterion_score`: critérios internos, avaliadores, datas e notas individuais.
- `assets.project_file`: qualquer arquivo com `publication_authorized = false`.

---

## 3. Cache e Retirada de Publicação (Dependência Produto / Infra)

Antes de fechar o comportamento público da API/portal sobre o catálogo:

1. **Invalidação / SLA após retirada de publicação:** quando um projeto deixa de atender `status = 'published' AND is_public = true` (edição para `draft`/`archived` ou `is_public = false`), nenhum cache (HTTP/CDN/Redis/aplicação) deve continuar servindo o item além do SLA formal a ser aprovado.
2. **Estado atual:** **pendente de confirmação formal com Produto e Infra.** Não há política de TTL, *cache-control* ou evento de purga documentada nem implementada no escopo de banco.

---

## 4. Critério de Índices e Comprovação por Medição (`EXPLAIN ANALYZE`)

1. **Único índice público existente na `develop` (`V0017` — DB-017):**
   - Índice: `idx_project_public_title` em `academic_pi.project (title) WHERE is_public AND status = 'published'`.
   - Comprovação pareada já registrada em [`evidence/DB-017-query-performance.md`](../evidence/DB-017-query-performance.md) (30.004 projetos sintéticos determinísticos; consulta Q1 paginada `LIMIT 20` caiu de `2,004 ms` com `Seq Scan` para `0,056 ms` com `Index Scan`).
2. **Novos índices para `palavra-chave`, `curso`, `semestre` e `ODS`:**
   - **Não criados nesta entrega**, em conformidade estrita com o bloqueio da Issue `#14`: *"Não criar colunas, filtros, ordenação, paginação ou índices para decisões que ainda não foram aprovadas"*.
   - **Protocolo obrigatório após aprovação de Produto:**
     1. Registrar formalmente os campos aprovados, operadores de filtro e ordenação real da consulta.
     2. Gerar carga sintética determinística (sem `random()`, sem PII) com volume declarado e executar `ANALYZE`.
     3. Medir a consulta real em 3+ execuções com `EXPLAIN (ANALYZE, BUFFERS)` **antes** do índice.
     4. Criar migration incremental (`VNNNN__...`) apenas para os índices cujo ganho supere o ruído e justifique o custo de escrita/armazenamento.
     5. Repetir `EXPLAIN (ANALYZE, BUFFERS)` sobre o mesmo volume e registrar os planos antes/depois em `evidence/`.
