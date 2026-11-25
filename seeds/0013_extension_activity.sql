-- Seeds sinteticos deterministicos para extension.activity (DB-013)
-- Idempotente via ON CONFLICT DO NOTHING
-- Estritamente sintetico, sem dados pessoais reais (alinhado a seeds/README.md, ADR-011, DB-003, DB-008, DB-012 e DB-013)

BEGIN;

-- =============================================================================
-- 1. Participantes sinteticos complementares aprovados para projetos com Extensao
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
    (
        'b0000000-0000-4000-8000-000000000013',
        'mock.ext.student.13@synthetic.local',
        'Mock Extension Student Thirteen',
        '13131313131',
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
        'd0000000-0000-4000-8000-000000000013',
        'b0000000-0000-4000-8000-000000000013',
        'c0000000-0000-4000-8000-000000000002',
        'student',
        'RA-SYN-2026-013',
        'active',
        '2026-01-01 10:00:00+00',
        '2026-01-01 10:00:00+00'
    )
ON CONFLICT (id) DO NOTHING;

-- Participacao aprovada do usuario b0000000-...0005 no Projeto 2 (Extensao pura) e
-- do estudante b0000000-...0013 no Projeto 3 (Hibrido PI + Extensao)
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
        'd3000000-0000-4000-8000-000000000013',
        'b0000000-0000-4000-8000-000000000102',
        false,
        true,
        'b0000000-0000-4000-8000-000000000005',
        'approved',
        NULL,
        '2026-02-16 10:00:00+00',
        '2026-02-18 14:00:00+00',
        '2026-02-16 10:00:00+00',
        '2026-02-18 14:00:00+00'
    ),
    (
        'd3000000-0000-4000-8000-000000000014',
        'b0000000-0000-4000-8000-000000000103',
        true,
        true,
        'b0000000-0000-4000-8000-000000000013',
        'approved',
        NULL,
        '2026-03-02 09:00:00+00',
        '2026-03-04 11:00:00+00',
        '2026-03-02 09:00:00+00',
        '2026-03-04 11:00:00+00'
    )
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- 2. extension.activity (Atividades e Horas Vigentes de Extensao)
-- =============================================================================
INSERT INTO extension.activity (
    id,
    participation_id,
    project_id,
    student_id,
    title,
    description,
    submitted_at,
    validated_hours,
    last_validated_by,
    last_validated_at,
    created_at,
    updated_at
)
VALUES
    -- Atividade 1: Projeto 2 (Extensao), Aluno 1 — horas definidas e validadas pelo docente responsavel (Professor 1)
    (
        'e1300000-0000-4000-8000-000000000001',
        'd3000000-0000-4000-8000-000000000002',
        'b0000000-0000-4000-8000-000000000102',
        'b0000000-0000-4000-8000-000000000001',
        'Oficina de Letramento Digital Comunitario',
        'Conducao de oficina pratica sobre navegacao segura e ferramentas digitais basicas para turmas comunitarias.',
        '2026-04-10 14:00:00+00',
        4,
        'b0000000-0000-4000-8000-000000000002',
        '2026-04-12 10:00:00+00',
        '2026-04-10 14:00:00+00',
        '2026-04-12 10:00:00+00'
    ),
    -- Atividade 2: Projeto 2 (Extensao), Aluno 1 — segunda atividade da mesma participacao com horas fracionarias vigentes
    (
        'e1300000-0000-4000-8000-000000000002',
        'd3000000-0000-4000-8000-000000000002',
        'b0000000-0000-4000-8000-000000000102',
        'b0000000-0000-4000-8000-000000000001',
        'Plantao de Orientacao Tecnica Aberta',
        'Atendimento supervisionado para configuracao de dispositivos e acessibilidade digital da comunidade externa.',
        '2026-05-18 15:30:00+00',
        2.5,
        'b0000000-0000-4000-8000-000000000002',
        '2026-05-20 09:30:00+00',
        '2026-05-18 15:30:00+00',
        '2026-05-20 09:30:00+00'
    ),
    -- Atividade 3: Projeto 2 (Extensao), Aluno 1 — atividade enviada dentro do periodo aguardando definicao/validacao de horas
    (
        'e1300000-0000-4000-8000-000000000003',
        'd3000000-0000-4000-8000-000000000002',
        'b0000000-0000-4000-8000-000000000102',
        'b0000000-0000-4000-8000-000000000001',
        'Elaboracao de Apostila Sintetica de Inclusao Digital',
        'Organizacao de guia ilustrado de apoio aos encontros presenciais do programa comunitario.',
        '2026-09-05 11:00:00+00',
        NULL,
        NULL,
        NULL,
        '2026-09-05 11:00:00+00',
        '2026-09-05 11:00:00+00'
    ),
    -- Atividade 4: Projeto 2 (Extensao), segundo participante aprovado — horas vigentes validadas pelo docente responsavel
    (
        'e1300000-0000-4000-8000-000000000004',
        'd3000000-0000-4000-8000-000000000013',
        'b0000000-0000-4000-8000-000000000102',
        'b0000000-0000-4000-8000-000000000005',
        'Mediacao em Laboratorio Aberto Comunitario',
        'Acompanhamento de exercicios praticos em laboratorio de informatica durante ciclo de oficinas.',
        '2026-06-12 13:00:00+00',
        6,
        'b0000000-0000-4000-8000-000000000002',
        '2026-06-14 16:00:00+00',
        '2026-06-12 13:00:00+00',
        '2026-06-14 16:00:00+00'
    ),
    -- Atividade 5: Projeto 3 (Hibrido PI + Extensao), Estudante 13 — validada pelo docente responsavel do Projeto 3 (Coordinator 1)
    (
        'e1300000-0000-4000-8000-000000000005',
        'd3000000-0000-4000-8000-000000000014',
        'b0000000-0000-4000-8000-000000000103',
        'b0000000-0000-4000-8000-000000000013',
        'Demonstracao Comunitaria de Prototipo Sustentavel',
        'Apresentacao aberta de solucao de eficiencia energetica para moradores e parceiros locais.',
        '2026-08-20 10:00:00+00',
        3.75,
        'b0000000-0000-4000-8000-000000000003',
        '2026-08-22 17:00:00+00',
        '2026-08-20 10:00:00+00',
        '2026-08-22 17:00:00+00'
    )
ON CONFLICT (id) DO NOTHING;

COMMIT;
