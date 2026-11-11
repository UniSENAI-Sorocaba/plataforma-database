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
  "SELECT string_agg(version, ',' ORDER BY version) FROM public.schema_migration WHERE version IN ('V0001', 'V0002', 'V0003', 'V0004');" \
  | grep -qx 'V0001,V0002,V0003,V0004'

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

echo "[validate] 8. Validando integridade e funcionamento de constraints em public.audit_event..."
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" <<'EOF'
DO $$
BEGIN
  BEGIN
    INSERT INTO public.audit_event (id, schema_name, table_name, operation)
    VALUES ('ffffffff-ffff-ffff-ffff-ffffffffffff', 'test', 'test', 'INVALID_OP');
    RAISE EXCEPTION 'Constraint check failed to reject invalid operation';
  EXCEPTION
    WHEN check_violation THEN
      NULL;
  END;
END $$;
EOF

echo "[validate] 9. Validando presenca e cobertura de seeds deterministicos em public.audit_event..."
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT (count(*) >= 15)::text FROM public.audit_event;" \
  | grep -qx 'true'

docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT string_agg(DISTINCT schema_name, ',' ORDER BY schema_name) FROM public.audit_event WHERE schema_name IN ('academic_pi','assets','auth','extension','institutional');" \
  | grep -qx 'academic_pi,assets,auth,extension,institutional'

docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT string_agg(DISTINCT operation, ',' ORDER BY operation) FROM public.audit_event WHERE operation IN ('DELETE','INSERT','UPDATE');" \
  | grep -qx 'DELETE,INSERT,UPDATE'

echo "[validate] 10. Validando tabelas de identidade, usuario e vinculo (DB-004)..."
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT string_agg(table_schema || '.' || table_name, ',' ORDER BY table_schema, table_name) FROM information_schema.tables WHERE (table_schema = 'auth' AND table_name IN ('user', 'user_identity')) OR (table_schema = 'institutional' AND table_name IN ('academic_class', 'academic_link'));" \
  | grep -qx 'auth.user,auth.user_identity,institutional.academic_class,institutional.academic_link'

echo "[validate] 11. Validando check constraints de identidade, usuario e vinculo..."
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT string_agg(conname, ',' ORDER BY conname) FROM pg_constraint WHERE conrelid IN ('auth.user'::regclass, 'auth.user_identity'::regclass, 'institutional.academic_class'::regclass, 'institutional.academic_link'::regclass) AND contype = 'c';" \
  | grep -qx 'academic_class_code_ck,academic_class_name_ck,academic_class_term_ck,academic_link_registration_number_ck,academic_link_role_ck,academic_link_status_ck,user_cpf_ck,user_email_ck,user_full_name_ck,user_identity_email_ck,user_identity_provider_ck,user_identity_provider_subject_ck,user_password_hash_ck,user_status_ck'

echo "[validate] 12. Validando foreign keys de identidade e vinculo..."
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT string_agg(conname, ',' ORDER BY conname) FROM pg_constraint WHERE conrelid IN ('auth.user_identity'::regclass, 'institutional.academic_link'::regclass) AND contype = 'f';" \
  | grep -qx 'academic_link_class_fk,academic_link_user_fk,user_identity_user_fk'

echo "[validate] 13. Validando unique constraints de identidade, usuario e vinculo..."
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT string_agg(conname, ',' ORDER BY conname) FROM pg_constraint WHERE conrelid IN ('auth.user'::regclass, 'auth.user_identity'::regclass, 'institutional.academic_class'::regclass, 'institutional.academic_link'::regclass) AND contype = 'u';" \
  | grep -qx 'academic_class_code_unq,academic_link_user_class_role_unq,user_cpf_unq,user_email_unq,user_identity_provider_subject_unq'

echo "[validate] 14. Validando indices de identidade, usuario e vinculo..."
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT string_agg(indexname, ',' ORDER BY indexname) FROM pg_indexes WHERE schemaname IN ('auth', 'institutional') AND tablename IN ('user', 'user_identity', 'academic_class', 'academic_link') AND indexname LIKE 'idx_%';" \
  | grep -qx 'idx_academic_class_code,idx_academic_class_is_active,idx_academic_class_term,idx_academic_link_class_id,idx_academic_link_status,idx_academic_link_user_id,idx_user_cpf,idx_user_email,idx_user_identity_provider_subject,idx_user_identity_user_id,idx_user_status'

