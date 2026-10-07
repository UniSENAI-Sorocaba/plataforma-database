# Convenções e Padrões de Arquitetura de Banco de Dados (DB-001)

Este documento estabelece as convenções oficiais de banco de dados, arquitetura de segurança e políticas de evolução de schema para o repositório plataforma-database, estritamente alinhado com a *ADR-011*.

## 1. Convenções de Nomenclatura e Organização

Todos os objetos do banco de dados devem seguir convenções padronizadas para garantir consistência, legibilidade e integração fluida entre os serviços.

- *Idioma dos Objetos:* Todos os nomes de schemas, tabelas, colunas, restrições (constraints) e índices devem ser escritos exclusivamente em *inglês*.

- *Schemas:* Os schemas de domínio padrão devem ser nomeados em letras minúsculas, sem espaços ou caracteres especiais:
  - auth
  - academic_pi
  - extension
  - assets
  - institutional

- *Tabelas e Colunas:* Nomeadas utilizando o padrão snake_case (ex.: audit_event, schema_migration, occurred_at, actor_id).

- *Padrões de Prefixos e Sufixos para Restrições e Índices:*
  - *Índices:* Prefixo idx_<nome_tabela>_<nome_coluna> (ex.: idx_audit_event_occurred_at).
  - *Check Constraints:* Sufixo <nome_tabela>_<nome_coluna>_ck ou <nome_tabela>_<regra>_ck (ex.: audit_event_operation_ck).
  - *Foreign Keys:* Sufixo <nome_tabela>_<tabela_referenciada>_fk.
  - *Primary Keys:* Nomenclatura implícita padrão ou pk_<nome_tabela>.

## 2. Tipos de Dados e Padrões de Integridade

Para dar suporte a sistemas distribuídos e garantir rastreabilidade temporal precisa, os seguintes tipos de dados são estritamente obrigatórios:

- *Chaves Primárias (PK):* Devem utilizar UUID para garantir unicidade global entre microsserviços e ambientes externos.

- *Timestamps:* Devem utilizar o tipo timestamptz (timestamp with time zone) com o valor padrão now(), evitando ambiguidades de fuso horário em servidores distribuídos.

- *Dados Semiestruturados:* Estruturas complexas, flexíveis ou históricos de alterações devem utilizar jsonb (ex.: old_data e new_data na tabela de auditoria).

- *Nulabilidade e Validação:* Colunas necessárias para a regra de negócio devem declarar explicitamente NOT NULL. Validações de integridade (CHECK constraints) devem ser definidas para prevenir strings vazias ou dados inválidos.

## 3. Arquitetura de Segurança e Auditabilidade

A segurança do banco de dados é garantida pela combinação de um acesso restrito por padrão nos schemas e pelo rastreamento completo de alterações.

### 3.1 Postura de Segurança e Privilégios

- *Seguro por Padrão (Secure-by-Default):* Os schemas de domínio não concedem privilégios de USAGE ou CREATE para a role PUBLIC automaticamente.

- *Gestão Explícita de Roles:* Para evitar arquiteturas especulativas, a criação de roles específicas de aplicação (ex.: api_user, admin_user) e privilégios explícitos (GRANT/REVOKE) fica diferida até a definição formal de uma matriz de controle de acesso para os ambientes.

### 3.2 Auditabilidade (public.audit_event)

A tabela public.audit_event fornece a estrutura centralizada para registro de alterações de dados (INSERT, UPDATE, DELETE).

- *Identificação:* Armazena o ator (actor_id) e a entidade afetada (schema_name, table_name, record_id).

- *Rastreio Temporal:* Registra a data/hora da operação via occurred_at (timestamptz).

- *Deltas de Estado:* Permite armazenar os dados originais (old_data) e modificados (new_data) no formato jsonb.

A implementação dos mecanismos responsáveis por gerar os eventos de auditoria fica condicionada às entregas responsáveis pela aplicação e pelo controle de acesso.

## 4. Estratégias de Migração e Evolução de Schema

### 4.1 Padrões para Arquivos de Migration

- *Formato de Versionamento:* Padrão sequencial incremental: VXXXX__descricao.sql (ex.: V0001__create_domain_schemas.sql, V0002__create_audit_event.sql).

- *Rastreio de Execução:* As migrations aplicadas são registradas na tabela public.schema_migration com número de versão, descrição e timestamp de execução (applied_at).

- *Idempotência e Atomicidade:* Todo script de migração deve ser delimitado por uma transação (BEGIN; ... COMMIT;) e utilizar cláusulas de proteção (CREATE SCHEMA IF NOT EXISTS, CREATE TABLE IF NOT EXISTS, ON CONFLICT DO NOTHING).

- *Controle de Execução:* Automatizado via script migrate.sh utilizando ON_ERROR_STOP=1 para interromper a execução imediatamente em caso de erro.

### 4.2 Estratégia de Upgrade e Roll-forward (Padrão)

- *Roll-forward:* Para correções de schema, ajustes ou novas tabelas/colunas, o procedimento padrão é aplicar uma nova migração incremental (ex.: V0003) contendo a alteração.

- *Imutabilidade de Arquivos:* Migrations já executadas em ambientes compartilhados ou de produção nunca devem ser editadas ou removidas diretamente.

### 4.3 Estratégia de Rollback e Recuperação (Operações Destrutivas)

- *Obrigatoriedade de Backup:* Antes de executar qualquer migração contendo operações destrutivas (ex.: DROP TABLE, DROP COLUMN), é obrigatório realizar um backup completo ou snapshot do banco de dados.

- *Recuperação:* Em caso de falha durante uma alteração destrutiva em produção, a recuperação do sistema será realizada via Point-in-Time Recovery (PITR) utilizando o backup prévio.

### 4.4 Alterações Destrutivas: Estratégia Expand and Contract

Para executar alterações que quebrem compatibilidade (ex.: renomear colunas, alterar tipos de dados ou dividir tabelas) sem gerar downtime:

1. *Fase Expand (Expandir):* Cria-se a nova estrutura via migration (ex.: V000X) mantendo a estrutura antiga ativa, garantindo retrocompatibilidade com a aplicação no ar.

2. *Fase Transition (Transição):* Migram-se os dados existentes (backfill) e atualizam-se os serviços da aplicação para ler e escrever apenas na nova estrutura.

3. *Fase Contract (Contrair):* Após confirmar que nenhum serviço ativo utiliza a estrutura antiga, aplica-se uma migração posterior (ex.: V000Y) para remover com segurança os objetos legados (mediante backup prévio).

## 5. Diretrizes para Dados de Seed

- *Localização e Política:* Definidos em seeds/README e executados via seed.sh.

- *Idempotência:* Scripts de seed devem utilizar ON CONFLICT ou verificações condicionais para permitir execuções repetidas sem duplicar registros.

- *Determinismo:* Os seeds devem atribuir IDs fixos e determinísticos (ex.: UUIDs constantes).

- *Dados Exclusivamente Sintéticos:* Não é permitido o uso de dados pessoais reais ou sensíveis. Todos os dados de seed devem ser 100% sintéticos.

## 6. Scripts de Automação e Verificação

- migrate.sh: Executa as migrações SQL incrementais em ordem cronológica, interrompendo a execução em caso de erro com ON_ERROR_STOP=1.

- seed.sh: Popula o banco de dados com dados sintéticos determinísticos.

- validate.sh: Valida a existência dos schemas de domínio esperados (auth, academic_pi, extension, assets e institutional) por meio de consulta ao information_schema.