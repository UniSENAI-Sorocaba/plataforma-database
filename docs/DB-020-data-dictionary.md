# Dicionário de Dados — Plataforma Digital (`plataforma-database`) (DB-020)

Este dicionário consolida os schemas, tabelas, colunas, tipos de dados, restrições de integridade (*constraints*), triggers e índices efetivamente criados pelas migrations vigentes na branch `develop` (`V0001`, `V0002`, `V0003`, `V0004`, `V0006`, `V0007`, `V0008`, `V0009`, `V0011`, `V0013` e `V0017`, PostgreSQL 16).

> [!NOTE]
> Apenas objetos materializados nas migrations em `migrations/*.sql` da `develop` estão listados abaixo. Estruturas de entregas em andamento ou pendentes (ex.: critérios/notas da `DB-010`, valores de `assets.file_lifecycle_state`, tabelas conceituais do rascunho `DB-021`) são explicitamente diferenciadas do schema materializado.

---

## 1. Visão Geral dos Schemas

| Schema | Migration de Criação | Tabelas Vigentes (`develop`) | Observações |
| :--- | :--- | :--- | :--- |
| `public` | Padrão PostgreSQL (`V0001`–`V0006`) | `schema_migration`, `audit_event`, `roles`, `permissions`, `role_permissions`, `user_roles` | Controle de migrations, registro técnico mínimo e RBAC |
| `auth` | `V0001` | `user`, `user_identity`, `user_session` | Identidade central, federação OIDC/OAuth2 e sessões/tokens |
| `institutional` | `V0001` | `academic_class`, `academic_link` | Turmas acadêmicas e vínculos institucionais |
| `academic_pi` | `V0001` | `project`, `enrollment_period`, `project_instructor`, `project_participation`, `project_evaluation` | Projetos de PI/Extensão, inscrições, responsáveis e avaliações individuais (`V0009`) |
| `extension` | `V0001` | `activity` | Atividades e horas vigentes de extensão (`V0013`) |
| `assets` | `V0001` | `file_lifecycle_state`, `project_file` | Metadados e hash SHA-256 de artefatos (binários ficam fora do PostgreSQL) |

> **Postura de Segurança (`V0001`, validada por `scripts/validate.sh` passo 7):** nenhum dos 5 schemas de domínio (`auth`, `academic_pi`, `extension`, `assets`, `institutional`) concede `USAGE` ou `CREATE` à role `PUBLIC`.

---

## 2. Schema `public`

### 2.1 `public.schema_migration` (`V0001`)
Catálogo de versões aplicadas por `scripts/migrate.sh`.

| Coluna | Tipo | Nulo | Padrão | Descrição / Regra |
| :--- | :--- | :--- | :--- | :--- |
| `version` | `varchar(20)` | `NOT NULL` | — | **PK.** Identificador da migration (ex.: `V0001`, `V0009`, `V0013`) |
| `description` | `text` | `NOT NULL` | — | Descrição curta da migration |
| `applied_at` | `timestamptz` | `NOT NULL` | `now()` | Timestamp UTC de registro |

### 2.2 `public.audit_event` (`V0002`, restrita por `V0007`)
Registro técnico/operacional mínimo. Por força da **DB-007** (`V0007`), não armazena snapshots de valores acadêmicos ou de negócio.

| Coluna | Tipo | Nulo | Padrão | Descrição / Regra |
| :--- | :--- | :--- | :--- | :--- |
| `id` | `uuid` | `NOT NULL` | — | **PK** |
| `occurred_at` | `timestamptz` | `NOT NULL` | `now()` | Instante UTC do evento técnico |
| `schema_name` | `varchar(63)` | `NOT NULL` | — | `audit_event_schema_name_ck`: `schema_name <> ''` |
| `table_name` | `varchar(63)` | `NOT NULL` | — | `audit_event_table_name_ck`: `table_name <> ''` |
| `operation` | `varchar(10)` | `NOT NULL` | — | `audit_event_operation_ck`: `IN ('INSERT', 'UPDATE', 'DELETE')` |
| `record_id` | `uuid` | `NULL` | — | Identificador do registro afetado |
| `actor_id` | `uuid` | `NULL` | — | Identificador do ator técnico |
| `old_data` | `jsonb` | `NULL` | — | Descontinuada (`V0007`): `audit_event_no_snapshot_ck` exige `NULL` |
| `new_data` | `jsonb` | `NULL` | — | Descontinuada (`V0007`): `audit_event_no_snapshot_ck` exige `NULL` |

