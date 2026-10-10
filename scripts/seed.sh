#!/usr/bin/env sh
set -eu

DB_NAME="${PGDATABASE:-plataforma}"
DB_USER="${PGUSER:-plataforma}"

echo "[seed] Aplicando seeds deterministicos em $DB_NAME..."

applied=0
for seed in seeds/*.sql; do
  [ -e "$seed" ] || continue
  echo "[seed] Aplicando $seed em $DB_NAME..."
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" < "$seed"
  applied=$((applied + 1))
done

if [ "$applied" -eq 0 ]; then
  echo "[seed] Nenhum arquivo SQL encontrado no diretorio seeds/."
else
  echo "[seed] $applied arquivo(s) de seed aplicado(s) com sucesso em $DB_NAME."
fi
