# Evidência de Validação, Guardrails e Testes Controlados de Pool — PostgreSQL 16 (DB-019)

- **Identificador de Trabalho (Work ID):** DB-019
- **Título:** Pool do PostgreSQL suporta a carga integrada sem exaurir conexões
- **Responsável:** Enzo Gabriel
- **Revisor:** Henrique
- **Prioridade / Sprint:** P0 / S5
- **Dependência Externa Identificada:** `UniSENAI-Sorocaba/plataforma-quality#24` (`[QA-024] k6 valida 200 RPS e p95 <=500 ms` — **aberta / pendente**; distinta de `plataforma-database#24`, que corresponde a `[EXT-05-DB] Persistir inscrições em extensão`)
- **Rastreabilidade:** Issue #19 · Branch `feat/DB-019-postgresql-pool` (base `origin/develop` @ `e482e7a`)

---

## 1. Resumo Executivo e Estado dos Critérios de Aceite

1. **Instrumentação e Guardrails no Repositório de Banco (`plataforma-database`):**
   - Configurados e validados em `compose.yaml` os parâmetros de proteção e observabilidade do PostgreSQL 16 (`max_connections=100`, `superuser_reserved_connections=3`, `reserved_connections=2`, `idle_in_transaction_session_timeout=60s`, `lock_timeout=10s`, `statement_timeout=0`, `log_lock_waits=on`), sem aumento arbitrário de `max_connections` e sem criar migrations de telemetria no schema funcional.
   - Implementados o coletor reproduzível de snapshots periódicos (`scripts/monitor_pool.sh`) e a suíte local isolada de concorrência e guardrails (`scripts/run_pool_load_test.sh`), com alvos `make monitor-pool` e `make test-pool`.
2. **Medições Locais Controladas Executadas (PostgreSQL 16.16):**
   - **Cenário S1 (`10` conexões persistentes = 1 réplica HikariCP padrão, `10s`, leitura):** **`4.115,83 TPS`** (`41.094` transações de script / `~164.376` consultas SQL), latência média **`2,430 ms`**, `0` falhas (`0,000%`), ocupação máxima **`10,53%`** dos slots regulares (`10/95`), `0` sessões em espera de lock/I/O, veredito `HEALTHY_NO_EXHAUSTION`.
   - **Cenário S2 (`40` conexões persistentes = 4 réplicas HikariCP × `10`, `10s`, carga mista R/W transacional):** **`4.008,28 TPS`** (`40.158` transações R/W), latência média **`9,979 ms`**, `0` falhas (`0,000%`), ocupação máxima **`42,11%`** dos slots regulares (`40/95`), eventos reais de espera capturados (`LWLock:WALWrite`, `IO:WALSync`), `0` deadlocks, `0` erros de conexão, veredito `HEALTHY_NO_EXHAUSTION`.
   - **Cenário S3 (Guardrails e Saturação Controlada):** comprovados (a) bloqueio limpo ao exceder limite de role não-superuser preservando o monitoramento administrativo (`admin_monitoring_alive=true`), (b) encerramento automático de transação esquecida em `idle in transaction` (`FATAL: terminating connection due to idle-in-transaction timeout`) e (c) aborto limpo de espera bloqueante por `lock_timeout` (`ERROR: canceling statement due to lock timeout`).
3. **Situação Honesta frente à `QA-024`:**
   - Como `UniSENAI-Sorocaba/plataforma-quality#24` (`QA-024`) ainda está aberta e o ambiente/script k6 integrado de staging (`200 RPS`, `p95 <= 500 ms`) ainda não foi publicado pelas dependências `BE-001–018`, `FE-001` e `INF-009–012`, **a execução conjunta integrada em staging não é declarada concluída nesta evidência**. Os testes aqui registrados são **verificações locais controladas em Docker** e não substituem a rodada integrada com Backend + k6 quando a `QA-024` estiver disponível.

---

## 2. Ambiente de Medição

