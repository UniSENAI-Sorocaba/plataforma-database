BEGIN;

-- DB-011: metadados de arquivos de projeto (SPEC-PI-004). O conteudo binario fica fora
-- do PostgreSQL (armazenamento externo); aqui ficam apenas hash, proprietario, tipo,
-- lifecycle e a referencia ao objeto armazenado.

-- Estados de lifecycle ainda NAO foram definidos por Produto/Infra (SPEC-PI-004).
-- A tabela nasce vazia: os valores serao inseridos por migration propria quando aprovados.
CREATE TABLE IF NOT EXISTS assets.file_lifecycle_state (
    code varchar(50) PRIMARY KEY,
    created_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT file_lifecycle_state_code_ck
        CHECK (code ~ '^[a-z][a-z0-9_]*$')
);

COMMENT ON TABLE assets.file_lifecycle_state IS
    'Estados de lifecycle de arquivos. Sem valores ate Produto/Infra aprovarem (SPEC-PI-004).';

CREATE TABLE IF NOT EXISTS assets.project_file (
    id uuid PRIMARY KEY,
    project_id uuid NOT NULL,
    owner_user_id uuid NOT NULL,
    file_type varchar(10) NOT NULL,
    hash_algorithm varchar(20) NOT NULL DEFAULT 'sha256',
    content_hash varchar(64) NOT NULL,
    storage_ref varchar(1024) NOT NULL,
    lifecycle_state varchar(50) NOT NULL,
    publication_authorized boolean NOT NULL DEFAULT false,
    publication_authorized_by uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT project_file_project_fk
        FOREIGN KEY (project_id)
        REFERENCES academic_pi.project (id)
        ON DELETE RESTRICT,

    CONSTRAINT project_file_owner_user_fk
        FOREIGN KEY (owner_user_id)
        REFERENCES auth.user (id)
        ON DELETE RESTRICT,

    CONSTRAINT project_file_lifecycle_state_fk
        FOREIGN KEY (lifecycle_state)
        REFERENCES assets.file_lifecycle_state (code)
        ON DELETE RESTRICT,

    CONSTRAINT project_file_publication_authorizer_fk
        FOREIGN KEY (publication_authorized_by)
        REFERENCES auth.user (id)
        ON DELETE RESTRICT,

    -- Tipos aprovados no Caderno (item 51): PDF, DOCX e imagem. Limite de tamanho e MIME
    -- ainda nao foram definidos e nao sao fixados aqui.
    CONSTRAINT project_file_file_type_ck
        CHECK (file_type IN ('pdf', 'docx', 'image')),

    CONSTRAINT project_file_hash_algorithm_ck
        CHECK (hash_algorithm = 'sha256'),

    CONSTRAINT project_file_content_hash_ck
        CHECK (content_hash ~ '^[0-9a-f]{64}$'),

    CONSTRAINT project_file_storage_ref_ck
        CHECK (length(trim(storage_ref)) > 0),

    -- Acesso interno nao implica publicacao: publicar exige autorizacao registrada.
    CONSTRAINT project_file_publication_ck
        CHECK (NOT publication_authorized OR publication_authorized_by IS NOT NULL),

    CONSTRAINT project_file_storage_ref_unq
        UNIQUE (storage_ref)
);

CREATE INDEX IF NOT EXISTS idx_project_file_project_id
    ON assets.project_file (project_id);

CREATE INDEX IF NOT EXISTS idx_project_file_owner_user_id
    ON assets.project_file (owner_user_id);

CREATE INDEX IF NOT EXISTS idx_project_file_content_hash
    ON assets.project_file (content_hash);

CREATE INDEX IF NOT EXISTS idx_project_file_lifecycle_state
    ON assets.project_file (lifecycle_state);

CREATE INDEX IF NOT EXISTS idx_project_file_publication_authorized_by
    ON assets.project_file (publication_authorized_by)
    WHERE publication_authorized_by IS NOT NULL;

COMMENT ON TABLE assets.project_file IS
    'Metadados de arquivos de projeto. O binario NAO e armazenado no PostgreSQL; storage_ref aponta para o objeto externo.';
COMMENT ON COLUMN assets.project_file.content_hash IS
    'Hash SHA-256 do conteudo em hexadecimal minusculo, para conferir a integridade do objeto externo.';

INSERT INTO public.schema_migration (version, description)
VALUES ('V0011', 'create project file metadata')
ON CONFLICT (version) DO NOTHING;

COMMIT;
