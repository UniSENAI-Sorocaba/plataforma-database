#!/usr/bin/env sh
set -eu

for seed in seeds/*.sql; do
  [ -e "$seed" ] || exit 0
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U plataforma -d plataforma < "$seed"
done