| Item | Valor Real Observado |
| :--- | :--- |
| **PostgreSQL** | `PostgreSQL 16.16 on x86_64-pc-linux-musl, compiled by gcc (Alpine 15.2.0) 15.2.0, 64-bit` |
| **Ferramenta de Carga Local** | `pgbench (PostgreSQL) 16.16` (conexões persistentes sem `-C`, emulando reuso de pool HikariCP) |
| **Docker Engine / Recursos** | `29.8.1` · `12 CPUs` · `8.301.330.432 bytes` (`~7,731 GiB` RAM disponível ao motor Linux) |
| **Base de Código** | `feat/DB-019-postgresql-pool` (a partir de `origin/develop` @ `e482e7a`) |
| **Migrations Aplicadas** | `V0001, V0002, V0003, V0004, V0006, V0007, V0008, V0011, V0017` |
| **Dataset Sintético de Carga** | `5.000` alunos, `100` docentes, `604` projetos, `1.203` períodos e `15.005` participações em banco temporário isolado (`plataforma_pool_load_test`) |

---

## 3. Parâmetros do PostgreSQL 16 (Antes vs. Depois) e Atribuição por Responsável

### 3.1 `pg_settings` Antes e Depois da Parametrização em `compose.yaml`

**Antes (`default` da imagem `postgres:16-alpine`):**

```text
                name                 | setting | unit | boot_val |       source
-------------------------------------+---------+------+----------+--------------------
 deadlock_timeout                    | 1000    | ms   | 1000     | default
 idle_in_transaction_session_timeout | 0       | ms   | 0        | default
 lock_timeout                        | 0       | ms   | 0        | default
 log_lock_waits                      | off     |      | off      | default
 max_connections                     | 100     |      | 100      | configuration file
 reserved_connections                | 0       |      | 0        | default
 shared_buffers                      | 16384   | 8kB  | 16384    | configuration file
 statement_timeout                   | 0       | ms   | 0        | default
 superuser_reserved_connections      | 3       |      | 3        | default
 work_mem                            | 4096    | kB   | 4096     | default
```

**Depois (`compose.yaml` com guardrails parametrizáveis):**

```text
                name                 | setting | unit | boot_val |       source
-------------------------------------+---------+------+----------+--------------------
 deadlock_timeout                    | 1000    | ms   | 1000     | default
 idle_in_transaction_session_timeout | 60000   | ms   | 0        | command line
 lock_timeout                        | 10000   | ms   | 0        | command line
 log_lock_waits                      | on      |      | off      | command line
 max_connections                     | 100     |      | 100      | command line
 reserved_connections                | 2       |      | 0        | command line
 shared_buffers                      | 16384   | 8kB  | 16384    | configuration file
 statement_timeout                   | 0       | ms   | 0        | command line
 superuser_reserved_connections      | 3       |      | 3        | command line
 work_mem                            | 4096    | kB   | 4096     | default
```

### 3.2 Valores Identificados no Banco e no Pool do Backend (`plataforma-backend` @ `develop`)

| Responsável | Repositório / Arquivo | Parâmetro | Valor Vigente Identificado |
| :--- | :--- | :--- | :--- |
| **Banco de Dados** | `plataforma-database` (`compose.yaml`) | `max_connections` / `superuser_reserved_connections` / `reserved_connections` | `100` / `3` / `2` (`95` slots regulares úteis) |
| **Banco de Dados** | `plataforma-database` (`compose.yaml`) | `idle_in_transaction_session_timeout` / `lock_timeout` / `statement_timeout` | `60s` / `10s` / `0` (`log_lock_waits = on`) |
| **Backend** | `plataforma-backend` (`application.yaml`) | `spring.jpa.open-in-view` | `false` (declarado explicitamente) |
| **Backend** | `plataforma-backend` (`application.yaml`) | `spring.datasource.hikari.maximum-pool-size` / `minimum-idle` | `10` / `10` por réplica JVM (padrão HikariCP; bloco `hikari.*` ainda não customizado) |
| **Backend** | `plataforma-backend` (`application.yaml`) | `spring.datasource.hikari.connection-timeout` / `idle-timeout` / `max-lifetime` | `30000 ms` / `600000 ms` / `1800000 ms` (padrão HikariCP) |
| **QA** | `plataforma-quality` (`Issue #24` / `tests/performance/README.md`) | Meta `QA-024` (k6 em staging integrado) | `200 RPS` e `p95 <= 500 ms` (script k6 e execução em staging ainda pendentes) |

