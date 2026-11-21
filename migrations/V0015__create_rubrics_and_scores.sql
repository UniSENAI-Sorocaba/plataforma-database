-- Migration: V0015 - Rubricas versionadas e notas (F4/T17)
BEGIN;

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
    ADD COLUMN IF NOT EXISTS rubric_version_id uuid,
    ADD COLUMN IF NOT EXISTS final_score numeric(5,2);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'evaluation_rubric_version_fk') THEN
        ALTER TABLE academic_pi.evaluation
            ADD CONSTRAINT evaluation_rubric_version_fk FOREIGN KEY (rubric_version_id)
            REFERENCES academic_pi.rubric_version (id) ON DELETE RESTRICT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'evaluation_final_score_ck') THEN
        ALTER TABLE academic_pi.evaluation
            ADD CONSTRAINT evaluation_final_score_ck CHECK (final_score IS NULL OR (final_score >= 0 AND final_score <= 10));
    END IF;
END $$;

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
VALUES ('V0015', 'create versioned rubrics and evaluation scores')
ON CONFLICT (version) DO NOTHING;

COMMIT;

