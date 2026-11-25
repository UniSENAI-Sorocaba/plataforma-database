# Pool do PostgreSQL 16, Guardrails de Conexão e Monitoramento sob Carga (DB-019)

Este documento estabelece a configuração dos limites e timeouts de conexão do PostgreSQL 16 sob responsabilidade da equipe de Banco de Dados, a matriz de responsabilidades e coordenação com o pool HikariCP do Backend, a arquitetura reproduzível de monitoramento sob carga (`scripts/monitor_pool.sh`) e o protocolo de execução local e integrada com QA (`QA-024`), em conformidade com a **ADR-011**, **DB-001**, **DB-017** e a **Issue #19**.

---

## 1. Escopo e Identificação Correta da Dependência `QA-024`

- **Issue desta entrega:** `UniSENAI-Sorocaba/plataforma-database#19` (`[DB-019] Pool do PostgreSQL suporta a carga integrada sem exaurir conexões`).
- **Dependência externa real (`QA-024`):** `UniSENAI-Sorocaba/plataforma-quality#24` (`[QA-024] k6 valida 200 RPS e p95 <=500 ms` — atualmente **aberta**, dependente de `BE-001–018`, `FE-001` e `INF-009–012`).
  - **Atenção de rastreabilidade:** no repositório `plataforma-database`, a Issue `#24` corresponde a `[EXT-05-DB] Persistir inscrições em extensão` e **não** representa o cenário de carga `QA-024`.
- **Princípio de não extrapolação:** como o cenário k6 versionado e o ambiente integrado de staging da `QA-024` ainda não foram publicados em `plataforma-quality` (onde `tests/performance/README.md` registra apenas a meta inicial de `200 RPS` e `p95 <= 500 ms`), esta entrega fornece toda a instrumentação, guardrails do PostgreSQL 16 e medições locais controladas reproduzíveis, mantendo o aceite da execução integrada explicitamente pendente da conclusão da `QA-024`.
- **Preservação do schema funcional:** nenhuma migration foi criada para armazenar telemetria ou dados de teste; os artefatos de medição são gravados em arquivos estruturados (`CSV` e texto) fora do schema de domínio.

---

## 2. Parâmetros do PostgreSQL 16 e Justificativa Técnica

Os parâmetros abaixo foram avaliados e parametrizados via variáveis de ambiente em `compose.yaml` (`command: postgres -c ...`), permitindo calibração por ambiente sem alterar código ou imagens:

| Parâmetro PostgreSQL 16 | Padrão Original | Valor Configurado (`compose.yaml`) | Variável de Override | Justificativa Técnica |
| :--- | :--- | :--- | :--- | :--- |
| `max_connections` | `100` | **`100`** | `PG_MAX_CONNECTIONS` | **Mantido sem aumento arbitrário.** Cada backend PostgreSQL consome memória privada (`work_mem = 4 MB` por operação de ordenação/hash + caches de catálogo) e disputa `ProcArrayLock`/CPU. Com `95` slots regulares úteis, atende até `8` réplicas do Backend com pool padrão (`10`) mantendo folga operacional. |
| `superuser_reserved_connections` | `3` | **`3`** | `PG_SUPERUSER_RESERVED_CONNECTIONS` | Reserva 3 conexões exclusivas para contas `SUPERUSER` em diagnóstico e recuperação emergencial. |
| `reserved_connections` | `0` | **`2`** | `PG_RESERVED_CONNECTIONS` | Recurso nativo do PostgreSQL 16 que reserva 2 conexões adicionais para roles operacionais/observabilidade com `pg_use_reserved_connections`, evitando cegueira de monitoramento caso a aplicação esgote os slots regulares (`95 = 100 - 3 - 2`). |
| `idle_in_transaction_session_timeout` | `0` (desligado) | **`60s`** (`60000 ms`) | `PG_IDLE_IN_TX_TIMEOUT` | Encerra automaticamente sessões esquecidas em `idle in transaction` após 60 s (`SQLSTATE 25P03`), impedindo retenção indefinida de locks de linha, bloqueio de `VACUUM` e exaustão silenciosa do pool HikariCP. |
| `lock_timeout` | `0` (desligado) | **`10s`** (`10000 ms`) | `PG_LOCK_TIMEOUT` | Aborta comandos bloqueados em fila de lock por mais de 10 s (`SQLSTATE 55P03`), evitando efeito cascata que prenderia todas as threads do pool da aplicação atrás de um único lock. |
| `statement_timeout` | `0` (desligado) | **`0`** (nível servidor) | `PG_STATEMENT_TIMEOUT` | Mantido `0` globalmente no servidor para não interromper cargas/migrations administrativas; recomenda-se `30s` na sessão/role OLTP da aplicação em coordenação com o Backend. |
| `log_lock_waits` | `off` | **`on`** | `PG_LOG_LOCK_WAITS` | Registra no log do PostgreSQL esperas de lock que ultrapassem `deadlock_timeout` (`1000 ms`), viabilizando correlação direta durante testes de carga. |

