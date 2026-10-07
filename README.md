# Plataforma Digital — Database

Migrations e dados sintéticos para PostgreSQL 16. Este repositório é a única fonte de migrations de banco da plataforma.

## Convenções iniciais

- nomes em `snake_case` e no singular;
- chaves primárias UUID geradas pela aplicação;
- timestamps como `timestamptz`, sempre em UTC;
- schemas de domínio: `auth`, `academic_pi`, `extension`, `assets` e `institutional`;
- migrations `VNNNN__descricao.sql`, apenas incrementais depois de publicadas;
- seeds determinísticos, sintéticos e sem dados pessoais.

## Validação local

Requer Docker com Compose.

```bash
make up
make migrate
make seed
make validate
make down
```

O `make validate` verifica a existência dos schemas de domínio esperados no PostgreSQL e confirma a estrutura básica definida pela DB-001.

## Pendência de governança

A tag informada em `.governance-baseline` ainda não foi publicada. A verificação tag→SHA deve ser habilitada assim que Product Governance publicar a baseline.
