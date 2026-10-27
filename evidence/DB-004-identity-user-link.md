# Evidência de Validação — DB-004

**Identificador de Trabalho (Work ID):** DB-004  
**Título:** Identidade/usuário/vínculo têm constraints e migration testada  
**Sprint / Prioridade:** S1 / P0  
**Estimativa:** 8 SP  
**Responsável inicial:** Henrique Marchetti  
**Revisor:** Isabelly  
**Dependências:** DB-001  
**Autoridade Normativa:** `plataforma-governance/_KB/README.md` (baseline `.governance-baseline`)  
**Rastreabilidade:** Closes #4  

---

## 1. Resumo Executivo da Entrega

A entrega **DB-004** implementa a modelagem relacional completa, migração incremental versionada, restrições de integridade, índices, seeds determinísticos e validações funcionais de segurança para os domínios de identidade, conta de usuário e vínculo acadêmico com turmas.

Todos os critérios de aceitação foram integralmente atendidos:

- **Modelagem Relacional e Integridade Referencial:** Criação das tabelas `auth.user`, `auth.user_identity`, `institutional.academic_class` e `institutional.academic_link`.
- **Desacoplamento e Suporte Híbrido de Autenticação:** Separação entre conta de usuário (`auth.user`) e provedores federados OIDC/OAuth2 (`auth.user_identity`), permitindo simultaneamente login federado e credenciais locais (Argon2id) sem colisão.
- **Normalização e Unicidade de CPF:** Campo `cpf varchar(11)` estritamente restrito a 11 dígitos numéricos via CHECK constraint, com garantia de unicidade global (`user_cpf_unq`) e permissão de valor nulo para usuários federados ou contas institucionais sem coleta de CPF.
- **Ciclo de Vida e Estados Operacionais:** Controle estrito de status da conta (`'pending'`, `'active'`, `'inactive'`, `'suspended'`) e do vínculo (`'active'`, `'inactive'`, `'completed'`, `'dropped'`).
- **Suporte a Múltiplas Turmas e Usuário sem Vínculo:** Relação 1:N entre usuário e turmas permitindo que o mesmo aluno pertença a múltiplos agrupamentos acadêmicos com matrículas distintas, além de suporte nativo para usuários desacoplados de qualquer turma (0..N).
- **Migration Incremental e Idempotência:** Implementação da migração `migrations/V0003__create_identity_user_and_academic_link.sql` executável de forma idempotente e atômica.
- **Validação de Upgrade Incremental e Clean Install:** Cobertura automatizada no script `scripts/validate.sh` e `scripts/validate_upgrade.sh`, validando instalação do zero e atualização incremental a partir de versão baseline.
- **Seeds Sintéticos e LGPD:** Criação de `seeds/0002_identity_user_link.sql` 100% determinístico e fictício (`@synthetic.local`), em conformidade preventiva com a LGPD e verificação Anti-PII.

---

## 2. Especificação Estrutural e Matriz de Objetos Criados

### 2.1 Tabelas
| Schema | Tabela | Finalidade | Chave Primária |
| :--- | :--- | :--- | :--- |
| `auth` | `user` | Conta canônica de usuário e ciclo de vida | UUID (aplicação) |
| `auth` | `user_identity` | Mapeamento de identidades federadas OIDC/OAuth2 | UUID (aplicação) |
| `institutional` | `academic_class` | Cadastro de turmas e classes acadêmicas | UUID (aplicação) |
| `institutional` | `academic_link` | Vínculo entre usuário e turma com papel acadêmico | UUID (aplicação) |

