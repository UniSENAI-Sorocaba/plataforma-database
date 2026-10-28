-- Migration: V0006 - Implementação do modelo de Papéis, Permissões e Escopos (DB-006)
BEGIN;

-- 1. Tabela de Papéis (Roles)
CREATE TABLE IF NOT EXISTS roles (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE,
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 2. Tabela de Permissões (Ações x Recursos)
CREATE TABLE IF NOT EXISTS permissions (
    id SERIAL PRIMARY KEY,
    action VARCHAR(50) NOT NULL,
    resource VARCHAR(50) NOT NULL,
    description TEXT,
    CONSTRAINT uk_permissions_action_resource UNIQUE (action, resource)
);

-- 3. Associação entre Papéis e Permissões (N:N)
CREATE TABLE IF NOT EXISTS role_permissions (
    role_id INT NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    permission_id INT NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

-- 4. Atribuição de Papéis aos Usuários com Escopo
CREATE TABLE IF NOT EXISTS user_roles (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL,
    role_id INT NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    scope_type VARCHAR(30) NOT NULL DEFAULT 'GLOBAL',
    scope_id VARCHAR(100) NOT NULL DEFAULT '*',
    assigned_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    assigned_by UUID,

    -- CONSTRAINT CRÍTICA: Bloqueia duplicidade de papel no mesmo escopo
    CONSTRAINT uk_user_role_scope UNIQUE (user_id, role_id, scope_type, scope_id)
);

-- Índices de consulta rápida
CREATE INDEX IF NOT EXISTS idx_user_roles_lookup 
    ON user_roles(user_id, scope_type, scope_id);

CREATE INDEX IF NOT EXISTS idx_role_permissions_role 
    ON role_permissions(role_id);

COMMIT;