### Fórmula de Orçamento de Conexões

$$\text{Slots Regulares Úteis} = \text{max\_connections} - \text{superuser\_reserved\_connections} - \text{reserved\_connections}$$

Com os valores atuais ($100 - 3 - 2 = 95$), a regra de coordenação com Backend e Infraestrutura é:

$$N_{\text{réplicas Backend}} \times \text{hikari.maximum-pool-size} + M_{\text{margem CI/migração}} \le 95$$

Exemplo seguro para staging/produção inicial: até **4 réplicas** do Backend com `maximum-pool-size = 15` ($4 \times 15 = 60$ conexões, ocupação máxima de $63{,}2\%$ dos slots regulares) ou até **8 réplicas** com o padrão `maximum-pool-size = 10` ($80$ conexões, $84{,}2\%$).

---

## 3. Matriz de Parâmetros por Equipe Responsável e Como Obtê-los

Conforme regra de governança, **nenhum parâmetro do repositório `plataforma-backend` foi alterado nesta entrega**. A inspeção somente leitura de `plataforma-backend` (`branch develop`, `src/main/resources/application.yaml`) confirmou:

- `spring.jpa.open-in-view: false` (**já ativo** — evita retenção de conexão durante serialização HTTP).
- Nenhum bloco explícito `spring.datasource.hikari.*` declarado até o momento, aplicando-se os padrões do Spring Boot 3 / HikariCP.

| Camada / Equipe Responsável | Repositório | Parâmetro | Estado Atual Identificado | Recomendação para Execução Conjunta (`QA-024`) |
| :--- | :--- | :--- | :--- | :--- |
| **Banco de Dados** | `plataforma-database` | `max_connections`, `superuser_reserved_connections`, `reserved_connections`, `idle_in_transaction_session_timeout`, `lock_timeout`, `log_lock_waits` | `100` / `3` / `2` / `60s` / `10s` / `on` em `compose.yaml` | Replicar equivalentes no Parameter Group gerenciado em staging (`INF-009–012`). |
| **Backend (Pool HikariCP)** | `plataforma-backend` | `spring.datasource.hikari.maximum-pool-size` | Implícito (`10` por réplica JVM) | Parametrizar via env (`${DB_POOL_MAX_SIZE:10}`) respeitando a fórmula de orçamento por réplica. |
| **Backend (Pool HikariCP)** | `plataforma-backend` | `spring.datasource.hikari.minimum-idle` | Implícito (`= maximum-pool-size`, `10`) | Manter igual a `maximum-pool-size` sob carga constante para evitar custo de abertura de conexão no pico. |
| **Backend (Pool HikariCP)** | `plataforma-backend` | `spring.datasource.hikari.connection-timeout` | Implícito (`30000 ms`) | Ajustar para `5000–10000 ms` caso deseje falha rápida compatível com `p95 <= 500 ms` da `QA-024`. |
| **Backend (Pool HikariCP)** | `plataforma-backend` | `spring.datasource.hikari.max-lifetime` | Implícito (`1800000 ms` / `30m`) | Manter 1–2 minutos abaixo de qualquer timeout de rede/proxy/RDS. |
| **Backend (Identificação)** | `plataforma-backend` | `spring.datasource.hikari.data-source-properties.ApplicationName` | Não declarado (`PostgreSQL JDBC Driver`) | Definir `plataforma-backend` (ou instância) para rastreio exato na coluna `by_app_user` do `monitor_pool.sh`. |
| **Backend (Métricas)** | `plataforma-backend` | `management.endpoints.web.exposure.include` | `health,info` | Expor `metrics`/`prometheus` em ambiente de teste para coletar `hikaricp.connections.active`, `idle`, `pending` e `timeout`. |
| **QA (Carga Integrada)** | `plataforma-quality` | Script k6 (`QA-024`) | Pendente (`Issue #24` aberta; meta `200 RPS`, `p95 <= 500 ms`) | Executar `monitor_pool.sh` em paralelo ao disparo do k6 no mesmo intervalo UTC. |

