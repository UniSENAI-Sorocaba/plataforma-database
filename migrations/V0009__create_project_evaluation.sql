BEGIN;

-- DB-009: persistencia de avaliacoes individuais vinculadas a projeto, avaliador e aluno
-- participante avaliado, sem entidade ou agenda de banca (Issue #9, SPEC-PI-002 / SPEC-PI-003).
-- Regras funcionais dependentes de validacao formal do Andre (autorizacao detalhada de
-- avaliadores na Extensao, relacao entre atribuicoes discentes e avaliacoes docentes,
-- unicidade por tripla, autoavaliacao, estados/prazos e visibilidade por papel) nao sao
-- cristalizadas prematuramente neste schema.

CREATE TABLE IF NOT EXISTS academic_pi.project_evaluation (
    id uuid PRIMARY KEY,
    project_id uuid NOT NULL,
    evaluator_user_id uuid NOT NULL,
    evaluated_student_id uuid NOT NULL,
    assigned_by_user_id uuid,
    evaluation_date date,
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

    -- Garante que o aluno avaliado pertence ao projeto (participacao registrada em V0008)
    CONSTRAINT project_evaluation_participation_fk
        FOREIGN KEY (project_id, evaluated_student_id)
        REFERENCES academic_pi.project_participation (project_id, student_id)
        ON DELETE RESTRICT,

    CONSTRAINT project_evaluation_assigned_by_user_fk
        FOREIGN KEY (assigned_by_user_id)
        REFERENCES auth."user" (id)
        ON DELETE RESTRICT,

    -- Consistencia de atribuicao: no PI, quando ha atribuicao pela coordenacao, registra-se
    -- conjuntamente quem atribuiu e a data atribuida; avaliacoes diretas sem atribuicao mantem ambos nulos.
    CONSTRAINT project_evaluation_assignment_ck
        CHECK ((assigned_by_user_id IS NULL) = (evaluation_date IS NULL)),

    -- Alvo de FK composta para notas por criterio na DB-010 (impede referencia cruzada entre projetos)
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
    'Avaliacao individual vinculada a projeto, usuario avaliador e aluno participante avaliado, sem entidade ou agenda de banca (DB-009).';
COMMENT ON COLUMN academic_pi.project_evaluation.assigned_by_user_id IS
    'Usuario que realizou a atribuicao do avaliador (ex.: coordenacao no PI); nulo em avaliacoes adicionadas sem atribuicao previa.';
COMMENT ON COLUMN academic_pi.project_evaluation.evaluation_date IS
    'Data atribuida para a avaliacao quando ha atribuicao registrada em assigned_by_user_id.';

INSERT INTO public.schema_migration (version, description)
VALUES ('V0009', 'create project evaluation')
ON CONFLICT (version) DO NOTHING;

COMMIT;
