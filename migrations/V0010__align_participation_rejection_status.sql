-- Migration: V0010 - Alinha o status de recusa ao contrato da API (REJECTED)
BEGIN;

ALTER TABLE academic_pi.participation_request
    DROP CONSTRAINT IF EXISTS participation_request_status_ck,
    DROP CONSTRAINT IF EXISTS participation_request_decision_ck;

UPDATE academic_pi.participation_request
SET status = 'REJECTED'
WHERE status = 'DENIED';

ALTER TABLE academic_pi.participation_request
    ADD CONSTRAINT participation_request_status_ck
        CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED', 'WITHDRAWN')),
    ADD CONSTRAINT participation_request_decision_ck CHECK (
        (status IN ('PENDING', 'WITHDRAWN') AND decided_at IS NULL AND decided_by IS NULL)
        OR (status IN ('APPROVED', 'REJECTED') AND decided_at IS NOT NULL AND decided_by IS NOT NULL)
    );

INSERT INTO public.schema_migration (version, description)
VALUES ('V0010', 'align participation rejection status with API contract')
ON CONFLICT (version) DO NOTHING;

COMMIT;
