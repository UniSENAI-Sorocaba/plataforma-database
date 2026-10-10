# Seeds Sintéticos e Determinísticos (DB-003)

Este documento estabelece a especificação técnica, taxonomia de dados, conformidade regulatória (LGPD) e estratégia operacional dos dados de semente (seeds) determinísticos do repositório `plataforma-database`, alinhado com a **ADR-011**, convenções da **DB-001** e automações da **DB-002**.

---

## 1. Contexto e Objetivos

A entrega **DB-003** implementa o provisionamento de dados mockados no PostgreSQL da plataforma com as seguintes diretrizes:

1. **Determinismo Estrito:** Todos os identificadores (UUIDs), datas/horas (`timestamptz`) e valores são imutáveis e previsíveis. Não há dependência de funções não-determinísticas como `gen_random_uuid()` ou `now()`.
2. **Dados Exclusivamente Sintéticos (Anti-PII / LGPD):** Eliminação completa de quaisquer dados pessoais reais ou identificáveis de pessoas físicas. A plataforma adota uma postura de conformidade preventiva com a LGPD.
3. **Idempotência Operacional:** Execuções repetidas da esteira de seeds (`make seed`) produzem exatamente o mesmo estado final, sem duplicação de linhas ou erros de chave primária.
4. **Cobertura Abrangente dos Schemas de Domínio:** Representação de eventos realistas para todos os 5 schemas de domínio definidos na DB-001:
   - `auth`
   - `academic_pi`
   - `extension`
   - `assets`
   - `institutional`
5. **Cobertura Integral de Operações de Auditoria:** Cenários para as operações `INSERT`, `UPDATE` e `DELETE` na tabela central `public.audit_event`.

---

## 2. Taxonomia e Convenção de Identificadores (UUIDs)

Para manter legibilidade e evitar colisões entre entidades, os dados sintéticos utilizam a seguinte convenção padronizada de UUIDs:

| Papel da Entidade | Prefixo / Formato | Exemplo de UUID | Descrição |
| :--- | :--- | :--- | :--- |
| **Evento de Auditoria (PK)** | `00000000-0000-4000-8000-0000000000XX` | `00000000-0000-4000-8000-000000000001` | Chave primária da tabela `public.audit_event` |
| **Ator do Sistema (Actor ID)** | `a0000000-0000-4000-8000-0000000000XX` | `a0000000-0000-4000-8000-000000000001` | Identificador do usuário/serviço que efetuou a ação |
| **Registro Afetado (Record ID)** | `b0000000-0000-4000-8000-0000000000XX` | `b0000000-0000-4000-8000-000000000001` | Identificador da entidade de negócio afetada |

---

## 3. Matriz de Cobertura de Seeds (`seeds/0001_audit_event.sql`)

A tabela abaixo descreve os 15 eventos sintéticos determinísticos implementados:

| ID do Evento | Schema | Tabela | Operação | Ator | Registro | Resumo do Payload Sintético |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `...0001` | `auth` | `user` | `INSERT` | `a...0001` | `b...0001` | Criação de usuário mock (`mock.student.01@synthetic.local`) |
| `...0002` | `auth` | `user` | `UPDATE` | `a...0002` | `b...0001` | Atualização de status: `pending` → `active` |
| `...0003` | `auth` | `session_token` | `DELETE` | `a...0001` | `b...0002` | Revogação de sessão expirada |
| `...0004` | `academic_pi` | `project` | `INSERT` | `a...0003` | `b...0003` | Cadastro de projeto acadêmico sintético (`PI-2026-SYN-001`) |
| `...0005` | `academic_pi` | `project` | `UPDATE` | `a...0003` | `b...0003` | Submissão de projeto: `draft` → `submitted` |
| `...0006` | `academic_pi` | `project_draft` | `DELETE` | `a...0003` | `b...0004` | Remoção de rascunho obsoleto substituído por submissão |
| `...0007` | `extension` | `community_action` | `INSERT` | `a...0004` | `b...0005` | Cadastro de ação de extensão regional (`EXT-2026-SYN-101`) |
| `...0008` | `extension` | `community_action` | `UPDATE` | `a...0004` | `b...0005` | Aprovação de proposta de extensão |
| `...0009` | `extension` | `action_prospect` | `DELETE` | `a...0004` | `b...0006` | Cancelamento de prospecto duplicado |
| `...0010` | `assets` | `lab_equipment` | `INSERT` | `a...0005` | `b...0007` | Cadastro de recurso computacional de laboratório (`SYN-ASSET-001`) |
| `...0011` | `assets` | `lab_equipment` | `UPDATE` | `a...0005` | `b...0007` | Reserva de equipamento para projeto acadêmico |
| `...0012` | `assets` | `asset_reservation` | `DELETE` | `a...0005` | `b...0008` | Desalocação e encerramento de período de reserva |
| `...0013` | `institutional` | `campus_unit` | `INSERT` | `a...0005` | `b...0009` | Cadastro de unidade mock de campus (`SYN-SOR-01`) |
| `...0014` | `institutional` | `campus_unit` | `UPDATE` | `a...0005` | `b...0009` | Ajuste de capacidade da unidade institucional |
| `...0015` | `institutional` | `temporary_notice` | `DELETE` | `a...0005` | `b...0010` | Arquivamento de comunicado institucional temporário |

---

## 4. Política de Privacidade e Conformidade com a LGPD

A governança da plataforma impõe regras rígidas de segurança e privacidade:
- **Ausência de Dados Pessoais:** Nenhuma migration ou seed armazena nomes reais, CPFs, RGs, endereços físicos, números telefônicos ou qualquer outro dado pessoal identificável.
- **Sufixos e Domínios Mock:** E-mails utilizam unicamente o domínio não-roteável `.synthetic.local` ou `.invalid`.
- **Validação Automatizada:** O script `scripts/validate.sh` executa uma checagem regex automatizada (passo 10) que rejeita ativamente a presença de provedores reais de e-mail e padrões de documentos pessoais.

---

## 5. Idempotência e Execução Automatizada

Os seeds são gerenciados via `scripts/seed.sh` e acionados no ciclo de vida padrão do `Makefile`:

```bash
# Executa todas as sementes sintéticas
make seed
```

Cada instrução SQL utiliza:
```sql
INSERT INTO public.audit_event (...)
VALUES (...)
ON CONFLICT (id) DO NOTHING;
```

Mesmo sob múltiplas invocações consecutivas, nenhuma linha duplicada é inserida e nenhuma falha de integridade é disparada.

---

## 6. Estratégia de Rollback e Saneamento de Dados

Caso seja necessário remover os dados sintéticos em ambientes de desenvolvimento ou homologação:

### 6.1 Remoção Seletiva por Faixa Determinística
Como todos os IDs de seeds residem na faixa prefixada `00000000-0000-4000-8000-%`:
```sql
DELETE FROM public.audit_event
WHERE id::text LIKE '00000000-0000-4000-8000-%';
```

### 6.2 Reinicialização Completa do Ambiente Local
Para restabelecer um ambiente limpo com recarga de seeds a partir do zero:
```bash
make down
make up
make migrate
make seed
make validate
```
