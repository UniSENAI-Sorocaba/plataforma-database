-- Seeds sinteticos deterministicos para auth.user, auth.user_identity, institutional.academic_class e institutional.academic_link
-- Idempotente via ON CONFLICT (id) DO NOTHING
-- Estritamente sintetico, sem dados pessoais reais (alinhado a seeds/README.md, ADR-011, DB-003 e DB-004)

-- =============================================================================
-- 1. auth.user
-- =============================================================================
INSERT INTO auth.user (
    id,
    email,
    full_name,
    cpf,
    password_hash,
    status,
    created_at,
    updated_at
)
VALUES
    (
        'b0000000-0000-4000-8000-000000000001',
        'mock.student.01@synthetic.local',
        'Mock Student One',
        '11111111111',
        NULL,
        'active',
        '2026-01-01 10:00:00+00',
        '2026-01-01 10:00:00+00'
    ),
    (
        'b0000000-0000-4000-8000-000000000002',
        'mock.professor.01@synthetic.local',
        'Mock Professor One',
        '22222222222',
        NULL,
        'active',
        '2026-01-01 10:00:00+00',
        '2026-01-01 10:00:00+00'
    ),
    (
        'b0000000-0000-4000-8000-000000000003',
        'mock.coordinator.01@synthetic.local',
        'Mock Coordinator One',
        '33333333333',
        NULL,
        'active',
        '2026-01-01 10:00:00+00',
        '2026-01-01 10:00:00+00'
    ),
    (
        'b0000000-0000-4000-8000-000000000004',
        'mock.pending.user@synthetic.local',
        'Mock Pending User',
        '44444444444',
        NULL,
        'pending',
        '2026-01-01 10:00:00+00',
        '2026-01-01 10:00:00+00'
    ),
    (
        'b0000000-0000-4000-8000-000000000005',
        'mock.unaffiliated.user@synthetic.local',
        'Mock Unaffiliated User',
        NULL,
        NULL,
        'active',
        '2026-01-01 10:00:00+00',
        '2026-01-01 10:00:00+00'
    )
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- 2. auth.user_identity
-- =============================================================================
INSERT INTO auth.user_identity (
    id,
    user_id,
    provider,
    provider_subject,
    email,
    last_authenticated_at,
    created_at,
    updated_at
)
VALUES
    (
        'e0000000-0000-4000-8000-000000000001',
        'b0000000-0000-4000-8000-000000000001',
        'oidc',
        'sub-synthetic-student-01',
        'mock.student.01@synthetic.local',
        '2026-01-01 10:00:00+00',
        '2026-01-01 10:00:00+00',
        '2026-01-01 10:00:00+00'
    ),
    (
        'e0000000-0000-4000-8000-000000000002',
        'b0000000-0000-4000-8000-000000000002',
        'oidc',
        'sub-synthetic-professor-01',
        'mock.professor.01@synthetic.local',
        '2026-01-01 10:00:00+00',
        '2026-01-01 10:00:00+00',
        '2026-01-01 10:00:00+00'
    )
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- 3. institutional.academic_class
-- =============================================================================
INSERT INTO institutional.academic_class (
    id,
    code,
    name,
    term,
    is_active,
    created_at,
    updated_at
)
VALUES
    (
        'c0000000-0000-4000-8000-000000000001',
        'SYN-TURMA-2026-ENG-01',
        'Engenharia de Software 2026.1',
        '2026.1',
        true,
        '2026-01-01 10:00:00+00',
        '2026-01-01 10:00:00+00'
    ),
    (
        'c0000000-0000-4000-8000-000000000002',
        'SYN-TURMA-2026-ADS-02',
        'Analise e Desenvolvimento de Sistemas 2026.1',
        '2026.1',
        true,
        '2026-01-01 10:00:00+00',
        '2026-01-01 10:00:00+00'
    )
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- 4. institutional.academic_link
-- =============================================================================
INSERT INTO institutional.academic_link (
    id,
    user_id,
    class_id,
    role,
    registration_number,
    status,
    created_at,
    updated_at
)
VALUES
    -- Aluno mock vinculado a turma ENG
    (
        'd0000000-0000-4000-8000-000000000001',
        'b0000000-0000-4000-8000-000000000001',
        'c0000000-0000-4000-8000-000000000001',
        'student',
        'RA-SYN-2026-001',
        'active',
        '2026-01-01 10:00:00+00',
        '2026-01-01 10:00:00+00'
    ),
    -- Mesmo aluno mock vinculado a turma ADS (valida cenario multi-turma)
    (
        'd0000000-0000-4000-8000-000000000002',
        'b0000000-0000-4000-8000-000000000001',
        'c0000000-0000-4000-8000-000000000002',
        'student',
        'RA-SYN-2026-001',
        'active',
        '2026-01-01 10:00:00+00',
        '2026-01-01 10:00:00+00'
    ),
    -- Docente mock vinculado a turma ENG
    (
        'd0000000-0000-4000-8000-000000000003',
        'b0000000-0000-4000-8000-000000000002',
        'c0000000-0000-4000-8000-000000000001',
        'professor',
        'DOC-SYN-2026-001',
        'active',
        '2026-01-01 10:00:00+00',
        '2026-01-01 10:00:00+00'
    ),
    -- Coordenacao mock vinculada a turma ENG
    (
        'd0000000-0000-4000-8000-000000000004',
        'b0000000-0000-4000-8000-000000000003',
        'c0000000-0000-4000-8000-000000000001',
        'coordinator',
        'COORD-SYN-2026-001',
        'active',
        '2026-01-01 10:00:00+00',
        '2026-01-01 10:00:00+00'
    ),
    -- Usuario com vinculo desativado (valida ativacao/desativacao de vinculo)
    (
        'd0000000-0000-4000-8000-000000000005',
        'b0000000-0000-4000-8000-000000000004',
        'c0000000-0000-4000-8000-000000000002',
        'student',
        'RA-SYN-2026-004',
        'inactive',
        '2026-01-01 10:00:00+00',
        '2026-01-01 10:00:00+00'
    )
ON CONFLICT (id) DO NOTHING;
