#!/usr/bin/env sh
set -eu

# DB-019: Coletor reproduzivel de snapshots de conexoes, esperas, transacoes, saturacao e recursos
# do PostgreSQL 16 sob carga (local ou execucao conjunta com QA-024), sem alterar o schema funcional.
#
# Variaveis de ambiente suportadas:
#   PGDATABASE               Banco monitorado (padrao: plataforma)
#   PGUSER                   Usuario de monitoramento (padrao: plataforma)
#   INTERVAL_SEC             Intervalo entre snapshots em segundos (padrao: 1)
#   SAMPLES                  Numero de snapshots a capturar (padrao: 10)
#   OUT_DIR                  Diretorio de saida dos artefatos (padrao: tmp/pool-runs/<UTC>)
#   SATURATION_WARN_PCT      Percentual de alerta de uso de slots regulares (padrao: 80)

DB_NAME="${PGDATABASE:-plataforma}"
DB_USER="${PGUSER:-plataforma}"
INTERVAL_SEC="${INTERVAL_SEC:-1}"
SAMPLES="${SAMPLES:-10}"
SATURATION_WARN_PCT="${SATURATION_WARN_PCT:-80}"
RUN_TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_DIR="${OUT_DIR:-tmp/pool-runs/$RUN_TS}"

mkdir -p "$OUT_DIR"

CONTAINER_ID="$(docker compose ps -q postgres)"
if [ -z "$CONTAINER_ID" ]; then
  echo "ERRO [monitor_pool]: Container do servico postgres nao esta em execucao." >&2
  exit 1
fi

START_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# 1. Registra configuracoes vigentes do PostgreSQL 16 e recursos do host Docker
{
  echo "# PostgreSQL 16 & Container Baseline ($START_ISO)"
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -Atc \
    "SELECT 'pg_version=' || version();"
  docker info --format 'docker_server={{.ServerVersion}} | host_cpus={{.NCPU}} | host_mem_bytes={{.MemTotal}}' 2>/dev/null | tr -d '\r' || true
  echo ""
  echo "## Relevant PostgreSQL Settings"
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT name, setting, unit, boot_val, source FROM pg_settings WHERE name IN ('max_connections','superuser_reserved_connections','reserved_connections','idle_in_transaction_session_timeout','statement_timeout','lock_timeout','log_lock_waits','deadlock_timeout','shared_buffers','work_mem') ORDER BY name;"
} | tr -d '\r' > "$OUT_DIR/pg_settings.txt"

# 2. Captura contadores iniciais de pg_stat_database
BASE_DB_STATS="$(docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -AtF '|' -c \
  "SELECT COALESCE(xact_commit,0), COALESCE(xact_rollback,0), COALESCE(blks_read,0), COALESCE(blks_hit,0), COALESCE(deadlocks,0), COALESCE(temp_files,0), COALESCE(temp_bytes,0) FROM pg_stat_database WHERE datname = '$DB_NAME';" | tr -d '\r')"

CSV_FILE="$OUT_DIR/snapshots.csv"
echo "sample,captured_at_utc,max_connections,superuser_reserved,reserved_connections,usable_regular_slots,client_backends,other_backends,active_conns,idle_conns,idle_in_tx_conns,idle_in_tx_aborted_conns,utilization_pct,waiting_sessions,wait_events,active_xacts,max_xact_ms,max_query_ms,max_idle_in_tx_ms,by_app_user,container_cpu_pct,container_mem_usage,container_mem_pct,container_pids,saturation_status" > "$CSV_FILE"