### 2.2 Restrições de Integridade (Constraints)
| Tabela | Nome da Restrição | Tipo | Regra / Expressão |
| :--- | :--- | :--- | :--- |
| `auth.user` | `user_email_ck` | CHECK | Formato regex de e-mail válido |
| `auth.user` | `user_full_name_ck` | CHECK | Nome não vazio e com tamanho mínimo de 2 caracteres |
| `auth.user` | `user_cpf_ck` | CHECK | `cpf IS NULL OR cpf ~ '^[0-9]{11}$'` |
| `auth.user` | `user_password_hash_ck` | CHECK | Hash não vazio quando preenchido |
| `auth.user` | `user_status_ck` | CHECK | `status IN ('pending', 'active', 'inactive', 'suspended')` |
| `auth.user` | `user_email_unq` | UNIQUE | Unicidade de e-mail |
| `auth.user` | `user_cpf_unq` | UNIQUE | Unicidade de CPF quando presente |
| `auth.user_identity` | `user_identity_user_fk` | FOREIGN KEY | `REFERENCES auth.user(id) ON DELETE CASCADE` |
| `auth.user_identity` | `user_identity_provider_ck` | CHECK | Provedor não vazio |
| `auth.user_identity` | `user_identity_provider_subject_ck` | CHECK | Subject/ID do provedor não vazio |
| `auth.user_identity` | `user_identity_email_ck` | CHECK | Validação de e-mail opcional |
| `auth.user_identity` | `user_identity_provider_subject_unq` | UNIQUE | `(provider, provider_subject)` |
| `institutional.academic_class` | `academic_class_code_ck` | CHECK | Código de turma não vazio |
| `institutional.academic_class` | `academic_class_name_ck` | CHECK | Nome de turma não vazio |
| `institutional.academic_class` | `academic_class_term_ck` | CHECK | Semestre/termo letivo não vazio |
| `institutional.academic_class` | `academic_class_code_unq` | UNIQUE | Código de turma único |
| `institutional.academic_link` | `academic_link_user_fk` | FOREIGN KEY | `REFERENCES auth.user(id) ON DELETE CASCADE` |
| `institutional.academic_link` | `academic_link_class_fk` | FOREIGN KEY | `REFERENCES institutional.academic_class(id) ON DELETE RESTRICT` |
| `institutional.academic_link` | `academic_link_role_ck` | CHECK | `role IN ('student', 'professor', 'coordinator')` |
| `institutional.academic_link` | `academic_link_registration_number_ck` | CHECK | Matrícula não vazia quando informada |
| `institutional.academic_link` | `academic_link_status_ck` | CHECK | `status IN ('active', 'inactive', 'completed', 'dropped')` |
| `institutional.academic_link` | `academic_link_user_class_role_unq` | UNIQUE | `(user_id, class_id, role)` |

### 2.3 Índices de Desempenho
- `idx_user_email` em `auth.user (email)`
- `idx_user_status` em `auth.user (status)`
- `idx_user_cpf` em `auth.user (cpf)`
- `idx_user_identity_user_id` em `auth.user_identity (user_id)`
- `idx_user_identity_provider_subject` em `auth.user_identity (provider, provider_subject)`
- `idx_academic_class_code` em `institutional.academic_class (code)`
- `idx_academic_class_term` em `institutional.academic_class (term)`
- `idx_academic_class_is_active` em `institutional.academic_class (is_active)`
- `idx_academic_link_user_id` em `institutional.academic_link (user_id)`
- `idx_academic_link_class_id` em `institutional.academic_link (class_id)`
- `idx_academic_link_status` em `institutional.academic_link (status)`

---

## 3. Matriz de Cenários de Testes Funcionais Validados

