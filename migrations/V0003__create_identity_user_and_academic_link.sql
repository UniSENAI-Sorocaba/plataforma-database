BEGIN;

-- =============================================================================
-- Schema: auth
-- =============================================================================

-- 1. auth.user: Conta central de usuario
CREATE TABLE IF NOT EXISTS auth.user (
    id uuid PRIMARY KEY,
    email varchar(255) NOT NULL,
    full_name varchar(255) NOT NULL,
    cpf varchar(11),
    password_hash varchar(255),
    status varchar(20) NOT NULL DEFAULT 'pending',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT user_email_ck
        CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),

    CONSTRAINT user_full_name_ck
        CHECK (full_name <> '' AND length(trim(full_name)) >= 2),

    CONSTRAINT user_cpf_ck
        CHECK (cpf IS NULL OR cpf ~ '^[0-9]{11}$'),

    CONSTRAINT user_password_hash_ck
        CHECK (password_hash IS NULL OR password_hash <> ''),

    CONSTRAINT user_status_ck
        CHECK (status IN ('pending', 'active', 'inactive', 'suspended')),

    CONSTRAINT user_email_unq
        UNIQUE (email),

    CONSTRAINT user_cpf_unq
        UNIQUE (cpf)
);

CREATE INDEX IF NOT EXISTS idx_user_email
    ON auth.user (email);

CREATE INDEX IF NOT EXISTS idx_user_status
    ON auth.user (status);

CREATE INDEX IF NOT EXISTS idx_user_cpf
    ON auth.user (cpf);

-- 2. auth.user_identity: Identidade institucional e federada (OIDC / OAuth2)
CREATE TABLE IF NOT EXISTS auth.user_identity (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL,
    provider varchar(50) NOT NULL,
    provider_subject varchar(255) NOT NULL,
    email varchar(255),
    last_authenticated_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT user_identity_user_fk
        FOREIGN KEY (user_id)
        REFERENCES auth.user (id)
        ON DELETE CASCADE,

    CONSTRAINT user_identity_provider_ck
        CHECK (provider <> ''),

    CONSTRAINT user_identity_provider_subject_ck
        CHECK (provider_subject <> ''),

    CONSTRAINT user_identity_email_ck
        CHECK (email IS NULL OR (email <> '' AND position('@' in email) > 1)),

    CONSTRAINT user_identity_provider_subject_unq
        UNIQUE (provider, provider_subject)
);

CREATE INDEX IF NOT EXISTS idx_user_identity_user_id
    ON auth.user_identity (user_id);

CREATE INDEX IF NOT EXISTS idx_user_identity_provider_subject
    ON auth.user_identity (provider, provider_subject);

-- =============================================================================
-- Schema: institutional
-- =============================================================================

-- 3. institutional.academic_class: Turma / agrupamento academico
CREATE TABLE IF NOT EXISTS institutional.academic_class (
    id uuid PRIMARY KEY,
    code varchar(50) NOT NULL,
    name varchar(255) NOT NULL,
    term varchar(20) NOT NULL,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT academic_class_code_ck
        CHECK (code <> ''),

    CONSTRAINT academic_class_name_ck
        CHECK (name <> ''),

    CONSTRAINT academic_class_term_ck
        CHECK (term <> ''),

    CONSTRAINT academic_class_code_unq
        UNIQUE (code)
);

CREATE INDEX IF NOT EXISTS idx_academic_class_code
    ON institutional.academic_class (code);

CREATE INDEX IF NOT EXISTS idx_academic_class_term
    ON institutional.academic_class (term);

CREATE INDEX IF NOT EXISTS idx_academic_class_is_active
    ON institutional.academic_class (is_active);

-- 4. institutional.academic_link: Vinculo do usuario com turma/instituicao
CREATE TABLE IF NOT EXISTS institutional.academic_link (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL,
    class_id uuid NOT NULL,
    role varchar(30) NOT NULL DEFAULT 'student',
    registration_number varchar(50),
    status varchar(20) NOT NULL DEFAULT 'active',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT academic_link_user_fk
        FOREIGN KEY (user_id)
        REFERENCES auth.user (id)
        ON DELETE CASCADE,

    CONSTRAINT academic_link_class_fk
        FOREIGN KEY (class_id)
        REFERENCES institutional.academic_class (id)
        ON DELETE RESTRICT,

    CONSTRAINT academic_link_role_ck
        CHECK (role IN ('student', 'professor', 'coordinator')),

    CONSTRAINT academic_link_registration_number_ck
        CHECK (registration_number IS NULL OR registration_number <> ''),

    CONSTRAINT academic_link_status_ck
        CHECK (status IN ('active', 'inactive', 'completed', 'dropped')),

    CONSTRAINT academic_link_user_class_role_unq
        UNIQUE (user_id, class_id, role)
);

CREATE INDEX IF NOT EXISTS idx_academic_link_user_id
    ON institutional.academic_link (user_id);

CREATE INDEX IF NOT EXISTS idx_academic_link_class_id
    ON institutional.academic_link (class_id);

CREATE INDEX IF NOT EXISTS idx_academic_link_status
    ON institutional.academic_link (status);

-- =============================================================================
-- Migration record
-- =============================================================================

INSERT INTO public.schema_migration (version, description)
VALUES ('V0003', 'create identity user and academic link')
ON CONFLICT (version) DO NOTHING;

COMMIT;
