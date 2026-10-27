-- Seeds sintéticas: PG-006 / SPEC-AUTH-003 (DB-006)
BEGIN;

-- Papéis Iniciais
INSERT INTO roles (name, description) VALUES
    ('COORDENACAO', 'Gestão de usuários, turmas, cursos e permissões'),
    ('DOCENTE', 'Criação e gestão de projetos, aprovação de participantes e validação de horas'),
    ('ALUNO', 'Participação em projetos e submissão de atividades')
ON CONFLICT (name) DO NOTHING;

-- Permissões Essenciais
INSERT INTO permissions (action, resource, description) VALUES
    ('MANAGE', 'USER', 'Cadastrar, inativar e gerenciar usuários'),
    ('MANAGE', 'ROLE', 'Atribuir e revogar papéis'),
    ('CREATE', 'PROJECT', 'Cadastrar propostas de projetos'),
    ('MANAGE_MEMBERS', 'PROJECT', 'Aprovar ou remover participantes de projetos'),
    ('VALIDATE_HOURS', 'PROJECT', 'Validar e aprovar horas de extensão'),
    ('EVALUATE', 'PROJECT', 'Lançar notas e fichas de avaliação'),
    ('SUBMIT', 'ACTIVITY', 'Enviar entregas e arquivos de relatórios')
ON CONFLICT (action, resource) DO NOTHING;

-- Permissões da COORDENACAO
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p
WHERE r.name = 'COORDENACAO' 
  AND p.resource IN ('USER', 'ROLE')
ON CONFLICT DO NOTHING;

-- Permissões do DOCENTE
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p
WHERE r.name = 'DOCENTE' 
  AND (p.resource = 'PROJECT' OR (p.action = 'EVALUATE' AND p.resource = 'PROJECT'))
ON CONFLICT DO NOTHING;

-- Permissões do ALUNO
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p
WHERE r.name = 'ALUNO' 
  AND p.action = 'SUBMIT' AND p.resource = 'ACTIVITY'
ON CONFLICT DO NOTHING;

COMMIT;