BEGIN;

-- =============================================================================
-- Schema: auth
-- =============================================================================

-- 1. auth.user_session: Armazenamento e ciclo de vida de sessoes e refresh tokens
CREATE TABLE IF NOT EXISTS auth.user_session (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL,
    token_hash varchar(64) NOT NULL,
    family_id uuid NOT NULL,
    replaced_by_token_id uuid,
    client_ip varchar(45),
    user_agent text,
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    revoked_at timestamptz,
    last_used_at timestamptz,

    CONSTRAINT user_session_user_fk
        FOREIGN KEY (user_id)
        REFERENCES auth.user (id)
        ON DELETE CASCADE,

    CONSTRAINT user_session_replaced_by_token_fk
        FOREIGN KEY (replaced_by_token_id)
        REFERENCES auth.user_session (id)
        ON DELETE SET NULL,

    CONSTRAINT user_session_token_hash_ck
        CHECK (token_hash <> '' AND length(token_hash) = 64),

    CONSTRAINT user_session_expires_at_ck
        CHECK (expires_at > created_at),

    CONSTRAINT user_session_token_hash_unq
        UNIQUE (token_hash)
);

-- 2. Indices de desempenho
CREATE INDEX IF NOT EXISTS idx_user_session_user_id
    ON auth.user_session (user_id);

CREATE INDEX IF NOT EXISTS idx_user_session_family_id
    ON auth.user_session (family_id);

CREATE INDEX IF NOT EXISTS idx_user_session_active_lookup
    ON auth.user_session (user_id, expires_at)
    WHERE revoked_at IS NULL;

-- 3. Registro formal no catalogo de migrations
INSERT INTO public.schema_migration (version, description)
VALUES ('V0004', 'create user session')
ON CONFLICT (version) DO NOTHING;

COMMIT;
