BEGIN;

CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS academic_pi;
CREATE SCHEMA IF NOT EXISTS extension;
CREATE SCHEMA IF NOT EXISTS assets;
CREATE SCHEMA IF NOT EXISTS institutional;

CREATE TABLE IF NOT EXISTS public.schema_migration (
    version varchar(20) PRIMARY KEY,
    description text NOT NULL,
    applied_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.schema_migration (version, description)
VALUES ('V0001', 'create domain schemas')
ON CONFLICT (version) DO NOTHING;

COMMIT;
