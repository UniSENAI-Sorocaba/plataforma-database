#!/usr/bin/env sh
set -eu

DB_NAME="${PGDATABASE:-plataforma}"
DB_USER="${PGUSER:-plataforma}"

echo "[validate] 1. Validando schemas de dominio em $DB_NAME..."
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT string_agg(schema_name, ',' ORDER BY schema_name) FROM information_schema.schemata WHERE schema_name IN ('auth','academic_pi','extension','assets','institutional');" \
  | grep -qx 'academic_pi,assets,auth,extension,institutional'

echo "[validate] 2. Validando tabela public.schema_migration..."
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'schema_migration';" \
  | grep -qx '1'

echo "[validate] 3. Validando registro das migrations aplicadas..."
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT string_agg(version, ',' ORDER BY version) FROM public.schema_migration WHERE version IN ('V0001', 'V0002');" \
  | grep -qx 'V0001,V0002'

echo "[validate] 4. Validando tabela public.audit_event..."
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'audit_event';" \
  | grep -qx '1'

echo "[validate] 5. Validando indices da tabela public.audit_event..."
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT string_agg(indexname, ',' ORDER BY indexname) FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'audit_event' AND indexname IN ('idx_audit_event_actor','idx_audit_event_occurred_at','idx_audit_event_record');" \
  | grep -qx 'idx_audit_event_actor,idx_audit_event_occurred_at,idx_audit_event_record'

echo "[validate] 6. Validando check constraints da tabela public.audit_event..."
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT string_agg(conname, ',' ORDER BY conname) FROM pg_constraint WHERE conrelid = 'public.audit_event'::regclass AND contype = 'c' AND conname IN ('audit_event_operation_ck','audit_event_schema_name_ck','audit_event_table_name_ck');" \
  | grep -qx 'audit_event_operation_ck,audit_event_schema_name_ck,audit_event_table_name_ck'

echo "[validate] 7. Validando postura de seguranca (sem USAGE/CREATE para PUBLIC)..."
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT count(*) FROM information_schema.schemata WHERE schema_name IN ('auth','academic_pi','extension','assets','institutional') AND (has_schema_privilege('public', schema_name, 'USAGE') OR has_schema_privilege('public', schema_name, 'CREATE'));" \
  | grep -qx '0'

echo "[validate] 8. Validando integridade e funcionamento de constraints..."
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" <<'EOF'
DO $$
BEGIN
  BEGIN
    INSERT INTO public.audit_event (id, schema_name, table_name, operation)
    VALUES ('ffffffff-ffff-ffff-ffff-ffffffffffff', 'test', 'test', 'INVALID_OP');
    RAISE EXCEPTION 'Constraint check failed to reject invalid operation';
  EXCEPTION
    WHEN check_violation THEN
      -- Comportamento esperado: constraint bloqueou operacao invalida com sucesso
      NULL;
  END;
END $$;
EOF

echo "[validate] Todas as validacoes de compatibilidade e integridade foram concluidas com sucesso!"