- **Índices:** `idx_audit_event_occurred_at`, `idx_audit_event_record`, `idx_audit_event_actor`.

### 2.3 `public.roles` (`V0006`)
Papéis institucionais de autorização (RBAC).

| Coluna | Tipo | Nulo | Padrão | Descrição / Regra |
| :--- | :--- | :--- | :--- | :--- |
| `id` | `serial` (`integer`) | `NOT NULL` | `nextval(...)` | **PK** |
| `name` | `varchar(50)` | `NOT NULL` | — | **UNIQUE.** `roles_name_ck`: `length(trim(name)) > 0` |
| `description` | `text` | `NULL` | — | Descrição do papel |
| `created_at` | `timestamptz` | `NOT NULL` | `CURRENT_TIMESTAMP` | Data de criação em UTC |

### 2.4 `public.permissions` (`V0006`)
Matriz de ações e recursos autorizáveis.

| Coluna | Tipo | Nulo | Padrão | Descrição / Regra |
| :--- | :--- | :--- | :--- | :--- |
| `id` | `serial` (`integer`) | `NOT NULL` | `nextval(...)` | **PK** |
| `action` | `varchar(50)` | `NOT NULL` | — | `permissions_action_ck`: `length(trim(action)) > 0` |
| `resource` | `varchar(50)` | `NOT NULL` | — | `permissions_resource_ck`: `length(trim(resource)) > 0` |
| `description` | `text` | `NULL` | — | Descrição da permissão |

- **Unique:** `uk_permissions_action_resource (action, resource)`.

### 2.5 `public.role_permissions` (`V0006`)
Associação N:N entre papéis e permissões.

| Coluna | Tipo | Nulo | Padrão | Descrição / Regra |
| :--- | :--- | :--- | :--- | :--- |
| `role_id` | `integer` | `NOT NULL` | — | **PK**, **FK** `roles(id)` (`ON DELETE CASCADE`) |
| `permission_id` | `integer` | `NOT NULL` | — | **PK**, **FK** `permissions(id)` (`ON DELETE CASCADE`) |

- **Índices:** `idx_role_permissions_role`, `idx_role_permissions_permission`.

### 2.6 `public.user_roles` (`V0006`)
Atribuição de papéis a usuários com escopo explícito.

| Coluna | Tipo | Nulo | Padrão | Descrição / Regra |
| :--- | :--- | :--- | :--- | :--- |
| `id` | `serial` (`integer`) | `NOT NULL` | `nextval(...)` | **PK** |
| `user_id` | `uuid` | `NOT NULL` | — | **FK** `user_roles_user_fk` -> `auth.user(id)` (`ON DELETE CASCADE`) |
| `role_id` | `integer` | `NOT NULL` | — | **FK** -> `roles(id)` (`ON DELETE CASCADE`) |
| `scope_type` | `varchar(30)` | `NOT NULL` | `'GLOBAL'` | `user_roles_scope_type_ck`: `IN ('GLOBAL', 'PROJETO', 'TURMA', 'CURSO')` |
| `scope_id` | `varchar(100)` | `NOT NULL` | `'*'` | `user_roles_scope_id_ck`, `user_roles_scope_consistency_ck` (`GLOBAL` exige `'*'`) |
| `assigned_at` | `timestamptz` | `NOT NULL` | `CURRENT_TIMESTAMP` | Instante da atribuição |
| `assigned_by` | `uuid` | `NULL` | — | **FK** `user_roles_assigned_by_fk` -> `auth.user(id)` (`ON DELETE SET NULL`) |

