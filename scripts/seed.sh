#!/usr/bin/env sh
set -eu

DB_NAME="${PGDATABASE:-plataforma}"
DB_USER="${PGUSER:-plataforma}"

for seed in seeds/*.sql; do
  [ -e "$seed" ] || exit 0
  echo "Aplicando seed $seed em $DB_NAME..."
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" < "$seed"
done