### Como obter os valores vigentes em cada lado antes de uma bateria de testes

1. **No PostgreSQL (`plataforma-database`):**
   ```bash
   docker compose exec -T postgres psql -U plataforma -d plataforma -c \
     "SELECT name, setting, unit, source FROM pg_settings WHERE name IN ('max_connections','superuser_reserved_connections','reserved_connections','idle_in_transaction_session_timeout','statement_timeout','lock_timeout','log_lock_waits') ORDER BY name;"
   ```
2. **No Backend (`plataforma-backend`, com a equipe responsável):**
   - Arquivo `src/main/resources/application.yaml` (e variáveis `SPRING_DATASOURCE_HIKARI_*` do deploy);
   - Em execução com Actuator Metrics habilitado: `GET /actuator/metrics/hikaricp.connections.max`, `/hikaricp.connections.active`, `/hikaricp.connections.pending` e `/hikaricp.connections.timeout`.

---

## 4. Solução Reproduzível de Monitoramento e Testes Locais

### 4.1 Coletor de Snapshots (`scripts/monitor_pool.sh` / `make monitor-pool`)

Coleta snapshots periódicos sem criar objetos no banco e grava em `$OUT_DIR` (padrão `tmp/pool-runs/<UTC>`, ignorado pelo Git em execuções avulsas):

- `pg_settings.txt`: versão exata do PostgreSQL, CPUs/memória do host Docker e tabela de parâmetros vigentes;
- `snapshots.csv`: série temporal contendo conexões totais/clientes, `active`, `idle`, `idle in transaction`, `idle in transaction (aborted)`, limite `max_connections`, conexões reservadas, utilização percentual sobre os slots regulares úteis, sessões aguardando (`wait_event_type <> 'Client'`), eventos de espera agregados (`LWLock`, `Lock`, `IO`, etc.), transações ativas e duração máxima (`xact_start`, `query_start`, `state_change`), distribuição por `usuario@application_name`, CPU/memória/PIDs do container (`docker stats`) e flag de saturação (`OK`, `WAIT_OR_IDLE_TX`, `WARN_HIGH_UTIL`, `SATURATED`);
- `summary.txt`: picos, médias, deltas de `pg_stat_database` (`commits`, `rollbacks`, `cache_hit_ratio`, `deadlocks`, `temp_files`), contagem de erros `FATAL`/`ERROR` nos logs do PostgreSQL (`53300`, `25P03`, `55P03`, `57014`) e veredito consolidado.

Exemplo de uso durante uma futura execução integrada da `QA-024` (ex.: janela de 5 minutos com amostragem a cada 2 s):

```bash
INTERVAL_SEC=2 SAMPLES=150 OUT_DIR=evidence/DB-019-qa024-staging ./scripts/monitor_pool.sh
```

### 4.2 Suíte Controlada Local (`scripts/run_pool_load_test.sh` / `make test-pool`)

Provisiona um banco isolado temporário (`plataforma_pool_load_test`) e uma role não-superuser (`db019_app_pool`), aplica todas as migrations, seeds e carga sintética determinística (`5.000` alunos, `600` projetos, `15.005` participações), executa três cenários controlados (`S1` 10 conexões persistentes de leitura, `S2` 40 conexões persistentes mistas R/W e `S3` verificação de exaustão de limite, slots reservados, `idle_in_transaction_session_timeout` e `lock_timeout`) e remove integralmente o banco e a role temporários ao final.
