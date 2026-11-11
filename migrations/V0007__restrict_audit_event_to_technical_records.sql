BEGIN;

-- DB-007: reconcilia public.audit_event com o Caderno de Validacoes (SPEC-AUTH-004).
-- Nao ha auditoria de negocio nem historico de valores anteriores (notas, horas ou
-- qualquer dado academico). Estrategia Expand and Contract: esta migration interrompe
-- a escrita de snapshots e remove os existentes; as colunas old_data/new_data nao sao
-- removidas aqui para nao quebrar consumidores ainda nao migrados (contract posterior).

-- 1. Remove snapshots ja persistidos (valores anteriores e novos de dados academicos).
UPDATE public.audit_event
SET old_data = NULL,
    new_data = NULL
WHERE old_data IS NOT NULL
   OR new_data IS NOT NULL;

-- 2. Impede que novos snapshots sejam persistidos.
ALTER TABLE public.audit_event
    DROP CONSTRAINT IF EXISTS audit_event_no_snapshot_ck;

ALTER TABLE public.audit_event
    ADD CONSTRAINT audit_event_no_snapshot_ck
    CHECK (old_data IS NULL AND new_data IS NULL);

COMMENT ON TABLE public.audit_event IS
    'Registro tecnico/operacional minimo. Nao e trilha de auditoria de negocio e nao guarda valores anteriores (SPEC-AUTH-004, DB-007).';
COMMENT ON COLUMN public.audit_event.old_data IS
    'Descontinuada: sempre NULL (audit_event_no_snapshot_ck). Remocao prevista em migration de contract.';
COMMENT ON COLUMN public.audit_event.new_data IS
    'Descontinuada: sempre NULL (audit_event_no_snapshot_ck). Remocao prevista em migration de contract.';

INSERT INTO public.schema_migration (version, description)
VALUES ('V0007', 'restrict audit event to technical records')
ON CONFLICT (version) DO NOTHING;

COMMIT;
