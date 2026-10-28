BEGIN;

CREATE TABLE IF NOT EXISTS academic_pi.project (
    id uuid PRIMARY KEY,
    title varchar(200) NOT NULL,
    description text,
    is_pi boolean NOT NULL DEFAULT false,
    is_extension boolean NOT NULL DEFAULT false,
    status varchar(20) NOT NULL DEFAULT 'draft',
    is_public boolean NOT NULL DEFAULT false,
    starts_at timestamptz,
    ends_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT project_title_ck
        CHECK (length(trim(title)) > 0),

    CONSTRAINT project_category_ck
        CHECK (is_pi OR is_extension),

    CONSTRAINT project_status_ck
        CHECK (status IN ('draft', 'published', 'archived')),

    CONSTRAINT project_period_ck
        CHECK (ends_at IS NULL OR starts_at IS NULL OR ends_at >= starts_at),

    -- Alvo da FK composta de project_participation (garante que a copia das categorias nunca diverge)
    CONSTRAINT project_id_category_unq
        UNIQUE (id, is_pi, is_extension)
);

CREATE TABLE IF NOT EXISTS academic_pi.enrollment_period (
    id uuid PRIMARY KEY,
    project_id uuid NOT NULL,
    opens_at timestamptz NOT NULL,
    closes_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT enrollment_period_project_fk
        FOREIGN KEY (project_id)
        REFERENCES academic_pi.project (id)
        ON DELETE RESTRICT,

    CONSTRAINT enrollment_period_window_ck
        CHECK (closes_at >= opens_at)
);

CREATE INDEX IF NOT EXISTS idx_enrollment_period_project_id
    ON academic_pi.enrollment_period (project_id);

CREATE TABLE IF NOT EXISTS academic_pi.project_instructor (
    id uuid PRIMARY KEY,
    project_id uuid NOT NULL,
    instructor_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT project_instructor_project_fk
        FOREIGN KEY (project_id)
        REFERENCES academic_pi.project (id)
        ON DELETE RESTRICT,

    CONSTRAINT project_instructor_project_instructor_unq
        UNIQUE (project_id, instructor_id)
);

-- project_id ja e coberto pelo unique composto; falta o lado do docente
CREATE INDEX IF NOT EXISTS idx_project_instructor_instructor_id
    ON academic_pi.project_instructor (instructor_id);

CREATE TABLE IF NOT EXISTS academic_pi.project_participation (
    id uuid PRIMARY KEY,
    project_id uuid NOT NULL,
    is_pi boolean NOT NULL,
    is_extension boolean NOT NULL,
    student_id uuid NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'requested',
    justification text,
    requested_at timestamptz NOT NULL DEFAULT now(),
    decided_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT project_participation_project_fk
        FOREIGN KEY (project_id, is_pi, is_extension)
        REFERENCES academic_pi.project (id, is_pi, is_extension)
        ON DELETE RESTRICT,

    CONSTRAINT project_participation_category_ck
        CHECK (is_pi OR is_extension),

    CONSTRAINT project_participation_status_ck
        CHECK (status IN ('requested', 'approved', 'denied', 'withdrawn', 'removed')),

    CONSTRAINT project_participation_justification_ck
        CHECK (status <> 'removed' OR (justification IS NOT NULL AND length(trim(justification)) > 0)),

    CONSTRAINT project_participation_project_student_unq
        UNIQUE (project_id, student_id)
);

CREATE INDEX IF NOT EXISTS idx_project_participation_student_id
    ON academic_pi.project_participation (student_id);

CREATE UNIQUE INDEX IF NOT EXISTS idx_project_participation_student_active_pi
    ON academic_pi.project_participation (student_id)
    WHERE is_pi AND status IN ('requested', 'approved');

CREATE UNIQUE INDEX IF NOT EXISTS idx_project_participation_student_active_extension
    ON academic_pi.project_participation (student_id)
    WHERE is_extension AND status IN ('requested', 'approved');

INSERT INTO public.schema_migration (version, description)
VALUES ('V0008', 'create project tables')
ON CONFLICT (version) DO NOTHING;

COMMIT;