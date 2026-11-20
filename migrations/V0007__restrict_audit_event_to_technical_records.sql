-- DB-007: mantém a auditoria como registro técnico mínimo, sem snapshots.
BEGIN;

UPDATE public.audit_event
SET old_data = NULL,
    new_data = NULL
WHERE old_data IS NOT NULL
   OR new_data IS NOT NULL;

ALTER TABLE public.audit_event
    DROP CONSTRAINT IF EXISTS audit_event_no_snapshot_ck;

ALTER TABLE public.audit_event
    ADD CONSTRAINT audit_event_no_snapshot_ck
    CHECK (old_data IS NULL AND new_data IS NULL);

COMMENT ON TABLE public.audit_event IS
    'Registro tecnico/operacional minimo. Nao armazena valores anteriores ou novos de dados de negocio.';

COMMENT ON COLUMN public.audit_event.old_data IS
    'Descontinuada: sempre NULL por audit_event_no_snapshot_ck.';

COMMENT ON COLUMN public.audit_event.new_data IS
    'Descontinuada: sempre NULL por audit_event_no_snapshot_ck.';

INSERT INTO public.schema_migration (version, description)
VALUES ('V0007', 'restrict audit event to technical records')
ON CONFLICT (version) DO NOTHING;

COMMIT;
