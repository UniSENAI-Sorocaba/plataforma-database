# Evidência DB-007: registros operacionais sem auditoria de negócio

Banco: PostgreSQL 16 (`postgres:16-alpine`, `compose.yaml`). Comandos: `docker compose up -d --wait`, `scripts/migrate.sh`, `scripts/seed.sh`, `scripts/validate.sh`, `scripts/validate_upgrade.sh`. `make` não estava disponível no ambiente; os scripts chamados por cada alvo do `Makefile` foram executados diretamente.

## Resultados
| Verificação | Resultado |
|---|---|
| Instalação limpa (migrate + seed + validate, passos 1–22 e 9.1–9.3) | Passou |
| Upgrade incremental V0001 → V0007, idempotência de migrations e seeds | Passou |
| Rotinas/triggers que alimentam `public.audit_event` | 0 encontrados (`pg_proc`, `pg_trigger`) |
| Linhas com `old_data`/`new_data` após `V0007` | 0 |
| Inserção com `old_data` ou `new_data` | Rejeitada (`check_violation`) |
| Inserção de evento técnico (sem snapshot) | Aceita |

## Upgrade sobre dados legados
Banco criado em V0002 com o seed anterior (`origin/develop:seeds/0001_audit_event.sql`):

- antes de `V0007`: 15 linhas com snapshot;
- depois de `V0007`: 0 linhas com snapshot, 15 eventos preservados.

## Eventos técnicos que permanecem
`id`, `occurred_at`, `schema_name`, `table_name`, `operation`, `record_id`, `actor_id`. Credenciais, senhas, tokens e valores acadêmicos anteriores não são registrados.

## Limitações
- Testes automatizados em CI não foram executados nesta evidência (apenas localmente).
- Retenção e forma dos registros técnicos dependem de Segurança/Infra.
- Colunas `old_data`/`new_data` ainda existem (sempre `NULL`); remoção prevista em migration de contract.
