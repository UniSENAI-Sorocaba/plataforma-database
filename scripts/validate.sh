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
  "SELECT string_agg(version, ',' ORDER BY version) FROM public.schema_migration WHERE version IN ('V0001', 'V0002', 'V0003');" \
  | grep -qx 'V0001,V0002,V0003'

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

echo "[validate] 18. Validando tabelas de sessao e recuperacao (DB-005)..."
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT string_agg(table_name, ',' ORDER BY table_name) FROM information_schema.tables WHERE table_schema = 'auth' AND table_name IN ('password_recovery_token', 'refresh_token', 'session');" \
  | grep -qx 'password_recovery_token,refresh_token,session'

echo "[validate] 19. Validando indices de expiracao e consulta por sessao/familia..."
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT string_agg(indexname, ',' ORDER BY indexname) FROM pg_indexes WHERE schemaname = 'auth' AND indexname IN ('idx_password_recovery_expiration','idx_password_recovery_user','idx_refresh_token_expiration','idx_refresh_token_family','idx_refresh_token_session','idx_session_expiration','idx_session_family_id','idx_session_user_status');" \
  | grep -qx 'idx_password_recovery_expiration,idx_password_recovery_user,idx_refresh_token_expiration,idx_refresh_token_family,idx_refresh_token_session,idx_session_expiration,idx_session_family_id,idx_session_user_status'

echo "[validate] 20. Validando comportamento de rotacao, revogacao e uso unico..."
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" <<'EOF'
DO $$
DECLARE
  v_user_id uuid := 'f0000000-0000-4000-8000-000000000001';
  v_session_id uuid := 'f0000000-0000-4000-8000-000000000041';
  v_family_id uuid := 'f0000000-0000-4000-8000-000000000042';
  v_refresh_id uuid := 'f0000000-0000-4000-8000-000000000043';
  v_recovery_id uuid := 'f0000000-0000-4000-8000-000000000044';
  v_now timestamptz := '2026-01-01T10:00:00Z';
BEGIN
  INSERT INTO auth.user (id, email, full_name, status)
  VALUES (v_user_id, 'session.test@synthetic.local', 'Session Test User', 'active');

  INSERT INTO auth.session (id, user_id, family_id, created_at, expires_at)
  VALUES (v_session_id, v_user_id, v_family_id, v_now, v_now + interval '30 days');

  INSERT INTO auth.refresh_token (id, session_id, family_id, token_hash, issued_at, expires_at)
  VALUES (v_refresh_id, v_session_id, v_family_id, repeat('a', 64), v_now, v_now + interval '30 days');

  UPDATE auth.refresh_token
     SET used_at = v_now + interval '1 minute'
   WHERE id = v_refresh_id;

  UPDATE auth.session
     SET status = 'revoked', revoked_at = v_now + interval '1 minute', revoked_reason = 'reuse'
   WHERE id = v_session_id;

  INSERT INTO auth.password_recovery_token (id, user_id, token_hash, created_at, expires_at)
  VALUES (v_recovery_id, v_user_id, repeat('b', 64), v_now, v_now + interval '15 minutes');

  UPDATE auth.password_recovery_token
     SET used_at = v_now + interval '2 minutes'
   WHERE id = v_recovery_id;

  IF (SELECT status FROM auth.session WHERE id = v_session_id) <> 'revoked'
     OR (SELECT used_at IS NOT NULL FROM auth.refresh_token WHERE id = v_refresh_id) IS NOT TRUE
     OR (SELECT used_at IS NOT NULL FROM auth.password_recovery_token WHERE id = v_recovery_id) IS NOT TRUE THEN
    RAISE EXCEPTION 'Lifecycle DB-005 nao foi persistido corretamente';
  END IF;

  DELETE FROM auth.password_recovery_token WHERE id = v_recovery_id;
  DELETE FROM auth.refresh_token WHERE id = v_refresh_id;
  DELETE FROM auth.session WHERE id = v_session_id;
  DELETE FROM auth.user WHERE id = v_user_id;
END $$;
EOF

echo "[validate] 21. Validando modelo RBAC, escopos e integridade (DB-006)..."
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT string_agg(table_name, ',' ORDER BY table_name) FROM information_schema.tables WHERE table_schema = 'public' AND table_name IN ('permissions', 'role_permissions', 'roles', 'user_roles');" \
  | grep -qx 'permissions,role_permissions,roles,user_roles'

docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT count(*) FROM public.schema_migration WHERE version = 'V0006';" | grep -qx '1'

docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT string_agg(conname, ',' ORDER BY conname) FROM pg_constraint WHERE conrelid IN ('public.roles'::regclass, 'public.permissions'::regclass, 'public.user_roles'::regclass) AND contype = 'c';" \
  | grep -qx 'permissions_action_ck,permissions_resource_ck,roles_name_ck,user_roles_scope_consistency_ck,user_roles_scope_id_ck,user_roles_scope_type_ck'

docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT (count(*) >= 3)::text || ',' || (SELECT (count(*) >= 7)::text FROM public.permissions) || ',' || (SELECT (count(*) >= 7)::text FROM public.user_roles) FROM public.roles;" \
  | grep -qx 'true,true,true'

echo "[validate] 22. Validando modelo de projetos e participacao (DB-008)..."
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT string_agg(table_name, ',' ORDER BY table_name) FROM information_schema.tables WHERE table_schema = 'academic_pi' AND table_name IN ('enrollment_period', 'participation_request', 'project', 'project_participant', 'project_responsible');" \
  | grep -qx 'enrollment_period,participation_request,project,project_participant,project_responsible'

docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT count(*) FROM public.schema_migration WHERE version = 'V0008';" | grep -qx '1'

docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" <<'EOF'
DO $$
DECLARE
  v_teacher uuid := 'f0000000-0000-4000-8000-000000000001';
  v_student uuid := 'f0000000-0000-4000-8000-000000000002';
  v_project uuid := 'f0000000-0000-4000-8000-000000000051';
  v_project_2 uuid := 'f0000000-0000-4000-8000-000000000052';
  v_period uuid := 'f0000000-0000-4000-8000-000000000053';
  v_period_2 uuid := 'f0000000-0000-4000-8000-000000000054';
  v_request uuid := 'f0000000-0000-4000-8000-000000000055';
BEGIN
  INSERT INTO auth."user" (id, email, full_name, status)
  VALUES (v_teacher, 'project.teacher@synthetic.local', 'Project Teacher', 'active'),
         (v_student, 'project.student@synthetic.local', 'Project Student', 'active');

  INSERT INTO academic_pi.project (id, title, summary, description, classification, continuity, publication_status, created_by)
  VALUES (v_project, 'Projeto de Teste', 'Resumo do projeto de teste', repeat('Descricao do projeto de teste. ', 3), 'PI', 'CONTINUOUS', 'PUBLISHED', v_teacher),
         (v_project_2, 'Projeto de Teste Dois', 'Resumo do projeto de teste dois', repeat('Descricao do segundo projeto de teste. ', 3), 'PI', 'CONTINUOUS', 'PUBLISHED', v_teacher);

  INSERT INTO academic_pi.project_responsible (project_id, user_id)
  VALUES (v_project, v_teacher), (v_project_2, v_teacher);

  INSERT INTO academic_pi.enrollment_period (id, project_id, academic_term, starts_at, ends_at, created_by)
  VALUES (v_period, v_project, '2026.2', '2026-01-01T00:00:00Z', '2026-12-31T00:00:00Z', v_teacher),
         (v_period_2, v_project_2, '2026.2', '2026-01-01T00:00:00Z', '2026-12-31T00:00:00Z', v_teacher);

  INSERT INTO academic_pi.participation_request (id, project_id, period_id, student_id, status, decided_at, decided_by)
  VALUES (v_request, v_project, v_period, v_student, 'APPROVED', now(), v_teacher);

  INSERT INTO academic_pi.project_participant (project_id, period_id, student_id)
  VALUES (v_project, v_period, v_student);

  BEGIN
    INSERT INTO academic_pi.project_participant (project_id, period_id, student_id)
    VALUES (v_project_2, v_period_2, v_student);
    RAISE EXCEPTION 'DB-008 permitiu exceder limite de PI';
  EXCEPTION WHEN unique_violation THEN
    NULL;
  END;

  DELETE FROM academic_pi.project_participant WHERE project_id = v_project AND period_id = v_period AND student_id = v_student;
  DELETE FROM academic_pi.participation_request WHERE id = v_request;
  DELETE FROM academic_pi.enrollment_period WHERE id IN (v_period, v_period_2);
  ALTER TABLE academic_pi.project_responsible DISABLE TRIGGER project_responsible_minimum_trigger;
  DELETE FROM academic_pi.project WHERE id IN (v_project, v_project_2);
  ALTER TABLE academic_pi.project_responsible ENABLE TRIGGER project_responsible_minimum_trigger;
  DELETE FROM auth."user" WHERE id IN (v_teacher, v_student);
END $$;
EOF

echo "[validate] Todas as validacoes de compatibilidade, integridade, constraints e seeds concluidas com sucesso!"
