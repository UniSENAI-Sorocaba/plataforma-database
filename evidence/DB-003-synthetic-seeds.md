# Evidência de Validação — DB-003

**Identificador de Trabalho (Work ID):** DB-003  
**Título:** Seeds sintéticos são determinísticos e sem dados pessoais  
**Sprint / Prioridade:** S0 / P0  
**Estimativa:** 3 SP  
**Responsável inicial:** Diogo Lopes Antunes  
**Revisor:** Henrique  
**Dependências:** DB-002  
**Autoridade Normativa:** `plataforma-governance/_KB/README.md` (baseline `.governance-baseline`)  
**Rastreabilidade:** Closes #3  

---

## 1. Resumo Executivo da Entrega

A entrega **DB-003** implementa e padroniza os dados de seed mockados para o banco de dados PostgreSQL 16 da plataforma. Todos os critérios de aceitação foram plenamente atendidos:

- **Determinismo Estrito:** Identificadores gerados com UUIDs constantes, timestamps estáticos em UTC e ordenação previsível.
- **Conformidade com a LGPD (Anti-PII):** Ausência total de dados pessoais ou sensíveis reais. Todas as entidades, nomes e e-mails utilizam identificadores exclusivamente mockados e sintéticos (`@synthetic.local`, `mock.student.01`).
- **Idempotência Operacional:** Execução segura repetida (`ON CONFLICT (id) DO NOTHING`) com garantia de ausência de erros ou duplicações.
- **Cobertura Completa de Schemas e Operações:** Seeds estruturados cobrindo todos os 5 esquemas de domínio (`auth`, `academic_pi`, `extension`, `assets`, `institutional`) e todas as 3 operações de auditoria (`INSERT`, `UPDATE`, `DELETE`) na tabela `public.audit_event`.
- **Validação Integrada:** Automação estendida nos scripts `validate.sh` e `validate_upgrade.sh`, validada na esteira de CI do GitHub Actions.

---

## 2. Especificação e Catálogo de Seeds

