# DB-011: Metadados de artefatos

## 1. Objetivo
Guardar no banco os metadados necessários para localizar e validar arquivos de projeto (SPEC-PI-004). O conteúdo permanece fora do PostgreSQL; nenhuma coluna `bytea`.

## 2. Modelo (`V0011__create_project_file_metadata.sql`)
### `assets.project_file`
| Coluna | Regra |
|---|---|
| `id` | UUID, PK |
| `project_id` | FK `academic_pi.project(id)`, `ON DELETE RESTRICT` |
| `owner_user_id` | FK `auth.user(id)`, `ON DELETE RESTRICT`; quem enviou |
| `file_type` | `pdf`, `docx` ou `image` (Caderno, item 51) |
| `hash_algorithm` / `content_hash` | `sha256` e hexadecimal minúsculo de 64 caracteres |
| `storage_ref` | Referência ao objeto externo; não vazia e única |
| `lifecycle_state` | FK `assets.file_lifecycle_state(code)` |
| `publication_authorized` / `publication_authorized_by` | Padrão `false`; `true` exige autorizador (acesso interno não implica publicação) |

### `assets.file_lifecycle_state`
Tabela de domínio **vazia por decisão**: os estados de lifecycle dependem de Produto/Infra e não foram fixados.

## 3. Não definido (não foi assumido)
- Limite de tamanho e validação MIME (SPEC-PI-004): validação de conteúdo real fica no Backend.
- Valores de lifecycle: até serem aprovados, nenhum arquivo pode ser inserido fora de testes. A migration que popular a tabela depende dessa decisão.
- Janela de edição (até o início da avaliação): regra de aplicação, não do esquema.
- Remoção/substituição e retirada de publicação: dependem de contrato operacional.

## 4. Premissa registrada
`sha256` foi escolhido como algoritmo do hash (o Caderno não especifica). Trocar exige migration incremental.
