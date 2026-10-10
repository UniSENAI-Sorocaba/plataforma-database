-- Seeds sinteticos deterministicos para public.audit_event
-- Idempotente via ON CONFLICT (id) DO NOTHING
-- Estritamente sintetico, sem dados pessoais reais (alinhado a seeds/README.md, ADR-011 e DB-003)
-- Cobre os 5 schemas de dominio: auth, academic_pi, extension, assets e institutional
-- Cobre as 3 operacoes permitidas: INSERT, UPDATE, DELETE

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
VALUES
    -- =========================================================================
    -- Dominio: auth
    -- =========================================================================
    (
        '00000000-0000-4000-8000-000000000001',
        '2026-01-01 10:00:00+00',
        'auth',
        'user',
        'INSERT',
        'b0000000-0000-4000-8000-000000000001',
        'a0000000-0000-4000-8000-000000000001',
        NULL,
        '{"entity": "synthetic_user", "username": "mock.student.01", "email": "mock.student.01@synthetic.local", "role": "student", "status": "active"}'::jsonb
    ),
    (
        '00000000-0000-4000-8000-000000000002',
        '2026-01-01 10:01:00+00',
        'auth',
        'user',
        'UPDATE',
        'b0000000-0000-4000-8000-000000000001',
        'a0000000-0000-4000-8000-000000000002',
        '{"role": "student", "status": "pending"}'::jsonb,
        '{"role": "student", "status": "active"}'::jsonb
    ),
    (
        '00000000-0000-4000-8000-000000000003',
        '2026-01-01 10:02:00+00',
        'auth',
        'session_token',
        'DELETE',
        'b0000000-0000-4000-8000-000000000002',
        'a0000000-0000-4000-8000-000000000001',
        '{"session_token_id": "syn-token-expired-001", "revoked_at": "2026-01-01T10:02:00Z"}'::jsonb,
        NULL
    ),

    -- =========================================================================
    -- Dominio: academic_pi
    -- =========================================================================
    (
        '00000000-0000-4000-8000-000000000004',
        '2026-01-01 10:03:00+00',
        'academic_pi',
        'project',
        'INSERT',
        'b0000000-0000-4000-8000-000000000003',
        'a0000000-0000-4000-8000-000000000003',
        NULL,
        '{"project_code": "PI-2026-SYN-001", "title": "Synthetic AI Platform Architecture", "status": "draft"}'::jsonb
    ),
    (
        '00000000-0000-4000-8000-000000000005',
        '2026-01-01 10:04:00+00',
        'academic_pi',
        'project',
        'UPDATE',
        'b0000000-0000-4000-8000-000000000003',
        'a0000000-0000-4000-8000-000000000003',
        '{"status": "draft"}'::jsonb,
        '{"status": "submitted"}'::jsonb
    ),
    (
        '00000000-0000-4000-8000-000000000006',
        '2026-01-01 10:05:00+00',
        'academic_pi',
        'project_draft',
        'DELETE',
        'b0000000-0000-4000-8000-000000000004',
        'a0000000-0000-4000-8000-000000000003',
        '{"draft_code": "PI-DRAFT-TEMP-001", "reason": "superseded_by_submission"}'::jsonb,
        NULL
    ),

    -- =========================================================================
    -- Dominio: extension
    -- =========================================================================
    (
        '00000000-0000-4000-8000-000000000007',
        '2026-01-01 10:06:00+00',
        'extension',
        'community_action',
        'INSERT',
        'b0000000-0000-4000-8000-000000000005',
        'a0000000-0000-4000-8000-000000000004',
        NULL,
        '{"action_code": "EXT-2026-SYN-101", "name": "Synthetic Community Workshop", "target_audience": "regional_partner"}'::jsonb
    ),
    (
        '00000000-0000-4000-8000-000000000008',
        '2026-01-01 10:07:00+00',
        'extension',
        'community_action',
        'UPDATE',
        'b0000000-0000-4000-8000-000000000005',
        'a0000000-0000-4000-8000-000000000004',
        '{"approval_status": "in_review"}'::jsonb,
        '{"approval_status": "approved"}'::jsonb
    ),
    (
        '00000000-0000-4000-8000-000000000009',
        '2026-01-01 10:08:00+00',
        'extension',
        'action_prospect',
        'DELETE',
        'b0000000-0000-4000-8000-000000000006',
        'a0000000-0000-4000-8000-000000000004',
        '{"prospect_code": "EXT-PROSPECT-TEMP-001", "cancelled_reason": "duplicate_entry"}'::jsonb,
        NULL
    ),

    -- =========================================================================
    -- Dominio: assets
    -- =========================================================================
    (
        '00000000-0000-4000-8000-000000000010',
        '2026-01-01 10:09:00+00',
        'assets',
        'lab_equipment',
        'INSERT',
        'b0000000-0000-4000-8000-000000000007',
        'a0000000-0000-4000-8000-000000000005',
        NULL,
        '{"asset_tag": "SYN-ASSET-001", "equipment_type": "workstation_cluster", "room": "LAB-101", "status": "available"}'::jsonb
    ),
    (
        '00000000-0000-4000-8000-000000000011',
        '2026-01-01 10:10:00+00',
        'assets',
        'lab_equipment',
        'UPDATE',
        'b0000000-0000-4000-8000-000000000007',
        'a0000000-0000-4000-8000-000000000005',
        '{"status": "available"}'::jsonb,
        '{"status": "reserved_for_pi"}'::jsonb
    ),
    (
        '00000000-0000-4000-8000-000000000012',
        '2026-01-01 10:11:00+00',
        'assets',
        'asset_reservation',
        'DELETE',
        'b0000000-0000-4000-8000-000000000008',
        'a0000000-0000-4000-8000-000000000005',
        '{"reservation_id": "SYN-RES-TEMP-001", "status": "completed"}'::jsonb,
        NULL
    ),

    -- =========================================================================
    -- Dominio: institutional
    -- =========================================================================
    (
        '00000000-0000-4000-8000-000000000013',
        '2026-01-01 10:12:00+00',
        'institutional',
        'campus_unit',
        'INSERT',
        'b0000000-0000-4000-8000-000000000009',
        'a0000000-0000-4000-8000-000000000005',
        NULL,
        '{"unit_code": "SYN-SOR-01", "name": "Synthetic Sorocaba Center", "active": true}'::jsonb
    ),
    (
        '00000000-0000-4000-8000-000000000014',
        '2026-01-01 10:13:00+00',
        'institutional',
        'campus_unit',
        'UPDATE',
        'b0000000-0000-4000-8000-000000000009',
        'a0000000-0000-4000-8000-000000000005',
        '{"active": true, "capacity": 200}'::jsonb,
        '{"active": true, "capacity": 250}'::jsonb
    ),
    (
        '00000000-0000-4000-8000-000000000015',
        '2026-01-01 10:14:00+00',
        'institutional',
        'temporary_notice',
        'DELETE',
        'b0000000-0000-4000-8000-000000000010',
        'a0000000-0000-4000-8000-000000000005',
        '{"notice_id": "SYN-NOTICE-TEMP-001", "status": "archived"}'::jsonb,
        NULL
    )
ON CONFLICT (id) DO NOTHING;
