#!/usr/bin/env sh
set -eu

DB_USER="${PGUSER:-plataforma}"
CLEAN_DB="${PGDATABASE:-plataforma}"
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

# 5. Verifica se todas as migrations da branch foram aplicadas com sucesso
echo "5. Verificando que todas as migrations da branch foram aplicadas no upgrade..."
expected_versions=$(for f in migrations/*.sql; do [ -e "$f" ] && basename "$f" | cut -d'_' -f1; done | sort | paste -sd, -)
applied_versions=$(docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$UPGRADE_DB" -Atc \
  "SELECT string_agg(version, ',' ORDER BY version) FROM public.schema_migration;")

echo "   Migrations esperadas: $expected_versions"
echo "   Migrations aplicadas: $applied_versions"

if [ "$expected_versions" != "$applied_versions" ]; then
  echo "ERRO [validate_upgrade]: Divergencia nas migrations aplicadas no upgrade!" >&2
  echo "Esperadas: $expected_versions" >&2
  echo "Aplicadas: $applied_versions" >&2
  exit 1
fi

# Confirma explicitamente a presenca de V0006, V0008 e V0013
echo "$applied_versions" | grep -q 'V0006' || (echo "ERRO: V0006 ausente no upgrade" >&2 && exit 1)
echo "$applied_versions" | grep -q 'V0008' || (echo "ERRO: V0008 ausente no upgrade" >&2 && exit 1)
echo "$applied_versions" | grep -q 'V0013' || (echo "ERRO: V0013 ausente no upgrade" >&2 && exit 1)

# 6. Valida idempotencia de migrations: reexecuta migrate.sh no banco atualizado
echo "6. Testando idempotencia de migrations (reexecutando migrate.sh no banco atualizado)..."
PGDATABASE="$UPGRADE_DB" ./scripts/migrate.sh

recheck_versions=$(docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$UPGRADE_DB" -Atc \
  "SELECT string_agg(version, ',' ORDER BY version) FROM public.schema_migration;")
if [ "$recheck_versions" != "$applied_versions" ]; then
  echo "ERRO [validate_upgrade]: Idempotencia de migrations falhou! Lista de versoes foi alterada." >&2
  exit 1
fi

# 7. Aplica seeds deterministicos no banco atualizado
echo "7. Aplicando seeds deterministicos no banco atualizado..."
PGDATABASE="$UPGRADE_DB" ./scripts/seed.sh

# 8. Valida idempotencia de seeds: reexecuta seed.sh no banco atualizado
echo "8. Testando idempotencia de seeds (reexecutando seed.sh no banco atualizado)..."
PGDATABASE="$UPGRADE_DB" ./scripts/seed.sh

# 9. Executa suite completa de validacao
echo "9. Executando suite completa de validacao no banco atualizado..."
PGDATABASE="$UPGRADE_DB" ./scripts/validate.sh

# 10. Executa deteccao de drift estrutural entre instalacao limpa e upgrade
echo "10. Detectando drift estrutural entre instalacao limpa ($CLEAN_DB) e upgrade ($UPGRADE_DB)..."
./scripts/detect_drift.sh "$CLEAN_DB" "$UPGRADE_DB"

# 11. Limpa o banco de teste de upgrade
echo "11. Limpando banco temporario de upgrade..."
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d postgres -c \
  "DROP DATABASE IF EXISTS $UPGRADE_DB WITH (FORCE);"

echo "=== [validate_upgrade] Validacao de upgrade, compatibilidade, idempotencia e ausencia de drift concluida com sucesso! ==="
