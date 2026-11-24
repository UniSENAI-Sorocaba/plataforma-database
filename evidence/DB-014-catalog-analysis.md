# Evidência de Análise e Conformidade — Catálogo Público (DB-014)

**Work ID:** DB-014 · Issue `#14`  
**Responsável:** Nicolas Pureza · **Revisor:** Henrique  
**Dependências técnicas:** DB-008 (`V0008`) e DB-012 (`docs/DB-012-enrollment-periods.md`)  
**Documento de análise:** [`docs/DB-014-public-catalog-analysis.md`](../docs/DB-014-public-catalog-analysis.md)

---

## 1. Resumo da Verificação na `develop`

A entrega **DB-014** formaliza a análise dos campos candidatos do catálogo público (`palavra-chave`, `curso`, `semestre` e `ODS`) na fase atual (**análise de campos**, anterior à modelagem de novos filtros/índices), garantindo que:

1. **Nenhuma regra pendente foi cristalizada no schema:** a verificação automática em [`scripts/validate.sh`](../scripts/validate.sh) (passo `43`) comprova que `academic_pi.project` não recebeu colunas especulativas (`course_code`, `ods_codes`, `semester`, `academic_term`, `keywords`, `final_score`) nem índices adicionais além da PK, `project_id_category_unq` e `idx_project_public_title` (`V0017`).
2. **Apenas o índice já justificado por medição permanece ativo (`DB-017`):** `idx_project_public_title` (`ON academic_pi.project (title) WHERE is_public AND status = 'published'`) foi comprovado previamente na entrega **DB-017** com carga sintética determinística de `30.004` projetos ([`evidence/DB-017-query-performance.md`](DB-017-query-performance.md), [`evidence/DB-017-queries-antes-v0017.txt`](DB-017-queries-antes-v0017.txt) e [`evidence/DB-017-queries-apos-v0017.txt`](DB-017-queries-apos-v0017.txt)), reduzindo a mediana da consulta Q1 paginada (`LIMIT 20`) de `2,004 ms` para `0,056 ms`.
3. **Nenhum dado privado é indexado para consulta pública:** horas, notas (`academic_pi.evaluation_criterion_score`, `academic_pi.project_evaluation`), participações e rascunhos não possuem índices públicos nem colunas de exposição no catálogo.

---

## 2. Pendências Formais Registradas (Precedem Nova Migration)

| Item Pendente | Responsável pela Definição | Impacto / Ação Futura |
| :--- | :--- | :--- |
| Escopo dos filtros `palavra-chave`, `curso`, `semestre` e `ODS` | Produto | Definir modelagem (colunas/tabelas de domínio), operadores e ordenação real antes de criar migration. |
| Nota agregada do projeto | Produto (André — `DB-010`) | Definir se existe nota pública do projeto, escala e cálculo antes de qualquer exposição. |
| Cache e SLA de retirada de publicação (`unpublish`) | Produto / Infra | Definir TTL e mecanismo de invalidação para impedir que projeto retirado permaneça servido além do SLA aprovado. |
| Medição `EXPLAIN (ANALYZE, BUFFERS)` antes/depois de novos índices | Database | Executar com volume sintético determinístico somente após aprovação da consulta real. |
