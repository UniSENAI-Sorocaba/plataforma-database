-- DB-012: evidencia de janela, status e unicidade (periodo de inscricao e inscricao/participacao)
-- Tudo roda dentro de uma transacao que termina em ROLLBACK: o banco fica limpo.
-- Uso: docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U plataforma -d plataforma < DB-012-evidence-tests.sql

BEGIN;

DO $$
DECLARE
  u1 uuid := 'fc000000-0000-4000-8000-0000000000a1';
  u2 uuid := 'fc000000-0000-4000-8000-0000000000a2';
  p_pi1 uuid := 'fc000000-0000-4000-8000-000000000001';
  p_pi2 uuid := 'fc000000-0000-4000-8000-000000000002';
  p_ext uuid := 'fc000000-0000-4000-8000-000000000003';
  p_dual uuid := 'fc000000-0000-4000-8000-000000000004';
  per_ok uuid := 'fc000000-0000-4000-8000-0000000000b1';
  per_zero uuid := 'fc000000-0000-4000-8000-0000000000b2';
  per_past uuid := 'fc000000-0000-4000-8000-0000000000b3';
  per_now uuid := 'fc000000-0000-4000-8000-0000000000b4';
  v_open timestamptz;
  v_close timestamptz;
  v_status text;
BEGIN
  -- Dados sinteticos de apoio
  INSERT INTO auth."user" (id, email, full_name, status) VALUES
    (u1, 'db012.student1@synthetic.local', 'DB012 Student One', 'active'),
    (u2, 'db012.student2@synthetic.local', 'DB012 Student Two', 'active');

  INSERT INTO academic_pi.project (id, title, is_pi, is_extension) VALUES
    (p_pi1, 'DB012 PI 1', true, false),
    (p_pi2, 'DB012 PI 2', true, false),
    (p_ext, 'DB012 Extension', false, true),
    (p_dual, 'DB012 Dual', true, true);

  ---------------------------------------------------------------
  -- JANELA
  ---------------------------------------------------------------
  -- J01: periodo valido; datas guardadas em timestamptz (UTC), exibidas em UTC-3
  INSERT INTO academic_pi.enrollment_period (id, project_id, opens_at, closes_at)
  VALUES (per_ok, p_pi1, '2026-03-01 08:00:00-03', '2026-03-15 18:00:00-03');
  SELECT opens_at, closes_at INTO v_open, v_close FROM academic_pi.enrollment_period WHERE id = per_ok;
  RAISE NOTICE 'J01 OK periodo valido aceito. opens_at em UTC: % | em Brasilia (UTC-3): %',
    v_open AT TIME ZONE 'UTC', v_open AT TIME ZONE 'America/Sao_Paulo';

  -- J02: fechamento anterior a abertura e rejeitado
  BEGIN
    INSERT INTO academic_pi.enrollment_period (id, project_id, opens_at, closes_at)
    VALUES (gen_random_uuid(), p_pi1, '2026-04-10 08:00:00-03', '2026-04-01 08:00:00-03');
    RAISE EXCEPTION 'J02 FALHOU: janela invertida foi aceita';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'J02 OK janela invertida rejeitada: %', SQLERRM;
  END;

  -- J03: janela de duracao zero (closes_at = opens_at) e aceita pelo banco hoje (check usa >=)
  INSERT INTO academic_pi.enrollment_period (id, project_id, opens_at, closes_at)
  VALUES (per_zero, p_pi1, '2026-05-01 08:00:00-03', '2026-05-01 08:00:00-03');
  RAISE NOTICE 'J03 INFO janela de duracao zero aceita (check closes_at >= opens_at)';

  -- J04: datas podem ser alteradas (o banco nao impoe prazo nao prorrogavel nem libera ajuste por regra propria)
  UPDATE academic_pi.enrollment_period SET closes_at = closes_at + interval '7 days' WHERE id = per_ok;
  RAISE NOTICE 'J04 OK alteracao de data de fechamento aceita pelo banco (R61/R62 ficam fora do banco)';

  -- J05: mesmo alterando, a janela continua coerente
  BEGIN
    UPDATE academic_pi.enrollment_period SET closes_at = opens_at - interval '1 day' WHERE id = per_ok;
    RAISE EXCEPTION 'J05 FALHOU: alteracao que inverte a janela foi aceita';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'J05 OK alteracao que inverte a janela rejeitada: %', SQLERRM;
  END;

  ---------------------------------------------------------------
  -- STATUS
  ---------------------------------------------------------------
  -- S01: status do periodo e derivado das datas (nao ha coluna de status no periodo)
  INSERT INTO academic_pi.enrollment_period (id, project_id, opens_at, closes_at) VALUES
    (per_past, p_pi2, now() - interval '30 days', now() - interval '1 day'),
    (per_now,  p_pi2, now() - interval '1 day',   now() + interval '5 days');
  FOR v_status IN
    SELECT CASE WHEN now() < opens_at THEN 'futuro' WHEN now() <= closes_at THEN 'aberto' ELSE 'encerrado' END
    FROM academic_pi.enrollment_period WHERE id IN (per_past, per_now) ORDER BY opens_at
  LOOP
    RAISE NOTICE 'S01 INFO status derivado das datas: %', v_status;
  END LOOP;

  -- S02: inscricao nasce como requested; docente aprova com decided_at
  INSERT INTO academic_pi.project_participation (id, project_id, is_pi, is_extension, student_id)
  VALUES (gen_random_uuid(), p_pi1, true, false, u1);
  SELECT status INTO v_status FROM academic_pi.project_participation WHERE project_id = p_pi1 AND student_id = u1;
  RAISE NOTICE 'S02 OK inscricao criada com status padrao: %', v_status;

  UPDATE academic_pi.project_participation SET status = 'approved', decided_at = now()
  WHERE project_id = p_pi1 AND student_id = u1;
  SELECT status INTO v_status FROM academic_pi.project_participation WHERE project_id = p_pi1 AND student_id = u1;
  RAISE NOTICE 'S03 OK aprovacao persistida: %', v_status;

  -- S04: recusa e desistencia persistem (nao ocupam vaga do limite)
  INSERT INTO academic_pi.project_participation (id, project_id, is_pi, is_extension, student_id, status, decided_at)
  VALUES (gen_random_uuid(), p_pi1, true, false, u2, 'denied', now());
  INSERT INTO academic_pi.project_participation (id, project_id, is_pi, is_extension, student_id, status)
  VALUES (gen_random_uuid(), p_pi2, true, false, u2, 'withdrawn');
  RAISE NOTICE 'S04 OK recusa (denied) e desistencia (withdrawn) persistidas';

  -- S05: status fora do dominio e rejeitado (nao existe status de convite)
  BEGIN
    INSERT INTO academic_pi.project_participation (id, project_id, is_pi, is_extension, student_id, status)
    VALUES (gen_random_uuid(), p_ext, false, true, u2, 'invited');
    RAISE EXCEPTION 'S05 FALHOU: status invited foi aceito';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'S05 OK status fora do dominio rejeitado: %', SQLERRM;
  END;

  ---------------------------------------------------------------
  -- UNICIDADE
  ---------------------------------------------------------------
  -- U01: mesma inscricao repetida (mesmo aluno e projeto)
  BEGIN
    INSERT INTO academic_pi.project_participation (id, project_id, is_pi, is_extension, student_id)
    VALUES (gen_random_uuid(), p_pi1, true, false, u1);
    RAISE EXCEPTION 'U01 FALHOU: inscricao duplicada foi aceita';
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'U01 OK inscricao duplicada rejeitada: %', SQLERRM;
  END;

  -- U02: segundo PI ativo para o mesmo aluno
  BEGIN
    INSERT INTO academic_pi.project_participation (id, project_id, is_pi, is_extension, student_id)
    VALUES (gen_random_uuid(), p_pi2, true, false, u1);
    RAISE EXCEPTION 'U02 FALHOU: segundo PI ativo foi aceito';
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'U02 OK segundo PI ativo rejeitado: %', SQLERRM;
  END;

  -- U03: um PI e uma Extensao por vez e permitido
  INSERT INTO academic_pi.project_participation (id, project_id, is_pi, is_extension, student_id)
  VALUES (gen_random_uuid(), p_ext, false, true, u1);
  RAISE NOTICE 'U03 OK 1 PI + 1 Extensao permitido';

  -- U04: projeto nas duas categorias nao cabe com as duas vagas ocupadas
  BEGIN
    INSERT INTO academic_pi.project_participation (id, project_id, is_pi, is_extension, student_id)
    VALUES (gen_random_uuid(), p_dual, true, true, u1);
    RAISE EXCEPTION 'U04 FALHOU: projeto duplo foi aceito com as duas vagas ocupadas';
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'U04 OK projeto PI+Extensao rejeitado com as duas vagas ocupadas: %', SQLERRM;
  END;

  RAISE NOTICE 'DB-012: todos os cenarios concluidos';
END $$;

ROLLBACK;