echo "[validate] 15. Validando comportamento funcional e regras de integridade (DO block)..."
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" <<'EOF'
DO $$
DECLARE
  v_user_id uuid := 'f0000000-0000-4000-8000-000000000001';
  v_user_id_2 uuid := 'f0000000-0000-4000-8000-000000000002';
  v_class_id_1 uuid := 'f0000000-0000-4000-8000-000000000011';
  v_class_id_2 uuid := 'f0000000-0000-4000-8000-000000000012';
  v_identity_id uuid := 'f0000000-0000-4000-8000-000000000021';
  v_link_id_1 uuid := 'f0000000-0000-4000-8000-000000000031';
  v_link_id_2 uuid := 'f0000000-0000-4000-8000-000000000032';
BEGIN
  -- Teste 1: Rejeicao de email invalido
  BEGIN
    INSERT INTO auth.user (id, email, full_name, status)
    VALUES (v_user_id, 'email-invalido-sem-arroba', 'Test User', 'active');
    RAISE EXCEPTION 'Constraint user_email_ck falhou ao permitir email sem formato valido';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- Teste 2: Rejeicao de CPF invalido (formato nao normalizado ou com tamanho incorreto)
  BEGIN
    INSERT INTO auth.user (id, email, full_name, cpf, status)
    VALUES (v_user_id, 'test.cpf.bad@synthetic.local', 'Test User', '123456', 'active');
    RAISE EXCEPTION 'Constraint user_cpf_ck falhou ao permitir CPF fora de 11 digitos numericos';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO auth.user (id, email, full_name, cpf, status)
    VALUES (v_user_id, 'test.cpf.alpha@synthetic.local', 'Test User', '1234567890a', 'active');
    RAISE EXCEPTION 'Constraint user_cpf_ck falhou ao permitir caracteres nao numericos no CPF';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- Teste 3: Rejeicao de status de usuario invalido
  BEGIN
    INSERT INTO auth.user (id, email, full_name, status)
    VALUES (v_user_id, 'test.status@synthetic.local', 'Test User', 'STATUS_INVALIDO');
    RAISE EXCEPTION 'Constraint user_status_ck falhou ao permitir status invalido';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- Teste 4: Insercao de usuario valido (com e sem vinculo)
  INSERT INTO auth.user (id, email, full_name, cpf, status)
  VALUES (v_user_id, 'valid.user.1@synthetic.local', 'Valid Test User One', '99999999991', 'active');

  INSERT INTO auth.user (id, email, full_name, cpf, status)
  VALUES (v_user_id_2, 'valid.user.2@synthetic.local', 'Valid Test User Two', '99999999992', 'pending');

  -- Teste 5: Rejeicao de duplicidade de email
  BEGIN
    INSERT INTO auth.user (id, email, full_name, status)
    VALUES ('f0000000-0000-4000-8000-000000000009', 'valid.user.1@synthetic.local', 'Other User', 'active');
    RAISE EXCEPTION 'Constraint user_email_unq falhou ao permitir email duplicado';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  -- Teste 6: Rejeicao de duplicidade de CPF
  BEGIN
    INSERT INTO auth.user (id, email, full_name, cpf, status)
    VALUES ('f0000000-0000-4000-8000-000000000009', 'other.email@synthetic.local', 'Other User', '99999999991', 'active');
    RAISE EXCEPTION 'Constraint user_cpf_unq falhou ao permitir CPF duplicado';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  -- Teste 7: Insercao de identidade OIDC federada
  INSERT INTO auth.user_identity (id, user_id, provider, provider_subject, email)
  VALUES (v_identity_id, v_user_id, 'oidc', 'sub-test-valid-01', 'valid.user.1@synthetic.local');

  -- Teste 8: Rejeicao de duplicidade em provider + provider_subject
  BEGIN
    INSERT INTO auth.user_identity (id, user_id, provider, provider_subject, email)
    VALUES ('f0000000-0000-4000-8000-000000000029', v_user_id_2, 'oidc', 'sub-test-valid-01', 'other@synthetic.local');
    RAISE EXCEPTION 'Constraint user_identity_provider_subject_unq falhou ao permitir provider_subject duplicado';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  -- Teste 9: Insercao de turmas academicas
  INSERT INTO institutional.academic_class (id, code, name, term)
  VALUES (v_class_id_1, 'TEST-CLASS-01', 'Turma de Teste 1', '2026.1');

  INSERT INTO institutional.academic_class (id, code, name, term)
  VALUES (v_class_id_2, 'TEST-CLASS-02', 'Turma de Teste 2', '2026.1');

  -- Teste 10: Insercao de vinculo do estudante com multiplas turmas
  INSERT INTO institutional.academic_link (id, user_id, class_id, role, status)
  VALUES (v_link_id_1, v_user_id, v_class_id_1, 'student', 'active');

  INSERT INTO institutional.academic_link (id, user_id, class_id, role, status)
  VALUES (v_link_id_2, v_user_id, v_class_id_2, 'student', 'active');

  -- Teste 11: Rejeicao de vinculo duplicado na mesma turma com mesmo papel
  BEGIN
    INSERT INTO institutional.academic_link (id, user_id, class_id, role, status)
    VALUES ('f0000000-0000-4000-8000-000000000039', v_user_id, v_class_id_1, 'student', 'active');
    RAISE EXCEPTION 'Constraint academic_link_user_class_role_unq falhou ao permitir vinculo duplicado';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  -- Teste 12: Rejeicao de role ou status invalido no vinculo
  BEGIN
    INSERT INTO institutional.academic_link (id, user_id, class_id, role, status)
    VALUES ('f0000000-0000-4000-8000-000000000039', v_user_id_2, v_class_id_1, 'INVALID_ROLE', 'active');
    RAISE EXCEPTION 'Constraint academic_link_role_ck falhou ao permitir papel invalido';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO institutional.academic_link (id, user_id, class_id, role, status)
    VALUES ('f0000000-0000-4000-8000-000000000039', v_user_id_2, v_class_id_1, 'student', 'INVALID_STATUS');
    RAISE EXCEPTION 'Constraint academic_link_status_ck falhou ao permitir status invalido';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- Limpeza dos registros de teste
  DELETE FROM institutional.academic_link WHERE id IN (v_link_id_1, v_link_id_2);
  DELETE FROM institutional.academic_class WHERE id IN (v_class_id_1, v_class_id_2);
  DELETE FROM auth.user_identity WHERE id = v_identity_id;
  DELETE FROM auth.user WHERE id IN (v_user_id, v_user_id_2);
