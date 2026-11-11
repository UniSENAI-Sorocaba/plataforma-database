-- Seeds sinteticos deterministicos para roles, permissions, role_permissions e user_roles (DB-006)
-- Idempotente via ON CONFLICT DO NOTHING
-- Estritamente sintetico, sem dados pessoais reais (alinhado a seeds/README.md, ADR-011, DB-003, DB-004 e DB-006 / SPEC-AUTH-003)

BEGIN;

-- =============================================================================
-- 1. roles (Papeis Iniciais)
-- =============================================================================
INSERT INTO roles (name, description, created_at)
VALUES
    ('COORDENACAO', 'Gestao de usuarios, turmas, cursos e permissoes', '2026-01-01 10:00:00+00'),
    ('DOCENTE', 'Criacao e gestao de projetos, aprovacao de participantes e validacao de horas', '2026-01-01 10:00:00+00'),
    ('ALUNO', 'Participacao em projetos e submissao de atividades', '2026-01-01 10:00:00+00')
ON CONFLICT (name) DO NOTHING;

-- =============================================================================
-- 2. permissions (Permissoes Essenciais - Acoes x Recursos)
-- =============================================================================
INSERT INTO permissions (action, resource, description)
VALUES
    ('MANAGE', 'USER', 'Cadastrar, inativar e gerenciar usuarios'),
    ('MANAGE', 'ROLE', 'Atribuir e revogar papeis'),
    ('CREATE', 'PROJECT', 'Cadastrar propostas de projetos'),
    ('MANAGE_MEMBERS', 'PROJECT', 'Aprovar ou remover participantes de projetos'),
    ('VALIDATE_HOURS', 'PROJECT', 'Validar e aprovar horas de extensao'),
    ('EVALUATE', 'PROJECT', 'Lancar notas e fichas de avaliacao'),
    ('SUBMIT', 'ACTIVITY', 'Enviar entregas e arquivos de relatorios')
ON CONFLICT (action, resource) DO NOTHING;

-- =============================================================================
-- 3. role_permissions (Matriz de Permissoes por Papel)
-- =============================================================================

-- Permissoes da COORDENACAO
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
WHERE r.name = 'COORDENACAO'
  AND p.resource IN ('USER', 'ROLE')
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Permissoes do DOCENTE
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
WHERE r.name = 'DOCENTE'
  AND p.resource = 'PROJECT'
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Permissoes do ALUNO
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
WHERE r.name = 'ALUNO'
  AND p.action = 'SUBMIT'
  AND p.resource = 'ACTIVITY'
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- =============================================================================
-- 4. user_roles (Atribuicoes Sinteticas com Suporte a Escopo e Acumulo de Papeis)
-- =============================================================================

-- 4.1 Coordenador mock (b0000000-0000-4000-8000-000000000003):
-- Possui COORDENACAO global e tambem acumula DOCENTE em escopo de projeto (AC-AUTH-003-01)
INSERT INTO user_roles (user_id, role_id, scope_type, scope_id, assigned_at, assigned_by)
SELECT
    'b0000000-0000-4000-8000-000000000003'::uuid,
    r.id,
    'GLOBAL',
    '*',
    '2026-01-01 10:00:00+00'::timestamptz,
    'b0000000-0000-4000-8000-000000000003'::uuid
FROM roles r
WHERE r.name = 'COORDENACAO'
ON CONFLICT (user_id, role_id, scope_type, scope_id) DO NOTHING;

INSERT INTO user_roles (user_id, role_id, scope_type, scope_id, assigned_at, assigned_by)
SELECT
    'b0000000-0000-4000-8000-000000000003'::uuid,
    r.id,
    'PROJETO',
    'b0000000-0000-4000-8000-000000000101',
    '2026-01-01 10:00:00+00'::timestamptz,
    'b0000000-0000-4000-8000-000000000003'::uuid
FROM roles r
WHERE r.name = 'DOCENTE'
ON CONFLICT (user_id, role_id, scope_type, scope_id) DO NOTHING;

-- 4.2 Docente mock (b0000000-0000-4000-8000-000000000002):
-- Possui DOCENTE global (para criacao de propostas) e escopo em projeto especifico (AC-AUTH-003-03)
INSERT INTO user_roles (user_id, role_id, scope_type, scope_id, assigned_at, assigned_by)
SELECT
    'b0000000-0000-4000-8000-000000000002'::uuid,
    r.id,
    'GLOBAL',
    '*',
    '2026-01-01 10:00:00+00'::timestamptz,
    'b0000000-0000-4000-8000-000000000003'::uuid
FROM roles r
WHERE r.name = 'DOCENTE'
ON CONFLICT (user_id, role_id, scope_type, scope_id) DO NOTHING;

INSERT INTO user_roles (user_id, role_id, scope_type, scope_id, assigned_at, assigned_by)
SELECT
    'b0000000-0000-4000-8000-000000000002'::uuid,
    r.id,
    'PROJETO',
    'b0000000-0000-4000-8000-000000000101',
    '2026-01-01 10:00:00+00'::timestamptz,
    'b0000000-0000-4000-8000-000000000003'::uuid
FROM roles r
WHERE r.name = 'DOCENTE'
ON CONFLICT (user_id, role_id, scope_type, scope_id) DO NOTHING;

-- 4.3 Estudante mock (b0000000-0000-4000-8000-000000000001):
-- Possui ALUNO escopado em multiplas turmas e em projeto (AC-AUTH-003-05)
INSERT INTO user_roles (user_id, role_id, scope_type, scope_id, assigned_at, assigned_by)
SELECT
    'b0000000-0000-4000-8000-000000000001'::uuid,
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
    'b0000000-0000-4000-8000-000000000001'::uuid,
    r.id,
    'TURMA',
    'c0000000-0000-4000-8000-000000000002',
    '2026-01-01 10:00:00+00'::timestamptz,
    'b0000000-0000-4000-8000-000000000003'::uuid
FROM roles r
WHERE r.name = 'ALUNO'
ON CONFLICT (user_id, role_id, scope_type, scope_id) DO NOTHING;

INSERT INTO user_roles (user_id, role_id, scope_type, scope_id, assigned_at, assigned_by)
SELECT
    'b0000000-0000-4000-8000-000000000001'::uuid,
    r.id,
    'PROJETO',
    'b0000000-0000-4000-8000-000000000101',
    '2026-01-01 10:00:00+00'::timestamptz,
    'b0000000-0000-4000-8000-000000000003'::uuid
FROM roles r
WHERE r.name = 'ALUNO'
ON CONFLICT (user_id, role_id, scope_type, scope_id) DO NOTHING;

COMMIT;
