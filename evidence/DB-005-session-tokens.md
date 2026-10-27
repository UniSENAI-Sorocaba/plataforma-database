# Evidência de Validação — DB-005

**Identificador de Trabalho (Work ID):** DB-005  
**Título:** Sessões/tokens têm hash, expiração, revogação e índices  
**Sprint / Prioridade:** S1 / P0  
**Estimativa:** 5 SP  
**Responsável inicial:** Enzo Gabriel Tomas de Souza  
**Revisor:** Henrique Marchetti  
**Dependências:** DB-004  
**Autoridade Normativa:** `plataforma-governance/_KB/README.md` (baseline `.governance-baseline`), `SPEC-AUTH-002` e `Caderno de Validações de Escopo (AUTH, PI e Extensão)`  
**Rastreabilidade:** Closes #5  

---

## 1. Resumo Executivo da Entrega

A entrega **DB-005** implementa a modelagem relacional, migração incremental, restrições de integridade, índices de alto desempenho, seeds determinísticos e validações funcionais completas para o gerenciamento de sessões e controle server-side de tokens de renovação (*refresh tokens*) no schema `auth`.

Todos os critérios de aceitação foram integralmente atendidos:

- **Modelagem Relacional e Integridade Referencial:** Criação da tabela `auth.user_session` com chave estrangeira para `auth.user(id)` configurada com `ON DELETE CASCADE`.
- **Armazenamento Seguro de Tokens (Anti-Vazamento):** Persistência estrita na forma de hash criptográfico SHA-256 (`token_hash varchar(64)`), impedindo o armazenamento de tokens em texto puro no banco de dados (`MH-SEC-004`).
- **Prevenção de Redundância de Índices:** A restrição `UNIQUE (token_hash)` provisiona o índice B-Tree único automaticamente, eliminando a criação de índices secundários redundantes.
- **Rastreamento de Rotação e Famílias de Tokens:** Implementação das colunas `family_id uuid NOT NULL` (agrupamento de rotação) e `replaced_by_token_id uuid` (chave estrangeira auto-referencial com `ON DELETE SET NULL`), permitindo rastreabilidade completa e detecção de reutilização de tokens comprometidos (`AC-AUTH-002-03`).
- **Controle Temporal e Expiração Segura:** Campos `created_at`, `expires_at`, `revoked_at` e `last_used_at` em `timestamptz` UTC com constraint `expires_at > created_at`.
- **Índice Parcial Otimizado (Sem `now()`):** Criação de `idx_user_session_active_lookup` em `(user_id, expires_at) WHERE revoked_at IS NULL`, respeitando a exigência de imutabilidade do PostgreSQL e garantindo busca de sessões ativas em tempo constante.
- **Migration Incremental Atômica (`V0004`):** Criação de `migrations/V0004__create_user_session.sql` protegida por transação e registrada em `public.schema_migration`.
- **Seeds Sintéticos Determinísticos (Anti-PII):** Criação de `seeds/0003_user_session.sql` com 5 cenários determinísticos (sessão ativa, rotacionada, revogada por logout, sessão de coordenador e família invalidada por detecção de reuso), utilizando IPs reservados (RFC 5737) e hashes sintéticos.
- **Automação de Validação e Upgrade:** Atualização de `scripts/validate.sh` (passos 18 a 22 com validações funcionais via bloco `DO $$`) e `scripts/validate_upgrade.sh` cobrindo o ciclo completo de upgrade de `V0001` até `V0004`.

---

## 2. Especificação Estrutural e Matriz de Objetos Criados

### 2.1 Tabela
| Schema | Tabela | Finalidade | Chave Primária |
| :--- | :--- | :--- | :--- |
| `auth` | `user_session` | Armazenamento de sessões e controle de refresh tokens | UUID (aplicação) |

### 2.2 Restrições de Integridade (Constraints)
| Tabela | Nome da Restrição | Tipo | Regra / Expressão |
| :--- | :--- | :--- | :--- |
| `auth.user_session` | `user_session_user_fk` | FOREIGN KEY | `REFERENCES auth.user(id) ON DELETE CASCADE` |
| `auth.user_session` | `user_session_replaced_by_token_fk` | FOREIGN KEY | `REFERENCES auth.user_session(id) ON DELETE SET NULL` |
| `auth.user_session` | `user_session_token_hash_ck` | CHECK | `token_hash <> '' AND length(token_hash) = 64` |
| `auth.user_session` | `user_session_expires_at_ck` | CHECK | `expires_at > created_at` |
| `auth.user_session` | `user_session_token_hash_unq` | UNIQUE | `UNIQUE (token_hash)` |

### 2.3 Índices de Desempenho
- `idx_user_session_user_id` em `auth.user_session (user_id)`
- `idx_user_session_family_id` em `auth.user_session (family_id)`
- `idx_user_session_active_lookup` em `auth.user_session (user_id, expires_at) WHERE revoked_at IS NULL`