- **Unique:** `uk_user_role_scope (user_id, role_id, scope_type, scope_id)`.
- **Índices:** `idx_user_roles_lookup`, `idx_user_roles_role_id`.

---

## 3. Schema `auth`

### 3.1 `auth.user` (`V0003`)
Conta central de usuário da plataforma.

| Coluna | Tipo | Nulo | Padrão | Descrição / Regra |
| :--- | :--- | :--- | :--- | :--- |
| `id` | `uuid` | `NOT NULL` | — | **PK** |
| `email` | `varchar(255)` | `NOT NULL` | — | **UNIQUE** (`user_email_unq`). `user_email_ck` valida formato de e-mail |
| `full_name` | `varchar(255)` | `NOT NULL` | — | `user_full_name_ck`: `full_name <> '' AND length(trim(full_name)) >= 2` |
| `cpf` | `varchar(11)` | `NULL` | — | **UNIQUE** (`user_cpf_unq`). `user_cpf_ck`: `NULL` ou `^[0-9]{11}$` |
| `password_hash` | `varchar(255)` | `NULL` | — | `user_password_hash_ck`: `NULL` ou não vazio |
| `status` | `varchar(20)` | `NOT NULL` | `'pending'` | `user_status_ck`: `IN ('pending', 'active', 'inactive', 'suspended')` |
| `created_at` / `updated_at` | `timestamptz` | `NOT NULL` | `now()` | Criação / atualização em UTC |

- **Índices:** `idx_user_email`, `idx_user_status`, `idx_user_cpf`.

### 3.2 `auth.user_identity` (`V0003`)
Vínculo de identidade federada (OIDC / OAuth2).

| Coluna | Tipo | Nulo | Padrão | Descrição / Regra |
| :--- | :--- | :--- | :--- | :--- |
| `id` | `uuid` | `NOT NULL` | — | **PK** |
| `user_id` | `uuid` | `NOT NULL` | — | **FK** `user_identity_user_fk` -> `auth.user(id)` (`ON DELETE CASCADE`) |
| `provider` | `varchar(50)` | `NOT NULL` | — | `user_identity_provider_ck`: `provider <> ''` |
| `provider_subject` | `varchar(255)` | `NOT NULL` | — | `user_identity_provider_subject_ck`: `provider_subject <> ''` |
| `email` | `varchar(255)` | `NULL` | — | `user_identity_email_ck`: `NULL` ou contém `'@'` após posição 1 |
| `last_authenticated_at` | `timestamptz` | `NULL` | — | Última autenticação federada |
| `created_at` / `updated_at` | `timestamptz` | `NOT NULL` | `now()` | Criação / atualização em UTC |

- **Unique:** `user_identity_provider_subject_unq (provider, provider_subject)`.
- **Índices:** `idx_user_identity_user_id`, `idx_user_identity_provider_subject`.

### 3.3 `auth.user_session` (`V0004`)
Ciclo de vida de sessões e *refresh tokens* (apenas hash SHA-256).

| Coluna | Tipo | Nulo | Padrão | Descrição / Regra |
| :--- | :--- | :--- | :--- | :--- |
| `id` | `uuid` | `NOT NULL` | — | **PK** |
| `user_id` | `uuid` | `NOT NULL` | — | **FK** `user_session_user_fk` -> `auth.user(id)` (`ON DELETE CASCADE`) |
| `token_hash` | `varchar(64)` | `NOT NULL` | — | **UNIQUE** (`user_session_token_hash_unq`). `user_session_token_hash_ck`: 64 caracteres |
| `family_id` | `uuid` | `NOT NULL` | — | Família de rotação do token |
| `replaced_by_token_id` | `uuid` | `NULL` | — | **FK** `user_session_replaced_by_token_fk` -> `auth.user_session(id)` (`ON DELETE SET NULL`) |
| `client_ip` | `varchar(45)` | `NULL` | — | Endereço IP (IPv4/IPv6) |
| `user_agent` | `text` | `NULL` | — | User-agent do cliente |
| `created_at` | `timestamptz` | `NOT NULL` | `now()` | Emissão em UTC |
| `expires_at` | `timestamptz` | `NOT NULL` | — | `user_session_expires_at_ck`: `expires_at > created_at` |
| `revoked_at` / `last_used_at` | `timestamptz` | `NULL` | — | Revogação / último uso |

