-- Seeds sinteticos deterministicos para auth.user_session (DB-005)
-- Idempotente via ON CONFLICT (id) DO NOTHING
-- Estritamente sintetico, sem dados pessoais reais (alinhado a seeds/README.md, ADR-011, DB-003, DB-004 e DB-005)

-- =============================================================================
-- 1. auth.user_session
-- =============================================================================

-- Insercao do token sucessor primeiro para permitir referencia em replaced_by_token_id
INSERT INTO auth.user_session (
    id,
    user_id,
    token_hash,
    family_id,
    replaced_by_token_id,
    client_ip,
    user_agent,
    created_at,
    expires_at,
    revoked_at,
    last_used_at
)
VALUES
    -- Sessao sucessora ativa na cadeia de rotacao (estudante)
    (
        'c0000000-0000-4000-8000-000000000002',
        'b0000000-0000-4000-8000-000000000001',
        'b2c3d4e5f60718293a4b5c6d7e8f90123456789abcdef0123456789abcdef010',
        'd0000000-0000-4000-8000-000000000001',
        NULL,
        '192.0.2.10',
        'Mozilla/5.0 (Synthetic-Platform; TestDevice)',
        '2026-01-01 12:00:00+00',
        '2026-01-08 12:00:00+00',
        NULL,
        '2026-01-01 12:00:00+00'
    )
ON CONFLICT (id) DO NOTHING;

INSERT INTO auth.user_session (
    id,
    user_id,
    token_hash,
    family_id,
    replaced_by_token_id,
    client_ip,
    user_agent,
    created_at,
    expires_at,
    revoked_at,
    last_used_at
)
VALUES
    -- Sessao original rotacionada e superada (estudante)
    (
        'c0000000-0000-4000-8000-000000000001',
        'b0000000-0000-4000-8000-000000000001',
        'a1b2c3d4e5f60718293a4b5c6d7e8f90123456789abcdef0123456789abcdef0',
        'd0000000-0000-4000-8000-000000000001',
        'c0000000-0000-4000-8000-000000000002',
        '192.0.2.10',
        'Mozilla/5.0 (Synthetic-Platform; TestDevice)',
        '2026-01-01 10:00:00+00',
        '2026-01-08 10:00:00+00',
        '2026-01-01 12:00:00+00',
        '2026-01-01 12:00:00+00'
    ),
    -- Sessao revogada por logout explicito (professor)
    (
        'c0000000-0000-4000-8000-000000000003',
        'b0000000-0000-4000-8000-000000000002',
        'c3d4e5f60718293a4b5c6d7e8f90123456789abcdef0123456789abcdef01200',
        'd0000000-0000-4000-8000-000000000002',
        NULL,
        '192.0.2.20',
        'Mozilla/5.0 (Synthetic-Platform; Workstation)',
        '2026-01-01 08:00:00+00',
        '2026-01-08 08:00:00+00',
        '2026-01-01 09:30:00+00',
        '2026-01-01 09:30:00+00'
    ),
    -- Sessao ativa unica sem rotacao (coordenador)
    (
        'c0000000-0000-4000-8000-000000000004',
        'b0000000-0000-4000-8000-000000000003',
        'd4e5f60718293a4b5c6d7e8f90123456789abcdef0123456789abcdef0123000',
        'd0000000-0000-4000-8000-000000000003',
        NULL,
        '192.0.2.30',
        'Mozilla/5.0 (Synthetic-Platform; Mobile)',
        '2026-01-01 11:00:00+00',
        '2026-01-08 11:00:00+00',
        NULL,
        '2026-01-01 11:00:00+00'
    ),
    -- Sessao invalidada por deteccao de reuso de token (usuario standalone)
    (
        'c0000000-0000-4000-8000-000000000005',
        'b0000000-0000-4000-8000-000000000005',
        'e5f60718293a4b5c6d7e8f90123456789abcdef0123456789abcdef012340000',
        'd0000000-0000-4000-8000-000000000004',
        NULL,
        '192.0.2.50',
        'Mozilla/5.0 (Synthetic-Platform; TestDevice)',
        '2026-01-01 07:00:00+00',
        '2026-01-08 07:00:00+00',
        '2026-01-01 07:45:00+00',
        '2026-01-01 07:45:00+00'
    )
ON CONFLICT (id) DO NOTHING;