END $$;
EOF

echo "[validate] 16. Validando presenca de dados sinteticos nas tabelas DB-004..."
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT (count(*) >= 5)::text FROM auth.user;" | grep -qx 'true'

docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT (count(*) >= 2)::text FROM auth.user_identity;" | grep -qx 'true'

docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT (count(*) >= 2)::text FROM institutional.academic_class;" | grep -qx 'true'

docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT (count(*) >= 5)::text FROM institutional.academic_link;" | grep -qx 'true'

echo "[validate] 17. Validando conformidade Anti-PII e determinismo (sem dados pessoais)..."
# Auditoria
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT count(*) FROM public.audit_event WHERE id::text NOT LIKE '00000000-0000-4000-8000-%';" \
  | grep -qx '0'

docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT count(*) FROM public.audit_event WHERE (old_data::text ~* '(@gmail|@hotmail|@outlook|@yahoo|@senai|@unisenai|[0-9]{3}\.[0-9]{3}\.[0-9]{3}-[0-9]{2})') OR (new_data::text ~* '(@gmail|@hotmail|@outlook|@yahoo|@senai|@unisenai|[0-9]{3}\.[0-9]{3}\.[0-9]{3}-[0-9]{2})');" \
  | grep -qx '0'

# auth.user e auth.user_identity
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT count(*) FROM auth.user WHERE email ~* '(@gmail|@hotmail|@outlook|@yahoo|@senai|@unisenai)'; " \
  | grep -qx '0'

docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT count(*) FROM auth.user_identity WHERE email ~* '(@gmail|@hotmail|@outlook|@yahoo|@senai|@unisenai)'; " \
  | grep -qx '0'

echo "[validate] 18. Validando tabela auth.user_session (DB-005)..."
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'auth' AND table_name = 'user_session';" \
  | grep -qx '1'

echo "[validate] 19. Validando constraints e foreign keys de auth.user_session..."
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT string_agg(conname, ',' ORDER BY conname) FROM pg_constraint WHERE conrelid = 'auth.user_session'::regclass AND contype = 'c';" \
  | grep -qx 'user_session_expires_at_ck,user_session_token_hash_ck'

docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT string_agg(conname, ',' ORDER BY conname) FROM pg_constraint WHERE conrelid = 'auth.user_session'::regclass AND contype = 'f';" \
  | grep -qx 'user_session_replaced_by_token_fk,user_session_user_fk'

docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT string_agg(conname, ',' ORDER BY conname) FROM pg_constraint WHERE conrelid = 'auth.user_session'::regclass AND contype = 'u';" \
  | grep -qx 'user_session_token_hash_unq'

