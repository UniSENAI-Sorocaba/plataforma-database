-- Migration: V0016 - Certificados públicos verificáveis (F4/T18)
BEGIN;

CREATE TABLE IF NOT EXISTS extension.certificate (
    id uuid PRIMARY KEY,
    public_code varchar(64) NOT NULL UNIQUE,
    project_id uuid NOT NULL,
    period_id uuid NOT NULL,
    student_id uuid NOT NULL,
    content_hash char(64) NOT NULL,
    status varchar(16) NOT NULL DEFAULT 'ACTIVE',
    issued_by uuid NOT NULL REFERENCES auth."user" (id) ON DELETE RESTRICT,
    issued_at timestamptz NOT NULL DEFAULT now(),
    revoked_at timestamptz,
    revocation_reason varchar(1000),
    CONSTRAINT certificate_participant_fk FOREIGN KEY (project_id, period_id, student_id)
        REFERENCES academic_pi.project_participant (project_id, period_id, student_id) ON DELETE RESTRICT,
    CONSTRAINT certificate_hash_ck CHECK (content_hash ~ '^[0-9a-f]{64}$'),
    CONSTRAINT certificate_status_ck CHECK (status IN ('ACTIVE', 'REVOKED')),
    CONSTRAINT certificate_revocation_ck CHECK ((status = 'ACTIVE' AND revoked_at IS NULL AND revocation_reason IS NULL) OR (status = 'REVOKED' AND revoked_at IS NOT NULL AND length(trim(revocation_reason)) >= 3))
);

CREATE UNIQUE INDEX IF NOT EXISTS uk_certificate_participant
    ON extension.certificate (project_id, period_id, student_id);

INSERT INTO public.schema_migration (version, description)
VALUES ('V0016', 'create public verifiable extension certificates')
ON CONFLICT (version) DO NOTHING;

COMMIT;
