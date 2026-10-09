# Plataforma Digital — Database

Migrations e dados sintéticos para PostgreSQL 16. Este repositório é a única fonte de migrations de banco da plataforma.

## Convenções iniciais

- nomes em `snake_case` e no singular;
- chaves primárias UUID geradas pela aplicação;
- timestamps como `timestamptz`, sempre em UTC;
- schemas de domínio: `auth`, `academic_pi`, `extension`, `assets` e `institutional`;
- migrations `VNNNN__descricao.sql`, apenas incrementais depois de publicadas;
- seeds determinísticos, sintéticos e sem dados pessoais.

## Integração Contínua (CI)

A esteira de Integração Contínua é executada via GitHub Actions ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) a cada *push* e *pull request* direcionado à branch `main`.

A pipeline executa:
1. Subida de container limpo PostgreSQL 16 (`make up`);
2. Aplicação sequencial de migrations (`make migrate`);
3. Injeção de seeds determinísticos e sintéticos (`make seed`);
4. Validação estrutural de compatibilidade e segurança (`make validate`);
5. Validação de atualização incremental e idempotência (`make validate-upgrade`);
6. Encerramento ordenado dos containers (`make down`).

## Validação local

Requer Docker com Compose instalado e ativo.

```bash
# 1. Sobe o banco de dados limpo
make up

# 2. Aplica as migrations incrementais
make migrate

# 3. Aplica os seeds sintéticos determinísticos
make seed

# 4. Valida a estrutura, schemas, tabelas, índices e postura de segurança
make validate

# 5. Valida o fluxo de upgrade incremental e idempotência
make validate-upgrade

# 6. Ou executa todas as validações de uma vez
make test

# 7. Encerra e remove os containers locais
make down
```

O comando `make validate` verifica a existência dos schemas de domínio, a tabela de controle `public.schema_migration`, a tabela de auditoria `public.audit_event`, integridade de restrições (check constraints), índices e postura de segurança (ausência de privilégios públicos para a role `PUBLIC`).

O comando `make validate-upgrade` valida a migração incremental a partir do estado anterior (baseline V0001) para a versão atual, além de testar a idempotência de reaplicação das migrações.

## Documentação e Evidências

- [DB-001: Convenções e Padrões de Arquitetura de Banco](docs/DB-001-conventions.md)
- [DB-002: Integração Contínua e Validação de Compatibilidade](docs/DB-002-ci.md)
- [Evidência DB-001: Segurança e Privilégios](evidence/DB-001-security.txt)
- [Evidência DB-002: Validação de CI, Instalação Limpa e Upgrade](evidence/DB-002-ci-validation.md)

## Pendência de governança

A tag informada em `.governance-baseline` ainda não foi publicada. A verificação tag→SHA deve ser habilitada assim que Product Governance publicar a baseline.