SNAPSHOT_SQL="
WITH cfg AS (
  SELECT
    current_setting('max_connections')::int AS max_conn,
    current_setting('superuser_reserved_connections')::int AS su_res,
    COALESCE((SELECT setting::int FROM pg_settings WHERE name = 'reserved_connections'), 0) AS reg_res
),
act AS (
  SELECT *
  FROM pg_stat_activity
  WHERE pid <> pg_backend_pid()
),
waits AS (
  SELECT COALESCE(string_agg(we || '(' || cnt || ')', ';' ORDER BY cnt DESC, we), 'none') AS wait_summary
  FROM (
    SELECT wait_event_type || ':' || wait_event AS we, count(*) AS cnt
    FROM act
    WHERE backend_type = 'client backend'
      AND state = 'active'
      AND wait_event_type IS NOT NULL
      AND wait_event_type <> 'Client'
    GROUP BY wait_event_type, wait_event
  ) w
),
apps AS (
  SELECT COALESCE(string_agg(lbl || '=' || total || '(act:' || act_c || '/idle:' || idle_c || ')', ';' ORDER BY total DESC, lbl), 'none') AS app_summary
  FROM (
    SELECT
      COALESCE(usename, 'bg') || '@' || COALESCE(NULLIF(regexp_replace(application_name, '[,;|\" ]+', '_', 'g'), ''), 'unnamed') AS lbl,
      count(*) AS total,
      count(*) FILTER (WHERE state = 'active') AS act_c,
      count(*) FILTER (WHERE state = 'idle') AS idle_c
    FROM act
    WHERE backend_type = 'client backend'
    GROUP BY 1
  ) a
),
agg AS (
  SELECT
    count(*) FILTER (WHERE backend_type = 'client backend') AS client_backends,
    count(*) FILTER (WHERE backend_type <> 'client backend') AS other_backends,
    count(*) FILTER (WHERE backend_type = 'client backend' AND state = 'active') AS active_conns,
    count(*) FILTER (WHERE backend_type = 'client backend' AND state = 'idle') AS idle_conns,
    count(*) FILTER (WHERE backend_type = 'client backend' AND state = 'idle in transaction') AS idle_in_tx_conns,
    count(*) FILTER (WHERE backend_type = 'client backend' AND state = 'idle in transaction (aborted)') AS idle_in_tx_aborted_conns,
    count(*) FILTER (WHERE backend_type = 'client backend' AND state = 'active' AND wait_event_type IS NOT NULL AND wait_event_type <> 'Client') AS waiting_sessions,
    count(*) FILTER (WHERE backend_type = 'client backend' AND xact_start IS NOT NULL) AS active_xacts,
    COALESCE(round((max(EXTRACT(EPOCH FROM (clock_timestamp() - xact_start)) * 1000) FILTER (WHERE backend_type = 'client backend' AND xact_start IS NOT NULL))::numeric, 2), 0) AS max_xact_ms,
    COALESCE(round((max(EXTRACT(EPOCH FROM (clock_timestamp() - query_start)) * 1000) FILTER (WHERE backend_type = 'client backend' AND state = 'active' AND query_start IS NOT NULL))::numeric, 2), 0) AS max_query_ms,
    COALESCE(round((max(EXTRACT(EPOCH FROM (clock_timestamp() - state_change)) * 1000) FILTER (WHERE backend_type = 'client backend' AND state LIKE 'idle in transaction%'))::numeric, 2), 0) AS max_idle_in_tx_ms
  FROM act
)
SELECT
  to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS.MS\"Z\"'),
  cfg.max_conn,
  cfg.su_res,
  cfg.reg_res,
  GREATEST(cfg.max_conn - cfg.su_res - cfg.reg_res, 1) AS usable_slots,
  agg.client_backends,
  agg.other_backends,
  agg.active_conns,
  agg.idle_conns,
  agg.idle_in_tx_conns,
  agg.idle_in_tx_aborted_conns,
  round((agg.client_backends::numeric * 100.0) / GREATEST(cfg.max_conn - cfg.su_res - cfg.reg_res, 1), 2) AS util_pct,
  agg.waiting_sessions,
  waits.wait_summary,
  agg.active_xacts,
  COALESCE(agg.max_xact_ms, 0),
  COALESCE(agg.max_query_ms, 0),
  COALESCE(agg.max_idle_in_tx_ms, 0),
  apps.app_summary
FROM cfg, agg, waits, apps;
"

