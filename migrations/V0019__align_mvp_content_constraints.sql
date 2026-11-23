-- Migration: V0019 - Alinha limites de arquivos e indicadores de impacto ao MVP aprovado
BEGIN;

ALTER TABLE academic_pi.deliverable
    DROP CONSTRAINT IF EXISTS deliverable_size_ck;
ALTER TABLE academic_pi.deliverable
    ADD CONSTRAINT deliverable_size_ck CHECK (size_bytes > 0 AND size_bytes <= 20971520);

ALTER TABLE academic_pi.impact_version
    ADD COLUMN IF NOT EXISTS beneficiaries_count integer,
    ADD COLUMN IF NOT EXISTS activity_hours numeric(8,2),
    ADD COLUMN IF NOT EXISTS partners_count integer,
    ADD COLUMN IF NOT EXISTS territory varchar(200),
    ADD COLUMN IF NOT EXISTS beneficiary_summary varchar(1000),
    ADD COLUMN IF NOT EXISTS ods_codes text[];

ALTER TABLE academic_pi.impact_version
    DROP CONSTRAINT IF EXISTS impact_beneficiary_count_ck,
    DROP CONSTRAINT IF EXISTS impact_activity_hours_ck,
    DROP CONSTRAINT IF EXISTS impact_partners_count_ck;
ALTER TABLE academic_pi.impact_version
    ADD CONSTRAINT impact_beneficiary_count_ck CHECK (beneficiaries_count IS NULL OR beneficiaries_count >= 0),
    ADD CONSTRAINT impact_activity_hours_ck CHECK (activity_hours IS NULL OR activity_hours > 0),
    ADD CONSTRAINT impact_partners_count_ck CHECK (partners_count IS NULL OR partners_count >= 0);

INSERT INTO public.schema_migration (version, description)
VALUES ('V0019', 'align MVP file limits and impact indicators')
ON CONFLICT (version) DO NOTHING;

COMMIT;
