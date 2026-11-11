-- Migration: V0006 - Implementacao do modelo de Papeis, Permissoes e Escopos (DB-006)
BEGIN;

-- 1. Tabela de Papeis (Roles)
CREATE TABLE IF NOT EXISTS roles (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE,
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT roles_name_ck
        CHECK (length(trim(name)) > 0)
);

-- 2. Tabela de Permissoes (Acoes x Recursos)
CREATE TABLE IF NOT EXISTS permissions (
    id SERIAL PRIMARY KEY,
    action VARCHAR(50) NOT NULL,
    resource VARCHAR(50) NOT NULL,
    description TEXT,

    CONSTRAINT permissions_action_ck
        CHECK (length(trim(action)) > 0),

    CONSTRAINT permissions_resource_ck
        CHECK (length(trim(resource)) > 0),

    CONSTRAINT uk_permissions_action_resource
        UNIQUE (action, resource)
);

-- 3. Associacao entre Papeis e Permissoes (N:N)
CREATE TABLE IF NOT EXISTS role_permissions (
    role_id INT NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    permission_id INT NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

-- 4. Atribuicao de Papeis aos Usuarios com Escopo
CREATE TABLE IF NOT EXISTS user_roles (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL,
    role_id INT NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    scope_type VARCHAR(30) NOT NULL DEFAULT 'GLOBAL',
    scope_id VARCHAR(100) NOT NULL DEFAULT '*',
    assigned_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    assigned_by UUID,

    CONSTRAINT user_roles_user_fk
        FOREIGN KEY (user_id)
        REFERENCES auth."user" (id)
        ON DELETE CASCADE,

    CONSTRAINT user_roles_assigned_by_fk
        FOREIGN KEY (assigned_by)
        REFERENCES auth."user" (id)
        ON DELETE SET NULL,

    CONSTRAINT user_roles_scope_type_ck
        CHECK (scope_type IN ('GLOBAL', 'PROJETO', 'TURMA', 'CURSO')),

    CONSTRAINT user_roles_scope_id_ck
        CHECK (length(trim(scope_id)) > 0),

    CONSTRAINT user_roles_scope_consistency_ck
        CHECK (
            (scope_type = 'GLOBAL' AND scope_id = '*')
            OR (scope_type <> 'GLOBAL' AND scope_id <> '*')
        ),

    -- CONSTRAINT CRITICA: Bloqueia duplicidade de papel no mesmo escopo
    CONSTRAINT uk_user_role_scope
        UNIQUE (user_id, role_id, scope_type, scope_id)
);

-- Diagnostico previo para upgrade incremental: garante ausencia de registros orfaos em user_roles
DO $$
DECLARE
    orphan_users bigint;
    orphan_assigners bigint;
BEGIN
    SELECT count(*) INTO orphan_users
    FROM user_roles ur
    LEFT JOIN auth."user" u ON u.id = ur.user_id
    WHERE u.id IS NULL;

    SELECT count(*) INTO orphan_assigners
    FROM user_roles ur
    LEFT JOIN auth."user" u ON u.id = ur.assigned_by
    WHERE ur.assigned_by IS NOT NULL
      AND u.id IS NULL;

    IF orphan_users > 0 OR orphan_assigners > 0 THEN
        RAISE EXCEPTION 'V0006 bloqueada: % atribuicao(oes) com user_id orfao e % com assigned_by orfao em user_roles.',
            orphan_users, orphan_assigners;
    END IF;
END $$;

-- Aplicacao idempotente de constraints e FKs caso as tabelas ja existam de execucao anterior
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'roles_name_ck'
          AND conrelid = 'public.roles'::regclass
    ) THEN
        ALTER TABLE roles
            ADD CONSTRAINT roles_name_ck
            CHECK (length(trim(name)) > 0);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'permissions_action_ck'
          AND conrelid = 'public.permissions'::regclass
    ) THEN
        ALTER TABLE permissions
            ADD CONSTRAINT permissions_action_ck
            CHECK (length(trim(action)) > 0);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'permissions_resource_ck'
          AND conrelid = 'public.permissions'::regclass
    ) THEN
        ALTER TABLE permissions
            ADD CONSTRAINT permissions_resource_ck
            CHECK (length(trim(resource)) > 0);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'user_roles_user_fk'
          AND conrelid = 'public.user_roles'::regclass
    ) THEN
        ALTER TABLE user_roles
            ADD CONSTRAINT user_roles_user_fk
            FOREIGN KEY (user_id)
            REFERENCES auth."user" (id)
            ON DELETE CASCADE;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'user_roles_assigned_by_fk'
          AND conrelid = 'public.user_roles'::regclass
    ) THEN
        ALTER TABLE user_roles
            ADD CONSTRAINT user_roles_assigned_by_fk
            FOREIGN KEY (assigned_by)
            REFERENCES auth."user" (id)
            ON DELETE SET NULL;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'user_roles_scope_type_ck'
          AND conrelid = 'public.user_roles'::regclass
    ) THEN
        ALTER TABLE user_roles
            ADD CONSTRAINT user_roles_scope_type_ck
            CHECK (scope_type IN ('GLOBAL', 'PROJETO', 'TURMA', 'CURSO'));
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'user_roles_scope_id_ck'
          AND conrelid = 'public.user_roles'::regclass
    ) THEN
        ALTER TABLE user_roles
            ADD CONSTRAINT user_roles_scope_id_ck
            CHECK (length(trim(scope_id)) > 0);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'user_roles_scope_consistency_ck'
          AND conrelid = 'public.user_roles'::regclass
    ) THEN
        ALTER TABLE user_roles
            ADD CONSTRAINT user_roles_scope_consistency_ck
            CHECK (
                (scope_type = 'GLOBAL' AND scope_id = '*')
                OR (scope_type <> 'GLOBAL' AND scope_id <> '*')
            );
    END IF;
END $$;

-- Indices de consulta rapida
CREATE INDEX IF NOT EXISTS idx_user_roles_lookup
    ON user_roles (user_id, scope_type, scope_id);

CREATE INDEX IF NOT EXISTS idx_user_roles_role_id
    ON user_roles (role_id);

CREATE INDEX IF NOT EXISTS idx_role_permissions_role
    ON role_permissions (role_id);

CREATE INDEX IF NOT EXISTS idx_role_permissions_permission
    ON role_permissions (permission_id);

-- Registro formal no catalogo de migrations
INSERT INTO public.schema_migration (version, description)
VALUES ('V0006', 'create rbac schema')
ON CONFLICT (version) DO NOTHING;

COMMIT;
