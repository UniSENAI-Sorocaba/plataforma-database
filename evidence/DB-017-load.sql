-- DB-017: carga sintetica deterministica para medicao de consultas (sem random(), sem PII).
-- Uso (exemplo de volume pequeno):
--   docker compose exec -T postgres psql -v ON_ERROR_STOP=1 \
--     -v n_students=5000 -v n_projects=600 -v n_instr=100 \
--     -U plataforma -d plataforma < evidence/DB-017-load.sql
-- Requisitos: n_projects multiplo de 3 e >= 6; n_instr par e >= 2.
-- Para apagar tudo depois: docker compose down -v (o banco e descartavel).
-- IDs: usuarios e1..., projetos e2..., docentes e3..., periodos e4..., participacoes e5...

BEGIN;

-- Usuarios: 1..n_students sao alunos; n_students+1..n_students+n_instr sao docentes
INSERT INTO auth."user" (id, email, full_name, status)
SELECT ('e1000000-0000-4000-8000-' || lpad(g::text, 12, '0'))::uuid,
       'db017.u' || g || '@synthetic.local',
       'DB017 User ' || g,
       'active'
FROM generate_series(1, :n_students + :n_instr) AS g;

-- Projetos: g%3=1 so PI, g%3=0 so Extensao, g%3=2 nas duas categorias
-- status: 60% published, 25% draft, 15% archived; 10% marcados como publicos
INSERT INTO academic_pi.project (id, title, is_pi, is_extension, status, is_public)
SELECT ('e2000000-0000-4000-8000-' || lpad(g::text, 12, '0'))::uuid,
       'DB017 Project ' || g,
       (g % 3 IN (1, 2)),
       (g % 3 IN (0, 2)),
       CASE WHEN g % 20 < 12 THEN 'published' WHEN g % 20 < 17 THEN 'draft' ELSE 'archived' END,
       (g % 10 = 0)
FROM generate_series(1, :n_projects) AS g;

-- Docentes: 1 por projeto, mais um segundo nos projetos pares
INSERT INTO academic_pi.project_instructor (id, project_id, instructor_id)
SELECT ('e3000000-0000-4000-8000-' || lpad((row_number() OVER (ORDER BY g, k))::text, 12, '0'))::uuid,
       ('e2000000-0000-4000-8000-' || lpad(g::text, 12, '0'))::uuid,
       ('e1000000-0000-4000-8000-' || lpad((:n_students + k)::text, 12, '0'))::uuid
FROM (
  SELECT g, ((g - 1) % :n_instr) + 1 AS k
  FROM generate_series(1, :n_projects) AS g
  UNION ALL
  SELECT g, ((g - 1 + :n_instr / 2) % :n_instr) + 1
  FROM generate_series(1, :n_projects) AS g
  WHERE g % 2 = 0
) t;

-- Periodos de inscricao: um encerrado (fev/2026) e outro por projeto.
-- Aberto em 2026-11-20 para g%4=0; futuro (2027) para os demais.
INSERT INTO academic_pi.enrollment_period (id, project_id, opens_at, closes_at)
SELECT ('e4000000-0000-4000-8000-' || lpad((row_number() OVER (ORDER BY g, n))::text, 12, '0'))::uuid,
       ('e2000000-0000-4000-8000-' || lpad(g::text, 12, '0'))::uuid,
       o, c
FROM (
  SELECT g, 1 AS n,
         '2026-02-01 00:00:00-03'::timestamptz AS o,
         '2026-02-28 23:59:59-03'::timestamptz AS c
  FROM generate_series(1, :n_projects) AS g
  UNION ALL
  SELECT g, 2,
         CASE WHEN g % 4 = 0 THEN '2026-11-01 00:00:00-03'::timestamptz ELSE '2027-02-01 00:00:00-03'::timestamptz END,
         CASE WHEN g % 4 = 0 THEN '2026-12-15 23:59:59-03'::timestamptz ELSE '2027-02-28 23:59:59-03'::timestamptz END
  FROM generate_series(1, :n_projects) AS g
) t;

-- Participacoes: por aluno, 1 PI ativo (20% ainda 'requested'), 1 Extensao ativa e 1 PI recusado.
-- Respeita o limite de 1 PI + 1 Extensao ativos e a unicidade (projeto, aluno).
INSERT INTO academic_pi.project_participation
  (id, project_id, is_pi, is_extension, student_id, status, decided_at)
SELECT ('e5000000-0000-4000-8000-' || lpad((s * 3 + k)::text, 12, '0'))::uuid,
       ('e2000000-0000-4000-8000-' || lpad(p::text, 12, '0'))::uuid,
       flag_pi, flag_ext,
       ('e1000000-0000-4000-8000-' || lpad(s::text, 12, '0'))::uuid,
       st, decided
FROM (
  SELECT s, 1 AS k,
         3 * ((s - 1) % (:n_projects / 3)) + 1 AS p,
         true AS flag_pi, false AS flag_ext,
         CASE WHEN s % 5 = 0 THEN 'requested' ELSE 'approved' END AS st,
         CASE WHEN s % 5 = 0 THEN NULL ELSE '2026-02-10 12:00:00-03'::timestamptz END AS decided
  FROM generate_series(1, :n_students) AS s
  UNION ALL
  SELECT s, 2,
         3 * ((s * 7) % (:n_projects / 3)) + 3,
         false, true,
         'approved',
         '2026-02-10 12:00:00-03'::timestamptz
  FROM generate_series(1, :n_students) AS s
  UNION ALL
  SELECT s, 3,
         3 * (s % (:n_projects / 3)) + 1,
         true, false,
         'denied',
         '2026-02-12 12:00:00-03'::timestamptz
  FROM generate_series(1, :n_students) AS s
) t;

COMMIT;

-- Estatisticas atualizadas: sem isso o plano medido pode ser enganoso
ANALYZE auth."user";
ANALYZE academic_pi.project;
ANALYZE academic_pi.project_instructor;
ANALYZE academic_pi.enrollment_period;
ANALYZE academic_pi.project_participation;

-- Conferencia do volume carregado
SELECT 'usuarios' AS tabela, count(*) AS linhas FROM auth."user" WHERE email LIKE 'db017.%'
UNION ALL SELECT 'projetos', count(*) FROM academic_pi.project WHERE title LIKE 'DB017 %'
UNION ALL SELECT 'docentes_por_projeto', count(*) FROM academic_pi.project_instructor
UNION ALL SELECT 'periodos', count(*) FROM academic_pi.enrollment_period
UNION ALL SELECT 'participacoes', count(*) FROM academic_pi.project_participation;