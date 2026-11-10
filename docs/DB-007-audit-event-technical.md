# DB-007: Registros operacionais sem auditoria de negócio

## 1. Decisão aplicada
O Caderno de Validações (itens 50, 62 e 65) e a SPEC-AUTH-004 determinam que **não há auditoria de negócio** nem histórico de valores anteriores de notas, horas ou outros dados acadêmicos. Esta entrega reconcilia `public.audit_event` com essa decisão.

## 2. O que mudou (`V0007__restrict_audit_event_to_technical_records.sql`)
| Item | Antes | Depois |
|---|---|---|
| `old_data` / `new_data` | Aceitavam snapshots `jsonb` | Sempre `NULL` (`audit_event_no_snapshot_ck`) |
| Snapshots já persistidos | Presentes nos seeds | Removidos pela migration (`UPDATE ... SET NULL`) |
| Documentação da tabela | Trilha de alterações | `COMMENT` declara registro técnico, não auditoria de negócio |

Estratégia Expand and Contract: as colunas são mantidas (sem quebrar consumidores) e deixam de aceitar valores. A remoção física das colunas fica para uma migration de *contract* posterior.

## 3. O que permanece
Somente metadados técnicos: `id`, `occurred_at`, `schema_name`, `table_name`, `operation`, `record_id`, `actor_id`. Nenhum campo carrega credencial, senha, token ou valor acadêmico.

## 4. Fora do escopo (não decidido aqui)
- Forma e retenção dos registros técnicos/de segurança: decisão de Segurança/Infra.
- Se `record_id` + `actor_id` + `operation` sobre tabelas acadêmicas ainda caracterizam trilha de negócio (AC-AUTH-004-03): precisa de decisão de Segurança/PO antes de qualquer novo uso da tabela.
- Remoção das colunas `old_data`/`new_data` (contract).

## 5. Verificação
`scripts/validate.sh` passos 9.1–9.3: constraint presente, nenhuma linha com snapshot, nenhuma rotina ou trigger referencia `audit_event`, inserção técnica aceita e snapshots rejeitados.
