# Seeds Sintéticos e Determinísticos

Este diretório contém os scripts SQL responsáveis pelo provisionamento de dados mockados (seeds) no PostgreSQL da plataforma.

---

## 1. Princípios e Diretrizes Normativas

Conforme definido na **ADR-011**, nas convenções da **DB-001** e na entrega **DB-003**:

1. **Idempotência Absoluta:** Todos os scripts de seed devem poder ser executados múltiplas vezes consecutivas em um mesmo banco de dados sem produzir duplicidades, inconsistências ou interrupções de erro (uso obrigatório de `ON CONFLICT (id) DO NOTHING` ou `DO UPDATE`).
2. **Determinismo Estrito:** Nenhum valor gerado em tempo de execução (`gen_random_uuid()`, `now()`, `random()`) pode ser utilizado como chave de seed. Todos os identificadores (UUIDs), datas/horas (`timestamptz`) e conteúdos devem ser constantes e previsíveis.
3. **Dados Exclusivamente Sintéticos (Anti-PII / LGPD):** É terminantemente vedada a inclusão de quaisquer dados pessoais reais ou identificáveis (como nomes civis reais, CPFs, RGs, telefones, endereços ou e-mails pessoais). Todos os dados devem ser 100% fictícios e seguir padrões explícitos de identificação mockada (ex.: `@synthetic.local`, `mock.student.01`).

---

## 2. Convenção de Identificadores (UUIDs) Determinísticos

Para assegurar clareza, rastreabilidade e evitar colisões entre entidades, os seeds adotam a seguinte taxonomia de prefixos:

| Finalidade | Padrão / Faixa de UUID | Exemplo |
| :--- | :--- | :--- |
| **Identificador do Evento (PK)** | `00000000-0000-4000-8000-0000000000XX` | `00000000-0000-4000-8000-000000000001` |
| **Ator do Sistema (Actor ID)** | `a0000000-0000-4000-8000-0000000000XX` | `a0000000-0000-4000-8000-000000000001` |
| **Registro Afetado / Usuário (Record ID)** | `b0000000-0000-4000-8000-0000000000XX` | `b0000000-0000-4000-8000-000000000001` |
| **Sessão / Token (Session ID)** | `c0000000-0000-4000-8000-0000000000XX` | `c0000000-0000-4000-8000-000000000001` |
| **Família de Rotação (Family ID)** | `d0000000-0000-4000-8000-0000000000XX` | `d0000000-0000-4000-8000-000000000001` |

---

## 3. Catálogo de Seeds Ativos

### `0001_audit_event.sql`
- **Tabela Alvo:** `public.audit_event`
- **Migration Mínima Exigida:** `V0002__create_audit_event.sql`
- **Cobertura de Domínios:**
  - `auth`: Criação e atualização de usuário sintético, revogação de sessão (`INSERT`, `UPDATE`, `DELETE`).
  - `academic_pi`: Cadastro, submissão e descarte de rascunho de projeto acadêmico (`INSERT`, `UPDATE`, `DELETE`).
  - `extension`: Registro, aprovação e exclusão de prospecto de ação comunitária (`INSERT`, `UPDATE`, `DELETE`).
  - `assets`: Cadastro de equipamento, reserva para projeto e liberação de reserva (`INSERT`, `UPDATE`, `DELETE`).
  - `institutional`: Cadastro de unidade de campus, ajuste de capacidade e arquivamento de aviso (`INSERT`, `UPDATE`, `DELETE`).
- **Operações Cobertas:** `INSERT`, `UPDATE` e `DELETE`.

### `0002_identity_user_link.sql`
- **Tabelas Alvo:** `auth.user`, `auth.user_identity`, `institutional.academic_class`, `institutional.academic_link`
- **Migration Mínima Exigida:** `V0003__create_identity_user_and_academic_link.sql`
- **Cobertura de Domínios e Cenários:**
  - `auth.user`: Usuários sintéticos determinísticos com status `active` e `pending` (cenário de importação CSV aguardando ativação), além de usuário desvinculado (sem turmas associadas).
  - `auth.user_identity`: Identidades OIDC institucionais federadas mapeadas para contas de usuário.
  - `institutional.academic_class`: Turmas acadêmicas com código, nome e termo letivo (`2026.1`).
  - `institutional.academic_link`: Vínculos com papéis de `student`, `professor` e `coordinator`, cobrindo cenários de estudante em múltiplas turmas e status de vínculo inativo/desativado.
- **Conformidade Anti-PII:** CPFs e e-mails 100% fictícios (`@synthetic.local`), sem uso de dados reais (LGPD).

### `0003_user_session.sql`
- **Tabela Alvo:** `auth.user_session`
- **Migration Mínima Exigida:** `V0004__create_user_session.sql`
- **Cobertura de Domínios e Cenários:**
  - Sessão ativa válida de estudante com hash SHA-256 e sem revogação.
  - Sessão rotacionada e superada por token subsequente (`replaced_by_token_id`).
  - Sessão revogada por logout explícito de docente (`revoked_at` preenchido).
  - Sessão ativa de coordenador sem rotação.
  - Sessão invalidada por detecção de tentativa de reuso de token.
- **Conformidade Anti-PII:** Tokens em formato hash SHA-256 (64 hex chars), IPs de teste reservados (RFC 5737) e user-agents genéricos.

---

## 4. Execução e Validação

Para aplicar todos os seeds ordenados alfabeticamente:

```bash
# Via Makefile
make seed

# Diretamente via script (suporta PGDATABASE e PGUSER)
./scripts/seed.sh
```

A integridade e o cumprimento das regras de determinismo e privacidade dos seeds são validados automaticamente na esteira de CI através de `make validate` e `make validate-upgrade`.

---

## 5. Como Adicionar Novos Seeds

Ao criar novas tabelas por meio de migrações (`migrations/VNNNN__...`):
1. Crie um novo arquivo numerado no padrão `NNNN_<nome_entidade>.sql` dentro de `seeds/`.
2. Garanta que todas as chaves primárias utilizem UUIDs determinísticos fixos.
3. Assegure a idempotência utilizando `ON CONFLICT (<pk>) DO NOTHING;`.
4. Garanta que todos os campos de texto sejam puramente sintéticos e sem qualquer menção a informações de pessoas físicas reais.
5. Documente o novo arquivo neste `seeds/README.md`.
