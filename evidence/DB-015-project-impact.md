# Evidência DB-015: impacto social publicado

Banco: PostgreSQL 16 (`compose.yaml`). Scripts executados diretamente (`make` indisponível no ambiente): `migrate.sh`, `seed.sh`, `validate.sh`, `validate_upgrade.sh` (que executa `detect_drift.sh`).
Regras: `plataforma-governance/_KB/product/mvp-decisions-2026-11-21.md`, seção 6 (Approved, PO, 21/11/2026), e T20 do plano de MVP.

## Critérios de aceite da issue
| Critério | Verificação | Resultado |
|---|---|---|
| Cada campo persistido rastreia uma definição aprovada e sua origem | Tabela campo → definição → origem em `docs/DB-015-impact-indicators.md` (seção 2.2); origem em `declared_by` | Passou (revisão documental) |
| Publicação não é implícita; a consulta pública não retorna conteúdo não aprovado | Aprovar rascunho incompleto rejeitado; rascunho, em correção, retirado e projeto não público ficam fora da visão; conteúdo e ODS de impacto aprovado não mudam sem nova aprovação; reaprovação exige novo `approved_at` | Passou |
| Alteração substitui o valor vigente, sem tabela de histórico | Correção edita a mesma linha e a visão mostra o novo conteúdo; nenhuma tabela `*impact*` com version/history/audit | Passou |
| Evidência cobre autorização, retirada e privacidade | Aprovação em par, retirada imediata, visão sem `declared_by`/`approved_*`/`status`, sem colunas de dado identificável | Passou |

## Execução
| Verificação | Resultado |
|---|---|
| Instalação limpa: migrations V0001 a V0017, seeds 0001 a 0006, `validate.sh` passos 1 a 41 | Passou |
| Idempotência do seed 0006 (executado duas vezes, com triggers de guarda ativos) | Passou |
| `validate_upgrade.sh`: upgrade V0001 até a última migration, idempotência de migrations e seeds, `validate.sh` no banco atualizado | Passou |
| `detect_drift.sh` (dentro do upgrade): schemas de instalação limpa e de upgrade equivalentes | Passou ("Nenhum drift detectado") |
| Teste de mutação: remover `project_impact_approved_ck` (aprovação exige campos obrigatórios) | `validate.sh` falhou, como esperado |
| Teste de mutação: visão pública sem filtro de aprovação | `validate.sh` falhou, como esperado |
| Teste de mutação: remover o trigger `project_impact_guard_trg` | `validate.sh` falhou, como esperado |

Casos negativos do passo 40: estado inválido; aprovar rascunho incompleto; `approved_by` sem `approved_at`; beneficiários negativo; horas iguais a zero; parceiros negativo; período invertido; texto vazio; projeto e declarante inexistentes; ODS 0, 18 e duplicado; alterar conteúdo, incluir e remover ODS de impacto aprovado; reaprovar sem novo `approved_at`; impacto de projeto não público fora da consulta; remoção de declarante bloqueada.
Casos positivos: rascunho parcial, aprovação completa visível com ODS, correção (sai de `approved`, edita, nova aprovação) que substitui o vigente, retirada imediata.

## Limitações
- Execução local. O CI do GitHub (`CI Database`) passou no commit `5152cc9` do PR #60 (sobe banco limpo, migrations e validação de compatibilidade em 49 s).
- Transições de estado, papel de coordenação como aprovador e separação entre declarante e aprovador são regras do Backend, não do banco.
- Durante uma correção o impacto sai da consulta pública até a nova aprovação (sem tabela de versões não há como manter o antigo visível). Confirmação do PO pendente.
- O Backend (`main`) usa um modelo diferente (tabelas `impact` e `impact_version`, estados em maiúsculas, `evidenceUrl`, ODS em array). Divergências em `docs/DB-015-impact-indicators.md`, seção 6.
