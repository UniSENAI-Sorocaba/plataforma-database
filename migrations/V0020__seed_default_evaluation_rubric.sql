-- Migration: V0020 - Rubrica padrão para avaliação acadêmica
BEGIN;

INSERT INTO academic_pi.rubric (id, code, name, created_by)
VALUES ('e0000000-0000-4000-8000-000000000001', 'PI-MVP', 'Avaliação de projeto integrador', 'b0000000-0000-4000-8000-000000000003')
ON CONFLICT (code) DO NOTHING;

INSERT INTO academic_pi.rubric_version (id, rubric_id, version, created_by)
VALUES ('e1000000-0000-4000-8000-000000000001', 'e0000000-0000-4000-8000-000000000001', 1, 'b0000000-0000-4000-8000-000000000003')
ON CONFLICT (rubric_id, version) DO NOTHING;

INSERT INTO academic_pi.rubric_criterion (id, rubric_version_id, code, label, weight, min_score, max_score)
VALUES
    ('e2000000-0000-4000-8000-000000000001', 'e1000000-0000-4000-8000-000000000001', 'problem', 'Clareza do problema e dos objetivos', 0.25, 0, 10),
    ('e2000000-0000-4000-8000-000000000002', 'e1000000-0000-4000-8000-000000000001', 'solution', 'Qualidade e viabilidade da solução', 0.35, 0, 10),
    ('e2000000-0000-4000-8000-000000000003', 'e1000000-0000-4000-8000-000000000001', 'evidence', 'Evidências e resultados apresentados', 0.25, 0, 10),
    ('e2000000-0000-4000-8000-000000000004', 'e1000000-0000-4000-8000-000000000001', 'communication', 'Comunicação e participação', 0.15, 0, 10)
ON CONFLICT (rubric_version_id, code) DO NOTHING;

INSERT INTO public.schema_migration (version, description)
VALUES ('V0020', 'seed default academic evaluation rubric')
ON CONFLICT (version) DO NOTHING;

COMMIT;