i=1
while [ "$i" -le "$SAMPLES" ]; do
  PG_ROW="$(docker compose exec -T -e PGAPPNAME=db019_monitor postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -AtF '|' -c "$SNAPSHOT_SQL" | tr -d '\r')"

  C_STATS="$(docker stats --no-stream --format '{{.CPUPerc}}|{{.MemUsage}}|{{.MemPerc}}|{{.PIDs}}' "$CONTAINER_ID" 2>/dev/null | tr -d '\r' || echo 'N/A|N/A|N/A|N/A')"
  C_CPU="$(printf '%s' "$C_STATS" | cut -d'|' -f1)"
  C_MEM_USAGE="$(printf '%s' "$C_STATS" | cut -d'|' -f2 | tr ',' '.')"
  C_MEM_PCT="$(printf '%s' "$C_STATS" | cut -d'|' -f3)"
  C_PIDS="$(printf '%s' "$C_STATS" | cut -d'|' -f4)"

  UTIL_INT="$(printf '%s' "$PG_ROW" | cut -d'|' -f12 | cut -d'.' -f1)"
  WAITING_CNT="$(printf '%s' "$PG_ROW" | cut -d'|' -f13)"
  IDLE_TX_CNT="$(printf '%s' "$PG_ROW" | cut -d'|' -f10)"

  SAT_STATUS="OK"
  if [ "${UTIL_INT:-0}" -ge 95 ]; then
    SAT_STATUS="SATURATED"
  elif [ "${UTIL_INT:-0}" -ge "$SATURATION_WARN_PCT" ]; then
    SAT_STATUS="WARN_HIGH_UTIL"
  elif [ "${WAITING_CNT:-0}" -gt 0 ] || [ "${IDLE_TX_CNT:-0}" -gt 0 ]; then
    SAT_STATUS="WAIT_OR_IDLE_TX"
  fi

  CSV_PG="$(printf '%s' "$PG_ROW" | tr '|' ',')"
  echo "$i,$CSV_PG,$C_CPU,$C_MEM_USAGE,$C_MEM_PCT,$C_PIDS,$SAT_STATUS" >> "$CSV_FILE"

  if [ "$i" -lt "$SAMPLES" ]; then
    sleep "$INTERVAL_SEC"
  fi
  i=$((i + 1))
done

END_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# 3. Captura contadores finais de pg_stat_database e logs de erro do container no intervalo
END_DB_STATS="$(docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -AtF '|' -c \
  "SELECT COALESCE(xact_commit,0), COALESCE(xact_rollback,0), COALESCE(blks_read,0), COALESCE(blks_hit,0), COALESCE(deadlocks,0), COALESCE(temp_files,0), COALESCE(temp_bytes,0) FROM pg_stat_database WHERE datname = '$DB_NAME';" | tr -d '\r')"

LOG_SNIPPET="$(docker compose logs --since "$START_ISO" --no-color postgres 2>&1 | tr -d '\r' || true)"

CONN_LIMIT_ERRS="$(printf '%s\n' "$LOG_SNIPPET" | grep -cE 'too many clients already|remaining connection slots are reserved|connection limit exceeded' || true)"
IDLE_TX_ERRS="$(printf '%s\n' "$LOG_SNIPPET" | grep -c 'terminating connection due to idle-in-transaction timeout' || true)"
LOCK_TIMEOUT_ERRS="$(printf '%s\n' "$LOG_SNIPPET" | grep -c 'canceling statement due to lock timeout' || true)"
STMT_TIMEOUT_ERRS="$(printf '%s\n' "$LOG_SNIPPET" | grep -c 'canceling statement due to statement timeout' || true)"
DEADLOCK_ERRS="$(printf '%s\n' "$LOG_SNIPPET" | grep -c 'deadlock detected' || true)"

# 4. Consolida sumario com picos, medias e deltas via awk
awk -F',' \
  -v start_iso="$START_ISO" \
  -v end_iso="$END_ISO" \
  -v db_name="$DB_NAME" \
  -v samples="$SAMPLES" \
  -v interval_sec="$INTERVAL_SEC" \
  -v base_stats="$BASE_DB_STATS" \
  -v end_stats="$END_DB_STATS" \
  -v conn_errs="$CONN_LIMIT_ERRS" \
  -v idle_tx_errs="$IDLE_TX_ERRS" \
  -v lock_errs="$LOCK_TIMEOUT_ERRS" \
  -v stmt_errs="$STMT_TIMEOUT_ERRS" \
  -v deadlock_errs="$DEADLOCK_ERRS" '
