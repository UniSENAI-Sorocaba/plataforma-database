#!/usr/bin/env sh
set -eu

DB_USER="${PGUSER:-plataforma}"
UPGRADE_DB="plataforma_upgrade_test"

echo "=== [validate_upgrade] Iniciando validacao de upgrade incremental ==="

# 1. Cria um banco de dados limpo para o teste de upgrade
echo "1. Provisionando banco isolado para upgrade: $UPGRADE_DB..."
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d postgres -c \
  "DROP DATABASE IF EXISTS $UPGRADE_DB WITH (FORCE);"
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d postgres -c \
  "CREATE DATABASE $UPGRADE_DB OWNER $DB_USER;"

# 2. Aplica apenas a migration baseline (V0001)
echo "2. Aplicando migration baseline (V0001)..."
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$UPGRADE_DB" < migrations/V0001__create_domain_schemas.sql

# 3. Confirma que apenas V0001 esta registrada
echo "3. Validando estado pos-V0001..."
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$UPGRADE_DB" -Atc \
  "SELECT version FROM public.schema_migration;" | grep -qx 'V0001'

# 4. Executa upgrade usando migrate.sh
echo "4. Executando upgrade com migrate.sh..."
PGDATABASE="$UPGRADE_DB" ./scripts/migrate.sh

# 5. Verifica se V0002 foi aplicada com sucesso
echo "5. Verificando que V0002 foi aplicada no upgrade..."
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$UPGRADE_DB" -Atc \
  "SELECT count(*) FROM public.schema_migration WHERE version = 'V0002';" | grep -qx '1'

# 6. Valida idempotencia de migrations: reexecuta migrate.sh no banco atualizado
echo "6. Testando idempotencia de migrations (reexecutando migrate.sh no banco atualizado)..."
PGDATABASE="$UPGRADE_DB" ./scripts/migrate.sh

# 7. Aplica seeds deterministicos no banco atualizado
echo "7. Aplicando seeds deterministicos no banco atualizado..."
PGDATABASE="$UPGRADE_DB" ./scripts/seed.sh

# 8. Valida idempotencia de seeds: reexecuta seed.sh no banco atualizado
echo "8. Testando idempotencia de seeds (reexecutando seed.sh no banco atualizado)..."
PGDATABASE="$UPGRADE_DB" ./scripts/seed.sh

# 9. Executa suite completa de validacao
echo "9. Executando suite completa de validacao no banco atualizado..."
PGDATABASE="$UPGRADE_DB" ./scripts/validate.sh

# 10. Limpa o banco de teste de upgrade
echo "10. Limpando banco temporario de upgrade..."
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d postgres -c \
  "DROP DATABASE IF EXISTS $UPGRADE_DB WITH (FORCE);"

echo "=== [validate_upgrade] Validacao de upgrade, compatibilidade e idempotencia de seeds concluida com sucesso! ==="
