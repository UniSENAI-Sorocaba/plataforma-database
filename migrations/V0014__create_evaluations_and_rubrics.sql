-- Migration: V0014 - Avaliações, rubricas versionadas e notas (F4/T16-T17)
BEGIN;

CREATE TABLE IF NOT EXISTS academic_pi.evaluation (
    id uuid PRIMARY KEY,
    project_id uuid NOT NULL,
    period_id uuid NOT NULL,
    evaluated_student_id uuid NOT NULL,
    evaluation_date timestamptz NOT NULL,
    rubric_version_id uuid,
    final_score numeric(5,2),
    created_by uuid NOT NULL REFERENCES auth."user" (id) ON DELETE RESTRICT,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT evaluation_period_fk FOREIGN KEY (project_id, period_id)
        REFERENCES academic_pi.enrollment_period (project_id, id) ON DELETE CASCADE,
    CONSTRAINT evaluation_student_fk FOREIGN KEY (project_id, period_id, evaluated_student_id)
        REFERENCES academic_pi.project_participant (project_id, period_id, student_id) ON DELETE RESTRICT,
    CONSTRAINT evaluation_final_score_ck CHECK (final_score IS NULL OR (final_score >= 0 AND final_score <= 10))
);

CREATE INDEX IF NOT EXISTS idx_evaluation_project_period
    ON academic_pi.evaluation (project_id, period_id, evaluation_date, id);

CREATE TABLE IF NOT EXISTS academic_pi.evaluation_evaluator (
    evaluation_id uuid NOT NULL REFERENCES academic_pi.evaluation (id) ON DELETE CASCADE,
    evaluator_id uuid NOT NULL REFERENCES auth."user" (id) ON DELETE RESTRICT,
    assigned_by uuid NOT NULL REFERENCES auth."user" (id) ON DELETE RESTRICT,
    assigned_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (evaluation_id, evaluator_id)
);

CREATE TABLE IF NOT EXISTS academic_pi.rubric (
    id uuid PRIMARY KEY,
    code varchar(80) NOT NULL,
    name varchar(200) NOT NULL,
    created_by uuid NOT NULL REFERENCES auth."user" (id) ON DELETE RESTRICT,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT rubric_code_ck CHECK (length(trim(code)) BETWEEN 1 AND 80),
    CONSTRAINT rubric_name_ck CHECK (length(trim(name)) BETWEEN 3 AND 200),
    CONSTRAINT uk_rubric_code UNIQUE (code)
);

CREATE TABLE IF NOT EXISTS academic_pi.rubric_version (
    id uuid PRIMARY KEY,
    rubric_id uuid NOT NULL REFERENCES academic_pi.rubric (id) ON DELETE CASCADE,
    version integer NOT NULL,
    created_by uuid NOT NULL REFERENCES auth."user" (id) ON DELETE RESTRICT,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT rubric_version_positive_ck CHECK (version > 0),
    CONSTRAINT uk_rubric_version UNIQUE (rubric_id, version)
);

CREATE TABLE IF NOT EXISTS academic_pi.rubric_criterion (
    id uuid PRIMARY KEY,
    rubric_version_id uuid NOT NULL REFERENCES academic_pi.rubric_version (id) ON DELETE CASCADE,
    code varchar(80) NOT NULL,
    label varchar(200) NOT NULL,
    weight numeric(7,4) NOT NULL,
    min_score numeric(5,2) NOT NULL DEFAULT 0,
    max_score numeric(5,2) NOT NULL DEFAULT 10,
    CONSTRAINT rubric_criterion_code_ck CHECK (length(trim(code)) BETWEEN 1 AND 80),
    CONSTRAINT rubric_criterion_label_ck CHECK (length(trim(label)) BETWEEN 1 AND 200),
    CONSTRAINT rubric_criterion_weight_ck CHECK (weight > 0),
    CONSTRAINT rubric_criterion_range_ck CHECK (min_score >= 0 AND max_score <= 10 AND min_score < max_score),
    CONSTRAINT uk_rubric_criterion_code UNIQUE (rubric_version_id, code)
);

ALTER TABLE academic_pi.evaluation
    ADD CONSTRAINT evaluation_rubric_version_fk FOREIGN KEY (rubric_version_id)
    REFERENCES academic_pi.rubric_version (id) ON DELETE RESTRICT;

CREATE TABLE IF NOT EXISTS academic_pi.evaluation_criterion_score (
    evaluation_id uuid NOT NULL REFERENCES academic_pi.evaluation (id) ON DELETE CASCADE,
    criterion_id uuid NOT NULL REFERENCES academic_pi.rubric_criterion (id) ON DELETE RESTRICT,
    score numeric(5,2) NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (evaluation_id, criterion_id),
    CONSTRAINT evaluation_score_range_ck CHECK (score >= 0 AND score <= 10)
);

CREATE INDEX IF NOT EXISTS idx_rubric_version_rubric
    ON academic_pi.rubric_version (rubric_id, version DESC);

INSERT INTO public.schema_migration (version, description)
VALUES ('V0014', 'create evaluations and versioned rubrics')
ON CONFLICT (version) DO NOTHING;

COMMIT;