echo "[validate] 20. Validando indices de auth.user_session..."
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT string_agg(indexname, ',' ORDER BY indexname) FROM pg_indexes WHERE schemaname = 'auth' AND tablename = 'user_session' AND indexname LIKE 'idx_%';" \
  | grep -qx 'idx_user_session_active_lookup,idx_user_session_family_id,idx_user_session_user_id'

echo "[validate] 21. Validando regras funcionais e de integridade em auth.user_session (DO block)..."
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" <<'EOF'
DO $$
DECLARE
  v_user_id uuid := 'f0000000-0000-4000-8000-000000000099';
  v_session_id_1 uuid := 'f0000000-0000-4000-8000-000000000051';
  v_session_id_2 uuid := 'f0000000-0000-4000-8000-000000000052';
  v_family_id uuid := 'f0000000-0000-4000-8000-000000000061';
BEGIN
  -- Insere usuario de teste
  INSERT INTO auth.user (id, email, full_name, status)
  VALUES (v_user_id, 'test.session.user@synthetic.local', 'Session Test User', 'active');

  -- Teste 1: Rejeicao de token_hash curto (< 64 caracteres)
  BEGIN
    INSERT INTO auth.user_session (id, user_id, token_hash, family_id, expires_at)
    VALUES (v_session_id_1, v_user_id, 'hash_invalido_curto', v_family_id, now() + interval '7 days');
    RAISE EXCEPTION 'Constraint user_session_token_hash_ck falhou ao permitir hash com tamanho incorreto';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- Teste 2: Rejeicao de expires_at anterior ou igual a created_at
  BEGIN
    INSERT INTO auth.user_session (id, user_id, token_hash, family_id, created_at, expires_at)
    VALUES (v_session_id_1, v_user_id, repeat('a', 64), v_family_id, now(), now() - interval '1 hour');
    RAISE EXCEPTION 'Constraint user_session_expires_at_ck falhou ao permitir expires_at anterior a created_at';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- Teste 3: Insercao de sessao valida
  INSERT INTO auth.user_session (id, user_id, token_hash, family_id, expires_at)
  VALUES (v_session_id_1, v_user_id, repeat('a', 64), v_family_id, now() + interval '7 days');

  -- Teste 4: Rejeicao de duplicidade em token_hash
  BEGIN
    INSERT INTO auth.user_session (id, user_id, token_hash, family_id, expires_at)
    VALUES (v_session_id_2, v_user_id, repeat('a', 64), v_family_id, now() + interval '7 days');
    RAISE EXCEPTION 'Constraint user_session_token_hash_unq falhou ao permitir token_hash duplicado';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  -- Teste 5: Insercao de token rotacionado e vinculo em replaced_by_token_id
  INSERT INTO auth.user_session (id, user_id, token_hash, family_id, expires_at)
  VALUES (v_session_id_2, v_user_id, repeat('b', 64), v_family_id, now() + interval '7 days');

  UPDATE auth.user_session
  SET replaced_by_token_id = v_session_id_2, revoked_at = now()
  WHERE id = v_session_id_1;

  -- Teste 6: Exclusao em cascata ao remover usuario
  DELETE FROM auth.user WHERE id = v_user_id;

  IF EXISTS (SELECT 1 FROM auth.user_session WHERE id IN (v_session_id_1, v_session_id_2)) THEN
    RAISE EXCEPTION 'ON DELETE CASCADE falhou ao nao remover sessoes do usuario excluido';
  END IF;
END $$;
EOF

echo "[validate] 22. Validando presenca de dados sinteticos em auth.user_session..."
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT (count(*) >= 5)::text FROM auth.user_session;" | grep -qx 'true'

docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT count(*) FROM auth.user_session WHERE id::text NOT LIKE 'c0000000-0000-4000-8000-%';" \
  | grep -qx '0'

echo "[validate] 23. Validando tabelas e registro da migration de projetos (DB-008)..."
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT string_agg(table_name, ',' ORDER BY table_name) FROM information_schema.tables WHERE table_schema = 'academic_pi' AND table_name IN ('project', 'enrollment_period', 'project_instructor', 'project_participation');" \
  | grep -qx 'enrollment_period,project,project_instructor,project_participation'

docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT count(*) FROM public.schema_migration WHERE version = 'V0008';" \
  | grep -qx '1'

echo "[validate] 24. Validando check, unique e foreign keys das tabelas de projeto..."
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT string_agg(conname, ',' ORDER BY conname) FROM pg_constraint WHERE conrelid IN ('academic_pi.project'::regclass, 'academic_pi.enrollment_period'::regclass, 'academic_pi.project_instructor'::regclass, 'academic_pi.project_participation'::regclass) AND contype = 'c';" \
  | grep -qx 'enrollment_period_window_ck,project_category_ck,project_participation_category_ck,project_participation_justification_ck,project_participation_status_ck,project_period_ck,project_status_ck,project_title_ck'

docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT string_agg(conname, ',' ORDER BY conname) FROM pg_constraint WHERE conrelid IN ('academic_pi.project'::regclass, 'academic_pi.enrollment_period'::regclass, 'academic_pi.project_instructor'::regclass, 'academic_pi.project_participation'::regclass) AND contype = 'u';" \
  | grep -qx 'project_id_category_unq,project_instructor_project_instructor_unq,project_participation_project_student_unq'

docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT string_agg(conname, ',' ORDER BY conname) FROM pg_constraint WHERE conrelid IN ('academic_pi.enrollment_period'::regclass, 'academic_pi.project_instructor'::regclass, 'academic_pi.project_participation'::regclass) AND contype = 'f';" \
  | grep -qx 'enrollment_period_project_fk,project_instructor_project_fk,project_instructor_user_fk,project_participation_project_fk,project_participation_user_fk'

echo "[validate] 25. Validando indices das tabelas de projeto..."
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT string_agg(indexname, ',' ORDER BY indexname) FROM pg_indexes WHERE schemaname = 'academic_pi' AND tablename IN ('project', 'enrollment_period', 'project_instructor', 'project_participation') AND indexname LIKE 'idx_%';" \
  | grep -qx 'idx_enrollment_period_project_id,idx_project_instructor_instructor_id,idx_project_participation_student_active_extension,idx_project_participation_student_active_pi,idx_project_participation_student_id'

echo "[validate] 26. Validando regras funcionais e de integridade das tabelas de projeto (DO block)..."
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" <<'EOF'
DO $$
DECLARE
  v_student_1 uuid := 'f8000000-0000-4000-8000-0000000000a1';
  v_student_2 uuid := 'f8000000-0000-4000-8000-0000000000a2';
  v_instructor uuid := 'f8000000-0000-4000-8000-0000000000b1';
  p_pi uuid := 'f8000000-0000-4000-8000-000000000001';
  p_pi_2 uuid := 'f8000000-0000-4000-8000-000000000002';
  p_dual uuid := 'f8000000-0000-4000-8000-000000000003';
  p_ext uuid := 'f8000000-0000-4000-8000-000000000004';
