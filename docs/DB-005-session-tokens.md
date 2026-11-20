# DB-005 — Sessões, refresh tokens e recuperação

## Objetivo

Persistir o ciclo de vida de sessões autenticadas sem armazenar tokens em claro.

## Modelo

- `auth.session`: usuário, família, estado, expiração e motivo de revogação.
- `auth.refresh_token`: hash do token, rotação, uso, expiração e encadeamento do token substituto.
- `auth.password_recovery_token`: hash de token de recuperação, expiração, uso único e revogação.

Todos os vínculos possuem foreign keys para `auth.user`; consultas de sessão, família e tokens ativos possuem índices dedicados.

## Regras de segurança

- O valor original de refresh/recovery nunca é persistido.
- Hashes possuem tamanho mínimo de 64 caracteres e unicidade.
- Refresh usado pode ser marcado como reutilizado pelo serviço, permitindo revogar a família inteira.
- Token de recuperação usado não pode ser tratado como novo pelo contrato de aplicação.
- Expiração e revogação são consultáveis sem varredura completa.

## Migration e validação

- Migration: `migrations/V0004__create_auth_sessions_and_recovery_tokens.sql`.
- Validação local: `make up && make migrate && make test && make down`.
- O upgrade parte de V0001, aplica V0002–V0004, repete migrations e seeds e executa a suíte completa.
