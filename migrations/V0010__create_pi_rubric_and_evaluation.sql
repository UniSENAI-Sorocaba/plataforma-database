BEGIN;

-- DB-010: persiste criterios/pesos de rubrica de PI e avaliacoes individuais vinculadas a
-- projeto, avaliador e aluno avaliado (conforme DB-009 e SPEC-PI-002 / SPEC-PI-003), sem
-- cristalizar regras de nota que aguardam validacao formal do Andre (escala, precisao,
-- arredondamento, agregacao, avaliacao ausente, estados/prazos e titularidade da nota final).

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

-- 2. Avaliacao individual vinculada a projeto, avaliador e aluno avaliado (sem entidade/agenda de banca)
CREATE TABLE IF NOT EXISTS academic_pi.project_evaluation (
    id uuid PRIMARY KEY,
    project_id uuid NOT NULL,
    evaluator_user_id uuid NOT NULL,
    evaluated_student_id uuid NOT NULL,
    assigned_by_user_id uuid,
    evaluation_date date,
    overall_feedback text,
    finalized_at timestamptz,
    finalized_by_instructor_id uuid,
    reopened_at timestamptz,
    reopened_by_instructor_id uuid,
    corrected_at timestamptz,
    corrected_by_instructor_id uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT project_evaluation_project_fk
        FOREIGN KEY (project_id)
        REFERENCES academic_pi.project (id)
        ON DELETE RESTRICT,

    CONSTRAINT project_evaluation_evaluator_user_fk
        FOREIGN KEY (evaluator_user_id)
        REFERENCES auth."user" (id)
        ON DELETE RESTRICT,

    CONSTRAINT project_evaluation_evaluated_user_fk
        FOREIGN KEY (evaluated_student_id)
        REFERENCES auth."user" (id)
        ON DELETE RESTRICT,

    -- Garante que o aluno avaliado pertence ao projeto (DB-009 / DB-010)
    CONSTRAINT project_evaluation_participation_fk
        FOREIGN KEY (project_id, evaluated_student_id)
        REFERENCES academic_pi.project_participation (project_id, student_id)
        ON DELETE RESTRICT,

    CONSTRAINT project_evaluation_assigned_by_user_fk
        FOREIGN KEY (assigned_by_user_id)
        REFERENCES auth."user" (id)
        ON DELETE RESTRICT,

    -- Somente o docente responsavel pelo projeto pode finalizar, reabrir ou corrigir a avaliacao
    CONSTRAINT project_evaluation_finalized_by_instructor_fk
        FOREIGN KEY (project_id, finalized_by_instructor_id)
        REFERENCES academic_pi.project_instructor (project_id, instructor_id)
        ON DELETE RESTRICT,

    CONSTRAINT project_evaluation_reopened_by_instructor_fk
        FOREIGN KEY (project_id, reopened_by_instructor_id)
        REFERENCES academic_pi.project_instructor (project_id, instructor_id)
        ON DELETE RESTRICT,

    CONSTRAINT project_evaluation_corrected_by_instructor_fk
        FOREIGN KEY (project_id, corrected_by_instructor_id)
        REFERENCES academic_pi.project_instructor (project_id, instructor_id)
        ON DELETE RESTRICT,

    CONSTRAINT project_evaluation_distinct_actors_ck
        CHECK (evaluator_user_id <> evaluated_student_id),

    -- Quando a coordenacao atribui o avaliador, registra tambem a data da avaliacao
    CONSTRAINT project_evaluation_assignment_ck
        CHECK (assigned_by_user_id IS NULL OR evaluation_date IS NOT NULL),

    CONSTRAINT project_evaluation_finalization_ck
        CHECK ((finalized_at IS NULL) = (finalized_by_instructor_id IS NULL)),

    CONSTRAINT project_evaluation_reopen_ck
        CHECK ((reopened_at IS NULL) = (reopened_by_instructor_id IS NULL)),

    CONSTRAINT project_evaluation_correction_ck
        CHECK ((corrected_at IS NULL) = (corrected_by_instructor_id IS NULL)),

    CONSTRAINT project_evaluation_triplet_unq
        UNIQUE (project_id, evaluator_user_id, evaluated_student_id),

    -- Alvo da FK composta de evaluation_criterion_score
    CONSTRAINT project_evaluation_id_project_unq
        UNIQUE (id, project_id)
);

CREATE INDEX IF NOT EXISTS idx_project_evaluation_project_id
    ON academic_pi.project_evaluation (project_id);

CREATE INDEX IF NOT EXISTS idx_project_evaluation_evaluator_user_id
    ON academic_pi.project_evaluation (evaluator_user_id);

CREATE INDEX IF NOT EXISTS idx_project_evaluation_evaluated_student_id
    ON academic_pi.project_evaluation (evaluated_student_id);

CREATE INDEX IF NOT EXISTS idx_project_evaluation_assigned_by_user_id
    ON academic_pi.project_evaluation (assigned_by_user_id)
    WHERE assigned_by_user_id IS NOT NULL;

COMMENT ON TABLE academic_pi.project_evaluation IS
    'Avaliacao individual vinculada a projeto, avaliador e aluno participante, sem entidade de banca e sem estado/formula especulativos (DB-009, DB-010).';

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
VALUES ('V0010', 'create pi rubric and evaluation tables')
ON CONFLICT (version) DO NOTHING;

COMMIT;
