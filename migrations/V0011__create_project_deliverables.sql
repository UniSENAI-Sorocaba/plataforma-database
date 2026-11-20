-- Migration: V0011 - Entregáveis e metadados de upload (F3)
BEGIN;

CREATE TABLE IF NOT EXISTS academic_pi.deliverable (
    id uuid PRIMARY KEY,
    project_id uuid NOT NULL,
    period_id uuid NOT NULL,
    owner_id uuid NOT NULL,
    original_filename varchar(255) NOT NULL,
    content_type varchar(120) NOT NULL,
    size_bytes bigint NOT NULL,
    sha256 varchar(64),
    storage_key varchar(255) NOT NULL UNIQUE,
    version integer NOT NULL DEFAULT 1,
    status varchar(24) NOT NULL DEFAULT 'PENDING_UPLOAD',
    upload_token_hash varchar(64) NOT NULL UNIQUE,
    upload_expires_at timestamptz NOT NULL,
    download_token_hash varchar(64) UNIQUE,
    download_expires_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    uploaded_at timestamptz,
    cancelled_at timestamptz,

    CONSTRAINT deliverable_period_fk FOREIGN KEY (project_id, period_id)
        REFERENCES academic_pi.enrollment_period (project_id, id) ON DELETE RESTRICT,
    CONSTRAINT deliverable_owner_fk FOREIGN KEY (project_id, period_id, owner_id)
        REFERENCES academic_pi.project_participant (project_id, period_id, student_id) ON DELETE RESTRICT,
    CONSTRAINT deliverable_filename_ck CHECK (length(trim(original_filename)) BETWEEN 1 AND 255),
    CONSTRAINT deliverable_content_type_ck CHECK (length(trim(content_type)) BETWEEN 3 AND 120),
    CONSTRAINT deliverable_size_ck CHECK (size_bytes > 0 AND size_bytes <= 26214400),
    CONSTRAINT deliverable_sha256_ck CHECK (sha256 IS NULL OR sha256 ~ '^[0-9a-f]{64}$'),
    CONSTRAINT deliverable_version_ck CHECK (version > 0),
    CONSTRAINT deliverable_status_ck CHECK (status IN ('PENDING_UPLOAD', 'AVAILABLE', 'CANCELLED', 'EXPIRED')),
    CONSTRAINT deliverable_upload_state_ck CHECK (
        (status = 'PENDING_UPLOAD' AND sha256 IS NULL AND uploaded_at IS NULL AND cancelled_at IS NULL)
        OR (status = 'AVAILABLE' AND sha256 IS NOT NULL AND uploaded_at IS NOT NULL AND cancelled_at IS NULL)
        OR (status IN ('CANCELLED', 'EXPIRED') AND cancelled_at IS NOT NULL)
    ),
    CONSTRAINT deliverable_download_state_ck CHECK (
        (download_token_hash IS NULL AND download_expires_at IS NULL)
        OR (download_token_hash IS NOT NULL AND download_expires_at IS NOT NULL)
    )
);

CREATE INDEX IF NOT EXISTS idx_deliverable_project_period
    ON academic_pi.deliverable (project_id, period_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_deliverable_owner
    ON academic_pi.deliverable (owner_id, status, created_at DESC);

INSERT INTO public.schema_migration (version, description)
VALUES ('V0011', 'create project deliverables and upload metadata')
ON CONFLICT (version) DO NOTHING;

COMMIT;
