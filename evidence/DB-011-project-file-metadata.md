# Evidência DB-011: metadados de artefatos

Banco: PostgreSQL 16 (`compose.yaml`). Scripts executados diretamente (`make` indisponível no ambiente): `migrate.sh`, `seed.sh`, `validate.sh`, `validate_upgrade.sh`.

## Resultados
| Critério de aceite | Verificação | Resultado |
|---|---|---|
| Metadados apontam para arquivo externo e permitem conferir o hash | Hash armazenado comparado com `encode(sha256(conteudo),'hex')`; sem coluna `bytea` | Passou |
| Tipos aceitos = lista aprovada | `pdf`, `docx`, `image` aceitos; `exe` rejeitado | Passou |
| Referência órfã rejeitada | Projeto, lifecycle e `storage_ref` duplicado/vazio rejeitados | Passou |
| Proprietário inexistente rejeitado | FK `project_file_owner_user_fk`; remoção de proprietário com arquivos bloqueada | Passou |
| Testes sem dados reais | IDs, e-mails e conteúdo sintéticos; dados removidos ao fim (passo 26 confirma 0 resíduos) | Passou |
| Publicação não implícita | Padrão `false`; `true` sem autorizador rejeitado | Passou |
| Instalação limpa e upgrade | `validate.sh` (passos 1–30) e `validate_upgrade.sh` | Passou |

## Limitações
- Estados de lifecycle, limite de tamanho e MIME dependem de Produto/Infra; não foram fixados.
- Não há seed para `assets.project_file` porque exigiria estados de lifecycle ainda não aprovados.
- Execução local; CI não foi executado nesta evidência.
