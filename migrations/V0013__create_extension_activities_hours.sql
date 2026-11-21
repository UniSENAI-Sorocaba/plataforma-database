-- Migration: V0013 - Atividades e horas de Extensão (F4/T15)
BEGIN;

CREATE TABLE IF NOT EXISTS extension.activity (
    id uuid PRIMARY KEY,
    project_id uuid NOT NULL,
    period_id uuid NOT NULL,
    student_id uuid NOT NULL,
    title varchar(200) NOT NULL,
    description varchar(5000) NOT NULL,
    requested_hours numeric(6,2) NOT NULL,
    approved_hours numeric(6,2),
    status varchar(16) NOT NULL DEFAULT 'SUBMITTED',
    rejection_reason varchar(1000),
    submitted_at timestamptz NOT NULL DEFAULT now(),
    reviewed_at timestamptz,
    reviewed_by uuid REFERENCES auth."user" (id) ON DELETE RESTRICT,
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT activity_period_fk FOREIGN KEY (project_id, period_id)
        REFERENCES academic_pi.enrollment_period (project_id, id) ON DELETE RESTRICT,
    CONSTRAINT activity_student_fk FOREIGN KEY (project_id, period_id, student_id)
        REFERENCES academic_pi.project_participant (project_id, period_id, student_id) ON DELETE RESTRICT,
    CONSTRAINT activity_title_ck CHECK (length(trim(title)) BETWEEN 3 AND 200),
    CONSTRAINT activity_description_ck CHECK (length(trim(description)) BETWEEN 10 AND 5000),
    CONSTRAINT activity_requested_hours_ck CHECK (
        requested_hours >= 0.25 AND requested_hours <= 100
        AND requested_hours * 4 = trunc(requested_hours * 4)
    ),
    CONSTRAINT activity_approved_hours_ck CHECK (
        approved_hours IS NULL OR (
            approved_hours >= 0.25 AND approved_hours <= 100
            AND approved_hours * 4 = trunc(approved_hours * 4)
        )
    ),
    CONSTRAINT activity_status_ck CHECK (status IN ('SUBMITTED', 'APPROVED', 'REJECTED')),
    CONSTRAINT activity_review_state_ck CHECK (
        (status = 'SUBMITTED' AND approved_hours IS NULL AND rejection_reason IS NULL
            AND reviewed_at IS NULL AND reviewed_by IS NULL)
        OR (status = 'APPROVED' AND approved_hours IS NOT NULL AND rejection_reason IS NULL
            AND reviewed_at IS NOT NULL AND reviewed_by IS NOT NULL)
        OR (status = 'REJECTED' AND approved_hours IS NULL AND rejection_reason IS NOT NULL
            AND length(trim(rejection_reason)) BETWEEN 3 AND 1000
            AND reviewed_at IS NOT NULL AND reviewed_by IS NOT NULL)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS uk_activity_student_title
    ON extension.activity (project_id, period_id, student_id, lower(trim(title)));

CREATE INDEX IF NOT EXISTS idx_activity_student_status
    ON extension.activity (student_id, project_id, period_id, status, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_activity_project_status
    ON extension.activity (project_id, period_id, status, updated_at DESC);

INSERT INTO public.schema_migration (version, description)
VALUES ('V0013', 'create extension activities and hours')
ON CONFLICT (version) DO NOTHING;

COMMIT;
