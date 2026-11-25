-- DB-019: carga controlada de leitura (pgbench) exercitando consultas reais do dominio
-- Usa conexoes persistentes do pgbench para simular conexoes reutilizadas pelo pool (HikariCP).

\set student_idx random(1, 5000)
\set project_idx random(1, 600)

-- Q1: Listagem publica paginada de projetos (usa idx_project_public_title da V0017)
SELECT id, title, is_pi, is_extension
FROM academic_pi.project
WHERE is_public
  AND status = 'published'
ORDER BY title
LIMIT 20;

-- Q2: Participacoes ativas de um aluno aleatorio (usa idx_project_participation_student_id)
SELECT id, project_id, is_pi, is_extension, status
FROM academic_pi.project_participation
WHERE student_id = ('e1000000-0000-4000-8000-' || lpad(:student_idx::text, 12, '0'))::uuid
  AND status IN ('requested', 'approved');

-- Q3: Solicitacoes pendentes de um projeto para tela docente (usa project_participation_project_student_unq)
SELECT id, student_id, requested_at
FROM academic_pi.project_participation
WHERE project_id = ('e2000000-0000-4000-8000-' || lpad(:project_idx::text, 12, '0'))::uuid
  AND status = 'requested'
ORDER BY requested_at
LIMIT 20;

-- Q4: Janelas de inscricao abertas na data de referencia
SELECT e.id, e.project_id, e.closes_at
FROM academic_pi.enrollment_period e
WHERE e.project_id = ('e2000000-0000-4000-8000-' || lpad(:project_idx::text, 12, '0'))::uuid
  AND e.opens_at <= '2026-11-20 12:00:00-03'::timestamptz
  AND e.closes_at >= '2026-11-20 12:00:00-03'::timestamptz;
