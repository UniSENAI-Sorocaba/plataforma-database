-- Migration: V0008 - Projetos, responsáveis, períodos e participação (F3)
BEGIN;

CREATE TABLE IF NOT EXISTS academic_pi.project (
    id uuid PRIMARY KEY,
    title varchar(200) NOT NULL,
    summary varchar(500),
    description text,
    classification varchar(20) NOT NULL,
    continuity varchar(20) NOT NULL,
    end_date date,
    publication_status varchar(20) NOT NULL DEFAULT 'DRAFT',
    lifecycle_status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_by uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT project_created_by_fk FOREIGN KEY (created_by)
        REFERENCES auth."user" (id) ON DELETE RESTRICT,
    CONSTRAINT project_title_ck CHECK (length(trim(title)) BETWEEN 5 AND 200),
    CONSTRAINT project_summary_ck CHECK (summary IS NULL OR length(trim(summary)) BETWEEN 20 AND 500),
    CONSTRAINT project_description_ck CHECK (description IS NULL OR length(trim(description)) BETWEEN 50 AND 5000),
    CONSTRAINT project_classification_ck CHECK (classification IN ('PI', 'EXTENSION', 'BOTH')),
    CONSTRAINT project_continuity_ck CHECK (continuity IN ('CONTINUOUS', 'FIXED_END')),
    CONSTRAINT project_end_date_ck CHECK (
        (continuity = 'CONTINUOUS' AND end_date IS NULL)
        OR (continuity = 'FIXED_END' AND end_date IS NOT NULL)
    ),
    CONSTRAINT project_publication_status_ck CHECK (publication_status IN ('DRAFT', 'PUBLISHED')),
    CONSTRAINT project_lifecycle_status_ck CHECK (lifecycle_status IN ('ACTIVE', 'ARCHIVED')),
    CONSTRAINT project_published_fields_ck CHECK (
        publication_status = 'DRAFT'
        OR (summary IS NOT NULL AND description IS NOT NULL)
    )
);

CREATE INDEX IF NOT EXISTS idx_project_public_catalog
    ON academic_pi.project (publication_status, lifecycle_status, updated_at);

