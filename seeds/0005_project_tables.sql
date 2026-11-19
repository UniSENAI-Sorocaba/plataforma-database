-- Seeds sinteticos deterministicos para academic_pi.project, enrollment_period, project_instructor e project_participation (DB-008 e DB-016)
-- Idempotente via ON CONFLICT (id) DO NOTHING
-- Estritamente sintetico, sem dados pessoais reais (alinhado a seeds/README.md, ADR-011, DB-003, DB-004 e DB-008)

BEGIN;

-- =============================================================================
-- 1. academic_pi.project (Projetos de PI e Extensao)
-- =============================================================================
INSERT INTO academic_pi.project (
    id,
    title,
    description,
    is_pi,
    is_extension,
    status,
    is_public,
    starts_at,
    ends_at,
    created_at,
    updated_at
)
VALUES
    -- Projeto 1: Projeto Integrador publicado e publico (alinhado ao escopo em seeds/0004_rbac_roles_and_scopes.sql)
    (
        'b0000000-0000-4000-8000-000000000101',
        'Plataforma de Gestao Academica Inteligente',
        'Projeto Integrador voltado ao desenvolvimento de modulos de governanca, integracao e monitoramento de atividades academicas.',
        true,
        false,
        'published',
        true,
        '2026-02-01 08:00:00+00',
        '2026-06-30 18:00:00+00',
        '2026-01-01 10:00:00+00',
        '2026-01-01 10:00:00+00'
    ),
    -- Projeto 2: Acao Comunitaria de Extensao publicada e publica
    (
        'b0000000-0000-4000-8000-000000000102',
        'Programa de Inclusao Digital Comunitaria',
        'Projeto de extensao para capacitacao tecnologica e letramento digital voltado a comunidade externa do entorno do campus.',
        false,
        true,
        'published',
        true,
        '2026-02-15 08:00:00+00',
        '2026-11-30 18:00:00+00',
        '2026-01-01 10:00:00+00',
        '2026-01-01 10:00:00+00'
    ),
    -- Projeto 3: Projeto hibrido (PI + Extensao) em rascunho
    (
        'b0000000-0000-4000-8000-000000000103',
        'Laboratorio Aberto de Inovacao Sustentavel',
        'Iniciativa conjunta de prototipagem rapida para solucoes energeticas e engajamento comunitario.',
        true,
        true,
        'draft',
        false,
        '2026-03-01 08:00:00+00',
        '2026-12-15 18:00:00+00',
        '2026-01-01 10:00:00+00',
        '2026-01-01 10:00:00+00'
    ),
    -- Projeto 4: Projeto arquivado de ciclo anterior
    (
        'b0000000-0000-4000-8000-000000000104',
        'Sistema de Telemetria IoT para Eficiencia Energetica',
        'Projeto de integracao institucional do ciclo letivo anterior concluido e arquivado.',
        true,
        false,
        'archived',
        false,
        '2025-08-01 08:00:00+00',
        '2025-12-20 18:00:00+00',
        '2025-07-01 10:00:00+00',
        '2025-12-20 18:00:00+00'
    )
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- 2. academic_pi.enrollment_period (Janelas de Inscricao)
-- =============================================================================
INSERT INTO academic_pi.enrollment_period (
    id,
    project_id,
    opens_at,
    closes_at,
    created_at,
    updated_at
)
VALUES
    -- Janela de inscricao para o Projeto 1
    (
        'd1000000-0000-4000-8000-000000000001',
        'b0000000-0000-4000-8000-000000000101',
        '2026-01-10 08:00:00+00',
        '2026-01-30 23:59:59+00',
        '2026-01-01 10:00:00+00',
        '2026-01-01 10:00:00+00'
    ),
    -- Janela de inscricao para o Projeto 2
    (
        'd1000000-0000-4000-8000-000000000002',
        'b0000000-0000-4000-8000-000000000102',
        '2026-01-15 08:00:00+00',
        '2026-02-10 23:59:59+00',
        '2026-01-01 10:00:00+00',
        '2026-01-01 10:00:00+00'
    ),
    -- Janela de inscricao futura para o Projeto 3
    (
        'd1000000-0000-4000-8000-000000000003',
        'b0000000-0000-4000-8000-000000000103',
        '2026-02-01 08:00:00+00',
        '2026-02-28 23:59:59+00',
        '2026-01-01 10:00:00+00',
        '2026-01-01 10:00:00+00'
    )
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- 3. academic_pi.project_instructor (Docentes Responsaveis)
-- =============================================================================
INSERT INTO academic_pi.project_instructor (
    id,
    project_id,
    instructor_id,
    created_at
)
VALUES
    -- Docente mock 1 como responsavel pelo Projeto 1 (PI)
    (
        'd2000000-0000-4000-8000-000000000001',
        'b0000000-0000-4000-8000-000000000101',
        'b0000000-0000-4000-8000-000000000002',
        '2026-01-01 10:00:00+00'
    ),
    -- Docente mock 1 como responsavel pelo Projeto 2 (Extensao)
    (
        'd2000000-0000-4000-8000-000000000002',
        'b0000000-0000-4000-8000-000000000102',
        'b0000000-0000-4000-8000-000000000002',
        '2026-01-01 10:00:00+00'
    ),
    -- Coordenador mock 1 como responsavel pelo Projeto 3 (Hibrido)
    (
        'd2000000-0000-4000-8000-000000000003',
        'b0000000-0000-4000-8000-000000000103',
        'b0000000-0000-4000-8000-000000000003',
        '2026-01-01 10:00:00+00'
    )
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- 4. academic_pi.project_participation (Solicitacoes e Participacoes de Alunos)
-- =============================================================================
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
    -- Participacao ativa de Aluno 1 no Projeto 1 (apenas PI, aprovada)
    (
        'd3000000-0000-4000-8000-000000000001',
        'b0000000-0000-4000-8000-000000000101',
        true,
        false,
        'b0000000-0000-4000-8000-000000000001',
        'approved',
        NULL,
        '2026-01-15 14:00:00+00',
        '2026-01-20 09:00:00+00',
        '2026-01-15 14:00:00+00',
        '2026-01-20 09:00:00+00'
    ),
    -- Participacao ativa de Aluno 1 no Projeto 2 (apenas Extensao, aprovada; 1 PI + 1 Extensao simultaneos)
    (
        'd3000000-0000-4000-8000-000000000002',
        'b0000000-0000-4000-8000-000000000102',
        false,
        true,
        'b0000000-0000-4000-8000-000000000001',
        'approved',
        NULL,
        '2026-01-16 11:00:00+00',
        '2026-01-21 15:00:00+00',
        '2026-01-16 11:00:00+00',
        '2026-01-21 15:00:00+00'
    ),
    -- Participacao historica desistida voluntariamente de Aluno 1 no Projeto 4 (arquivado)
    (
        'd3000000-0000-4000-8000-000000000003',
        'b0000000-0000-4000-8000-000000000104',
        true,
        false,
        'b0000000-0000-4000-8000-000000000001',
        'withdrawn',
        NULL,
        '2025-08-05 10:00:00+00',
        '2025-08-10 10:00:00+00',
        '2025-08-05 10:00:00+00',
        '2025-09-01 10:00:00+00'
    ),
    -- Participacao com remocao fundamentada de Aluno 2 (pending user) no Projeto 4
    (
        'd3000000-0000-4000-8000-000000000004',
        'b0000000-0000-4000-8000-000000000104',
        true,
        false,
        'b0000000-0000-4000-8000-000000000004',
        'removed',
        'Desistencia voluntaria registrada pelo docente responsavel.',
        '2025-08-05 10:00:00+00',
        '2025-08-10 10:00:00+00',
        '2025-08-05 10:00:00+00',
        '2025-09-15 10:00:00+00'
    ),
    -- Solicitacao pendente de Aluno 2 (pending user) no Projeto 3 (Hibrido: PI + Extensao)
    (
        'd3000000-0000-4000-8000-000000000005',
        'b0000000-0000-4000-8000-000000000103',
        true,
        true,
        'b0000000-0000-4000-8000-000000000004',
        'requested',
        NULL,
        '2026-02-05 10:00:00+00',
        NULL,
        '2026-02-05 10:00:00+00',
        '2026-02-05 10:00:00+00'
    )
ON CONFLICT (id) DO NOTHING;

COMMIT;
