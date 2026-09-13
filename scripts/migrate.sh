#!/usr/bin/env sh
set -eu

for migration in migrations/*.sql; do
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U plataforma -d plataforma < "$migration"
done
