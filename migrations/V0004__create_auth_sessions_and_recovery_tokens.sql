BEGIN;

-- Sessao autenticada e familia de refresh tokens. O banco armazena somente
-- hashes de tokens opacos; o valor apresentado ao cliente nunca e persistido.
CREATE TABLE IF NOT EXISTS auth.session (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL,
    family_id uuid NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'active',
    created_at timestamptz NOT NULL DEFAULT now(),
    last_seen_at timestamptz,
    expires_at timestamptz NOT NULL,
    revoked_at timestamptz,
    revoked_reason varchar(30),

    CONSTRAINT session_user_fk
        FOREIGN KEY (user_id)
        REFERENCES auth.user (id)
        ON DELETE CASCADE,

    CONSTRAINT session_status_ck
        CHECK (status IN ('active', 'revoked', 'expired')),

    CONSTRAINT session_dates_ck
        CHECK (expires_at > created_at),

    CONSTRAINT session_last_seen_ck
        CHECK (last_seen_at IS NULL OR last_seen_at >= created_at),

    CONSTRAINT session_revocation_ck
        CHECK ((status = 'active' AND revoked_at IS NULL AND revoked_reason IS NULL)
            OR (status IN ('revoked', 'expired') AND revoked_at IS NOT NULL)),

    CONSTRAINT session_revoked_reason_ck
        CHECK (revoked_reason IS NULL OR revoked_reason IN ('logout', 'reuse', 'expired', 'security'))
);

CREATE INDEX IF NOT EXISTS idx_session_user_status
    ON auth.session (user_id, status);

CREATE INDEX IF NOT EXISTS idx_session_family_id
    ON auth.session (family_id);

CREATE INDEX IF NOT EXISTS idx_session_expiration
    ON auth.session (expires_at)
    WHERE status = 'active';

CREATE TABLE IF NOT EXISTS auth.refresh_token (
    id uuid PRIMARY KEY,
    session_id uuid NOT NULL,
    family_id uuid NOT NULL,
    token_hash varchar(255) NOT NULL,
    issued_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    used_at timestamptz,
    revoked_at timestamptz,
    replaced_by_id uuid,

    CONSTRAINT refresh_token_session_fk
        FOREIGN KEY (session_id)
        REFERENCES auth.session (id)
        ON DELETE CASCADE,

    CONSTRAINT refresh_token_replaced_by_fk
        FOREIGN KEY (replaced_by_id)
        REFERENCES auth.refresh_token (id)
        ON DELETE SET NULL,

    CONSTRAINT refresh_token_hash_ck
        CHECK (length(trim(token_hash)) >= 64),

    CONSTRAINT refresh_token_dates_ck
        CHECK (expires_at > issued_at),

    CONSTRAINT refresh_token_lifecycle_ck
        CHECK (used_at IS NULL OR used_at >= issued_at),

    CONSTRAINT refresh_token_hash_unq
        UNIQUE (token_hash)
);

CREATE INDEX IF NOT EXISTS idx_refresh_token_session
    ON auth.refresh_token (session_id, issued_at DESC);

CREATE INDEX IF NOT EXISTS idx_refresh_token_family
    ON auth.refresh_token (family_id);

CREATE INDEX IF NOT EXISTS idx_refresh_token_expiration
    ON auth.refresh_token (expires_at)
    WHERE used_at IS NULL AND revoked_at IS NULL;

CREATE TABLE IF NOT EXISTS auth.password_recovery_token (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL,
    token_hash varchar(255) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    used_at timestamptz,
    revoked_at timestamptz,

    CONSTRAINT password_recovery_user_fk
        FOREIGN KEY (user_id)
        REFERENCES auth.user (id)
        ON DELETE CASCADE,

    CONSTRAINT password_recovery_hash_ck
        CHECK (length(trim(token_hash)) >= 64),

    CONSTRAINT password_recovery_dates_ck
        CHECK (expires_at > created_at),

    CONSTRAINT password_recovery_lifecycle_ck
        CHECK ((used_at IS NULL OR used_at >= created_at)
            AND (revoked_at IS NULL OR revoked_at >= created_at)),

    CONSTRAINT password_recovery_hash_unq
        UNIQUE (token_hash)
);

CREATE INDEX IF NOT EXISTS idx_password_recovery_user
    ON auth.password_recovery_token (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_password_recovery_expiration
    ON auth.password_recovery_token (expires_at)
    WHERE used_at IS NULL AND revoked_at IS NULL;

INSERT INTO public.schema_migration (version, description)
VALUES ('V0004', 'create auth sessions and recovery tokens')
ON CONFLICT (version) DO NOTHING;

COMMIT;
