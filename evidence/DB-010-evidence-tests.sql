-- DB-010: evidencia de persistencia de criterios/rubricas e avaliacoes de PI sem cristalizar regras pendentes
-- Tudo roda dentro de uma transacao que termina em ROLLBACK: o banco fica limpo.
-- Uso: docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U plataforma -d plataforma < evidence/DB-010-evidence-tests.sql

BEGIN;

DO $$
DECLARE
  v_instructor uuid := 'fb100000-0000-4000-8000-000000000001';
  v_other_user uuid := 'fb100000-0000-4000-8000-000000000002';
  v_coord uuid := 'fb100000-0000-4000-8000-000000000003';
  v_peer_1 uuid := 'fb100000-0000-4000-8000-000000000004';
  v_peer_2 uuid := 'fb100000-0000-4000-8000-000000000005';
  v_evaluated uuid := 'fb100000-0000-4000-8000-000000000006';
  v_outsider uuid := 'fb100000-0000-4000-8000-000000000007';

  v_proj_pi uuid := 'fb100000-0000-4000-8000-000000000101';
  v_proj_pi_2 uuid := 'fb100000-0000-4000-8000-000000000102';

  v_crit_1 uuid := 'fb100000-0000-4000-8000-000000000201';
  v_crit_2 uuid := 'fb100000-0000-4000-8000-000000000202';
  v_crit_other uuid := 'fb100000-0000-4000-8000-000000000203';

  v_eval_peer_1 uuid := 'fb100000-0000-4000-8000-000000000301';
  v_eval_peer_2 uuid := 'fb100000-0000-4000-8000-000000000302';
  v_eval_inst uuid := 'fb100000-0000-4000-8000-000000000303';

  v_score_1 uuid := 'fb100000-0000-4000-8000-000000000401';
  v_score_2 uuid := 'fb100000-0000-4000-8000-000000000402';
  v_current_score numeric;
  v_row_count bigint;