---

## 3. Matriz de Cenários de Testes Funcionais Validados

Os seguintes cenários de validação funcional foram integrados e comprovados no script [scripts/validate.sh](file:///scripts/validate.sh) através de blocos transacionais `DO $$ ... $$`:

| # | Cenário Testado | Comportamento Esperado | Resultado Obtido |
| :--- | :--- | :--- | :--- |
| **01** | Tentativa de inserção com `token_hash` curto (< 64 caracteres) | Rejeição por violação da constraint `user_session_token_hash_ck` | Sucesso (bloqueado) |
| **02** | Tentativa de inserção com `expires_at <= created_at` | Rejeição por violação da constraint `user_session_expires_at_ck` | Sucesso (bloqueado) |
| **03** | Inserção de sessão válida com hash de 64 caracteres e datas coerentes | Inserção bem-sucedida no banco | Sucesso (inserido) |
| **04** | Tentativa de inserção de `token_hash` duplicado | Rejeição por violação da constraint `user_session_token_hash_unq` | Sucesso (bloqueado) |
| **05** | Inserção de token rotacionado e encadeamento em `replaced_by_token_id` | Atualização do token anterior para revogado e vínculo com o sucessor | Sucesso (rotacionado) |
| **06** | Exclusão do usuário titular em `auth.user` | Exclusão automática de todas as sessões associadas via `ON DELETE CASCADE` | Sucesso (cascata validada) |

---

## 4. Evidência do Pipeline de Integração Contínua (CI) e Validação Local

A esteira de automação do repositório executa a suíte de testes com a seguinte sequência verificada:

```
=== [CI Database - Execucao de Validacao DB-005] ===
1. docker compose up -d --wait (PostgreSQL 16 limpo)
2. ./scripts/migrate.sh
   - Aplicando migration migrations/V0001__create_domain_schemas.sql (OK)
   - Aplicando migration migrations/V0002__create_audit_event.sql (OK)
   - Aplicando migration migrations/V0003__create_identity_user_and_academic_link.sql (OK)
   - Aplicando migration migrations/V0004__create_user_session.sql (OK)
3. ./scripts/seed.sh
   - Aplicando seeds/0001_audit_event.sql (15 eventos sinteticos)
   - Aplicando seeds/0002_identity_user_link.sql (5 usuarios, 2 identidades, 2 turmas, 5 vinculos)
   - Aplicando seeds/0003_user_session.sql (5 sessoes sinteticas cobrindo ativa, rotacionada, revogada)
4. ./scripts/validate.sh
   - [validate] 1. Validando schemas de dominio em plataforma... OK
   - [validate] 2. Validando tabela public.schema_migration... OK
   - [validate] 3. Validando registro das migrations aplicadas (V0001,V0002,V0003,V0004)... OK
   - [validate] 4 a 17. Validando auditoria, seguranca PUBLIC, DB-004 e Anti-PII... OK
   - [validate] 18. Validando tabela auth.user_session (DB-005)... OK
   - [validate] 19. Validando constraints e foreign keys de auth.user_session... OK
   - [validate] 20. Validando indices de auth.user_session... OK
   - [validate] 21. Validando regras funcionais e de integridade em auth.user_session (DO block)... OK
   - [validate] 22. Validando presenca de dados sinteticos em auth.user_session... OK
   - [validate] Todas as validacoes de compatibilidade, integridade, constraints e seeds concluidas com sucesso!
5. ./scripts/validate_upgrade.sh
   - 1. Provisionando banco isolado para upgrade: plataforma_upgrade_test... OK
   - 2. Aplicando migration baseline (V0001)... OK
   - 3. Validando estado pos-V0001... OK
   - 4. Executando upgrade com migrate.sh... OK
   - 5. Verificando que V0002, V0003 e V0004 foram aplicadas no upgrade... OK
   - 6. Testando idempotencia de migrations (reexecutando migrate.sh no banco atualizado)... OK
   - 7. Aplicando seeds deterministicos no banco atualizado... OK
   - 8. Testando idempotencia de seeds (reexecutando seed.sh no banco atualizado)... OK
   - 9. Executando suite completa de validacao no banco atualizado... OK
   - 10. Limpando banco temporario de upgrade... OK
   - === [validate_upgrade] Validacao de upgrade, compatibilidade e idempotencia de seeds concluida com sucesso! ===
6. docker compose down (Desalocacao ordenada de recursos)
```

---

## 5. Rastreabilidade e Conclusão

- **Issue:** [DB-005] Sessões/tokens têm hash, expiração, revogação e índices (#5)
- **Status:** Implementado e validado em conformidade com as regras do projeto.
