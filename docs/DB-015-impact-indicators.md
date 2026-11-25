# DB-015: Impacto social publicado

## 1. Fonte das regras
- Decisões aprovadas pelo PO em 21/11/2026: `plataforma-governance`, `_KB/product/mvp-decisions-2026-11-21.md`, seção 6 ("Impactos e catálogo público"), status **Approved**. O arquivo está nas branches `release/v1.0.0` e `f5-governance-lighthouse-local` (ainda não na `main`).
- Plano de MVP, task T20 (`docs/mvp-v1-plan/tasks/T20-impacto-publicado.md`): criar estados, revisão/aprovação/retirada, renderizar apenas conteúdo aprovado. Métrica de aceite: zero conteúdo não aprovado público.
- Issue DB-015: sem histórico/versionamento; atualização substitui o valor vigente; sem catálogo genérico nem fórmula sem Produto.
- Caderno de Validações: horas e notas individuais não são públicas.

A SPEC-PORTAL-002 continua Draft e deve ser atualizada com estas decisões.

## 2. Modelo (`V0015__create_project_impact.sql`)
`academic_pi.project_impact` (uma linha por impacto, valor vigente), `academic_pi.project_impact_ods` (códigos ODS) e a visão `academic_pi.public_project_impact`.

### 2.1 Estados
`draft` → `submitted` → `approved` (= publicado) → `retired` (retirado da consulta pública). Origem: T20 ("criar estados") e o fluxo do Backend (`DRAFT`, `SUBMITTED`, `APPROVED`, `RETIRED`). As transições são regra do Backend; o banco garante o que não pode acontecer (seção 4).

### 2.2 Rastreabilidade: campo → definição aprovada → origem do dado

| Campo | Definição aprovada | Tipo e regra | Origem e validação |
|---|---|---|---|
| `summary` | Resumo (obrigatório para publicar) | texto, não vazio | Declarado pelo responsável do projeto; aprovado pela coordenação |
| `beneficiary_audience` | Público beneficiado (obrigatório) | texto, não vazio | Idem |
| `period_start`, `period_end` | Período (obrigatório) | datas, fim >= início | Idem |
| `territory` | Território (obrigatório) | texto, não vazio | Idem |
| `observed_result` | Resultado observado (obrigatório) | texto, não vazio | Idem |
| `evidence_text` | Evidência textual (obrigatória) | texto, não vazio | Idem |
| `declared_by` | Responsável do projeto declara | FK `auth."user"` | É a origem registrada de todo o conteúdo |
| `approved_by`, `approved_at` | Responsável pela aprovação; coordenação aprova | FK `auth."user"`, sempre juntos | O papel de coordenação é verificado pelo Backend |
| `beneficiaries_served` | Indicador `beneficiarios_atendidos` | inteiro >= 0 | Entrada manual do responsável; sem fórmula |
| `activity_hours` | Indicador `horas_atividade` | decimal > 0 (2 casas) | Entrada manual; total declarado do projeto, não soma de horas individuais |
| `partners_involved` | Indicador `parceiros_envolvidos` | inteiro >= 0 | Entrada manual; só a quantidade, sem identificar parceiros |
| `project_impact_ods` | Indicador `ods_codes` | códigos 1 a 17 (os 17 ODS da ONU), únicos por impacto | Entrada manual |

Fonte e fórmula: a decisão diz que os dados são **declarados pelo responsável** e **aprovados pela coordenação**, sem estimativa nem cálculo automático. Portanto a fonte de todo indicador é entrada manual e não existe fórmula nem coluna de cálculo.

Os nomes das colunas seguem a convenção DB-001 (inglês, snake_case); o mapa para os nomes da decisão está nos `COMMENT` das colunas.

## 3. Como cada regra aprovada é aplicada

| Regra aprovada | Aplicação no banco |
|---|---|
| Impacto publicado exige resumo, público beneficiado, período, território, resultado, evidência e responsável pela aprovação | `project_impact_approved_ck`: `status = 'approved'` exige esses campos, os 3 indicadores e a aprovação. Rascunhos podem estar incompletos |
| Indicadores com faixas definidas | CHECKs por coluna |
| Sem estimativa/cálculo automático | Sem coluna de cálculo |
| Catálogo público só expõe impacto aprovado | Visão `public_project_impact`: `status = 'approved'` de projeto `published` e público |
| Sem dado identificável de beneficiário; relato e imagem com pessoas exigem autorização | Não há coluna para relato, imagem, nome, CPF, e-mail nem lista de parceiros. A coordenação revisa o texto antes de aprovar |
| Correção substitui o conteúdo vigente após nova aprovação | Sem tabela de versões ou histórico. Ver seção 4 |
| Retirada deixa o conteúdo indisponível | `status = 'retired'` sai da visão pública imediatamente. Expurgo de cache (API 1 min, CDN 15 min) é da infraestrutura |

