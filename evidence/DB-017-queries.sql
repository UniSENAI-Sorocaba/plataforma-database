-- DB-017: consultas candidatas (derivadas do Caderno, não observadas na QA-024).
-- Uso, depois de carregar os dados com DB-017-load.sql:
--   docker compose exec -T postgres psql -v ON_ERROR_STOP=1 \
--     -U plataforma -d plataforma < evidence/DB-017-queries.sql
--
-- Rode cada consulta três vezes e compare as medianas.
-- Para comparar antes/depois, mantenha o mesmo conjunto de dados.
-- Atualize as estatísticas com ANALYZE antes de cada série.
-- EXPLAIN ANALYZE executa as consultas de leitura.

\pset pager off

-- Parâmetros fixos para manter a mesma janela e os mesmos registros.
\set ref '2026-11-20 12:00:00-03'
\set student 'e1000000-0000-4000-8000-000000001234'
\set proj_pending 'e2000000-0000-4000-8000-000000000013'

-- Resolve um docente sem depender do volume da carga.
SELECT instructor_id AS instr
FROM academic_pi.project_instructor
WHERE project_id = 'e2000000-0000-4000-8000-000000000007'
ORDER BY instructor_id
LIMIT 1
\gset

\echo '=== Q1 completa: portal publico, projetos publicados e publicos, ordenados por titulo (itens 29 e 35) ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title, is_pi, is_extension
FROM academic_pi.project
WHERE is_public
  AND status = 'published'
ORDER BY title;

\echo '=== Q1 paginada: portal publico, mesmos filtros e ordenacao, LIMIT 20 (itens 29 e 35) ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title, is_pi, is_extension
FROM academic_pi.project
WHERE is_public
  AND status = 'published'
ORDER BY title
LIMIT 20;

\echo '=== Q2: participacoes ativas de um aluno (itens 31 e 32) ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, project_id, is_pi, is_extension, status
FROM academic_pi.project_participation
WHERE student_id = :'student'
  AND status IN ('requested', 'approved');

\echo '=== Q3: solicitacoes pendentes de um projeto, tela de aprovacao do docente (itens 30 e 31) ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, student_id, requested_at
FROM academic_pi.project_participation
WHERE project_id = :'proj_pending'
  AND status = 'requested'
ORDER BY requested_at;

\echo '=== Q4: projetos de um docente com periodo aberto na data de referencia (itens 31 e 36) ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.id, p.title, e.opens_at, e.closes_at
FROM academic_pi.project_instructor pin
JOIN academic_pi.project p
  ON p.id = pin.project_id
JOIN academic_pi.enrollment_period e
  ON e.project_id = p.id
WHERE pin.instructor_id = :'instr'
  AND e.opens_at <= :'ref'
  AND e.closes_at >= :'ref';

\echo '=== Q5: projetos publicados com periodo aberto na data de referencia (itens 31 e 36) ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.id, p.title, e.closes_at
FROM academic_pi.enrollment_period e
JOIN academic_pi.project p
  ON p.id = e.project_id
WHERE e.opens_at <= :'ref'
  AND e.closes_at >= :'ref'
  AND p.status = 'published'
ORDER BY e.closes_at;

-- O custo de escrita W1 fica em DB-017-write-cost.sql.
-- Rode esse script separadamente, depois das medições de leitura:
-- o INSERT com ROLLBACK deixa linhas mortas em project até o VACUUM.