- **Índices:** `idx_user_session_user_id`, `idx_user_session_family_id`, `idx_user_session_active_lookup (WHERE revoked_at IS NULL)`.

---

## 4. Schema `institutional`

### 4.1 `institutional.academic_class` (`V0003`)
Turmas e agrupamentos acadêmicos.

| Coluna | Tipo | Nulo | Padrão | Descrição / Regra |
| :--- | :--- | :--- | :--- | :--- |
| `id` | `uuid` | `NOT NULL` | — | **PK** |
| `code` | `varchar(50)` | `NOT NULL` | — | **UNIQUE** (`academic_class_code_unq`). `academic_class_code_ck`: `code <> ''` |
| `name` | `varchar(255)` | `NOT NULL` | — | `academic_class_name_ck`: `name <> ''` |
| `term` | `varchar(20)` | `NOT NULL` | — | `academic_class_term_ck`: `term <> ''` (ex.: `2026.1`) |
| `is_active` | `boolean` | `NOT NULL` | `true` | Indica se a turma está ativa |
| `created_at` / `updated_at` | `timestamptz` | `NOT NULL` | `now()` | Criação / atualização em UTC |

- **Índices:** `idx_academic_class_code`, `idx_academic_class_term`, `idx_academic_class_is_active`.

### 4.2 `institutional.academic_link` (`V0003`)
Vínculo de usuário com turma e papel acadêmico.

| Coluna | Tipo | Nulo | Padrão | Descrição / Regra |
| :--- | :--- | :--- | :--- | :--- |
| `id` | `uuid` | `NOT NULL` | — | **PK** |
| `user_id` | `uuid` | `NOT NULL` | — | **FK** `academic_link_user_fk` -> `auth.user(id)` (`ON DELETE CASCADE`) |
| `class_id` | `uuid` | `NOT NULL` | — | **FK** `academic_link_class_fk` -> `institutional.academic_class(id)` (`ON DELETE RESTRICT`) |
| `role` | `varchar(30)` | `NOT NULL` | `'student'` | `academic_link_role_ck`: `IN ('student', 'professor', 'coordinator')` |
| `registration_number` | `varchar(50)` | `NULL` | — | `academic_link_registration_number_ck`: `NULL` ou `<> ''` |
| `status` | `varchar(20)` | `NOT NULL` | `'active'` | `academic_link_status_ck`: `IN ('active', 'inactive', 'completed', 'dropped')` |
| `created_at` / `updated_at` | `timestamptz` | `NOT NULL` | `now()` | Criação / atualização em UTC |

- **Unique:** `academic_link_user_class_role_unq (user_id, class_id, role)`.
- **Índices:** `idx_academic_link_user_id`, `idx_academic_link_class_id`, `idx_academic_link_status`.

---

## 5. Schema `academic_pi`

### 5.1 `academic_pi.project` (`V0008`, índice adicional `V0017`)
Projetos de PI, Extensão ou híbridos.

| Coluna | Tipo | Nulo | Padrão | Descrição / Regra |
| :--- | :--- | :--- | :--- | :--- |
| `id` | `uuid` | `NOT NULL` | — | **PK** |
| `title` | `varchar(200)` | `NOT NULL` | — | `project_title_ck`: `length(trim(title)) > 0` |
| `description` | `text` | `NULL` | — | Descrição do projeto |
| `is_pi` / `is_extension` | `boolean` | `NOT NULL` | `false` | `project_category_ck`: `is_pi OR is_extension` |
| `status` | `varchar(20)` | `NOT NULL` | `'draft'` | `project_status_ck`: `IN ('draft', 'published', 'archived')` |
| `is_public` | `boolean` | `NOT NULL` | `false` | Visibilidade no catálogo público |
| `starts_at` / `ends_at` | `timestamptz` | `NULL` | — | `project_period_ck`: `ends_at IS NULL OR starts_at IS NULL OR ends_at >= starts_at` |
| `created_at` / `updated_at` | `timestamptz` | `NOT NULL` | `now()` | Criação / atualização em UTC |