## 4. Proteção do conteúdo aprovado (triggers)
Para cumprir "zero conteúdo não aprovado público", o banco impede alteração silenciosa:
- `project_impact_guard`: um impacto `approved` não pode ter o conteúdo alterado enquanto continua `approved`.
- `project_impact_ods_guard`: os ODS de um impacto `approved` não podem ser incluídos, alterados ou removidos.
- Reaprovação exige **novo `approved_at`** ao voltar para `approved`.

Fluxo de correção suportado: o impacto sai de `approved` (volta para `draft` ou `submitted`), é editado e é aprovado de novo com nova aprovação. **Enquanto a correção aguarda aprovação, o impacto não aparece na consulta pública** (sem tabela de versões não há como manter o conteúdo antigo visível ao mesmo tempo). Isso nunca expõe conteúdo não aprovado; se o PO quiser que o antigo continue visível durante a correção, é preciso decidir uma estrutura de rascunho pendente, o que a issue hoje proíbe.

## 5. Decisões de modelagem e evidências
1. **Evidência é pública.** A decisão diz que o impacto publicado exige a evidência textual e que o catálogo expõe o "impacto aprovado". A visão expõe `evidence_text`, e não expõe `declared_by`, `approved_by`, `approved_at` nem o `status`.
2. **`activity_hours` é total declarado do projeto.** O Backend usa o mesmo conceito (`activityHours`, mínimo 0,01) e o Caderno impede somar horas individuais.
3. **Vários impactos por projeto são permitidos.** O Backend já consulta uma lista de impactos por projeto.
4. **ODS em tabela própria**, não em array: unicidade garantida e filtro do catálogo por ODS.
5. **Seed `0015`:** o impacto 1 entra como `draft` e é aprovado ao final porque os ODS só mudam fora de `approved`; os ODS usam `NOT EXISTS` (e não `ON CONFLICT`) porque o trigger roda antes da checagem de conflito.

## 6. Divergências com o Backend (a corrigir no Backend, não no banco)
Conferido em `plataforma-backend`, branch `main` (22/11/2026):

| Backend usa | Banco (DB-015) |
|---|---|
| `academic_pi.impact` + `academic_pi.impact_version` (versões; só a última é lida) | Uma tabela `project_impact` sem versões (decisão aprovada e issue) |
| `title` obrigatório | Não há título na decisão aprovada |
| `evidenceUrl` | `evidence_text` (a decisão diz evidência **textual**) |
| `beneficiarySummary` | `beneficiary_audience` (público beneficiado) |
| `ods_codes` como array de texto | Tabela `project_impact_ods` com `smallint` 1 a 17 |
| Estados em maiúsculas (`DRAFT`...) | Minúsculas, como as demais tabelas do banco (`draft`...) |
| Sem período (`period_start`/`period_end`) e sem resultado observado | Obrigatórios para aprovar, conforme a decisão |
| Em `develop`, o BE-019 ainda guarda histórico de eventos e retirada com motivo | Sem histórico (decisão aprovada) |

Além do impacto, o Backend referencia outras tabelas que não existem neste repositório (por exemplo `academic_pi.project_responsible` e `auth.user_role`). Isso é uma questão geral de alinhamento Backend e Banco, fora do escopo da DB-015.

## 7. Pendências
- Atualizar a SPEC-PORTAL-002 e a T20 do plano de MVP com a decisão de 21/11.
- Alinhar o Backend ao modelo da seção 6.
- Confirmação do PO sobre o comportamento de correção da seção 4.

## 8. Verificação
`scripts/validate.sh` passos 52 a 55: estrutura e triggers, ausência de histórico/versões, colunas da visão, regras funcionais (estados, aprovação incompleta, indicadores, período, FKs, ODS, guarda do conteúdo aprovado, correção com nova aprovação, retirada, projeto não público) e seeds (`seeds/0015_project_impact.sql`).