---

## 4. Resultados Reais das Bateria Controladas (`evidence/DB-019-test-output.txt`)

### 4.1 Quadro Comparativo dos Cenários S1 e S2

| Métrica Observada | Cenário S1 — Nominal (`10` conexões, leitura) | Cenário S2 — Multirréplica (`40` conexões, mista R/W) |
| :--- | :--- | :--- |
| **Duração** | `10 s` | `10 s` |
| **Concorrência (`pgbench`)** | `c = 10`, `j = 2` (`hikari_sim_1replica`) | `c = 40`, `j = 4` (`hikari_sim_4replicas`) |
| **Transações processadas** | `41.094` (`0` falhas — `0,000%`) | `40.158` (`0` falhas — `0,000%`) |
| **Taxa sustentada (TPS)** | **`4.115,83 TPS`** | **`4.008,28 TPS`** |
| **Latência média por script** | **`2,430 ms`** (conexão inicial `19,152 ms`) | **`9,979 ms`** (conexão inicial `40,879 ms`) |
| **Pico de conexões clientes / Utilização** | `10` / `95` slots (**`10,53%`**) | `40` / `95` slots (**`42,11%`**) |
| **Pico `active` / `idle` / `idle in tx`** | `6` / `4` / `0` | `35` / `7` / `21` |
| **Sessões aguardando / Eventos de espera** | `0` (`none`) | Pico `29` (`LWLock:WALWrite`, `IO:WALSync`) |
| **Duração máx. transação / query** | `2,59 ms` / `2,59 ms` | `12,17 ms` / `6,17 ms` (`idle_in_tx` máx `3,20 ms`) |
| **Cache Hit Ratio / Temp Files / Deadlocks** | `100,00%` / `0` / `0` | `100,00%` / `0` / `0` |
| **Recursos do Container (Pico CPU / Mem / PIDs)** | `890,21%` / `77,85 MiB` (`0,98%`) / `18 PIDs` | `934,05%` / `137,7 MiB` (`1,74%`) / `50 PIDs` |
| **Erros de conexão ou timeout** | `0` | `0` |
| **Veredito do Monitor** | `HEALTHY_NO_EXHAUSTION` | `HEALTHY_NO_EXHAUSTION` |

### 4.2 Amostra Real de Snapshots Periódicos (`evidence/DB-019-s1-snapshots.csv` e `evidence/DB-019-s2-snapshots.csv`)

