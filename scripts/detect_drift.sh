#!/usr/bin/env sh
set -eu

CLEAN_DB="${1:-${PGDATABASE:-plataforma}}"
UPGRADE_DB="${2:-plataforma_upgrade_test}"
DB_USER="${PGUSER:-plataforma}"

echo "=== [detect_drift] Iniciando deteccao de drift estrutural de schemas ==="
echo "   Banco de instalacao limpa (referencia): $CLEAN_DB"
echo "   Banco de upgrade incremental:          $UPGRADE_DB"

# 1. Verifica existencia dos dois bancos
clean_exists=$(docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d postgres -Atc \
  "SELECT 1 FROM pg_database WHERE datname = '$CLEAN_DB';")
if [ "$clean_exists" != "1" ]; then
  echo "ERRO [detect_drift]: Banco de instalacao limpa '$CLEAN_DB' nao encontrado." >&2
  exit 1
fi

upgrade_exists=$(docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d postgres -Atc \
  "SELECT 1 FROM pg_database WHERE datname = '$UPGRADE_DB';")
if [ "$upgrade_exists" != "1" ]; then
  echo "ERRO [detect_drift]: Banco de upgrade '$UPGRADE_DB' nao encontrado." >&2
  exit 1
fi

# 2. Diretorio temporario para os schemas extraidos
TMP_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t 'schema_drift')"
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

# 3. Funcao de extracao normalizada de schema
# Remove comentarios (--), linhas em branco, CRLF, setvals de sequences e meta-comandos psql (\restrict, \unrestrict)
dump_normalized_schema() {
  target_db="$1"
  docker compose exec -T postgres pg_dump -U "$DB_USER" -d "$target_db" \
    --schema-only \
    --no-owner \
    | tr -d '\r' \
    | sed -e '/^--/d' -e '/^[[:space:]]*$/d' -e '/SELECT pg_catalog\.setval/d' -e '/^\\/d'
}

echo "1. Extraindo DDL normalizado da instalacao limpa ($CLEAN_DB)..."
dump_normalized_schema "$CLEAN_DB" > "$TMP_DIR/clean_schema.sql"

echo "2. Extraindo DDL normalizado do banco atualizado ($UPGRADE_DB)..."
dump_normalized_schema "$UPGRADE_DB" > "$TMP_DIR/upgrade_schema.sql"

# 4. Validacao sumaria de contagem de objetos no catalogo
echo "3. Comparando contagem de objetos estruturais via catalogo..."
clean_counts=$(docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$CLEAN_DB" -Atc \
  "SELECT 'schemas=' || (SELECT count(*) FROM information_schema.schemata WHERE schema_name IN ('auth','academic_pi','extension','assets','institutional')) ||
          ',tables=' || (SELECT count(*) FROM information_schema.tables WHERE table_schema IN ('auth','academic_pi','extension','assets','institutional','public')) ||
          ',constraints=' || (SELECT count(*) FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace WHERE n.nspname IN ('auth','academic_pi','extension','assets','institutional','public')) ||
          ',indexes=' || (SELECT count(*) FROM pg_indexes WHERE schemaname IN ('auth','academic_pi','extension','assets','institutional','public'));")

upgrade_counts=$(docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$UPGRADE_DB" -Atc \
  "SELECT 'schemas=' || (SELECT count(*) FROM information_schema.schemata WHERE schema_name IN ('auth','academic_pi','extension','assets','institutional')) ||
          ',tables=' || (SELECT count(*) FROM information_schema.tables WHERE table_schema IN ('auth','academic_pi','extension','assets','institutional','public')) ||
          ',constraints=' || (SELECT count(*) FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace WHERE n.nspname IN ('auth','academic_pi','extension','assets','institutional','public')) ||
          ',indexes=' || (SELECT count(*) FROM pg_indexes WHERE schemaname IN ('auth','academic_pi','extension','assets','institutional','public'));")

echo "   Clean install: $clean_counts"
echo "   Upgrade:       $upgrade_counts"

if [ "$clean_counts" != "$upgrade_counts" ]; then
  echo "ERRO [detect_drift]: Contagem de objetos do catalogo difere entre $CLEAN_DB e $UPGRADE_DB!" >&2
  echo "Clean:   $clean_counts" >&2
  echo "Upgrade: $upgrade_counts" >&2
fi

# 5. Comparacao estrutural completa via diff
echo "4. Executando diff estrutural entre schemas DDL..."
if diff -u "$TMP_DIR/clean_schema.sql" "$TMP_DIR/upgrade_schema.sql" > "$TMP_DIR/schema_diff.patch"; then
  echo "=== [detect_drift] SUCESSO: Nenhum drift detectado! Schemas de instalacao limpa e upgrade sao equivalentes. ==="
  exit 0
else
  echo "================================================================================" >&2
  echo "FALHA [detect_drift]: DRIFT ESTRUTURAL DETECTADO ENTRE INSTALACAO LIMPA E UPGRADE!" >&2
  echo "Divergencias encontradas (clean_schema.sql -> upgrade_schema.sql):" >&2
  echo "================================================================================" >&2
  cat "$TMP_DIR/schema_diff.patch" >&2
  echo "================================================================================" >&2
  exit 1
fi
