-- DB-017: custo de escrita em academic_pi.project (W1).
-- Uso:
--   docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U plataforma -d plataforma < evidence/DB-017-write-cost.sql
-- Rode DEPOIS das medicoes de leitura (DB-017-queries.sql), nunca no meio delas.
-- A insercao e desfeita com ROLLBACK, mas deixa linhas mortas na tabela; o VACUUM final limpa isso
-- para nao distorcer as leituras seguintes.

\pset pager off

\echo '=== W1: custo de escrita, 20 mil projetos inseridos (desfeito com ROLLBACK) ==='
BEGIN;
EXPLAIN (ANALYZE, BUFFERS)
INSERT INTO academic_pi.project (id, title, is_pi, is_extension, status, is_public)
SELECT gen_random_uuid(), 'DB017 Write ' || g, true, false, 'published', (g % 10 = 0)
FROM generate_series(1, 20000) AS g;
ROLLBACK;

VACUUM (ANALYZE) academic_pi.project;