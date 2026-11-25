BEGIN;

-- DB-010: persiste criterios/pesos de rubrica de PI e evolui academic_pi.project_evaluation
-- (criada na DB-009 / V0009) com finalizacao/reabertura/correcao pelo docente responsavel
-- e notas vigentes por criterio sem historico, sem cristalizar regras de nota que aguardam
-- validacao formal do Andre (escala, precisao, arredondamento, agregacao, avaliacao ausente,
-- estados/prazos e titularidade da nota final).

-- 1. Criterios e pesos definidos pelo docente responsavel pelo projeto (PI)
CREATE TABLE IF NOT EXISTS academic_pi.evaluation_criterion (
    id uuid PRIMARY KEY,
    project_id uuid NOT NULL,
    defined_by_instructor_id uuid NOT NULL,
    name varchar(200) NOT NULL,
    description text,
    weight numeric NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT evaluation_criterion_project_fk
        FOREIGN KEY (project_id)
        REFERENCES academic_pi.project (id)
        ON DELETE RESTRICT,

    CONSTRAINT evaluation_criterion_defined_by_user_fk
        FOREIGN KEY (defined_by_instructor_id)
        REFERENCES auth."user" (id)
        ON DELETE RESTRICT,

    -- Garante que apenas um docente responsavel pelo projeto defina criterios
    CONSTRAINT evaluation_criterion_instructor_fk
        FOREIGN KEY (project_id, defined_by_instructor_id)
        REFERENCES academic_pi.project_instructor (project_id, instructor_id)
        ON DELETE RESTRICT,

    CONSTRAINT evaluation_criterion_name_ck
        CHECK (length(trim(name)) > 0),

    -- Peso positivo sem fixar escala maxima, precisao decimal ou soma obrigatoria (ex.: 100),
    -- que aguardam decisao formal do PO (SPEC-PI-003 / AC-PI-003-01).
    CONSTRAINT evaluation_criterion_weight_positive_ck
        CHECK (weight > 0),

    CONSTRAINT evaluation_criterion_project_name_unq
        UNIQUE (project_id, name),

    -- Alvo da FK composta de evaluation_criterion_score (impede nota em criterio de outro projeto)
    CONSTRAINT evaluation_criterion_id_project_unq
        UNIQUE (id, project_id)
);

CREATE INDEX IF NOT EXISTS idx_evaluation_criterion_project_id
    ON academic_pi.evaluation_criterion (project_id);

CREATE INDEX IF NOT EXISTS idx_evaluation_criterion_defined_by_instructor_id
    ON academic_pi.evaluation_criterion (defined_by_instructor_id);

COMMENT ON TABLE academic_pi.evaluation_criterion IS
    'Criterios e pesos de avaliacao definidos pelo docente responsavel pelo projeto (DB-010, SPEC-PI-003).';
COMMENT ON COLUMN academic_pi.evaluation_criterion.weight IS
    'Peso do criterio em numeric sem escala/precisao fixada ate validacao formal das regras de calculo (DB-010).';

-- 2. Evolucao incremental de academic_pi.project_evaluation (criada em V0009 / DB-009):
-- adiciona retorno textual geral e rastreio de finalizacao, reabertura e correcao pelo docente responsavel,
-- sem impor estados especulativos ou travas nao validadas pelo PO.
ALTER TABLE academic_pi.project_evaluation
    ADD COLUMN IF NOT EXISTS overall_feedback text,
    ADD COLUMN IF NOT EXISTS finalized_at timestamptz,
    ADD COLUMN IF NOT EXISTS finalized_by_instructor_id uuid,
    ADD COLUMN IF NOT EXISTS reopened_at timestamptz,
    ADD COLUMN IF NOT EXISTS reopened_by_instructor_id uuid,
    ADD COLUMN IF NOT EXISTS corrected_at timestamptz,
    ADD COLUMN IF NOT EXISTS corrected_by_instructor_id uuid;

