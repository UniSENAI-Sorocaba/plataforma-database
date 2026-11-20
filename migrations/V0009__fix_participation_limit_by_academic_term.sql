-- Migration: V0009 - Corrige limite de participacao para considerar o semestre
BEGIN;

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

INSERT INTO public.schema_migration (version, description)
VALUES ('V0009', 'fix participation limit by academic term')
ON CONFLICT (version) DO NOTHING;

COMMIT;