Os seguintes cenários de validação funcional foram integrados e comprovados no script [scripts/validate.sh](file:///scripts/validate.sh) através de blocos transacionais `DO $$ ... $$`:

| # | Cenário Testado | Comportamento Esperado | Resultado Obtido |
| :--- | :--- | :--- | :--- |
| **01** | Tentativa de inserção com formato de e-mail inválido | Rejeição por violação da constraint `user_email_ck` | Sucesso (bloqueado) |
| **02** | Tentativa de inserção de CPF com menos de 11 dígitos | Rejeição por violação da constraint `user_cpf_ck` | Sucesso (bloqueado) |
| **03** | Tentativa de inserção de CPF com caracteres alfanuméricos | Rejeição por violação da constraint `user_cpf_ck` | Sucesso (bloqueado) |
| **04** | Tentativa de inserção de usuário com status inválido | Rejeição por violação da constraint `user_status_ck` | Sucesso (bloqueado) |
| **05** | Inserção de usuário válido com CPF normalizado e status `active` | Inserção bem-sucedida no banco | Sucesso (inserido) |
| **06** | Inserção de usuário válido com status `pending` (CSV pendente) | Inserção bem-sucedida no banco | Sucesso (inserido) |
| **07** | Tentativa de inserção de e-mail duplicado | Rejeição por violação da constraint `user_email_unq` | Sucesso (bloqueado) |
| **08** | Tentativa de inserção de CPF duplicado | Rejeição por violação da constraint `user_cpf_unq` | Sucesso (bloqueado) |
| **09** | Inserção de identidade OIDC federada associada ao usuário | Inserção bem-sucedida com integridade referencial | Sucesso (inserido) |
| **10** | Tentativa de duplicação de `(provider, provider_subject)` | Rejeição por `user_identity_provider_subject_unq` | Sucesso (bloqueado) |
| **11** | Inserção de turmas acadêmicas distintas | Inserção bem-sucedida com códigos únicos | Sucesso (inserido) |
| **12** | Vinculação do mesmo estudante a múltiplas turmas | Inserções permitidas com registros distintos de vínculo | Sucesso (multi-turma) |
| **13** | Tentativa de duplicar vínculo para mesma turma e mesmo papel | Rejeição por `academic_link_user_class_role_unq` | Sucesso (bloqueado) |
| **14** | Tentativa de inserção de vínculo com papel acadêmico inválido | Rejeição por violação da constraint `academic_link_role_ck` | Sucesso (bloqueado) |
| **15** | Tentativa de inserção de vínculo com status de matrícula inválido | Rejeição por violação da constraint `academic_link_status_ck` | Sucesso (bloqueado) |
| **16** | Existência e integridade de usuário sem vínculo acadêmico | Operação autônoma de `auth.user` sem dependência de turmas | Sucesso (desacoplado) |

---

## 4. Evidência do Pipeline de Integração Contínua (CI)

A esteira automatizada no GitHub Actions executa os testes estruturais e de upgrade com o seguinte fluxo aprovado:

```
=== [CI Database - Execucao de Validacao] ===
1. docker compose up -d --wait (PostgreSQL 16 limpo)
2. ./scripts/migrate.sh
   - Aplicando migration migrations/V0001__create_domain_schemas.sql
   - Aplicando migration migrations/V0002__create_audit_event.sql
   - Aplicando migration migrations/V0003__create_identity_user_and_academic_link.sql
3. ./scripts/seed.sh
   - Aplicando seeds/0001_audit_event.sql (15 eventos sinteticos)
   - Aplicando seeds/0002_identity_user_link.sql (5 usuarios, 2 identidades, 2 turmas, 5 vinculos)
4. ./scripts/validate.sh
   - [validate] 1. Validando schemas de dominio em plataforma... OK
   - [validate] 2. Validando tabela public.schema_migration... OK
   - [validate] 3. Validando registro das migrations aplicadas (V0001,V0002,V0003)... OK
   - [validate] 4. Validando tabela public.audit_event... OK
   - [validate] 5. Validando indices da tabela public.audit_event... OK
   - [validate] 6. Validando check constraints da tabela public.audit_event... OK
   - [validate] 7. Validando postura de seguranca (sem USAGE/CREATE para PUBLIC)... OK
   - [validate] 8. Validando integridade e funcionamento de constraints em public.audit_event... OK
   - [validate] 9. Validando presenca e cobertura de seeds deterministicos em public.audit_event... OK
   - [validate] 10. Validando tabelas de identidade, usuario e vinculo (DB-004)... OK
   - [validate] 11. Validando check constraints de identidade, usuario e vinculo... OK
   - [validate] 12. Validando foreign keys de identidade e vinculo... OK
   - [validate] 13. Validando unique constraints de identidade, usuario e vinculo... OK
   - [validate] 14. Validando indices de identidade, usuario e vinculo... OK
   - [validate] 15. Validando comportamento funcional e regras de integridade (DO block)... OK
   - [validate] 16. Validando presenca de dados sinteticos nas tabelas DB-004... OK
   - [validate] 17. Validando conformidade Anti-PII e determinismo (sem dados pessoais)... OK
   - [validate] Todas as validacoes de compatibilidade, integridade, constraints e seeds concluidas com sucesso!
5. ./scripts/validate_upgrade.sh
   - 1. Provisionando banco isolado para upgrade: plataforma_upgrade_test... OK
   - 2. Aplicando migration baseline (V0001)... OK
   - 3. Validando estado pos-V0001... OK
   - 4. Executando upgrade com migrate.sh... OK
   - 5. Verificando que V0002 e V0003 foram aplicadas no upgrade... OK
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

- **Issue:** [DB-004] Identidade/usuário/vínculo têm constraints e migration testada (#4)
- **Critérios de Aceite:** Plenamente atendidos com migração incremental versionada, constraints de integridade, testes funcionais de rejeição e sucesso, suporte a upgrade e idempotência, documentação técnica completa e conformidade total com a LGPD e governança da plataforma.
