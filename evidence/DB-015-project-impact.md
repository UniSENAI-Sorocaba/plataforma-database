# Evidência DB-015: impacto social publicado

Banco: PostgreSQL 16 (`compose.yaml`). Scripts executados diretamente (`make` indisponível no ambiente): `migrate.sh`, `seed.sh`, `validate.sh`, `validate_upgrade.sh`, `detect_drift.sh`.
Regras: `plataforma-governance/_KB/product/mvp-decisions-2026-11-21.md`, seção 6 (Approved, PO, 21/11/2026).

## Critérios de aceite da issue
| Critério | Verificação | Resultado |
|---|---|---|
| Cada campo persistido rastreia uma definição aprovada e sua origem | Tabela de mapeamento em `docs/DB-015-impact-indicators.md`; origem em `declared_by` | Passou (revisão documental) |
| Publicação não é implícita; a consulta pública não retorna conteúdo não aprovado | Rascunho e publicação incompleta rejeitados; rascunho, retirado e projeto não público ficam fora da visão | Passou |
| Alteração substitui o valor vigente, sem tabela de histórico | `UPDATE` reflete na visão; nenhuma tabela `*impact*` com version/history/audit | Passou |
| Evidência cobre autorização, retirada e privacidade | Aprovação em par, retirada imediata, visão sem `evidence_text`/atores, sem colunas de dado identificável | Passou |

## Execução

| Verificação | Resultado |
|---|---|
| Instalação limpa: migrations V0001 a V0017, seeds 0001 a 0006, `validate.sh` passos 1 a 41 | Passou |
| `validate_upgrade.sh`: upgrade V0001 até a última migration, idempotência de migrations e seeds, `validate.sh` no banco atualizado e ausência de drift entre instalação limpa e upgrade | Passou |
| Teste de mutação: remoção de `project_impact_publication_ck` | `validate.sh` falhou, como esperado |
| Teste de mutação: visão pública sem filtro de publicação | `validate.sh` falhou, como esperado |

Casos negativos cobertos pelo passo 40: publicar rascunho; `approved_by` sem `approved_at`; beneficiários negativo; horas iguais a zero; parceiros negativo; período invertido; texto vazio; projeto e declarante inexistentes; ODS 0, 18 e duplicado; impacto de projeto não público fora da consulta; remoção de declarante bloqueada. Casos positivos: rascunho parcial, publicação completa, correção que substitui o vigente e retirada imediata.

## Limitações
- Execução local; o CI do GitHub roda no PR.
- Estados nomeados, aprovador de papel coordenação e separação declarante/aprovador não são impostos pelo banco (Backend).
- Divergência com o Backend (BE-019 versiona e guarda histórico) está registrada em `docs/DB-015-impact-indicators.md`.
