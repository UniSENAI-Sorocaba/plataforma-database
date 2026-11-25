-- DB-019: carga controlada mista leitura + escrita transacional (pgbench)
-- Simula multiplas replicas do Backend reutilizando conexoes persistentes do pool sob leituras e atualizacoes.

\set student_idx random(1, 5000)
\set project_idx random(1, 600)

BEGIN;

-- Leitura de perfil/usuario e participacoes ativas
SELECT u.id, u.status
FROM auth."user" u
WHERE u.id = ('e1000000-0000-4000-8000-' || lpad(:student_idx::text, 12, '0'))::uuid;

SELECT id, project_id, status
FROM academic_pi.project_participation
WHERE student_id = ('e1000000-0000-4000-8000-' || lpad(:student_idx::text, 12, '0'))::uuid
  AND status IN ('requested', 'approved');

-- Leitura do catalogo publico paginado
SELECT id, title
FROM academic_pi.project
WHERE is_public
  AND status = 'published'
ORDER BY title
LIMIT 20;

-- Escrita leve idempotente (touch de updated_at em projeto publicado para exercitar locks de linha e WAL)
UPDATE academic_pi.project
SET updated_at = now()
WHERE id = ('e2000000-0000-4000-8000-' || lpad(:project_idx::text, 12, '0'))::uuid;

COMMIT;
