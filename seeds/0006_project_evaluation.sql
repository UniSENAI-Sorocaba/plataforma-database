-- Seeds sinteticos deterministicos para academic_pi.project_evaluation (DB-009)
-- Idempotente via ON CONFLICT DO NOTHING
-- Estritamente sintetico, sem dados pessoais reais (alinhado a seeds/README.md, ADR-011, DB-003, DB-004, DB-008 e DB-009)

BEGIN;

-- =============================================================================
-- 1. Atores sinteticos complementares para cenarios de pares e docente externo ao projeto
-- =============================================================================
INSERT INTO auth."user" (
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
    -- Segundo estudante ativo para cenarios de avaliacao entre alunos (peer evaluation)
    (
        'b0000000-0000-4000-8000-000000000006',
        'mock.student.02@synthetic.local',
        'Mock Student Two',
        '66666666666',
        NULL,
        'active',
        '2026-01-01 10:00:00+00',
        '2026-01-01 10:00:00+00'
    ),
    -- Segundo docente ativo (nao cadastrado como project_instructor nos projetos 101 e 102)
    (
        'b0000000-0000-4000-8000-000000000007',
        'mock.professor.02@synthetic.local',
        'Mock Professor Two',
        '77777777777',
        NULL,
        'active',
        '2026-01-01 10:00:00+00',
        '2026-01-01 10:00:00+00'
    )
ON CONFLICT (id) DO NOTHING;

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
    (
        'd0000000-0000-4000-8000-000000000006',
        'b0000000-0000-4000-8000-000000000006',
        'c0000000-0000-4000-8000-000000000001',
        'student',
        'RA-SYN-2026-006',
        'active',
        '2026-01-01 10:00:00+00',
        '2026-01-01 10:00:00+00'
    ),
    (
        'd0000000-0000-4000-8000-000000000007',
        'b0000000-0000-4000-8000-000000000007',
        'c0000000-0000-4000-8000-000000000002',
        'professor',
        'DOC-SYN-2026-002',
        'active',
        '2026-01-01 10:00:00+00',
        '2026-01-01 10:00:00+00'
    )
ON CONFLICT (id) DO NOTHING;

INSERT INTO user_roles (user_id, role_id, scope_type, scope_id, assigned_at, assigned_by)
SELECT
    'b0000000-0000-4000-8000-000000000006'::uuid,
    r.id,
    'TURMA',
    'c0000000-0000-4000-8000-000000000001',
    '2026-01-01 10:00:00+00'::timestamptz,
    'b0000000-0000-4000-8000-000000000003'::uuid
FROM roles r
WHERE r.name = 'ALUNO'
ON CONFLICT (user_id, role_id, scope_type, scope_id) DO NOTHING;

INSERT INTO user_roles (user_id, role_id, scope_type, scope_id, assigned_at, assigned_by)
SELECT
    'b0000000-0000-4000-8000-000000000006'::uuid,
    r.id,
    'PROJETO',
    'b0000000-0000-4000-8000-000000000101',
    '2026-01-01 10:00:00+00'::timestamptz,
    'b0000000-0000-4000-8000-000000000003'::uuid
FROM roles r
WHERE r.name = 'ALUNO'
ON CONFLICT (user_id, role_id, scope_type, scope_id) DO NOTHING;

INSERT INTO user_roles (user_id, role_id, scope_type, scope_id, assigned_at, assigned_by)
SELECT
    'b0000000-0000-4000-8000-000000000007'::uuid,
    r.id,
    'GLOBAL',
    '*',
    '2026-01-01 10:00:00+00'::timestamptz,
    'b0000000-0000-4000-8000-000000000003'::uuid
FROM roles r
WHERE r.name = 'DOCENTE'
ON CONFLICT (user_id, role_id, scope_type, scope_id) DO NOTHING;

-- Participacao aprovada do Estudante 2 no Projeto 1 (PI) para cobrir avaliacao reciproca entre pares
INSERT INTO academic_pi.project_participation (
    id,
    project_id,
    is_pi,
    is_extension,
    student_id,
    status,
    justification,
    requested_at,
    decided_at,
    created_at,
    updated_at
)
VALUES
    (
        'd3000000-0000-4000-8000-000000000006',
        'b0000000-0000-4000-8000-000000000101',
        true,
        false,
        'b0000000-0000-4000-8000-000000000006',
        'approved',
        NULL,
        '2026-01-16 09:00:00+00',
        '2026-01-20 10:00:00+00',
        '2026-01-16 09:00:00+00',
        '2026-01-20 10:00:00+00'
    )
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- 2. academic_pi.project_evaluation (Avaliacoes Individuais sem Banca)
-- =============================================================================
INSERT INTO academic_pi.project_evaluation (
    id,
    project_id,
    evaluator_user_id,
    evaluated_student_id,
    assigned_by_user_id,
    evaluation_date,
    created_at,
    updated_at
)
VALUES
    -- Avaliacao 1 (PI): Docente responsavel (Professor 1) avalia Aluno 1 no Projeto 1 (PI)
    (
        'd4000000-0000-4000-8000-000000000001',
        'b0000000-0000-4000-8000-000000000101',
        'b0000000-0000-4000-8000-000000000002',
        'b0000000-0000-4000-8000-000000000001',
        NULL,
        NULL,
        '2026-06-15 14:00:00+00',
        '2026-06-15 14:00:00+00'
    ),
    -- Avaliacao 2 (PI - Aluno avaliando Aluno com atribuicao da Coordenacao):
    -- Coordenacao atribui Aluno 2 para avaliar Aluno 1 no Projeto 1 (PI) com data definida
    (
        'd4000000-0000-4000-8000-000000000002',
        'b0000000-0000-4000-8000-000000000101',
        'b0000000-0000-4000-8000-000000000006',
        'b0000000-0000-4000-8000-000000000001',
        'b0000000-0000-4000-8000-000000000003',
        DATE '2026-06-15',
        '2026-06-01 09:00:00+00',
        '2026-06-15 15:00:00+00'
    ),
    -- Avaliacao 3 (PI - Multiplas avaliacoes no mesmo projeto e avaliacao entre pares):
    -- Coordenacao atribui Aluno 1 para avaliar Aluno 2 no Projeto 1 (PI) com data definida
    (
        'd4000000-0000-4000-8000-000000000003',
        'b0000000-0000-4000-8000-000000000101',
        'b0000000-0000-4000-8000-000000000001',
        'b0000000-0000-4000-8000-000000000006',
        'b0000000-0000-4000-8000-000000000003',
        DATE '2026-06-16',
        '2026-06-01 09:05:00+00',
        '2026-06-16 16:00:00+00'
    ),
    -- Avaliacao 4 (Extensao): Docente responsavel (Professor 1) adiciona avaliacao para Aluno 1 no Projeto 2 (Extensao)
    (
        'd4000000-0000-4000-8000-000000000004',
        'b0000000-0000-4000-8000-000000000102',
        'b0000000-0000-4000-8000-000000000002',
        'b0000000-0000-4000-8000-000000000001',
        NULL,
        NULL,
        '2026-10-10 11:00:00+00',
        '2026-10-10 11:00:00+00'
    ),
    -- Avaliacao 5 (Extensao - Docente NAO responsavel pelo projeto):
    -- Professor 2 (sem vinculo em project_instructor do Projeto 2) adiciona avaliacao na Extensao
    (
        'd4000000-0000-4000-8000-000000000005',
        'b0000000-0000-4000-8000-000000000102',
        'b0000000-0000-4000-8000-000000000007',
        'b0000000-0000-4000-8000-000000000001',
        NULL,
        NULL,
        '2026-10-11 14:30:00+00',
        '2026-10-11 14:30:00+00'
    ),
    -- Avaliacao 6 (Extensao - Aluno avaliando outro aluno e multiplas avaliacoes no projeto):
    -- Aluno 2 avalia Aluno 1 participante do Projeto 2 (Extensao)
    (
        'd4000000-0000-4000-8000-000000000006',
        'b0000000-0000-4000-8000-000000000102',
        'b0000000-0000-4000-8000-000000000006',
        'b0000000-0000-4000-8000-000000000001',
        NULL,
        NULL,
        '2026-10-12 16:00:00+00',
        '2026-10-12 16:00:00+00'
    )
ON CONFLICT (id) DO NOTHING;

COMMIT;
