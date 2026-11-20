-- Migration: V0012 - Editais de Extensão e inscrições (F4/T14)
BEGIN;

CREATE TABLE IF NOT EXISTS extension.opportunity (
    id uuid PRIMARY KEY,
    project_id uuid,
    title varchar(200) NOT NULL,
    description varchar(5000) NOT NULL,
    status varchar(16) NOT NULL DEFAULT 'DRAFT',
    starts_at timestamptz NOT NULL,
    ends_at timestamptz NOT NULL,
    created_by uuid NOT NULL REFERENCES auth.user (id) ON DELETE RESTRICT,
    published_at timestamptz,
    closed_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT opportunity_project_fk FOREIGN KEY (project_id)
        REFERENCES academic_pi.project (id) ON DELETE RESTRICT,
    CONSTRAINT opportunity_title_ck CHECK (length(trim(title)) BETWEEN 5 AND 200),
    CONSTRAINT opportunity_description_ck CHECK (length(trim(description)) BETWEEN 20 AND 5000),
    CONSTRAINT opportunity_window_ck CHECK (starts_at < ends_at),
    CONSTRAINT opportunity_status_ck CHECK (status IN ('DRAFT', 'PUBLISHED', 'CLOSED')),
    CONSTRAINT opportunity_publication_state_ck CHECK (
        (status = 'DRAFT' AND published_at IS NULL AND closed_at IS NULL)
        OR (status = 'PUBLISHED' AND published_at IS NOT NULL AND closed_at IS NULL)
        OR (status = 'CLOSED' AND published_at IS NOT NULL AND closed_at IS NOT NULL)
    )
);

CREATE INDEX IF NOT EXISTS idx_opportunity_public_listing
    ON extension.opportunity (status, starts_at, ends_at, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_opportunity_project
    ON extension.opportunity (project_id, status, starts_at DESC);

CREATE TABLE IF NOT EXISTS extension.application (
    id uuid PRIMARY KEY,
    opportunity_id uuid NOT NULL REFERENCES extension.opportunity (id) ON DELETE CASCADE,
    student_id uuid NOT NULL REFERENCES auth.user (id) ON DELETE RESTRICT,
    status varchar(16) NOT NULL DEFAULT 'SUBMITTED',
    submitted_at timestamptz NOT NULL DEFAULT now(),
    withdrawn_at timestamptz,

    CONSTRAINT application_status_ck CHECK (status IN ('SUBMITTED', 'WITHDRAWN')),
    CONSTRAINT application_state_ck CHECK (
        (status = 'SUBMITTED' AND withdrawn_at IS NULL)
        OR (status = 'WITHDRAWN' AND withdrawn_at IS NOT NULL)
    ),
    CONSTRAINT application_opportunity_student_unq UNIQUE (opportunity_id, student_id)
);

CREATE INDEX IF NOT EXISTS idx_application_student
    ON extension.application (student_id, submitted_at DESC);

CREATE INDEX IF NOT EXISTS idx_application_opportunity
    ON extension.application (opportunity_id, status, submitted_at DESC);

INSERT INTO public.schema_migration (version, description)
VALUES ('V0012', 'create extension opportunities and applications')
ON CONFLICT (version) DO NOTHING;

COMMIT;