BEGIN
  -- Dados sinteticos de apoio
  INSERT INTO auth."user" (id, email, full_name, status) VALUES
    (v_instructor, 'db010.ev.instructor@synthetic.local', 'DB010 Evidence Instructor', 'active'),
    (v_other_user, 'db010.ev.other@synthetic.local', 'DB010 Evidence Other User', 'active'),
    (v_coord, 'db010.ev.coord@synthetic.local', 'DB010 Evidence Coordinator', 'active'),
    (v_peer_1, 'db010.ev.peer1@synthetic.local', 'DB010 Evidence Peer One', 'active'),
    (v_peer_2, 'db010.ev.peer2@synthetic.local', 'DB010 Evidence Peer Two', 'active'),
    (v_evaluated, 'db010.ev.evaluated@synthetic.local', 'DB010 Evidence Evaluated Student', 'active'),
    (v_outsider, 'db010.ev.outsider@synthetic.local', 'DB010 Evidence Outsider Student', 'active');

  INSERT INTO academic_pi.project (id, title, is_pi, is_extension, status) VALUES
    (v_proj_pi, 'DB010 PI Project 1', true, false, 'published'),
    (v_proj_pi_2, 'DB010 PI Project 2', true, false, 'published');

  INSERT INTO academic_pi.project_instructor (id, project_id, instructor_id) VALUES
    ('fb100000-0000-4000-8000-000000000501', v_proj_pi, v_instructor),
    ('fb100000-0000-4000-8000-000000000502', v_proj_pi_2, v_other_user);

  INSERT INTO academic_pi.project_participation (id, project_id, is_pi, is_extension, student_id, status) VALUES
    ('fb100000-0000-4000-8000-000000000601', v_proj_pi, true, false, v_evaluated, 'approved');

  -------------------------------------------------------------------
  -- CRITERIOS E PESOS (DOCENTE RESPONSAVEL)
  -------------------------------------------------------------------
  -- C01: Docente responsavel salva criterios e pesos (sem exigir soma 100 nem arredondamento prematuro)
  INSERT INTO academic_pi.evaluation_criterion (id, project_id, defined_by_instructor_id, name, weight) VALUES
    (v_crit_1, v_proj_pi, v_instructor, 'Implementacao e Arquitetura', 2.75),
    (v_crit_2, v_proj_pi, v_instructor, 'Validacao e Documentacao', 1.25),
    (v_crit_other, v_proj_pi_2, v_other_user, 'Criterio de Outro Projeto', 5);
  RAISE NOTICE 'C01 OK criterios e pesos definidos pelo docente responsavel (pesos: 2.75 e 1.25; soma = 4.00)';

  -- C02: Usuario nao responsavel pelo projeto e bloqueado ao criar criterio
  BEGIN
    INSERT INTO academic_pi.evaluation_criterion (id, project_id, defined_by_instructor_id, name, weight)
    VALUES (gen_random_uuid(), v_proj_pi, v_other_user, 'Criterio Indevido', 1);
    RAISE EXCEPTION 'C02 FALHOU: usuario nao responsavel conseguiu criar criterio';
  EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE 'C02 OK criacao de criterio por usuario nao responsavel bloqueada: %', SQLERRM;
  END;

  -- C03: Criterio com nome vazio, duplicado ou peso nao positivo e bloqueado
  BEGIN
    INSERT INTO academic_pi.evaluation_criterion (id, project_id, defined_by_instructor_id, name, weight)
    VALUES (gen_random_uuid(), v_proj_pi, v_instructor, '   ', 1);
    RAISE EXCEPTION 'C03 FALHOU: criterio com nome vazio aceito';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'C03 OK criterio com nome vazio rejeitado: %', SQLERRM;
  END;

  BEGIN
    INSERT INTO academic_pi.evaluation_criterion (id, project_id, defined_by_instructor_id, name, weight)
    VALUES (gen_random_uuid(), v_proj_pi, v_instructor, 'Peso Invalido', 0);
    RAISE EXCEPTION 'C04 FALHOU: criterio com peso <= 0 aceito';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'C04 OK criterio com peso <= 0 rejeitado: %', SQLERRM;
  END;

  -------------------------------------------------------------------
  -- AVALIACOES INDIVIDUAIS E ATRIBUICAO PELA COORDENACAO (DB-009 / DB-010)
  -------------------------------------------------------------------
  -- A01: Coordenacao atribui alunos avaliadores, projeto e data; quantidade variavel de avaliacoes
  INSERT INTO academic_pi.project_evaluation (id, project_id, evaluator_user_id, evaluated_student_id, assigned_by_user_id, evaluation_date) VALUES
    (v_eval_peer_1, v_proj_pi, v_peer_1, v_evaluated, v_coord, DATE '2026-11-20'),
    (v_eval_peer_2, v_proj_pi, v_peer_2, v_evaluated, v_coord, DATE '2026-11-21'),
    (v_eval_inst, v_proj_pi, v_instructor, v_evaluated, NULL, NULL);
  RAISE NOTICE 'A01 OK 3 avaliacoes vinculadas ao projeto, avaliadores e aluno participante (2 atribuidas pela coordenacao com data)';

  -- A02: Atribuicao pela coordenacao sem data e rejeitada
  BEGIN
    INSERT INTO academic_pi.project_evaluation (id, project_id, evaluator_user_id, evaluated_student_id, assigned_by_user_id, evaluation_date)
    VALUES (gen_random_uuid(), v_proj_pi, v_other_user, v_evaluated, v_coord, NULL);
    RAISE EXCEPTION 'A02 FALHOU: atribuicao sem data foi aceita';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'A02 OK atribuicao sem evaluation_date rejeitada: %', SQLERRM;
  END;

  -- A03: Aluno avaliado que nao pertence ao projeto e rejeitado
  BEGIN
    INSERT INTO academic_pi.project_evaluation (id, project_id, evaluator_user_id, evaluated_student_id)
    VALUES (gen_random_uuid(), v_proj_pi, v_instructor, v_outsider);
    RAISE EXCEPTION 'A03 FALHOU: avaliado fora do projeto foi aceito';
  EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE 'A03 OK avaliado nao participante do projeto rejeitado: %', SQLERRM;
  END;

  -------------------------------------------------------------------
  -- FINALIZACAO, REABERTURA E CORRECAO SEM HISTORICO
  -------------------------------------------------------------------
  -- N01: Lancamento de notas vigentes por criterio (sem impor constraint de escala nao validada)
  INSERT INTO academic_pi.evaluation_criterion_score (id, evaluation_id, project_id, criterion_id, score, feedback) VALUES
    (v_score_1, v_eval_peer_1, v_proj_pi, v_crit_1, 78.5, 'Nota inicial criterio 1'),
    (v_score_2, v_eval_peer_1, v_proj_pi, v_crit_2, 88, 'Nota inicial criterio 2');
  RAISE NOTICE 'N01 OK notas vigentes registradas por criterio (78.5 e 88)';

  -- N02: Criterio de outro projeto nao pode receber nota na avaliacao
  BEGIN
    INSERT INTO academic_pi.evaluation_criterion_score (id, evaluation_id, project_id, criterion_id, score)
    VALUES (gen_random_uuid(), v_eval_peer_1, v_proj_pi, v_crit_other, 90);
    RAISE EXCEPTION 'N02 FALHOU: criterio de outro projeto foi aceito';
  EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE 'N02 OK criterio de outro projeto rejeitado na avaliacao: %', SQLERRM;
  END;

  -- N03: Usuario nao responsavel nao finaliza, reabre nem corrige avaliacao
  BEGIN
    UPDATE academic_pi.project_evaluation
    SET finalized_at = now(), finalized_by_instructor_id = v_other_user
    WHERE id = v_eval_peer_1;
    RAISE EXCEPTION 'N03 FALHOU: usuario nao responsavel finalizou avaliacao';
  EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE 'N03 OK tentativa de finalizacao por nao responsavel bloqueada: %', SQLERRM;
  END;

  -- N04: Docente responsavel finaliza, reabre e corrige nota substituindo valor vigente sem historico
  UPDATE academic_pi.project_evaluation
  SET finalized_at = now(), finalized_by_instructor_id = v_instructor, updated_at = now()
  WHERE id = v_eval_peer_1;

  UPDATE academic_pi.project_evaluation
  SET reopened_at = now(), reopened_by_instructor_id = v_instructor, updated_at = now()
  WHERE id = v_eval_peer_1;

  UPDATE academic_pi.evaluation_criterion_score
  SET score = 94.25,
      feedback = 'Corrigido pelo docente responsavel',
      last_corrected_by_instructor_id = v_instructor,
      last_corrected_at = now(),
      updated_at = now()
  WHERE id = v_score_1;

  UPDATE academic_pi.project_evaluation
  SET corrected_at = now(), corrected_by_instructor_id = v_instructor, updated_at = now()
  WHERE id = v_eval_peer_1;

  SELECT count(*), max(score) INTO v_row_count, v_current_score
  FROM academic_pi.evaluation_criterion_score
  WHERE evaluation_id = v_eval_peer_1 AND criterion_id = v_crit_1;

  RAISE NOTICE 'N04 OK correcao pelo docente responsavel substituiu o valor vigente sem historico (linhas=% | valor_atual=%)',
    v_row_count, v_current_score;

  RAISE NOTICE 'DB-010: todos os cenarios concluidos com sucesso';
END $$;

ROLLBACK;
