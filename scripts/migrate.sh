#!/usr/bin/env sh
set -eu

DB_NAME="${PGDATABASE:-plataforma}"
DB_USER="${PGUSER:-plataforma}"

for migration in migrations/*.sql; do
  [ -e "$migration" ] || exit 0
  version=$(basename "$migration" | cut -d'_' -f1)

  # Verifica se a tabela schema_migration ja existe e se esta versao ja foi aplicada
  table_exists=$(docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
    "SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='schema_migration';" 2>/dev/null || true)

  if [ "$table_exists" = "1" ]; then
    already_applied=$(docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
      "SELECT 1 FROM public.schema_migration WHERE version = '$version';" 2>/dev/null || true)
    if [ "$already_applied" = "1" ]; then
      echo "Migration $version ja aplicada em $DB_NAME, ignorando."
      continue
    fi
  fi

  echo "Aplicando migration $migration em $DB_NAME..."
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" < "$migration"
done