- **Unique:** `project_id_category_unq (id, is_pi, is_extension)`.
- **Índice:** `idx_project_public_title (title) WHERE is_public AND status = 'published'` (`V0017`).

### 5.2 `academic_pi.enrollment_period` (`V0008`)
Janelas de inscrição associadas a projetos.

| Coluna | Tipo | Nulo | Padrão | Descrição / Regra |
| :--- | :--- | :--- | :--- | :--- |
| `id` | `uuid` | `NOT NULL` | — | **PK** |
| `project_id` | `uuid` | `NOT NULL` | — | **FK** `enrollment_period_project_fk` -> `academic_pi.project(id)` (`ON DELETE RESTRICT`) |
| `opens_at` / `closes_at` | `timestamptz` | `NOT NULL` | — | `enrollment_period_window_ck`: `closes_at >= opens_at` |
| `created_at` / `updated_at` | `timestamptz` | `NOT NULL` | `now()` | Criação / atualização em UTC |

- **Índice:** `idx_enrollment_period_project_id`.

### 5.3 `academic_pi.project_instructor` (`V0008`)
Docentes responsáveis vinculados a cada projeto.

| Coluna | Tipo | Nulo | Padrão | Descrição / Regra |
| :--- | :--- | :--- | :--- | :--- |
| `id` | `uuid` | `NOT NULL` | — | **PK** |
| `project_id` | `uuid` | `NOT NULL` | — | **FK** `project_instructor_project_fk` -> `academic_pi.project(id)` (`ON DELETE RESTRICT`) |
| `instructor_id` | `uuid` | `NOT NULL` | — | **FK** `project_instructor_user_fk` -> `auth.user(id)` (`ON DELETE RESTRICT`) |
| `created_at` | `timestamptz` | `NOT NULL` | `now()` | Criação em UTC |

- **Unique:** `project_instructor_project_instructor_unq (project_id, instructor_id)`.
- **Índice:** `idx_project_instructor_instructor_id`.

### 5.4 `academic_pi.project_participation` (`V0008`)
Solicitações e vínculos ativos/encerrados de alunos nos projetos.

| Coluna | Tipo | Nulo | Padrão | Descrição / Regra |
| :--- | :--- | :--- | :--- | :--- |
| `id` | `uuid` | `NOT NULL` | — | **PK** |
| `project_id` | `uuid` | `NOT NULL` | — | **FK composta** `project_participation_project_fk (project_id, is_pi, is_extension)` -> `academic_pi.project` (`ON DELETE RESTRICT`) |
| `is_pi` / `is_extension` | `boolean` | `NOT NULL` | — | `project_participation_category_ck`: `is_pi OR is_extension` |
| `student_id` | `uuid` | `NOT NULL` | — | **FK** `project_participation_user_fk` -> `auth.user(id)` (`ON DELETE RESTRICT`) |
| `status` | `varchar(20)` | `NOT NULL` | `'requested'` | `project_participation_status_ck`: `IN ('requested', 'approved', 'denied', 'withdrawn', 'removed')` |
| `justification` | `text` | `NULL` | — | `project_participation_justification_ck`: obrigatória e não vazia quando `status = 'removed'` |
| `requested_at` / `decided_at` | `timestamptz` | `NOT NULL` / `NULL` | `now()` / — | Solicitação e decisão |
| `created_at` / `updated_at` | `timestamptz` | `NOT NULL` | `now()` | Criação / atualização em UTC |

