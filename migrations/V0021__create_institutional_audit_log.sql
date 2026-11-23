BEGIN;
CREATE TABLE IF NOT EXISTS institutional.audit_log (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(), actor_id uuid NOT NULL REFERENCES auth."user"(id),
    action varchar(100) NOT NULL, target_type varchar(80) NOT NULL, target_id uuid, details jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_audit_log_created_at ON institutional.audit_log(created_at);
CREATE INDEX IF NOT EXISTS idx_audit_log_target ON institutional.audit_log(target_type, target_id);
COMMIT;