BEGIN
  -- Usuarios sinteticos de apoio
  INSERT INTO auth.user (id, email, full_name, status) VALUES
    (v_student_1, 'db008.validate.student1@synthetic.local', 'DB008 Validate Student One', 'active'),
    (v_student_2, 'db008.validate.student2@synthetic.local', 'DB008 Validate Student Two', 'active'),
    (v_instructor, 'db008.validate.instructor1@synthetic.local', 'DB008 Validate Instructor', 'active');

  INSERT INTO academic_pi.project (id, title, is_pi, is_extension) VALUES
    (p_pi, 'Validate PI 1', true, false),
    (p_pi_2, 'Validate PI 2', true, false),
    (p_dual, 'Validate Dual', true, true),
    (p_ext, 'Validate Extension', false, true);

  -- Teste 1: projeto sem categoria
  BEGIN
    INSERT INTO academic_pi.project (id, title, is_pi, is_extension)
    VALUES (gen_random_uuid(), 'Sem categoria', false, false);
    RAISE EXCEPTION 'Constraint project_category_ck falhou ao permitir projeto sem categoria';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- Teste 2: titulo vazio
  BEGIN
    INSERT INTO academic_pi.project (id, title, is_pi, is_extension)
    VALUES (gen_random_uuid(), '   ', true, false);
    RAISE EXCEPTION 'Constraint project_title_ck falhou ao permitir titulo vazio';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- Teste 3: janela de inscricao invertida
  BEGIN
    INSERT INTO academic_pi.enrollment_period (id, project_id, opens_at, closes_at)
    VALUES (gen_random_uuid(), p_pi, now(), now() - interval '1 day');
    RAISE EXCEPTION 'Constraint enrollment_period_window_ck falhou ao permitir fechamento anterior a abertura';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- Teste 4: aluno e docente inexistentes
  BEGIN
    INSERT INTO academic_pi.project_participation (id, project_id, is_pi, is_extension, student_id)
    VALUES (gen_random_uuid(), p_pi, true, false, gen_random_uuid());
    RAISE EXCEPTION 'Constraint project_participation_user_fk falhou ao permitir aluno inexistente';
  EXCEPTION WHEN foreign_key_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO academic_pi.project_instructor (id, project_id, instructor_id)
    VALUES (gen_random_uuid(), p_pi, gen_random_uuid());
    RAISE EXCEPTION 'Constraint project_instructor_user_fk falhou ao permitir docente inexistente';
  EXCEPTION WHEN foreign_key_violation THEN NULL;
  END;

  -- Teste 5: docente valido e repeticao no mesmo projeto
  INSERT INTO academic_pi.project_instructor (id, project_id, instructor_id)
  VALUES (gen_random_uuid(), p_pi, v_instructor);

  BEGIN
    INSERT INTO academic_pi.project_instructor (id, project_id, instructor_id)
    VALUES (gen_random_uuid(), p_pi, v_instructor);
    RAISE EXCEPTION 'Constraint project_instructor_project_instructor_unq falhou ao permitir docente repetido';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  -- Teste 6: categorias da participacao divergentes do projeto
  BEGIN
    INSERT INTO academic_pi.project_participation (id, project_id, is_pi, is_extension, student_id)
    VALUES (gen_random_uuid(), p_pi, false, true, v_student_1);
    RAISE EXCEPTION 'FK composta falhou ao permitir categorias divergentes do projeto';
  EXCEPTION WHEN foreign_key_violation THEN NULL;
  END;

  -- Teste 7: limite de 1 PI + 1 Extensao por estudante
  INSERT INTO academic_pi.project_participation (id, project_id, is_pi, is_extension, student_id)
  VALUES (gen_random_uuid(), p_pi, true, false, v_student_1);

  BEGIN
    INSERT INTO academic_pi.project_participation (id, project_id, is_pi, is_extension, student_id)
    VALUES (gen_random_uuid(), p_pi_2, true, false, v_student_1);
    RAISE EXCEPTION 'Indice idx_project_participation_student_active_pi falhou ao permitir segundo PI ativo';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  INSERT INTO academic_pi.project_participation (id, project_id, is_pi, is_extension, student_id)
  VALUES (gen_random_uuid(), p_ext, false, true, v_student_1);

  BEGIN
    INSERT INTO academic_pi.project_participation (id, project_id, is_pi, is_extension, student_id)
    VALUES (gen_random_uuid(), p_dual, true, true, v_student_1);
    RAISE EXCEPTION 'Indices parciais falharam ao permitir projeto duplo com as duas vagas ocupadas';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  -- Teste 8: remocao exige justificativa
  BEGIN
    INSERT INTO academic_pi.project_participation (id, project_id, is_pi, is_extension, student_id, status)
    VALUES (gen_random_uuid(), p_pi_2, true, false, v_student_2, 'removed');
    RAISE EXCEPTION 'Constraint project_participation_justification_ck falhou ao permitir remocao sem justificativa';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  INSERT INTO academic_pi.project_participation (id, project_id, is_pi, is_extension, student_id, status, justification)
  VALUES (gen_random_uuid(), p_pi_2, true, false, v_student_2, 'removed', 'Motivo sintetico de validacao');

  -- Teste 9: ON DELETE RESTRICT protege projeto e usuario
  BEGIN
    DELETE FROM academic_pi.project WHERE id = p_pi;
    RAISE EXCEPTION 'ON DELETE RESTRICT falhou ao permitir apagar projeto com participacao';
  EXCEPTION WHEN foreign_key_violation THEN NULL;
  END;

  BEGIN
    DELETE FROM auth.user WHERE id = v_student_1;
    RAISE EXCEPTION 'ON DELETE RESTRICT falhou ao permitir apagar usuario com participacao';
  EXCEPTION WHEN foreign_key_violation THEN NULL;
  END;

  -- Limpeza dos registros de teste (filhos antes dos pais)
  DELETE FROM academic_pi.project_participation WHERE student_id IN (v_student_1, v_student_2);
  DELETE FROM academic_pi.project_instructor WHERE instructor_id = v_instructor;
  DELETE FROM academic_pi.project WHERE id IN (p_pi, p_pi_2, p_dual, p_ext);
  DELETE FROM auth.user WHERE id IN (v_student_1, v_student_2, v_instructor);
END $$;
EOF

echo "[validate] 27. Validando tabelas de metadados de arquivos (DB-011)..."
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT string_agg(table_name, ',' ORDER BY table_name) FROM information_schema.tables WHERE table_schema = 'assets' AND table_name IN ('file_lifecycle_state', 'project_file');" \
  | grep -qx 'file_lifecycle_state,project_file'

docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT string_agg(conname, ',' ORDER BY conname) FROM pg_constraint WHERE conrelid = 'assets.project_file'::regclass AND contype IN ('c', 'f', 'u');" \
  | grep -qx 'project_file_content_hash_ck,project_file_file_type_ck,project_file_hash_algorithm_ck,project_file_lifecycle_state_fk,project_file_owner_user_fk,project_file_project_fk,project_file_publication_authorizer_fk,project_file_publication_ck,project_file_storage_ref_ck,project_file_storage_ref_unq'

echo "[validate] 28. Validando que o binario nao e armazenado em assets.project_file (DB-011)..."
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT count(*) FROM information_schema.columns WHERE table_schema = 'assets' AND table_name = 'project_file' AND data_type = 'bytea';" \
  | grep -qx '0'

echo "[validate] 29. Validando regras funcionais de assets.project_file (DO block)..."
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" <<'EOF'
DO $$
DECLARE
  v_owner uuid := 'e0000000-0000-4000-8000-000000000001';
  v_docente uuid := 'e0000000-0000-4000-8000-000000000002';
  v_project uuid := 'e0000000-0000-4000-8000-000000000011';
  v_hash text := encode(sha256('synthetic-file-content'::bytea), 'hex');
  v_type text;
  v_n int := 0;
