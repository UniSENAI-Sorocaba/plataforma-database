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
    is_published,
    created_at,
    updated_at
)
VALUES
    -- Impacto 1: aprovado e publicado (projeto 101 e publicado e publico)
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
        'b0000000-0000-4000-8000-000000000003',
        '2026-07-05 10:00:00+00',
        true,
        '2026-07-01 10:00:00+00',
        '2026-07-05 10:00:00+00'
    ),
    -- Impacto 2: aprovado, mas retirado/nao publicado (nao pode aparecer na consulta publica)
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
        false,
        '2026-06-01 10:00:00+00',
        '2026-06-10 10:00:00+00'
    ),
    -- Impacto 3: rascunho parcial (campos opcionais ainda vazios), sem aprovacao
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
        false,
        '2026-08-01 10:00:00+00',
        '2026-08-01 10:00:00+00'
    )
ON CONFLICT (id) DO NOTHING;

INSERT INTO academic_pi.project_impact_ods (impact_id, ods_code)
VALUES
    ('b0000000-0000-4000-8000-000000000201', 4),
    ('b0000000-0000-4000-8000-000000000201', 10),
    ('b0000000-0000-4000-8000-000000000202', 11)
ON CONFLICT (impact_id, ods_code) DO NOTHING;

COMMIT;
