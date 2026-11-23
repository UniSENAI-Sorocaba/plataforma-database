BEGIN;

-- DB-017: indice parcial para a listagem publica de projetos (portal publico, itens 29 e 35 do Caderno).
-- Usa somente coluna e predicado publicos (title; is_public e status = 'published'); nao inclui dado privado.
CREATE INDEX IF NOT EXISTS idx_project_public_title
  ON academic_pi.project (title)
  WHERE is_public AND status = 'published';

INSERT INTO public.schema_migration (version, description)
VALUES ('V0017', 'add public project title index')
ON CONFLICT (version) DO NOTHING;

COMMIT;