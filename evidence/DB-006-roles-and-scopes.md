# Evidência de Validação e Conformidade — Papéis, Permissões e Escopos (DB-006)

**Identificador de Trabalho (Work ID):** DB-006  
**Título:** Papéis/permissões evitam duplicidade e suportam escopo  
**Responsável:** Nicolas Pureza da Silva  
**Revisor:** Henrique Marchetti Coutinho  
**Dependências:** DB-004 (`auth.user`)  
**Autoridade Normativa:** ADR-002, ADR-003, ADR-011, SPEC-AUTH-003, MH-SEC-002, PG-006 e Caderno de Validações de Escopo  
**Rastreabilidade:** Issue #6 · PR do Ciclo 1: #32 · Entrega complementar de integridade, FKs, seeds e validação automatizada (Ciclo 2)

---

## 1. Resumo Executivo da Entrega

A entrega **DB-006** implementa e valida a estrutura relacional para o controle de acesso baseado em papéis e escopos (RBAC), garantindo prevenção estrita de duplicidade, suporte a escopos (`GLOBAL`, `PROJETO`, `TURMA`, `CURSO`), acúmulo de funções no mesmo cadastro (`auth.user`) e integridade referencial completa:

1. **Migration Incremental e Repetível (`V0006`):** O arquivo [`migrations/V0006__create_rbac_schema.sql`](../migrations/V0006__create_rbac_schema.sql) cria as tabelas `roles`, `permissions`, `role_permissions` e `user_roles`, executa diagnóstico prévio de órfãos, aplica de forma idempotente as chaves estrangeiras para `auth.user` (`user_roles_user_fk`, `user_roles_assigned_by_fk`) e check constraints de integridade, e registra formalmente a versão `'V0006'` em `public.schema_migration`.
2. **Prevenção de Duplicidade e Consistência de Escopo:**
   - `roles_name_key` e `roles_name_ck`: Impedem nomes de papéis duplicados ou em branco.
   - `uk_permissions_action_resource`, `permissions_action_ck` e `permissions_resource_ck`: Impedem permissões `(action, resource)` duplicadas ou vazias.
   - `PRIMARY KEY (role_id, permission_id)` em `role_permissions`: Impede duplicidade na matriz de permissões por papel.
   - `uk_user_role_scope (user_id, role_id, scope_type, scope_id)` em `user_roles`: Bloqueia a atribuição duplicada do mesmo papel no mesmo escopo para o mesmo usuário, enquanto permite o acúmulo de papéis distintos e a atuação em múltiplos escopos.
   - `user_roles_scope_type_ck`, `user_roles_scope_id_ck` e `user_roles_scope_consistency_ck`: Garantem que o escopo `GLOBAL` utilize exclusivamente `scope_id = '*'` e que escopos específicos (`PROJETO`, `TURMA`, `CURSO`) exijam um identificador concreto diferente de `'*'`.
3. **Seeds Determinísticos e Sintéticos (`0004_rbac_roles_and_scopes.sql`):** Localizados em [`seeds/0004_rbac_roles_and_scopes.sql`](../seeds/0004_rbac_roles_and_scopes.sql) (integrados ao loop `seeds/*.sql` do `scripts/seed.sh`), provisionando os papéis `COORDENACAO`, `DOCENTE` e `ALUNO`, 7 permissões essenciais e 7 atribuições sintéticas vinculadas aos usuários da `DB-004` sem dados pessoais (Anti-PII / LGPD).
4. **Automação de Validação (`validate.sh` e `validate_upgrade.sh`):** Inclusão dos passos 31 a 35 em [`scripts/validate.sh`](../scripts/validate.sh) e verificação da versão `V0006` no teste de upgrade incremental em [`scripts/validate_upgrade.sh`](../scripts/validate_upgrade.sh).

---

## 2. Matriz de Objetos e Restrições Verificados

### 2.1 Tabelas Criadas (`V0006`)
| Schema | Tabela | Finalidade | Chave Primária |
| :--- | :--- | :--- | :--- |
| `public` | `roles` | Catálogo de papéis do sistema (`COORDENACAO`, `DOCENTE`, `ALUNO`) | `id` (`SERIAL`) |
| `public` | `permissions` | Catálogo de permissões atômicas `(action, resource)` | `id` (`SERIAL`) |
| `public` | `role_permissions` | Associação N:N entre papéis e permissões | `(role_id, permission_id)` |
| `public` | `user_roles` | Atribuição de papéis a usuários (`auth.user`) com suporte a escopo | `id` (`SERIAL`) |