- **Unique:** `project_participation_project_student_unq (project_id, student_id)`.
- **Índices:** `idx_project_participation_student_id`, `idx_project_participation_student_active_pi`, `idx_project_participation_student_active_extension`.

### 5.5 `academic_pi.project_evaluation` (`V0009`)
Avaliação individual vinculada a projeto, usuário avaliador e aluno participante avaliado, sem entidade ou agenda de banca.

| Coluna | Tipo | Nulo | Padrão | Descrição / Regra |
| :--- | :--- | :--- | :--- | :--- |
| `id` | `uuid` | `NOT NULL` | — | **PK** |
| `project_id` | `uuid` | `NOT NULL` | — | **FK** `project_evaluation_project_fk` -> `academic_pi.project(id)` (`ON DELETE RESTRICT`) |
| `evaluator_user_id` | `uuid` | `NOT NULL` | — | **FK** `project_evaluation_evaluator_user_fk` -> `auth.user(id)` (`ON DELETE RESTRICT`) |
| `evaluated_student_id` | `uuid` | `NOT NULL` | — | **FK** `project_evaluation_evaluated_user_fk` -> `auth.user(id)`; **FK composta** `project_evaluation_participation_fk (project_id, evaluated_student_id)` -> `academic_pi.project_participation` (`ON DELETE RESTRICT`) |
| `assigned_by_user_id` | `uuid` | `NULL` | — | **FK** `project_evaluation_assigned_by_user_fk` -> `auth.user(id)` (`ON DELETE RESTRICT`) |
| `evaluation_date` | `date` | `NULL` | — | `project_evaluation_assignment_ck`: `(assigned_by_user_id IS NULL) = (evaluation_date IS NULL)` |
| `created_at` / `updated_at` | `timestamptz` | `NOT NULL` | `now()` | Carimbos UTC |

- **Unique:** `project_evaluation_id_project_unq (id, project_id)`.
- **Índices:** `idx_project_evaluation_project_id`, `idx_project_evaluation_evaluator_user_id`, `idx_project_evaluation_evaluated_student_id`, `idx_project_evaluation_assigned_by_user_id (WHERE assigned_by_user_id IS NOT NULL)`.

> *(Nota: critérios/pesos e extensões de finalização/reabertura/correção fazem parte da entrega **DB-010**, em PR separado.)*

---

## 6. Schema `extension`

### 6.1 `extension.activity` (`V0013`)
Atividades de Extensão e horas vigentes validadas por docente responsável, sem histórico de valores anteriores.

| Coluna | Tipo | Nulo | Padrão | Descrição / Regra |
| :--- | :--- | :--- | :--- | :--- |
| `id` | `uuid` | `NOT NULL` | — | **PK** |
| `participation_id` | `uuid` | `NOT NULL` | — | **FK** `activity_participation_fk` -> `academic_pi.project_participation(id)` (`ON DELETE RESTRICT`) |
| `project_id` | `uuid` | `NOT NULL` | — | **FK** `activity_project_fk` -> `academic_pi.project(id)` (`ON DELETE RESTRICT`) |
| `student_id` | `uuid` | `NOT NULL` | — | **FK** `activity_student_user_fk` -> `auth.user(id)`; **FK composta** `activity_project_student_participation_fk (project_id, student_id)` -> `academic_pi.project_participation` |
| `title` | `varchar(200)` | `NOT NULL` | — | `activity_title_ck`: `length(trim(title)) > 0` |
| `description` | `text` | `NOT NULL` | — | `activity_description_ck`: `length(trim(description)) > 0` |
| `submitted_at` | `timestamptz` | `NOT NULL` | `now()` | Submissão da atividade em UTC |
| `validated_hours` | `numeric` | `NULL` | — | `activity_validated_hours_positive_ck`: `NULL` ou `> 0` (sem escala/unidade cristalizada) |
| `last_validated_by` | `uuid` | `NULL` | — | **FK** `activity_last_validated_by_user_fk` -> `auth.user(id)`; **FK composta** `activity_last_validated_by_instructor_fk (project_id, last_validated_by)` -> `academic_pi.project_instructor` |
| `last_validated_at` | `timestamptz` | `NULL` | — | `activity_validation_consistency_ck`: `validated_hours`, `last_validated_by` e `last_validated_at` todos `NULL` ou todos preenchidos |
| `created_at` / `updated_at` | `timestamptz` | `NOT NULL` | `now()` | Carimbos UTC |

