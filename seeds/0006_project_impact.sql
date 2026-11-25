-- Seeds sinteticos deterministicos para academic_pi.project_impact e project_impact_ods (DB-015)
-- Migration minima: V0015__create_project_impact.sql (depende dos seeds 0002 e 0005)
-- Idempotente via ON CONFLICT. Estritamente sintetico, sem dados pessoais (seeds/README.md, ADR-011, DB-003).

BEGIN;

INSERT INTO academic_pi.project_impact (
    id,
    project_id,
    summary,
    beneficiary_audience,
    period_start,
    period_end,
    territory,
    observed_result,
    evidence_text,
    beneficiaries_served,
    activity_hours,
    partners_involved,
    declared_by,
    approved_by,
    approved_at,
    status,
    created_at,
    updated_at
)
VALUES
    -- Impacto 1: aprovado = publicado (projeto 101 e publicado e publico). Entra como draft e e aprovado ao final,
    -- porque ODS de impacto aprovado so mudam apos nova aprovacao (guarda da V0015)
    (
        'b0000000-0000-4000-8000-000000000201',
        'b0000000-0000-4000-8000-000000000101',
        'Oficinas sinteticas de organizacao de dados para turmas de ensino medio.',
        'Estudantes sinteticos de escola publica ficticia.',
        '2026-02-01',
        '2026-06-30',
        'Territorio sintetico A',
        'Turmas concluiram as oficinas e aplicaram a organizacao proposta.',
        'Lista agregada ficticia de presenca e registro textual das oficinas.',
        120,
        48.50,
        2,
        'b0000000-0000-4000-8000-000000000002',
        NULL,
        NULL,
        'draft',
        '2026-07-01 10:00:00+00',
        '2026-07-05 10:00:00+00'
    ),
    -- Impacto 2: retirado (retired), nao pode aparecer na consulta publica
    (
        'b0000000-0000-4000-8000-000000000202',
        'b0000000-0000-4000-8000-000000000102',
        'Acao sintetica de apoio a oficina comunitaria.',
        'Moradores sinteticos de bairro ficticio.',
        '2026-03-01',
        '2026-05-31',
        'Territorio sintetico B',
        'Participacao registrada de forma agregada.',
        'Registro textual agregado e ficticio da acao.',
        40,
        16.00,
        1,
        'b0000000-0000-4000-8000-000000000002',
        'b0000000-0000-4000-8000-000000000003',
        '2026-06-10 10:00:00+00',
        'retired',
        '2026-06-01 10:00:00+00',
        '2026-06-10 10:00:00+00'
    ),
    -- Impacto 3: rascunho (draft) parcial, sem aprovacao
    (
        'b0000000-0000-4000-8000-000000000203',
        'b0000000-0000-4000-8000-000000000103',
        'Rascunho sintetico de impacto.',
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        'b0000000-0000-4000-8000-000000000002',
        NULL,
        NULL,
        'draft',
        '2026-08-01 10:00:00+00',
        '2026-08-01 10:00:00+00'
    )
ON CONFLICT (id) DO NOTHING;

-- NOT EXISTS (e nao ON CONFLICT): o trigger de guarda dispara antes da checagem de conflito
INSERT INTO academic_pi.project_impact_ods (impact_id, ods_code)
SELECT v.impact_id, v.ods_code
FROM (VALUES
    ('b0000000-0000-4000-8000-000000000201'::uuid, 4::smallint),
    ('b0000000-0000-4000-8000-000000000201'::uuid, 10::smallint),
    ('b0000000-0000-4000-8000-000000000202'::uuid, 11::smallint)
) AS v (impact_id, ods_code)
WHERE NOT EXISTS (
    SELECT 1 FROM academic_pi.project_impact_ods o
    WHERE o.impact_id = v.impact_id AND o.ods_code = v.ods_code
);

-- Aprovacao do impacto 1 (idempotente: so age enquanto estiver em draft)
UPDATE academic_pi.project_impact
SET status = 'approved',
    approved_by = 'b0000000-0000-4000-8000-000000000003',
    approved_at = '2026-07-05 10:00:00+00',
    updated_at = '2026-07-05 10:00:00+00'
WHERE id = 'b0000000-0000-4000-8000-000000000201'
  AND status = 'draft';

COMMIT;
