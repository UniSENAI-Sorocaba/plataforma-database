BEGIN;

CREATE TABLE IF NOT EXISTS public.audit_event (
    id uuid PRIMARY KEY,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    schema_name varchar(63) NOT NULL,
    table_name varchar(63) NOT NULL,
    operation varchar(10) NOT NULL,
    record_id uuid,
    actor_id uuid,
    old_data jsonb,
    new_data jsonb,

    CONSTRAINT audit_event_operation_ck
        CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),

    CONSTRAINT audit_event_schema_name_ck
        CHECK (schema_name <> ''),

    CONSTRAINT audit_event_table_name_ck
        CHECK (table_name <> '')
);

CREATE INDEX IF NOT EXISTS idx_audit_event_occurred_at
    ON public.audit_event (occurred_at);

CREATE INDEX IF NOT EXISTS idx_audit_event_record
    ON public.audit_event (schema_name, table_name, record_id);

CREATE INDEX IF NOT EXISTS idx_audit_event_actor
    ON public.audit_event (actor_id);

INSERT INTO public.schema_migration (version, description)
VALUES ('V0002', 'create audit event')
ON CONFLICT (version) DO NOTHING;

COMMIT;