DO $$
BEGIN
    -- Somente o docente responsavel pelo projeto pode finalizar, reabrir ou corrigir a avaliacao
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'project_evaluation_finalized_by_instructor_fk'
          AND conrelid = 'academic_pi.project_evaluation'::regclass
    ) THEN
        ALTER TABLE academic_pi.project_evaluation
            ADD CONSTRAINT project_evaluation_finalized_by_instructor_fk
            FOREIGN KEY (project_id, finalized_by_instructor_id)
            REFERENCES academic_pi.project_instructor (project_id, instructor_id)
            ON DELETE RESTRICT;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'project_evaluation_reopened_by_instructor_fk'
          AND conrelid = 'academic_pi.project_evaluation'::regclass
    ) THEN
        ALTER TABLE academic_pi.project_evaluation
            ADD CONSTRAINT project_evaluation_reopened_by_instructor_fk
            FOREIGN KEY (project_id, reopened_by_instructor_id)
            REFERENCES academic_pi.project_instructor (project_id, instructor_id)
            ON DELETE RESTRICT;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'project_evaluation_corrected_by_instructor_fk'
          AND conrelid = 'academic_pi.project_evaluation'::regclass
    ) THEN
        ALTER TABLE academic_pi.project_evaluation
            ADD CONSTRAINT project_evaluation_corrected_by_instructor_fk
            FOREIGN KEY (project_id, corrected_by_instructor_id)
            REFERENCES academic_pi.project_instructor (project_id, instructor_id)
            ON DELETE RESTRICT;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'project_evaluation_finalization_ck'
          AND conrelid = 'academic_pi.project_evaluation'::regclass
    ) THEN
        ALTER TABLE academic_pi.project_evaluation
            ADD CONSTRAINT project_evaluation_finalization_ck
            CHECK ((finalized_at IS NULL) = (finalized_by_instructor_id IS NULL));
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'project_evaluation_reopen_ck'
          AND conrelid = 'academic_pi.project_evaluation'::regclass
    ) THEN
        ALTER TABLE academic_pi.project_evaluation
            ADD CONSTRAINT project_evaluation_reopen_ck
            CHECK ((reopened_at IS NULL) = (reopened_by_instructor_id IS NULL));
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'project_evaluation_correction_ck'
          AND conrelid = 'academic_pi.project_evaluation'::regclass
    ) THEN
        ALTER TABLE academic_pi.project_evaluation
            ADD CONSTRAINT project_evaluation_correction_ck
            CHECK ((corrected_at IS NULL) = (corrected_by_instructor_id IS NULL));
    END IF;
END $$;

-- 3. Nota vigente por criterio na avaliacao (sem historico de valores anteriores)
CREATE TABLE IF NOT EXISTS academic_pi.evaluation_criterion_score (
    id uuid PRIMARY KEY,
    evaluation_id uuid NOT NULL,
    project_id uuid NOT NULL,
    criterion_id uuid NOT NULL,
    score numeric NOT NULL,
    feedback text,
    last_corrected_by_instructor_id uuid,
    last_corrected_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT evaluation_criterion_score_evaluation_fk
        FOREIGN KEY (evaluation_id, project_id)
        REFERENCES academic_pi.project_evaluation (id, project_id)
        ON DELETE RESTRICT,

    CONSTRAINT evaluation_criterion_score_criterion_fk
        FOREIGN KEY (criterion_id, project_id)
        REFERENCES academic_pi.evaluation_criterion (id, project_id)
        ON DELETE RESTRICT,

    CONSTRAINT evaluation_criterion_score_corrected_by_instructor_fk
        FOREIGN KEY (project_id, last_corrected_by_instructor_id)
        REFERENCES academic_pi.project_instructor (project_id, instructor_id)
        ON DELETE RESTRICT,

    CONSTRAINT evaluation_criterion_score_correction_ck
        CHECK ((last_corrected_at IS NULL) = (last_corrected_by_instructor_id IS NULL)),

    -- Um unico valor vigente por (evaluation_id, criterion_id): correcao substitui score via UPDATE
    CONSTRAINT evaluation_criterion_score_eval_criterion_unq
        UNIQUE (evaluation_id, criterion_id)
);

CREATE INDEX IF NOT EXISTS idx_evaluation_criterion_score_evaluation_id
    ON academic_pi.evaluation_criterion_score (evaluation_id);

CREATE INDEX IF NOT EXISTS idx_evaluation_criterion_score_criterion_id
    ON academic_pi.evaluation_criterion_score (criterion_id);

CREATE INDEX IF NOT EXISTS idx_evaluation_criterion_score_project_id
    ON academic_pi.evaluation_criterion_score (project_id);

COMMENT ON TABLE academic_pi.evaluation_criterion_score IS
    'Valor vigente de nota por criterio da avaliacao. Nao armazena historico anterior; correcao substitui score in-place (DB-010, AC-PI-003-05).';
COMMENT ON COLUMN academic_pi.evaluation_criterion_score.score IS
    'Valor vigente do criterio em numeric sem constraint de escala/precisao ate aprovacao formal do Andre (DB-010).';

INSERT INTO public.schema_migration (version, description)
VALUES ('V0010', 'create pi rubric and evaluation scores')
ON CONFLICT (version) DO NOTHING;

COMMIT;