```text
# Cenário S1 (10 conexões persistentes de leitura)
sample,captured_at_utc,max_connections,superuser_reserved,reserved_connections,usable_regular_slots,client_backends,other_backends,active_conns,idle_conns,idle_in_tx_conns,idle_in_tx_aborted_conns,utilization_pct,waiting_sessions,wait_events,active_xacts,max_xact_ms,max_query_ms,max_idle_in_tx_ms,by_app_user,container_cpu_pct,container_mem_usage,container_mem_pct,container_pids,saturation_status
1,2026-11-25T03:56:13.877Z,100,3,2,95,10,5,6,4,0,0,10.53,0,none,5,0.97,0.97,0,db019_app_pool@hikari_sim_1replica=10(act:6/idle:4),873.52%,77.63MiB / 7.731GiB,0.98%,18,OK
2,2026-11-25T03:56:18.410Z,100,3,2,95,10,5,6,4,0,0,10.53,0,none,5,2.59,2.59,0,db019_app_pool@hikari_sim_1replica=10(act:6/idle:4),890.21%,77.85MiB / 7.731GiB,0.98%,18,OK

# Cenário S2 (40 conexões persistentes mistas R/W)
sample,captured_at_utc,max_connections,superuser_reserved,reserved_connections,usable_regular_slots,client_backends,other_backends,active_conns,idle_conns,idle_in_tx_conns,idle_in_tx_aborted_conns,utilization_pct,waiting_sessions,wait_events,active_xacts,max_xact_ms,max_query_ms,max_idle_in_tx_ms,by_app_user,container_cpu_pct,container_mem_usage,container_mem_pct,container_pids,saturation_status
1,2026-11-25T03:56:55.043Z,100,3,2,95,40,5,12,7,21,0,42.11,6,LWLock:WALWrite(5);IO:WALSync(1),33,8.91,2.97,1.34,db019_app_pool@hikari_sim_4replicas=40(act:12/idle:7),934.05%,137.7MiB / 7.731GiB,1.74%,50,WAIT_OR_IDLE_TX
2,2026-11-25T03:56:59.399Z,100,3,2,95,40,5,35,0,5,0,42.11,29,LWLock:WALWrite(28);IO:WALSync(1),40,12.17,6.17,3.20,db019_app_pool@hikari_sim_4replicas=40(act:35/idle:0),886.95%,137.2MiB / 7.731GiB,1.73%,50,WAIT_OR_IDLE_TX
```

### 4.3 Saída Verbatim do Cenário S3 (Guardrails de Saturação, Reserva Administrativa e Timeouts)

```text
## 3.1 Exaustao controlada da role da aplicacao sem afetar monitoramento administrativo
pgbench_overlimit_exit_code=0
pgbench: error: connection to server on socket "/run/postgresql/.s.PGSQL.5432" failed: FATAL:  too many connections for role "db019_app_pool"
admin_monitoring_alive=true

## 3.2 Encerramento automatico de sessao abandonada em idle in transaction
server_idle_in_transaction_session_timeout=1min
FATAL:  terminating connection due to idle-in-transaction timeout
server closed the connection unexpectedly

## 3.3 Aborto controlado de espera de lock via lock_timeout
server_lock_timeout=10s
lock_wait_exit_code=0
ERROR:  canceling statement due to lock timeout
```

### 4.4 Suíte de Compatibilidade, Upgrade Incremental e Ausência de Drift

- `./scripts/validate.sh` (passos 1 a 38, incluindo validação dos parâmetros `pg_settings` e ausência de tabelas de monitoramento nos schemas de domínio): **Passou**.
- `./scripts/validate_upgrade.sh` + `./scripts/detect_drift.sh`: **Passou**, com **zero drift estrutural** entre instalação limpa e upgrade incremental.

---

## 5. Limitações e Próximos Passos para Execução Integrada (`QA-024`)

1. **Ambiente local vs. Staging integrado:** os números de TPS e latência acima refletem execução local via socket/loopback em Docker Desktop com cache em memória (`cache_hit_ratio = 100%`) e sem a pilha HTTP/JVM/HikariCP real no caminho; **não devem ser reportados como resultado de staging/produção**.
2. **Roteiro quando `plataforma-quality#24` (`QA-024`) estiver disponível:**
   - Confirmar com Backend o número de réplicas em staging e os valores de `spring.datasource.hikari.*` (`ApplicationName=plataforma-backend`);
   - Iniciar `INTERVAL_SEC=2 SAMPLES=180 OUT_DIR=evidence/DB-019-qa024-staging ./scripts/monitor_pool.sh` imediatamente antes da execução do k6 a `200 RPS`;
   - Anexar `snapshots.csv` e `summary.txt` da rodada integrada para concluir o primeiro critério de aceite da Issue #19 em conjunto com QA e Backend.