NR == 1 { next }
{
  max_conn = $3
  su_res = $4
  reg_res = $5
  usable = $6
  if ($7 + 0 > peak_client) peak_client = $7 + 0
  sum_client += $7 + 0
  if ($9 + 0 > peak_active) peak_active = $9 + 0
  if ($10 + 0 > peak_idle) peak_idle = $10 + 0
  if ($11 + 0 > peak_idle_tx) peak_idle_tx = $11 + 0
  if ($13 + 0 > peak_util) peak_util = $13 + 0
  if ($14 + 0 > peak_wait) peak_wait = $14 + 0
  if ($16 + 0 > peak_xacts) peak_xacts = $16 + 0
  if ($17 + 0 > peak_xact_ms) peak_xact_ms = $17 + 0
  if ($18 + 0 > peak_query_ms) peak_query_ms = $18 + 0
  if ($19 + 0 > peak_idle_tx_ms) peak_idle_tx_ms = $19 + 0

  cpu_val = $21; sub(/%/, "", cpu_val)
  if (cpu_val + 0 > peak_cpu) peak_cpu = cpu_val + 0

  pids_val = $24
  if (pids_val + 0 > peak_pids) peak_pids = pids_val + 0
  last_mem = $22 " (" $23 ")"

  if ($15 != "none") waits_seen[$15]++
  if ($25 == "SATURATED") sat_count++
  if ($25 == "WARN_HIGH_UTIL") warn_count++
  n++
}
END {
  split(base_stats, b, "|")
  split(end_stats, e, "|")
  d_commit = e[1] - b[1]
  d_rollback = e[2] - b[2]
  d_read = e[3] - b[3]
  d_hit = e[4] - b[4]
  d_deadlock = e[5] - b[5]
  d_temp_files = e[6] - b[6]
  d_temp_bytes = e[7] - b[7]
  hit_ratio = (d_hit + d_read > 0) ? (d_hit * 100.0 / (d_hit + d_read)) : 100.0
  avg_client = (n > 0) ? (sum_client / n) : 0

  printf "=== DB-019 Pool & Resource Monitoring Summary ===\n"
  printf "database=%s | window_utc=%s..%s | samples=%d | interval_s=%s\n", db_name, start_iso, end_iso, n, interval_sec
  printf "limits: max_connections=%d | superuser_reserved=%d | reserved_connections=%d | usable_regular_slots=%d\n", max_conn, su_res, reg_res, usable
  printf "connections: peak_client=%d (avg=%.2f) | peak_active=%d | peak_idle=%d | peak_idle_in_tx=%d | peak_utilization_pct=%.2f%%\n", peak_client, avg_client, peak_active, peak_idle, peak_idle_tx, peak_util
  printf "waits_and_xacts: peak_waiting_sessions=%d | peak_active_xacts=%d | max_xact_ms=%.2f | max_query_ms=%.2f | max_idle_in_tx_ms=%.2f\n", peak_wait, peak_xacts, peak_xact_ms, peak_query_ms, peak_idle_tx_ms
  printf "db_activity_delta: commits=%d | rollbacks=%d | cache_hit_ratio=%.2f%% | deadlocks=%d | temp_files=%d (%d bytes)\n", d_commit, d_rollback, hit_ratio, d_deadlock, d_temp_files, d_temp_bytes
  printf "container_resources: peak_cpu_pct=%.2f%% | mem_last=%s | peak_pids=%d\n", peak_cpu, last_mem, peak_pids
  printf "log_errors_observed: conn_limit_exhausted=%d | idle_in_tx_timeout=%d | lock_timeout=%d | statement_timeout=%d | deadlocks=%d\n", conn_errs, idle_tx_errs, lock_errs, stmt_errs, deadlock_errs
  verdict = (sat_count > 0 || conn_errs + 0 > 0) ? "SATURATION_DETECTED" : ((warn_count > 0) ? "HIGH_UTILIZATION_WARNING" : "HEALTHY_NO_EXHAUSTION")
  printf "verdict=%s\n", verdict
}
' "$CSV_FILE" > "$OUT_DIR/summary.txt"

cat "$OUT_DIR/summary.txt"
