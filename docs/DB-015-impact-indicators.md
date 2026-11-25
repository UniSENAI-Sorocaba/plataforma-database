# DB-015: Impacto social publicado

## 1. Fonte das regras
Definições aprovadas pelo PO em 21/11/2026: `plataforma-governance`, `_KB/product/mvp-decisions-2026-11-21.md`, seção 6 ("Impactos e catálogo público"), status **Approved**. O arquivo está nas branches `release/v1.0.0` e `f5-governance-lighthouse-local` do repositório de governança (ainda não na `main`).

A SPEC-PORTAL-002 continua Draft; as decisões acima prevalecem e devem ser refletidas na SPEC.

## 2. Regras aprovadas e como o banco as aplica (`V0015__create_project_impact.sql`)

| Regra aprovada | Aplicação no banco |
|---|---|
| Impacto publicado exige resumo, público beneficiado, período, território, resultado observado, evidência textual e responsável pela aprovação | `project_impact_publication_ck`: se `is_published`, todos esses campos e a aprovação são obrigatórios. Rascunhos podem estar incompletos |
| Indicadores mínimos: `beneficiarios_atendidos` (inteiro >= 0), `horas_atividade` (decimal > 0), `parceiros_envolvidos` (inteiro >= 0) | Colunas `beneficiaries_served`, `activity_hours`, `partners_involved` com CHECK de faixa; obrigatórias na publicação |
| `ods_codes` | Tabela `project_impact_ods` (códigos 1 a 17, únicos por impacto) |
| Responsável do projeto declara; coordenação aprova | `declared_by` (origem) e `approved_by` + `approved_at` (sempre juntos, `project_impact_approval_ck`), todos FK para `auth."user"`. O papel de coordenação é verificado pelo Backend |
| Sem estimativa nem cálculo automático | Não há coluna de fórmula nem de origem calculada |
| Correção substitui o conteúdo vigente após nova aprovação | Uma linha por impacto; `UPDATE` substitui. **Não há tabela de versões nem de histórico** |
| Retirada deixa o conteúdo indisponível | `is_published = false` tira o impacto da consulta pública imediatamente. Expurgo de cache (API 1 min, CDN 15 min) é da infraestrutura |
| Catálogo público só expõe conteúdo aprovado | Visão `academic_pi.public_project_impact`: só impacto publicado e aprovado de projeto `published` e público |
| Sem dado identificável de beneficiário; relato e imagem com pessoas exigem autorização | Não há coluna para relato, imagem, nome, CPF, e-mail de beneficiário nem lista de parceiros (só a quantidade) |

## 3. Decisões tomadas por mim, a validar
1. **Evidência fora da consulta pública.** A decisão exige `evidence_text` para publicar, mas não diz se é pública. A visão **não** a expõe (mais restritivo; abrir depois é simples).
2. **`activity_hours` é total declarado do projeto**, não soma de horas individuais (que o Caderno diz não serem públicas).
3. **Vários impactos por projeto são permitidos** (sem UNIQUE em `project_id`). Restringir depois é possível; relaxar seria mais difícil.
4. **Sem máquina de estados:** só aprovação (`approved_*`) e publicação (`is_published`). Os estados nomeados não estão na decisão.
5. **ODS em tabela própria**, não em array, para unicidade e filtro do catálogo.
6. Colunas e tabelas em inglês, como na convenção DB-001; o mapa com os nomes da decisão está nos `COMMENT`.

## 4. Divergência com o Backend (BE-019)
O backend (`plataforma-backend`, branch `develop`, `docs/impact/README.md`) implementa versões, histórico de eventos e retirada com motivo. Isso **contradiz** a decisão aprovada (correção substitui o vigente) e a própria issue DB-015 (não criar tabela de versões). O banco segue a decisão aprovada. O Backend precisa ser alinhado; a T20 do plano de MVP ainda cita "versionar conteúdo".

## 5. Pendências
- Reconciliar SPEC-PORTAL-002 e a T20 com a decisão de 21/11.
- Confirmar os itens da seção 3.
- Papel de coordenação como aprovador e separação entre declarante e aprovador: regra do Backend (a decisão não impõe).
- Prazo de expurgo de cache: infraestrutura.

## 6. Verificação
`scripts/validate.sh` passos 38 a 41: estrutura, ausência de histórico/versões, colunas da visão pública, regras funcionais (publicação incompleta, aprovação, indicadores inválidos, período, FKs, ODS, correção, retirada, projeto não público) e seeds (`seeds/0006_project_impact.sql`).