### 2.2 Restrições de Integridade (Constraints)
| Tabela | Nome da Constraint | Tipo | Regra Verificada |
| :--- | :--- | :--- | :--- |
| `roles` | `roles_name_key` | `UNIQUE` | Unicidade do nome do papel (`name`) |
| `roles` | `roles_name_ck` | `CHECK` | Nome do papel não vazio (`length(trim(name)) > 0`) |
| `permissions` | `uk_permissions_action_resource` | `UNIQUE` | Unicidade do par `(action, resource)` |
| `permissions` | `permissions_action_ck` | `CHECK` | Ação não vazia (`length(trim(action)) > 0`) |
| `permissions` | `permissions_resource_ck` | `CHECK` | Recurso não vazio (`length(trim(resource)) > 0`) |
| `role_permissions` | `role_permissions_pkey` | `PRIMARY KEY` | Unicidade da associação `(role_id, permission_id)` |
| `user_roles` | `uk_user_role_scope` | `UNIQUE` | Unicidade composta `(user_id, role_id, scope_type, scope_id)` |
| `user_roles` | `user_roles_user_fk` | `FOREIGN KEY` | Referência a `auth.user(id)` com `ON DELETE CASCADE` |
| `user_roles` | `user_roles_assigned_by_fk` | `FOREIGN KEY` | Referência a `auth.user(id)` com `ON DELETE SET NULL` |
| `user_roles` | `user_roles_scope_type_ck` | `CHECK` | `scope_type IN ('GLOBAL', 'PROJETO', 'TURMA', 'CURSO')` |
| `user_roles` | `user_roles_scope_id_ck` | `CHECK` | `length(trim(scope_id)) > 0` |
| `user_roles` | `user_roles_scope_consistency_ck` | `CHECK` | `(scope_type = 'GLOBAL' AND scope_id = '*') OR (scope_type <> 'GLOBAL' AND scope_id <> '*')` |

### 2.3 Índices de Desempenho
- `idx_user_roles_lookup` em `user_roles (user_id, scope_type, scope_id)`
- `idx_user_roles_role_id` em `user_roles (role_id)`
- `idx_role_permissions_role` em `role_permissions (role_id)`
- `idx_role_permissions_permission` em `role_permissions (permission_id)`

---

## 3. Evidência dos Testes Funcionais Automatizados (`scripts/validate.sh`)

O bloco `DO $$` na etapa 34 do script `scripts/validate.sh` valida ativamente os cenários positivos e negativos de integridade:

| # | Cenário de Teste Executado | Comportamento Esperado | Resultado |
| :---: | :--- | :--- | :---: |
| **01** | Tentativa de inserir papel com `name` vazio ou apenas espaços | Rejeição por `roles_name_ck` (`check_violation`) | Sucesso (bloqueado) |
| **02** | Tentativa de inserir papel com `name` duplicado (`'COORDENACAO'`) | Rejeição por `roles_name_key` (`unique_violation`) | Sucesso (bloqueado) |
| **03** | Tentativa de inserir permissão com `action` ou `resource` vazio | Rejeição por `permissions_action_ck` / `permissions_resource_ck` (`check_violation`) | Sucesso (bloqueado) |
| **04** | Tentativa de inserir permissão com `(action, resource)` duplicado | Rejeição por `uk_permissions_action_resource` (`unique_violation`) | Sucesso (bloqueado) |
| **05** | Tentativa de atribuir papel a `user_id` inexistente em `auth.user` | Rejeição por `user_roles_user_fk` (`foreign_key_violation`) | Sucesso (bloqueado) |
| **06** | Tentativa de atribuir papel com `scope_type` inválido (`'ESCOPO_INVALIDO'`) | Rejeição por `user_roles_scope_type_ck` (`check_violation`) | Sucesso (bloqueado) |
| **07** | Tentativa de atribuir `scope_type = 'GLOBAL'` com `scope_id <> '*'` | Rejeição por `user_roles_scope_consistency_ck` (`check_violation`) | Sucesso (bloqueado) |
| **08** | Tentativa de atribuir `scope_type = 'PROJETO'` com `scope_id = '*'` | Rejeição por `user_roles_scope_consistency_ck` (`check_violation`) | Sucesso (bloqueado) |
| **09** | Atribuição cumulativa de `COORDENACAO` (`GLOBAL`) e `DOCENTE` (`PROJETO` 1 e 2) ao mesmo usuário | Inserções permitidas comprovando acúmulo de papéis e múltiplos escopos | Sucesso (inserido) |
| **10** | Tentativa de duplicar o mesmo papel no mesmo escopo para o mesmo usuário | Rejeição por `uk_user_role_scope` (`unique_violation`) | Sucesso (bloqueado) |
| **11** | Exclusão do usuário autorizador (`assigned_by`) em `auth.user` | Atribuições preservadas com `assigned_by = NULL` (`ON DELETE SET NULL`) | Sucesso (preservado) |
| **12** | Exclusão do usuário titular (`user_id`) em `auth.user` | Remoção automática das atribuições via `ON DELETE CASCADE` | Sucesso (cascata validada) |