CREATE TABLE IF NOT EXISTS academic_pi.project_responsible (
    project_id uuid NOT NULL REFERENCES academic_pi.project (id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth."user" (id) ON DELETE RESTRICT,
    assigned_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (project_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_project_responsible_user
    ON academic_pi.project_responsible (user_id, project_id);

CREATE TABLE IF NOT EXISTS academic_pi.enrollment_period (
    id uuid PRIMARY KEY,
    project_id uuid NOT NULL REFERENCES academic_pi.project (id) ON DELETE CASCADE,
    academic_term varchar(20) NOT NULL,
    starts_at timestamptz NOT NULL,
    ends_at timestamptz NOT NULL,
    created_by uuid NOT NULL REFERENCES auth."user" (id) ON DELETE RESTRICT,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT enrollment_period_term_ck CHECK (length(trim(academic_term)) > 0),
    CONSTRAINT enrollment_period_window_ck CHECK (starts_at < ends_at),
    CONSTRAINT uk_enrollment_period_project_term UNIQUE (project_id, academic_term),
    CONSTRAINT uk_enrollment_period_project_id UNIQUE (project_id, id)
);

CREATE INDEX IF NOT EXISTS idx_enrollment_period_window
    ON academic_pi.enrollment_period (starts_at, ends_at);

CREATE TABLE IF NOT EXISTS academic_pi.participation_request (
    id uuid PRIMARY KEY,
    project_id uuid NOT NULL REFERENCES academic_pi.project (id) ON DELETE CASCADE,
    period_id uuid NOT NULL,
    student_id uuid NOT NULL REFERENCES auth."user" (id) ON DELETE RESTRICT,
    status varchar(20) NOT NULL DEFAULT 'PENDING',
    requested_at timestamptz NOT NULL DEFAULT now(),
    decided_at timestamptz,
    decided_by uuid REFERENCES auth."user" (id) ON DELETE RESTRICT,
    withdrawn_at timestamptz,

    CONSTRAINT participation_request_status_ck
        CHECK (status IN ('PENDING', 'APPROVED', 'DENIED', 'WITHDRAWN')),
    CONSTRAINT participation_request_decision_ck CHECK (
        (status IN ('PENDING', 'WITHDRAWN') AND decided_at IS NULL AND decided_by IS NULL)
        OR (status IN ('APPROVED', 'DENIED') AND decided_at IS NOT NULL AND decided_by IS NOT NULL)
    ),
    CONSTRAINT participation_request_withdrawal_ck CHECK (
        (status = 'WITHDRAWN' AND withdrawn_at IS NOT NULL)
        OR (status <> 'WITHDRAWN' AND withdrawn_at IS NULL)
    ),
    CONSTRAINT uk_participation_request_project_student_period
        UNIQUE (project_id, student_id, period_id),
    CONSTRAINT participation_request_period_project_fk
        FOREIGN KEY (project_id, period_id)
        REFERENCES academic_pi.enrollment_period (project_id, id)
        ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS idx_participation_request_project_status
    ON academic_pi.participation_request (project_id, status);

CREATE TABLE IF NOT EXISTS academic_pi.project_participant (
    project_id uuid NOT NULL REFERENCES academic_pi.project (id) ON DELETE CASCADE,
    period_id uuid NOT NULL,
    student_id uuid NOT NULL REFERENCES auth."user" (id) ON DELETE RESTRICT,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    joined_at timestamptz NOT NULL DEFAULT now(),
    removed_at timestamptz,
    removed_by uuid REFERENCES auth."user" (id) ON DELETE RESTRICT,
    removal_reason varchar(1000),

    PRIMARY KEY (project_id, period_id, student_id),
    CONSTRAINT project_participant_status_ck CHECK (status IN ('ACTIVE', 'REMOVED')),
    CONSTRAINT project_participant_removal_ck CHECK (
        (status = 'ACTIVE' AND removed_at IS NULL AND removed_by IS NULL AND removal_reason IS NULL)
        OR (status = 'REMOVED' AND removed_at IS NOT NULL AND removed_by IS NOT NULL
            AND length(trim(removal_reason)) > 0)
    ),
    CONSTRAINT project_participant_period_project_fk
        FOREIGN KEY (project_id, period_id)
        REFERENCES academic_pi.enrollment_period (project_id, id)
        ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS idx_project_participant_student_term
    ON academic_pi.project_participant (student_id, period_id, status);

CREATE OR REPLACE FUNCTION academic_pi.prevent_last_responsible_removal()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (SELECT count(*) FROM academic_pi.project_responsible WHERE project_id = OLD.project_id) <= 1 THEN
        RAISE EXCEPTION 'project must have at least one responsible teacher'
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS project_responsible_minimum_trigger
    ON academic_pi.project_responsible;
CREATE TRIGGER project_responsible_minimum_trigger
    BEFORE DELETE ON academic_pi.project_responsible
    FOR EACH ROW EXECUTE FUNCTION academic_pi.prevent_last_responsible_removal();

CREATE OR REPLACE FUNCTION academic_pi.enforce_participation_limits()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    incoming_classification varchar(20);
    incoming_term varchar(20);
    has_pi boolean;
    has_extension boolean;
BEGIN
    IF NEW.status <> 'ACTIVE' THEN
        RETURN NEW;
    END IF;

    SELECT p.classification, ep.academic_term
      INTO incoming_classification, incoming_term
    FROM academic_pi.project p
    JOIN academic_pi.enrollment_period ep ON ep.id = NEW.period_id
    WHERE p.id = NEW.project_id;

    PERFORM pg_advisory_xact_lock(
        hashtextextended(NEW.student_id::text || ':' || incoming_term, 0)
    );

    SELECT EXISTS (
        SELECT 1
        FROM academic_pi.project_participant pp
        JOIN academic_pi.enrollment_period ep ON ep.id = pp.period_id
        JOIN academic_pi.project p ON p.id = pp.project_id
        WHERE pp.student_id = NEW.student_id
          AND ep.academic_term = incoming_term
          AND pp.status = 'ACTIVE'
          AND pp.project_id <> NEW.project_id
          AND p.classification IN ('PI', 'BOTH')
    ) INTO has_pi;

    SELECT EXISTS (
        SELECT 1
        FROM academic_pi.project_participant pp
        JOIN academic_pi.enrollment_period ep ON ep.id = pp.period_id
        JOIN academic_pi.project p ON p.id = pp.project_id
        WHERE pp.student_id = NEW.student_id
          AND ep.academic_term = incoming_term
          AND pp.status = 'ACTIVE'
          AND pp.project_id <> NEW.project_id
          AND p.classification IN ('EXTENSION', 'BOTH')
    ) INTO has_extension;

    IF incoming_classification IN ('PI', 'BOTH') AND has_pi THEN
        RAISE EXCEPTION 'student already has an active PI participation in this term'
            USING ERRCODE = 'unique_violation';
    END IF;
    IF incoming_classification IN ('EXTENSION', 'BOTH') AND has_extension THEN
        RAISE EXCEPTION 'student already has an active Extension participation in this term'
            USING ERRCODE = 'unique_violation';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS project_participant_limits_trigger
    ON academic_pi.project_participant;
CREATE TRIGGER project_participant_limits_trigger
    BEFORE INSERT OR UPDATE OF project_id, period_id, student_id, status
    ON academic_pi.project_participant
    FOR EACH ROW EXECUTE FUNCTION academic_pi.enforce_participation_limits();

INSERT INTO public.schema_migration (version, description)
VALUES ('V0008', 'create projects participation and enrollment periods')
ON CONFLICT (version) DO NOTHING;

COMMIT;
