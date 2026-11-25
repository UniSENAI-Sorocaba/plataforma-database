BEGIN;

-- DB-015: impacto social publicado. Definicoes aprovadas pelo PO em 21/11/2026
-- (plataforma-governance, _KB/product/mvp-decisions-2026-11-21.md, secao 6), branch release/v1.0.0.
-- Regras: o responsavel pelo projeto declara; a coordenacao aprova; sem estimativa automatica;
-- correcao SUBSTITUI o conteudo vigente (sem tabela de versoes nem historico); retirada desliga a publicacao.
-- Nao ha coluna para relato, imagem, identificacao de beneficiario ou de parceiro (dados identificaveis nao entram).

CREATE TABLE IF NOT EXISTS academic_pi.project_impact (
    id uuid PRIMARY KEY,
    project_id uuid NOT NULL,
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
    is_published boolean NOT NULL DEFAULT false,
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

    -- Publicacao nunca e implicita: exige aprovacao e todos os campos obrigatorios do impacto publicado.
    CONSTRAINT project_impact_publication_ck
        CHECK (
            NOT is_published
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

CREATE INDEX IF NOT EXISTS idx_project_impact_published_project_id
    ON academic_pi.project_impact (project_id)
    WHERE is_published;

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

-- Consulta publica: somente impacto aprovado e publicado de projeto publicado e publico.
-- Nao expoe evidence_text, declared_by, approved_by nem approved_at (decisao de expor evidencia pendente).
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
WHERE i.is_published
  AND i.approved_at IS NOT NULL
  AND p.is_public
  AND p.status = 'published';

COMMENT ON TABLE academic_pi.project_impact IS
    'Impacto social do projeto. Valor vigente apenas: correcao substitui o conteudo (sem versoes/historico). Nao guarda relato, imagem nem dado identificavel de beneficiario ou parceiro.';
COMMENT ON COLUMN academic_pi.project_impact.beneficiaries_served IS 'Indicador beneficiarios_atendidos (inteiro >= 0).';
COMMENT ON COLUMN academic_pi.project_impact.activity_hours IS 'Indicador horas_atividade (decimal > 0). Total declarado do projeto; nao e soma de horas individuais de alunos.';
COMMENT ON COLUMN academic_pi.project_impact.partners_involved IS 'Indicador parceiros_envolvidos (inteiro >= 0), apenas a quantidade.';
COMMENT ON COLUMN academic_pi.project_impact.declared_by IS 'Origem: usuario responsavel pelo projeto que declarou o dado.';
COMMENT ON COLUMN academic_pi.project_impact.approved_by IS 'Usuario da coordenacao que aprovou; o papel e verificado pelo Backend.';
COMMENT ON VIEW academic_pi.public_project_impact IS
    'Unica fonte para a consulta publica de impacto: aprovado, publicado e de projeto publico.';

INSERT INTO public.schema_migration (version, description)
VALUES ('V0015', 'create project impact')
ON CONFLICT (version) DO NOTHING;

COMMIT;
