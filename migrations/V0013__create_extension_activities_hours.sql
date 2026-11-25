BEGIN;

-- DB-013: persistencia de atividades e horas vigentes de Extensao sem historico de valores
-- anteriores nem trilha de auditoria de negocio (Issue #13, Caderno de Validacoes, DB-007, DB-012).
-- Regras funcionais dependentes de validacao formal do Andre (unidade e limites de horas,
-- estados da atividade, tratamento/motivo de recusa, possibilidade de reenvio apos recusa e
-- resolucao do conflito R61/R62 sobre prorrogacao/ajuste de prazo) nao sao cristalizadas
-- prematuramente neste schema.

CREATE TABLE IF NOT EXISTS extension.activity (
    id uuid PRIMARY KEY,
    participation_id uuid NOT NULL,
    project_id uuid NOT NULL,
    student_id uuid NOT NULL,
    title varchar(200) NOT NULL,
    description text NOT NULL,
    submitted_at timestamptz NOT NULL DEFAULT now(),
    validated_hours numeric,
    last_validated_by uuid,
    last_validated_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT activity_participation_fk
        FOREIGN KEY (participation_id)
        REFERENCES academic_pi.project_participation (id)
        ON DELETE RESTRICT,

    CONSTRAINT activity_project_fk
        FOREIGN KEY (project_id)
        REFERENCES academic_pi.project (id)
        ON DELETE RESTRICT,

    CONSTRAINT activity_student_user_fk
        FOREIGN KEY (student_id)
        REFERENCES auth."user" (id)
        ON DELETE RESTRICT,

    -- Garante vinculo coerente entre projeto e aluno participante registrado em V0008
    CONSTRAINT activity_project_student_participation_fk
        FOREIGN KEY (project_id, student_id)
        REFERENCES academic_pi.project_participation (project_id, student_id)
        ON DELETE RESTRICT,

    CONSTRAINT activity_last_validated_by_user_fk
        FOREIGN KEY (last_validated_by)
        REFERENCES auth."user" (id)
        ON DELETE RESTRICT,

    -- Garante no banco que somente um docente responsavel pelo projeto pode definir e validar horas
    CONSTRAINT activity_last_validated_by_instructor_fk
        FOREIGN KEY (project_id, last_validated_by)
        REFERENCES academic_pi.project_instructor (project_id, instructor_id)
        ON DELETE RESTRICT,

    CONSTRAINT activity_title_ck
        CHECK (length(trim(title)) > 0),

    CONSTRAINT activity_description_ck
        CHECK (length(trim(description)) > 0),

    -- Horas vigentes em numeric sem escala/precisao nem limites arbitraros ate validacao do Andre
    CONSTRAINT activity_validated_hours_positive_ck
        CHECK (validated_hours IS NULL OR validated_hours > 0),

    -- Quando ha horas vigentes definidas, exige identificacao e instante de quem validou por ultimo
    CONSTRAINT activity_validation_consistency_ck
        CHECK (
            (validated_hours IS NULL AND last_validated_by IS NULL AND last_validated_at IS NULL)
            OR (validated_hours IS NOT NULL AND last_validated_by IS NOT NULL AND last_validated_at IS NOT NULL)
        )
);

CREATE INDEX IF NOT EXISTS idx_activity_participation_id
    ON extension.activity (participation_id);

CREATE INDEX IF NOT EXISTS idx_activity_project_id
    ON extension.activity (project_id);

CREATE INDEX IF NOT EXISTS idx_activity_student_id
    ON extension.activity (student_id);

CREATE INDEX IF NOT EXISTS idx_activity_last_validated_by
    ON extension.activity (last_validated_by)
    WHERE last_validated_by IS NOT NULL;

-- Valida coerencia exata da participacao (participation_id = (project_id, student_id)),
-- categoria de Extensao (is_extension = true), participacao aprovada no envio/edicao do aluno
-- e janela do projeto [starts_at, ends_at] para envio/correcao de informacoes pelo aluno,
-- sem cristalizar o conflito R61/R62 sobre ajuste de datas do projeto.
CREATE OR REPLACE FUNCTION extension.validate_activity_participation_and_window()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_part_project_id uuid;
    v_part_student_id uuid;
    v_is_extension boolean;
    v_part_status varchar(20);
    v_proj_starts_at timestamptz;
    v_proj_ends_at timestamptz;
BEGIN
    SELECT pp.project_id, pp.student_id, pp.is_extension, pp.status, p.starts_at, p.ends_at
      INTO v_part_project_id, v_part_student_id, v_is_extension, v_part_status, v_proj_starts_at, v_proj_ends_at
      FROM academic_pi.project_participation pp
      JOIN academic_pi.project p ON p.id = pp.project_id
     WHERE pp.id = NEW.participation_id;

    IF v_part_project_id IS NULL
       OR v_part_project_id <> NEW.project_id
       OR v_part_student_id <> NEW.student_id THEN
        RAISE EXCEPTION 'activity participation_id (%) does not match (project_id %, student_id %)',
            NEW.participation_id, NEW.project_id, NEW.student_id
            USING ERRCODE = '23503';
    END IF;

    IF NOT v_is_extension THEN
        RAISE EXCEPTION 'extension activity requires a project participation with is_extension = true'
            USING ERRCODE = '23514';
    END IF;

    IF TG_OP = 'INSERT' THEN
        IF v_part_status <> 'approved' THEN
            RAISE EXCEPTION 'extension activity submission requires an approved project participation (current: %)',
                v_part_status
                USING ERRCODE = '23514';
        END IF;

        IF v_proj_starts_at IS NOT NULL AND NEW.submitted_at < v_proj_starts_at THEN
            RAISE EXCEPTION 'activity submitted_at (%) precedes project starts_at (%)',
                NEW.submitted_at, v_proj_starts_at
                USING ERRCODE = '23514';
        END IF;

        IF v_proj_ends_at IS NOT NULL AND NEW.submitted_at > v_proj_ends_at THEN
            RAISE EXCEPTION 'activity submitted_at (%) exceeds project ends_at (%)',
                NEW.submitted_at, v_proj_ends_at
                USING ERRCODE = '23514';
        END IF;
    ELSIF TG_OP = 'UPDATE' THEN
        IF NEW.participation_id IS DISTINCT FROM OLD.participation_id
           OR NEW.project_id IS DISTINCT FROM OLD.project_id
           OR NEW.student_id IS DISTINCT FROM OLD.student_id
           OR NEW.title IS DISTINCT FROM OLD.title
           OR NEW.description IS DISTINCT FROM OLD.description
           OR NEW.submitted_at IS DISTINCT FROM OLD.submitted_at THEN

            IF v_part_status <> 'approved' THEN
                RAISE EXCEPTION 'student activity modification requires an approved project participation (current: %)',
                    v_part_status
                    USING ERRCODE = '23514';
            END IF;

            IF v_proj_starts_at IS NOT NULL AND (NEW.submitted_at < v_proj_starts_at OR now() < v_proj_starts_at) THEN
                RAISE EXCEPTION 'student activity modification is not allowed before project starts_at (%)',
                    v_proj_starts_at
                    USING ERRCODE = '23514';
            END IF;

            IF v_proj_ends_at IS NOT NULL AND (NEW.submitted_at > v_proj_ends_at OR now() > v_proj_ends_at) THEN
                RAISE EXCEPTION 'student activity modification is not allowed after project ends_at (%)',
                    v_proj_ends_at
                    USING ERRCODE = '23514';
            END IF;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS activity_participation_and_window_trg ON extension.activity;
CREATE TRIGGER activity_participation_and_window_trg
    BEFORE INSERT OR UPDATE ON extension.activity
    FOR EACH ROW
    EXECUTE FUNCTION extension.validate_activity_participation_and_window();

COMMENT ON TABLE extension.activity IS
    'Atividade de Extensao vinculada a participacao do aluno. Persiste somente o estado e horas vigentes e quem validou por ultimo, sem historico de valores anteriores (DB-013).';
COMMENT ON COLUMN extension.activity.validated_hours IS
    'Quantidade vigente de horas definida e validada pelo docente responsavel, em numeric sem unidade/escala cristalizada ate decisao formal do PO (DB-013).';
COMMENT ON COLUMN extension.activity.last_validated_by IS
    'Identificacao do docente responsavel pelo projeto que validou por ultimo o valor vigente de horas (DB-013).';

INSERT INTO public.schema_migration (version, description)
VALUES ('V0013', 'create extension activities and hours')
ON CONFLICT (version) DO NOTHING;

COMMIT;
