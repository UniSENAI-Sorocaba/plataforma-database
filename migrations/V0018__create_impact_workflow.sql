-- Migration: V0018 - Impacto público versionado e aprovado (F5/T20)
BEGIN;

CREATE TABLE IF NOT EXISTS academic_pi.impact (
    id uuid PRIMARY KEY,
    project_id uuid NOT NULL REFERENCES academic_pi.project (id) ON DELETE CASCADE,
    title varchar(200) NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    created_by uuid NOT NULL REFERENCES auth."user" (id) ON DELETE RESTRICT,
    reviewed_by uuid REFERENCES auth."user" (id) ON DELETE RESTRICT,
    reviewed_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT impact_title_ck CHECK (length(trim(title)) BETWEEN 3 AND 200),
    CONSTRAINT impact_status_ck CHECK (status IN ('DRAFT','SUBMITTED','APPROVED','RETIRED')),
    CONSTRAINT impact_review_ck CHECK ((status = 'APPROVED') = (reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL))
);

CREATE TABLE IF NOT EXISTS academic_pi.impact_version (
    id uuid PRIMARY KEY,
    impact_id uuid NOT NULL REFERENCES academic_pi.impact (id) ON DELETE CASCADE,
    version integer NOT NULL,
    summary varchar(1000) NOT NULL,
    evidence_url varchar(1000),
    created_by uuid NOT NULL REFERENCES auth."user" (id) ON DELETE RESTRICT,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT impact_version_positive_ck CHECK (version > 0),
    CONSTRAINT impact_summary_ck CHECK (length(trim(summary)) BETWEEN 10 AND 1000),
    CONSTRAINT impact_evidence_url_ck CHECK (evidence_url IS NULL OR length(trim(evidence_url)) BETWEEN 1 AND 1000),
    CONSTRAINT uk_impact_version UNIQUE (impact_id, version)
);

CREATE INDEX IF NOT EXISTS idx_impact_public_status ON academic_pi.impact (status, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_impact_version_latest ON academic_pi.impact_version (impact_id, version DESC);

INSERT INTO public.schema_migration (version, description)
VALUES ('V0018', 'create versioned public impact approval workflow')
ON CONFLICT (version) DO NOTHING;

COMMIT;