BEGIN
  INSERT INTO auth."user" (id, email, full_name, status)
  VALUES (v_owner, 'db011.owner@synthetic.local', 'Synthetic Owner', 'active'),
         (v_docente, 'db011.docente@synthetic.local', 'Synthetic Docente', 'active');

  INSERT INTO academic_pi.project (id, title, is_pi)
  VALUES (v_project, 'Synthetic DB-011 project', true);

  -- Estado de teste, existente apenas dentro deste bloco (valores reais dependem de Produto/Infra)
  INSERT INTO assets.file_lifecycle_state (code) VALUES ('synthetic_state');

  -- Teste 1: PDF, DOCX e imagem sao aceitos e o hash armazenado confere com o conteudo
  FOREACH v_type IN ARRAY ARRAY['pdf', 'docx', 'image'] LOOP
    v_n := v_n + 1;
    INSERT INTO assets.project_file (id, project_id, owner_user_id, file_type, content_hash, storage_ref, lifecycle_state)
    VALUES (('e0000000-0000-4000-8000-0000000001' || lpad(v_n::text, 2, '0'))::uuid, v_project, v_owner, v_type, v_hash, 'synthetic/' || v_type || '/' || v_n, 'synthetic_state');
  END LOOP;

  IF (SELECT count(*) FROM assets.project_file WHERE project_id = v_project AND content_hash = encode(sha256('synthetic-file-content'::bytea), 'hex')) <> 3 THEN
    RAISE EXCEPTION 'hash armazenado nao confere com o hash do conteudo';
  END IF;

  -- Publicacao nao e implicita
  IF (SELECT bool_or(publication_authorized) FROM assets.project_file WHERE project_id = v_project) THEN
    RAISE EXCEPTION 'publication_authorized deveria ser false por padrao';
  END IF;

  -- Teste 2: tipo fora da lista aprovada e rejeitado
  BEGIN
    INSERT INTO assets.project_file (id, project_id, owner_user_id, file_type, content_hash, storage_ref, lifecycle_state)
    VALUES ('e0000000-0000-4000-8000-000000000199', v_project, v_owner, 'exe', v_hash, 'synthetic/exe/1', 'synthetic_state');
    RAISE EXCEPTION 'project_file_file_type_ck falhou ao permitir tipo fora da lista';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- Teste 3: hash invalido (tamanho e caixa) e rejeitado
  BEGIN
    INSERT INTO assets.project_file (id, project_id, owner_user_id, file_type, content_hash, storage_ref, lifecycle_state)
    VALUES ('e0000000-0000-4000-8000-000000000198', v_project, v_owner, 'pdf', 'abc123', 'synthetic/hash/1', 'synthetic_state');
    RAISE EXCEPTION 'project_file_content_hash_ck falhou ao permitir hash curto';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO assets.project_file (id, project_id, owner_user_id, file_type, content_hash, storage_ref, lifecycle_state)
    VALUES ('e0000000-0000-4000-8000-000000000197', v_project, v_owner, 'pdf', upper(v_hash), 'synthetic/hash/2', 'synthetic_state');
    RAISE EXCEPTION 'project_file_content_hash_ck falhou ao permitir hash em maiusculas';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- Teste 4: referencia de armazenamento vazia e duplicada sao rejeitadas
  BEGIN
    INSERT INTO assets.project_file (id, project_id, owner_user_id, file_type, content_hash, storage_ref, lifecycle_state)
    VALUES ('e0000000-0000-4000-8000-000000000196', v_project, v_owner, 'pdf', v_hash, '   ', 'synthetic_state');
    RAISE EXCEPTION 'project_file_storage_ref_ck falhou ao permitir referencia vazia';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO assets.project_file (id, project_id, owner_user_id, file_type, content_hash, storage_ref, lifecycle_state)
    VALUES ('e0000000-0000-4000-8000-000000000195', v_project, v_owner, 'pdf', v_hash, 'synthetic/pdf/1', 'synthetic_state');
    RAISE EXCEPTION 'project_file_storage_ref_unq falhou ao permitir referencia duplicada';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  -- Teste 5: proprietario inexistente e rejeitado
  BEGIN
    INSERT INTO assets.project_file (id, project_id, owner_user_id, file_type, content_hash, storage_ref, lifecycle_state)
    VALUES ('e0000000-0000-4000-8000-000000000194', v_project, 'e0000000-0000-4000-8000-0000000009ff', 'pdf', v_hash, 'synthetic/owner/1', 'synthetic_state');
    RAISE EXCEPTION 'project_file_owner_user_fk falhou ao permitir proprietario inexistente';
  EXCEPTION WHEN foreign_key_violation THEN NULL;
  END;

  -- Teste 6: referencia orfa (projeto ou lifecycle inexistente) e rejeitada
  BEGIN
    INSERT INTO assets.project_file (id, project_id, owner_user_id, file_type, content_hash, storage_ref, lifecycle_state)
    VALUES ('e0000000-0000-4000-8000-000000000193', 'e0000000-0000-4000-8000-0000000009fe', v_owner, 'pdf', v_hash, 'synthetic/project/1', 'synthetic_state');
    RAISE EXCEPTION 'project_file_project_fk falhou ao permitir projeto inexistente';
  EXCEPTION WHEN foreign_key_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO assets.project_file (id, project_id, owner_user_id, file_type, content_hash, storage_ref, lifecycle_state)
    VALUES ('e0000000-0000-4000-8000-000000000192', v_project, v_owner, 'pdf', v_hash, 'synthetic/state/1', 'estado_inexistente');
    RAISE EXCEPTION 'project_file_lifecycle_state_fk falhou ao permitir lifecycle inexistente';
  EXCEPTION WHEN foreign_key_violation THEN NULL;
  END;

  -- Teste 7: publicacao sem autorizador e rejeitada; com autorizador e aceita
  BEGIN
    INSERT INTO assets.project_file (id, project_id, owner_user_id, file_type, content_hash, storage_ref, lifecycle_state, publication_authorized)
    VALUES ('e0000000-0000-4000-8000-000000000191', v_project, v_owner, 'image', v_hash, 'synthetic/pub/1', 'synthetic_state', true);
    RAISE EXCEPTION 'project_file_publication_ck falhou ao permitir publicacao sem autorizador';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  INSERT INTO assets.project_file (id, project_id, owner_user_id, file_type, content_hash, storage_ref, lifecycle_state, publication_authorized, publication_authorized_by)
  VALUES ('e0000000-0000-4000-8000-000000000190', v_project, v_owner, 'image', v_hash, 'synthetic/pub/2', 'synthetic_state', true, v_docente);

  -- Teste 8: usuario proprietario com arquivos nao pode ser removido (sem orfaos)
  BEGIN
    DELETE FROM auth."user" WHERE id = v_owner;
    RAISE EXCEPTION 'ON DELETE RESTRICT falhou ao permitir remover proprietario com arquivos';
  EXCEPTION WHEN foreign_key_violation THEN NULL;
  END;

  -- Limpeza dos dados sinteticos do teste
  DELETE FROM assets.project_file WHERE project_id = v_project;
  DELETE FROM assets.file_lifecycle_state WHERE code = 'synthetic_state';
  DELETE FROM academic_pi.project WHERE id = v_project;
  DELETE FROM auth."user" WHERE id IN (v_owner, v_docente);
END $$;
EOF

echo "[validate] 30. Validando que a validacao nao deixou dados residuais em assets (DB-011)..."
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT (SELECT count(*) FROM assets.project_file) || ',' || (SELECT count(*) FROM assets.file_lifecycle_state);" \
  | grep -qx '0,0'

echo "[validate] Todas as validacoes de compatibilidade, integridade, constraints e seeds concluidas com sucesso!"
echo "[validate] Todas as validacoes de compatibilidade, integridade, constraints e seeds concluidas com sucesso!"
