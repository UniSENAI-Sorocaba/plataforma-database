-- Migration: V0014 - Avaliações e vínculos autorizados (F4/T16)
BEGIN;

CREATE TABLE IF NOT EXISTS academic_pi.evaluation (
    id uuid PRIMARY KEY,
    project_id uuid NOT NULL,
    period_id uuid NOT NULL,
    evaluated_student_id uuid NOT NULL,
    evaluation_date timestamptz NOT NULL,
    created_by uuid NOT NULL REFERENCES auth."user" (id) ON DELETE RESTRICT,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT evaluation_period_fk FOREIGN KEY (project_id, period_id)
        REFERENCES academic_pi.enrollment_period (project_id, id) ON DELETE RESTRICT,
    CONSTRAINT evaluation_student_fk FOREIGN KEY (project_id, period_id, evaluated_student_id)
        REFERENCES academic_pi.project_participant (project_id, period_id, student_id) ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS academic_pi.evaluation_evaluator (
    evaluation_id uuid NOT NULL REFERENCES academic_pi.evaluation (id) ON DELETE CASCADE,
    evaluator_id uuid NOT NULL REFERENCES auth."user" (id) ON DELETE RESTRICT,
    assigned_by uuid NOT NULL REFERENCES auth."user" (id) ON DELETE RESTRICT,
    assigned_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (evaluation_id, evaluator_id)
);

CREATE INDEX IF NOT EXISTS idx_evaluation_project_period
    ON academic_pi.evaluation (project_id, period_id, evaluation_date, id);

CREATE INDEX IF NOT EXISTS idx_evaluation_evaluator
    ON academic_pi.evaluation_evaluator (evaluator_id, assigned_at DESC);

CREATE OR REPLACE FUNCTION academic_pi.validate_evaluation_target()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM academic_pi.project_participant
        WHERE project_id = NEW.project_id AND period_id = NEW.period_id
          AND student_id = NEW.evaluated_student_id AND status = 'ACTIVE'
    ) THEN
        RAISE EXCEPTION 'evaluation target must be an active project participant';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION academic_pi.validate_evaluation_evaluator()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_project_id uuid;
    v_period_id uuid;
    v_target_id uuid;
BEGIN
    SELECT project_id, period_id, evaluated_student_id
      INTO v_project_id, v_period_id, v_target_id
      FROM academic_pi.evaluation
     WHERE id = NEW.evaluation_id;

    IF v_target_id IS NULL THEN
        RAISE EXCEPTION 'evaluation does not exist';
    END IF;
    IF NEW.evaluator_id = v_target_id THEN
        RAISE EXCEPTION 'a student cannot evaluate themselves';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM auth."user" WHERE id = NEW.evaluator_id AND status = 'active'
    ) THEN
        RAISE EXCEPTION 'evaluator must be an active user';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM academic_pi.project_responsible
         WHERE project_id = v_project_id AND user_id = NEW.evaluator_id
        UNION ALL
        SELECT 1 FROM academic_pi.project_participant
         WHERE project_id = v_project_id AND period_id = v_period_id
           AND student_id = NEW.evaluator_id AND status = 'ACTIVE'
    ) THEN
        RAISE EXCEPTION 'evaluator has no active project link';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS evaluation_target_validation_trigger ON academic_pi.evaluation;
CREATE TRIGGER evaluation_target_validation_trigger
    BEFORE INSERT OR UPDATE OF project_id, period_id, evaluated_student_id
    ON academic_pi.evaluation
    FOR EACH ROW EXECUTE FUNCTION academic_pi.validate_evaluation_target();

DROP TRIGGER IF EXISTS evaluation_evaluator_validation_trigger ON academic_pi.evaluation_evaluator;
CREATE TRIGGER evaluation_evaluator_validation_trigger
    BEFORE INSERT OR UPDATE OF evaluation_id, evaluator_id
    ON academic_pi.evaluation_evaluator
    FOR EACH ROW EXECUTE FUNCTION academic_pi.validate_evaluation_evaluator();

INSERT INTO public.schema_migration (version, description)
VALUES ('V0014', 'create evaluations and authorized evaluators')
ON CONFLICT (version) DO NOTHING;

COMMIT;