- **Trigger:** `activity_participation_and_window_trg` (`extension.validate_activity_participation_and_window()`): valida coerência com `participation_id`, exigência de `is_extension = true`, status `'approved'` e janela `[starts_at, ends_at]` do projeto no envio/edição pelo aluno.
- **Índices:** `idx_activity_participation_id`, `idx_activity_project_id`, `idx_activity_student_id`, `idx_activity_last_validated_by (WHERE last_validated_by IS NOT NULL)`.

---

## 7. Schema `assets`

### 7.1 `assets.file_lifecycle_state` (`V0011`)
Tabela de domínio para estados de ciclo de vida de arquivos. **Nasce vazia por decisão** até definição formal de Produto/Infra (`SPEC-PI-004`).

| Coluna | Tipo | Nulo | Padrão | Descrição / Regra |
| :--- | :--- | :--- | :--- | :--- |
| `code` | `varchar(50)` | `NOT NULL` | — | **PK.** `file_lifecycle_state_code_ck`: `code ~ '^[a-z][a-z0-9_]*$'` |
| `created_at` | `timestamptz` | `NOT NULL` | `now()` | Criação em UTC |

### 7.2 `assets.project_file` (`V0011`)
Metadados de arquivos vinculados a projetos (sem armazenamento de binário no banco).

| Coluna | Tipo | Nulo | Padrão | Descrição / Regra |
| :--- | :--- | :--- | :--- | :--- |
| `id` | `uuid` | `NOT NULL` | — | **PK** |
| `project_id` | `uuid` | `NOT NULL` | — | **FK** `project_file_project_fk` -> `academic_pi.project(id)` (`ON DELETE RESTRICT`) |
| `owner_user_id` | `uuid` | `NOT NULL` | — | **FK** `project_file_owner_user_fk` -> `auth.user(id)` (`ON DELETE RESTRICT`) |
| `file_type` | `varchar(10)` | `NOT NULL` | — | `project_file_file_type_ck`: `IN ('pdf', 'docx', 'image')` |
| `hash_algorithm` | `varchar(20)` | `NOT NULL` | `'sha256'` | `project_file_hash_algorithm_ck`: `hash_algorithm = 'sha256'` |
| `content_hash` | `varchar(64)` | `NOT NULL` | — | `project_file_content_hash_ck`: `content_hash ~ '^[0-9a-f]{64}$'` |
| `storage_ref` | `varchar(1024)` | `NOT NULL` | — | **UNIQUE** (`project_file_storage_ref_unq`). `project_file_storage_ref_ck`: `length(trim(storage_ref)) > 0` |
| `lifecycle_state` | `varchar(50)` | `NOT NULL` | — | **FK** `project_file_lifecycle_state_fk` -> `assets.file_lifecycle_state(code)` |
| `publication_authorized` | `boolean` | `NOT NULL` | `false` | `project_file_publication_ck`: se `true`, exige `publication_authorized_by IS NOT NULL` |
| `publication_authorized_by` | `uuid` | `NULL` | — | **FK** `project_file_publication_authorizer_fk` -> `auth.user(id)` |
| `created_at` / `updated_at` | `timestamptz` | `NOT NULL` | `now()` | Carimbos UTC |

- **Índices:** `idx_project_file_project_id`, `idx_project_file_owner_user_id`, `idx_project_file_content_hash`, `idx_project_file_lifecycle_state`, `idx_project_file_publication_authorized_by (WHERE publication_authorized_by IS NOT NULL)`.
