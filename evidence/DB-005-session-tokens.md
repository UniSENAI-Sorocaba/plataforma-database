# Evidência DB-005 — Sessões e tokens

**Data:** 2026-11-20  
**Status:** PASS local

## Resultado

- V0004 aplicada em banco existente sem alterar V0001–V0003.
- Sessão, refresh token e recovery token criados com constraints, foreign keys e índices.
- Fluxo sintético de uso, rotação, revogação e uso único validado.
- Upgrade desde V0001 até V0004 validado.
- Reexecução de migrations e seeds validada como idempotente.
- Validação anti-PII e de segurança dos schemas mantida.

## Comandos

```text
make up
make migrate
make test
make down
```

Resultado: todos os passos concluídos com sucesso.
