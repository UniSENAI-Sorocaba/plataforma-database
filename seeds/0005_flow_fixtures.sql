-- Fixtures determinísticos para os fluxos E2E integrados (sem dados reais).
BEGIN;

INSERT INTO auth."user" (id, email, full_name, cpf, password_hash, status, created_at, updated_at)
VALUES ('b0000000-0000-4000-8000-000000000006', 'mock.admin.01@synthetic.local', 'Mock Admin One', '00000000604', NULL, 'active', '2026-01-01 10:00:00+00', '2026-01-01 10:00:00+00')
ON CONFLICT (id) DO NOTHING;

INSERT INTO roles (name, description, created_at)
VALUES ('ADMIN', 'Administracao tecnica da plataforma', '2026-01-01 10:00:00+00')
ON CONFLICT (name) DO NOTHING;

INSERT INTO user_roles (user_id, role_id, scope_type, scope_id, assigned_at, assigned_by)
SELECT 'b0000000-0000-4000-8000-000000000006'::uuid, r.id, 'GLOBAL', '*', '2026-01-01 10:00:00+00', 'b0000000-0000-4000-8000-000000000006'::uuid
FROM roles r WHERE r.name = 'ADMIN'
ON CONFLICT (user_id, role_id, scope_type, scope_id) DO NOTHING;

INSERT INTO academic_pi.project (
    id, title, summary, description, classification, continuity, end_date,
    publication_status, lifecycle_status, created_by, created_at, updated_at
)
VALUES (
    'b0000000-0000-4000-8000-000000000101',
    'Laboratorio Comunitario de Prototipagem',
    'Projeto integrador sintético para validar jornadas acadêmicas e comunitárias.',
    'Projeto sintético de teste para participação, entregas, atividades, horas e avaliações da Plataforma Digital.',
    'BOTH', 'FIXED_END', '2027-06-30', 'PUBLISHED', 'ACTIVE',
    'b0000000-0000-4000-8000-000000000003', '2026-01-01 10:00:00+00', '2026-01-01 10:00:00+00'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO academic_pi.project_responsible (project_id, user_id, assigned_at)
VALUES ('b0000000-0000-4000-8000-000000000101', 'b0000000-0000-4000-8000-000000000002', '2026-01-01 10:00:00+00')
ON CONFLICT (project_id, user_id) DO NOTHING;

INSERT INTO academic_pi.enrollment_period (id, project_id, academic_term, starts_at, ends_at, created_by, created_at, updated_at)
VALUES ('c0000000-0000-4000-8000-000000000101', 'b0000000-0000-4000-8000-000000000101', '2026.2', '2026-11-01 00:00:00+00', '2026-12-31 23:59:59+00', 'b0000000-0000-4000-8000-000000000003', '2026-01-01 10:00:00+00', '2026-01-01 10:00:00+00')
ON CONFLICT (id) DO NOTHING;

INSERT INTO academic_pi.participation_request (id, project_id, period_id, student_id, status, requested_at, decided_at, decided_by)
VALUES ('d0000000-0000-4000-8000-000000000101', 'b0000000-0000-4000-8000-000000000101', 'c0000000-0000-4000-8000-000000000101', 'b0000000-0000-4000-8000-000000000001', 'APPROVED', '2026-11-02 10:00:00+00', '2026-11-03 10:00:00+00', 'b0000000-0000-4000-8000-000000000002')
ON CONFLICT (id) DO NOTHING;

INSERT INTO academic_pi.project_participant (project_id, period_id, student_id, status, joined_at)
VALUES ('b0000000-0000-4000-8000-000000000101', 'c0000000-0000-4000-8000-000000000101', 'b0000000-0000-4000-8000-000000000001', 'ACTIVE', '2026-11-03 10:00:00+00')
ON CONFLICT (project_id, period_id, student_id) DO NOTHING;

INSERT INTO extension.opportunity (id, project_id, title, description, status, starts_at, ends_at, created_by, published_at, created_at, updated_at)
VALUES ('b0000000-0000-4000-8000-000000000401', 'b0000000-0000-4000-8000-000000000101', 'Oficinas de Prototipagem Comunitária', 'Oportunidade sintética para validar inscrição única em edital publicado.', 'PUBLISHED', '2026-11-01 00:00:00+00', '2026-12-31 23:59:59+00', 'b0000000-0000-4000-8000-000000000003', '2026-11-01 00:00:00+00', '2026-01-01 10:00:00+00', '2026-01-01 10:00:00+00')
ON CONFLICT (id) DO NOTHING;

COMMIT;
