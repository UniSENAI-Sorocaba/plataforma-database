BEGIN;

-- DB-015: impacto social publicado. Definicoes aprovadas pelo PO em 21/11/2026
-- (plataforma-governance, _KB/product/mvp-decisions-2026-11-21.md, secao 6, branch release/v1.0.0).
-- Regras: o responsavel pelo projeto declara; a coordenacao aprova; sem estimativa automatica;
-- correcao SUBSTITUI o conteudo vigente apos nova aprovacao (sem tabela de versoes nem historico);
-- so conteudo aprovado e publico. Nao ha coluna para relato, imagem, identificacao de
-- beneficiario ou de parceiro (dados identificaveis nao entram).
-- Estados (T20 do plano de MVP e consumidor Backend): draft, submitted, approved, retired.
-- Impacto aprovado = publicado; retired = retirado da consulta publica.

CREATE TABLE IF NOT EXISTS academic_pi.project_impact (
    id uuid PRIMARY KEY,
    project_id uuid NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'draft',
    summary text,
    beneficiary_audience text,
    period_start date,
    period_end date,
    territory text,
    observed_result text,
    evidence_text text,
    beneficiaries_served integer,
    activity_hours numeric(10, 2),
    partners_involved integer,
    declared_by uuid NOT NULL,
    approved_by uuid,
    approved_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT project_impact_project_fk
        FOREIGN KEY (project_id)
        REFERENCES academic_pi.project (id)
        ON DELETE RESTRICT,

    CONSTRAINT project_impact_declared_by_fk
        FOREIGN KEY (declared_by)
        REFERENCES auth."user" (id)
        ON DELETE RESTRICT,

    CONSTRAINT project_impact_approved_by_fk
        FOREIGN KEY (approved_by)
        REFERENCES auth."user" (id)
        ON DELETE RESTRICT,

    CONSTRAINT project_impact_status_ck
        CHECK (status IN ('draft', 'submitted', 'approved', 'retired')),

    CONSTRAINT project_impact_text_fields_ck
        CHECK (
            (summary IS NULL OR length(trim(summary)) > 0)
            AND (beneficiary_audience IS NULL OR length(trim(beneficiary_audience)) > 0)
            AND (territory IS NULL OR length(trim(territory)) > 0)
            AND (observed_result IS NULL OR length(trim(observed_result)) > 0)
            AND (evidence_text IS NULL OR length(trim(evidence_text)) > 0)
        ),

    CONSTRAINT project_impact_period_ck
        CHECK (period_start IS NULL OR period_end IS NULL OR period_end >= period_start),

    -- Indicadores minimos aprovados: inteiro nao negativo, decimal positivo, inteiro nao negativo.
    CONSTRAINT project_impact_beneficiaries_served_ck
        CHECK (beneficiaries_served IS NULL OR beneficiaries_served >= 0),

    CONSTRAINT project_impact_activity_hours_ck
        CHECK (activity_hours IS NULL OR activity_hours > 0),

    CONSTRAINT project_impact_partners_involved_ck
        CHECK (partners_involved IS NULL OR partners_involved >= 0),

    CONSTRAINT project_impact_approval_ck
        CHECK ((approved_by IS NULL) = (approved_at IS NULL)),

    -- Publicacao nunca e implicita: aprovado exige aprovacao registrada e todos os campos
    -- obrigatorios do impacto publicado.
    CONSTRAINT project_impact_approved_ck
        CHECK (
            status <> 'approved'
            OR (
                approved_by IS NOT NULL
                AND approved_at IS NOT NULL
                AND summary IS NOT NULL
                AND beneficiary_audience IS NOT NULL
                AND period_start IS NOT NULL
                AND period_end IS NOT NULL
                AND territory IS NOT NULL
                AND observed_result IS NOT NULL
                AND evidence_text IS NOT NULL
                AND beneficiaries_served IS NOT NULL
                AND activity_hours IS NOT NULL
                AND partners_involved IS NOT NULL
            )
        )
);

CREATE INDEX IF NOT EXISTS idx_project_impact_project_id
    ON academic_pi.project_impact (project_id);

CREATE INDEX IF NOT EXISTS idx_project_impact_declared_by
    ON academic_pi.project_impact (declared_by);

CREATE INDEX IF NOT EXISTS idx_project_impact_approved_by
    ON academic_pi.project_impact (approved_by)
    WHERE approved_by IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_project_impact_approved_project_id
    ON academic_pi.project_impact (project_id)
    WHERE status = 'approved';

-- Codigos ODS: lista relacional (sem array) para unicidade e filtro do catalogo. Sao os 17 ODS da ONU.
CREATE TABLE IF NOT EXISTS academic_pi.project_impact_ods (
    impact_id uuid NOT NULL,
    ods_code smallint NOT NULL,

    CONSTRAINT project_impact_ods_pk
        PRIMARY KEY (impact_id, ods_code),

    CONSTRAINT project_impact_ods_impact_fk
        FOREIGN KEY (impact_id)
        REFERENCES academic_pi.project_impact (id)
        ON DELETE CASCADE,

    CONSTRAINT project_impact_ods_code_ck
        CHECK (ods_code BETWEEN 1 AND 17)
);

CREATE INDEX IF NOT EXISTS idx_project_impact_ods_code
    ON academic_pi.project_impact_ods (ods_code);

