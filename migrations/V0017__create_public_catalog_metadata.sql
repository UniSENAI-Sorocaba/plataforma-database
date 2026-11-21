-- Migration: V0017 - Metadados e consulta pública paginada (F5/T19)
BEGIN;

ALTER TABLE academic_pi.project
    ADD COLUMN IF NOT EXISTS course_code varchar(80),
    ADD COLUMN IF NOT EXISTS ods_codes varchar(20)[] NOT NULL DEFAULT '{}';

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'project_course_code_ck') THEN
        ALTER TABLE academic_pi.project ADD CONSTRAINT project_course_code_ck
            CHECK (course_code IS NULL OR length(trim(course_code)) BETWEEN 2 AND 80);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'project_ods_codes_ck') THEN
        ALTER TABLE academic_pi.project ADD CONSTRAINT project_ods_codes_ck
            CHECK (cardinality(ods_codes) <= 17 AND ods_codes <@ ARRAY['ODS-1','ODS-2','ODS-3','ODS-4','ODS-5','ODS-6','ODS-7','ODS-8','ODS-9','ODS-10','ODS-11','ODS-12','ODS-13','ODS-14','ODS-15','ODS-16','ODS-17']::varchar[]);
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_project_public_catalog_filter
    ON academic_pi.project (publication_status, lifecycle_status, course_code, updated_at, id);
CREATE INDEX IF NOT EXISTS idx_project_public_catalog_ods
    ON academic_pi.project USING gin (ods_codes);

INSERT INTO public.schema_migration (version, description)
VALUES ('V0017', 'create public catalog metadata and filter indexes')
ON CONFLICT (version) DO NOTHING;

COMMIT;