---

## 4. Fluxo de Validação de Instalação Limpa e Upgrade Incremental

```
=== [CI Database - Execucao de Validacao DB-006] ===
1. docker compose up -d --wait (PostgreSQL 16 limpo)
2. ./scripts/migrate.sh
   - Aplicando migration migrations/V0001__create_domain_schemas.sql (OK)
   - Aplicando migration migrations/V0002__create_audit_event.sql (OK)
   - Aplicando migration migrations/V0003__create_identity_user_and_academic_link.sql (OK)
   - Aplicando migration migrations/V0004__create_user_session.sql (OK)
   - Aplicando migration migrations/V0006__create_rbac_schema.sql (OK)
   - Aplicando migration migrations/V0007__restrict_audit_event_to_technical_records.sql (OK)
   - Aplicando migration migrations/V0008__create_project_tables.sql (OK)
   - Aplicando migration migrations/V0011__create_project_file_metadata.sql (OK)
3. ./scripts/seed.sh
   - Aplicando seeds/0001_audit_event.sql (OK)
   - Aplicando seeds/0002_identity_user_link.sql (OK)
   - Aplicando seeds/0003_user_session.sql (OK)
   - Aplicando seeds/0004_rbac_roles_and_scopes.sql (3 papeis, 7 permissoes, 7 role_permissions, 7 user_roles) (OK)
4. ./scripts/validate.sh
   - [validate] 1 a 30. Validando schemas, auditoria, DB-004, DB-005, DB-007, DB-008 e DB-011... OK
   - [validate] 31. Validando tabelas e registro da migration de RBAC (DB-006)... OK
   - [validate] 32. Validando check, unique e foreign keys das tabelas de RBAC (DB-006)... OK
   - [validate] 33. Validando indices das tabelas de RBAC (DB-006)... OK
   - [validate] 34. Validando regras funcionais, prevencao de duplicidade, suporte a escopo e acumulo de papeis em RBAC (DO block)... OK
   - [validate] 35. Validando presenca e cobertura de seeds deterministicos em RBAC (DB-006)... OK
   - [validate] Todas as validacoes de compatibilidade, integridade, constraints e seeds concluidas com sucesso!
5. ./scripts/validate_upgrade.sh
   - 1. Provisionando banco isolado para upgrade: plataforma_upgrade_test... OK
   - 2. Aplicando migration baseline (V0001)... OK
   - 3. Validando estado pos-V0001... OK
   - 4. Executando upgrade com migrate.sh... OK
   - 5. Verificando que V0002, V0003, V0004 e V0006 foram aplicadas no upgrade... OK
   - 6. Testando idempotencia de migrations (reexecutando migrate.sh no banco atualizado)... OK
   - 7. Aplicando seeds deterministicos no banco atualizado... OK
   - 8. Testando idempotencia de seeds (reexecutando seed.sh no banco atualizado)... OK
   - 9. Executando suite completa de validacao no banco atualizado... OK
   - 10. Limpando banco temporario de upgrade... OK
   - === [validate_upgrade] Validacao de upgrade, compatibilidade e idempotencia de seeds concluida com sucesso! ===
```

---

## 5. Rastreabilidade e Conclusão

- **Issue:** [DB-006] Papéis/permissões evitam duplicidade e suportam escopo (#6)
- **Critérios de Aceite:** Atendidos com constraints de unicidade e escopo, chaves estrangeiras para `auth.user`, registro em `public.schema_migration`, seeds determinísticos sem dados pessoais e cobertura automatizada em `validate.sh` e `validate_upgrade.sh`.
