-- Seed sintetico deterministico para public.audit_event
-- Idempotente via ON CONFLICT (id) DO NOTHING
-- Estritamente sintetico, sem dados pessoais reais (alinhado a seeds/README.md e ADR-011)

INSERT INTO public.audit_event (
    id,
    occurred_at,
    schema_name,
    table_name,
    operation,
    record_id,
    actor_id,
    old_data,
    new_data
)
VALUES (
    '00000000-0000-4000-8000-000000000001',
    '2026-01-01 00:00:00+00',
    'auth',
    'user',
    'INSERT',
    '00000000-0000-4000-8000-000000000002',
    '00000000-0000-4000-8000-000000000003',
    NULL,
    '{"entity": "synthetic_user", "action": "create", "environment": "test"}'::jsonb
)
ON CONFLICT (id) DO NOTHING;
