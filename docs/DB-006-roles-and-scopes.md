# DB-006: Modelo de Papéis, Permissões e Escopos

## 1. Decisões Arquiteturais e Alinhamentos
- **Cadastro Único**: Cada CPF possui um cadastro único no sistema, que pode ser ativado ou inativado pela Coordenação.
- **Acúmulo de Papéis**: O sistema permite acúmulo de papéis. Um usuário que seja Docente e Coordenador recebe a soma cumulativa de permissões de ambos.
- **Suporte a Escopos**: O modelo suporta tanto abrangência global (`scope_type = 'GLOBAL'`, `scope_id = '*'`) quanto entidades específicas (`scope_type = 'PROJETO'`, `scope_id = '<ID>'`).
- **Prevenção de Duplicidade**: Implementada através da constraint `uk_user_role_scope (user_id, role_id, scope_type, scope_id)`.

## 2. Matriz de Papéis e Permissões Iniciais
| Papel | Ação | Recurso | Escopo Típico |
|---|---|---|---|
| COORDENACAO | MANAGE | USER | GLOBAL |
| COORDENACAO | MANAGE | ROLE | GLOBAL |
| DOCENTE | CREATE, MANAGE_MEMBERS, VALIDATE_HOURS, EVALUATE | PROJECT | PROJETO |
| ALUNO | SUBMIT | ACTIVITY | PROJETO / TURMA |

## 3. Limitações e Follow-ups
- A supressão de controle de bancas e a simplificação de trilhas de auditoria seguem o alinhamento do Caderno de Validações e aguardam aprovação final de SPEC-AUTH.