-- Guarda de integridade: conteudo aprovado (publico) so muda depois de nova aprovacao.
-- A correcao exige sair de 'approved' (rascunho/enviado), editar e aprovar de novo com NOVA aprovacao.
CREATE OR REPLACE FUNCTION academic_pi.project_impact_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.status = 'approved' AND NEW.status = 'approved' AND (
        NEW.project_id IS DISTINCT FROM OLD.project_id
        OR NEW.summary IS DISTINCT FROM OLD.summary
        OR NEW.beneficiary_audience IS DISTINCT FROM OLD.beneficiary_audience
        OR NEW.period_start IS DISTINCT FROM OLD.period_start
        OR NEW.period_end IS DISTINCT FROM OLD.period_end
        OR NEW.territory IS DISTINCT FROM OLD.territory
        OR NEW.observed_result IS DISTINCT FROM OLD.observed_result
        OR NEW.evidence_text IS DISTINCT FROM OLD.evidence_text
        OR NEW.beneficiaries_served IS DISTINCT FROM OLD.beneficiaries_served
        OR NEW.activity_hours IS DISTINCT FROM OLD.activity_hours
        OR NEW.partners_involved IS DISTINCT FROM OLD.partners_involved
        OR NEW.declared_by IS DISTINCT FROM OLD.declared_by
    ) THEN
        RAISE EXCEPTION 'impacto aprovado nao pode ser alterado sem nova aprovacao'
            USING ERRCODE = 'check_violation';
    END IF;

    IF NEW.status = 'approved' AND OLD.status <> 'approved'
       AND NEW.approved_at IS NOT DISTINCT FROM OLD.approved_at THEN
        RAISE EXCEPTION 'nova aprovacao exige novo approved_at'
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION academic_pi.project_impact_ods_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_impact uuid;
BEGIN
    v_impact := CASE WHEN TG_OP = 'INSERT' THEN NEW.impact_id ELSE OLD.impact_id END;

    IF EXISTS (
        SELECT 1 FROM academic_pi.project_impact WHERE id = v_impact AND status = 'approved'
    ) THEN
        RAISE EXCEPTION 'ODS de impacto aprovado nao pode ser alterado sem nova aprovacao'
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

DROP TRIGGER IF EXISTS project_impact_guard_trg ON academic_pi.project_impact;
CREATE TRIGGER project_impact_guard_trg
    BEFORE UPDATE ON academic_pi.project_impact
    FOR EACH ROW EXECUTE FUNCTION academic_pi.project_impact_guard();

DROP TRIGGER IF EXISTS project_impact_ods_guard_trg ON academic_pi.project_impact_ods;
CREATE TRIGGER project_impact_ods_guard_trg
    BEFORE INSERT OR UPDATE OR DELETE ON academic_pi.project_impact_ods
    FOR EACH ROW EXECUTE FUNCTION academic_pi.project_impact_ods_guard();

-- Consulta publica: somente impacto aprovado de projeto publicado e publico.
-- Nao expoe declared_by, approved_by, approved_at nem status interno.
CREATE OR REPLACE VIEW academic_pi.public_project_impact AS
SELECT
    i.id,
    i.project_id,
    i.summary,
    i.beneficiary_audience,
    i.period_start,
    i.period_end,
    i.territory,
    i.observed_result,
    i.evidence_text,
    i.beneficiaries_served,
    i.activity_hours,
    i.partners_involved,
    COALESCE(
        (SELECT array_agg(o.ods_code ORDER BY o.ods_code)
           FROM academic_pi.project_impact_ods o
          WHERE o.impact_id = i.id),
        '{}'::smallint[]
    ) AS ods_codes
FROM academic_pi.project_impact i
JOIN academic_pi.project p ON p.id = i.project_id
WHERE i.status = 'approved'
  AND i.approved_at IS NOT NULL
  AND p.is_public
  AND p.status = 'published';

COMMENT ON TABLE academic_pi.project_impact IS
    'Impacto social do projeto. Valor vigente apenas (sem versoes/historico); conteudo aprovado so muda apos nova aprovacao. Nao guarda relato, imagem nem dado identificavel de beneficiario ou parceiro.';
COMMENT ON COLUMN academic_pi.project_impact.status IS 'draft, submitted, approved (publicado) ou retired (retirado da consulta publica). Transicoes sao regra do Backend.';
COMMENT ON COLUMN academic_pi.project_impact.beneficiaries_served IS 'Indicador beneficiarios_atendidos (inteiro >= 0).';
COMMENT ON COLUMN academic_pi.project_impact.activity_hours IS 'Indicador horas_atividade (decimal > 0). Total declarado do projeto; nao e soma de horas individuais de alunos.';
COMMENT ON COLUMN academic_pi.project_impact.partners_involved IS 'Indicador parceiros_envolvidos (inteiro >= 0), apenas a quantidade.';
COMMENT ON COLUMN academic_pi.project_impact.declared_by IS 'Origem: usuario responsavel pelo projeto que declarou o dado.';
COMMENT ON COLUMN academic_pi.project_impact.approved_by IS 'Usuario da coordenacao que aprovou; o papel e verificado pelo Backend.';
COMMENT ON VIEW academic_pi.public_project_impact IS
    'Unica fonte para a consulta publica de impacto: aprovado e de projeto publicado e publico.';

INSERT INTO public.schema_migration (version, description)
VALUES ('V0015', 'create project impact')
ON CONFLICT (version) DO NOTHING;

COMMIT;