O arquivo [`seeds/0001_audit_event.sql`](file:///seeds/0001_audit_event.sql) implementa 15 registros sintéticos estruturados segundo a taxonomia:

- **Chave Primária do Evento (id):** Faixa reservada `00000000-0000-4000-8000-000000000001` até `...0015`
- **Ator do Sistema (actor_id):** Faixa reservada `a0000000-0000-4000-8000-000000000001` até `...0005`
- **Registro do Objeto (record_id):** Faixa reservada `b0000000-0000-4000-8000-000000000001` até `...0010`
- **Timestamps:** Valores estáticos em UTC entre `2026-01-01 10:00:00+00` e `2026-01-01 10:14:00+00`

### Matriz de Registros Sintéticos

| ID | Domínio | Tabela | Operação | Finalidade Sintética |
| :--- | :--- | :--- | :--- | :--- |
| `00000000-0000-4000-8000-000000000001` | `auth` | `user` | `INSERT` | Inclusão de usuário estudante sintético |
| `00000000-0000-4000-8000-000000000002` | `auth` | `user` | `UPDATE` | Atualização de status de cadastro |
| `00000000-0000-4000-8000-000000000003` | `auth` | `session_token` | `DELETE` | Revogação de sessão expirada |
| `00000000-0000-4000-8000-000000000004` | `academic_pi` | `project` | `INSERT` | Registro de projeto acadêmico de PI |
| `00000000-0000-4000-8000-000000000005` | `academic_pi` | `project` | `UPDATE` | Submissão de projeto acadêmico |
| `00000000-0000-4000-8000-000000000006` | `academic_pi` | `project_draft` | `DELETE` | Descarte de rascunho de projeto |
| `00000000-0000-4000-8000-000000000007` | `extension` | `community_action` | `INSERT` | Proposta de ação de extensão |
| `00000000-0000-4000-8000-000000000008` | `extension` | `community_action` | `UPDATE` | Aprovação de proposta de extensão |
| `00000000-0000-4000-8000-000000000009` | `extension` | `action_prospect` | `DELETE` | Cancelamento de prospecto duplicado |
| `00000000-0000-4000-8000-000000000010` | `assets` | `lab_equipment` | `INSERT` | Registro de cluster de computação de laboratório |
| `00000000-0000-4000-8000-000000000011` | `assets` | `lab_equipment` | `UPDATE` | Reserva de equipamento para projeto |
| `00000000-0000-4000-8000-000000000012` | `assets` | `asset_reservation` | `DELETE` | Liberação de recurso de laboratório |
| `00000000-0000-4000-8000-000000000013` | `institutional` | `campus_unit` | `INSERT` | Registro de unidade institucional |
| `00000000-0000-4000-8000-000000000014` | `institutional` | `campus_unit` | `UPDATE` | Atualização de capacidade física |
| `00000000-0000-4000-8000-000000000015` | `institutional` | `temporary_notice` | `DELETE` | Arquivamento de informe institucional |

---

## 3. Evidência de Validação na Instalação Limpa (Clean Install)

### 3.1 Procedimento de Execução
```bash
make up
make migrate
make seed
make validate
```

### 3.2 Resultado das Verificações Automatizadas (`validate.sh`)
1. **Schemas de domínio:** Verificada a presença de `academic_pi`, `assets`, `auth`, `extension`, `institutional`.
2. **Versionamento:** Tabela `public.schema_migration` contém `V0001` e `V0002`.
3. **Estrutura de Auditoria:** Tabela `public.audit_event`, seus índices (`idx_audit_event_*`) e check constraints validados.
4. **Postura de Segurança:** Verificação com `has_schema_privilege` confirmou ausência de privilégios para a role `PUBLIC`.
5. **Cobertura de Seeds (Passo 9 de `validate.sh`):**
   - Cardinalidade verificada: contagem de registros em `public.audit_event` >= 15.
   - Schemas cobertos nos seeds: `academic_pi,assets,auth,extension,institutional`.
   - Operações cobertas nos seeds: `DELETE,INSERT,UPDATE`.
6. **Determinismo e Conformidade Anti-PII (Passo 10 de `validate.sh`):**
   - IDs de auditoria pertencem estritamente à faixa determinística `00000000-0000-4000-8000-%`.
   - Varredura por regex em campos JSONB (`old_data` e `new_data`) confirmou zero ocorrências de provedores reais de email ou padrões de documentos pessoais.

---

## 4. Evidência de Validação de Upgrade e Idempotência

### 4.1 Procedimento de Execução (`validate_upgrade.sh`)
```bash
make validate-upgrade
```

### 4.2 Verificações Realizadas
1. Provisionamento de banco isolado temporário (`plataforma_upgrade_test`).
2. Aplicação da migration base `V0001`.
3. Execução do upgrade via `migrate.sh` aplicando `V0002`.
4. Teste de **idempotência de migrações**: Reexecução de `migrate.sh` ignorando migrações já registradas sem falhas.
5. Aplicação dos seeds determinísticos via `seed.sh`.
6. Teste de **idempotência de seeds**: Reexecução de `seed.sh` sobre o banco com dados já carregados.
   - O comando conclui com sucesso.
   - O número de linhas em `public.audit_event` permanece inalterado em 15.
   - Nenhuma violação de chave primária ou colisão de dados é disparada.
7. Execução bem-sucedida de toda a suíte de validação (`validate.sh`) sobre o banco atualizado e com seeds.
8. Limpeza do banco de teste temporário.

---

## 5. Estratégia Segura de Rollback

Em conformidade com as diretrizes de governança:
1. **Reversão de Seeds em Desenvolvimento:**
   ```sql
   DELETE FROM public.audit_event WHERE id::text LIKE '00000000-0000-4000-8000-%';
   ```
2. **Ambientes Isolados de Teste:** O ciclo `make down && make up && make migrate && make seed` garante reprodutibilidade integral a partir do zero em qualquer estação de trabalho ou pipeline.
3. **Imutabilidade de Migrações:** As migrações de banco permanecem intactas e a evolução segue a política padrão de Roll-Forward e Expand and Contract.

---

## 6. Conclusão e Critérios de Aceite

| Critério de Aceite | Status | Evidência / Validação |
| :--- | :---: | :--- |
| Seeds sintéticos são determinísticos | **Atendido** | IDs fixos, timestamps UTC estáticos, ordenação determinística e idempotência comprovada |
| Seeds sem dados pessoais (LGPD) | **Atendido** | Uso exclusivo de dados mockados (`@synthetic.local`, `mock.student.01`), rejeição automatizada via regex |
| Validação de instalação limpa e upgrade | **Atendido** | Passos automatizados em `validate.sh` e `validate_upgrade.sh` integrados no `Makefile` e GitHub Actions |
| Rastreabilidade e documentação vinculadas | **Atendido** | Atualizações em `seeds/README.md`, `docs/DB-003-seeds.md` e vínculo com Issue #3 |
