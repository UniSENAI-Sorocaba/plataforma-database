#!/usr/bin/env sh
set -eu

# DB-019: Suite reproduzivel de verificacao local de pool, concorrencia e guardrails do PostgreSQL 16
# em banco temporario isolado (plataforma_pool_load_test), preservando o banco principal e os volumes.
#
# Executa tres cenarios controlados:
#   S1 (nominal):      10 conexoes persistentes reutilizadas (equivalente a 1 replica HikariCP padrao), leitura (12s)
#   S2 (multireplica): 40 conexoes persistentes reutilizadas (equivalente a 4 replicas HikariCP x 10), carga mista R/W (12s)
#   S3 (guardrails):   exaustao controlada de limite de role nao-superuser, idle_in_transaction_session_timeout e lock_timeout

ADMIN_USER="${PGUSER:-plataforma}"
TEST_DB="plataforma_pool_load_test"
APP_ROLE="db019_app_pool"
APP_PASS="db019_synthetic_local_only"
DURATION_SEC="${DURATION_SEC:-12}"
EVIDENCE_BASE="${EVIDENCE_BASE:-tmp/db019-runs}"

cleanup() {
  echo "[pool_load_test] Limpando banco e role temporarios ($TEST_DB / $APP_ROLE)..."
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$ADMIN_USER" -d postgres -c \
    "DROP DATABASE IF EXISTS $TEST_DB WITH (FORCE);" >/dev/null 2>&1 || true
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$ADMIN_USER" -d postgres -c \
    "DROP ROLE IF EXISTS $APP_ROLE;" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

echo "=== [DB-019] 1. Provisionando banco isolado ($TEST_DB) e role de aplicacao nao-superuser ($APP_ROLE) ==="
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$ADMIN_USER" -d postgres -c \
  "DROP DATABASE IF EXISTS $TEST_DB WITH (FORCE);"
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$ADMIN_USER" -d postgres -c \
  "DROP ROLE IF EXISTS $APP_ROLE;"
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$ADMIN_USER" -d postgres -c \
  "CREATE ROLE $APP_ROLE LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD '$APP_PASS';"
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$ADMIN_USER" -d postgres -c \
  "CREATE DATABASE $TEST_DB OWNER $ADMIN_USER;"

echo "=== [DB-019] 2. Aplicando migrations, seeds e carga sintetica deterministica (5.000 alunos / 600 projetos / 15.005 participacoes) ==="
PGDATABASE="$TEST_DB" ./scripts/migrate.sh >/dev/null
PGDATABASE="$TEST_DB" ./scripts/seed.sh >/dev/null

docker compose exec -T postgres psql -v ON_ERROR_STOP=1 \
  -v n_students=5000 -v n_projects=600 -v n_instr=100 \
  -U "$ADMIN_USER" -d "$TEST_DB" < evidence/DB-017-load.sql >/dev/null

# Concede privilegios estritos de DML nos schemas necessarios apenas no banco temporario de teste
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$ADMIN_USER" -d "$TEST_DB" <<EOF >/dev/null
GRANT CONNECT ON DATABASE $TEST_DB TO $APP_ROLE;
GRANT USAGE ON SCHEMA academic_pi, auth TO $APP_ROLE;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA academic_pi, auth TO $APP_ROLE;
EOF

# Copia os scripts de workload para /tmp dentro do container para execucao direta pelo pgbench
docker compose cp evidence/DB-019-workload-read.sql postgres:/tmp/db019_read.sql >/dev/null
docker compose cp evidence/DB-019-workload-mixed.sql postgres:/tmp/db019_mixed.sql >/dev/null

# -----------------------------------------------------------------------------
# Cenario S1: 10 conexoes persistentes reutilizadas (1 replica HikariCP padrao)
# -----------------------------------------------------------------------------
S1_DIR="$EVIDENCE_BASE/s1-nominal-10conns"
rm -rf "$S1_DIR"
mkdir -p "$S1_DIR"

echo "=== [DB-019] 3. Executando Cenario S1: 10 conexoes persistentes (leitura, ${DURATION_SEC}s) ==="
PGDATABASE="$TEST_DB" INTERVAL_SEC=1 SAMPLES=$((DURATION_SEC + 1)) OUT_DIR="$S1_DIR" ./scripts/monitor_pool.sh > "$S1_DIR/monitor_stdout.txt" &
MON_PID=$!

sleep 1
docker compose exec -T -e PGPASSWORD="$APP_PASS" -e PGAPPNAME="hikari_sim_1replica" postgres \
  pgbench -U "$APP_ROLE" -n -c 10 -j 2 -T "$DURATION_SEC" -f /tmp/db019_read.sql "$TEST_DB" \
  | tr -d '\r' > "$S1_DIR/pgbench.txt" 2>&1

wait "$MON_PID"
cat "$S1_DIR/pgbench.txt"
cat "$S1_DIR/summary.txt"

# -----------------------------------------------------------------------------
# Cenario S2: 40 conexoes persistentes reutilizadas (4 replicas HikariCP x 10)
# -----------------------------------------------------------------------------
S2_DIR="$EVIDENCE_BASE/s2-multireplica-40conns"
rm -rf "$S2_DIR"
mkdir -p "$S2_DIR"

echo "=== [DB-019] 4. Executando Cenario S2: 40 conexoes persistentes (carga mista R/W, ${DURATION_SEC}s) ==="
PGDATABASE="$TEST_DB" INTERVAL_SEC=1 SAMPLES=$((DURATION_SEC + 1)) OUT_DIR="$S2_DIR" ./scripts/monitor_pool.sh > "$S2_DIR/monitor_stdout.txt" &
MON_PID=$!

sleep 1
docker compose exec -T -e PGPASSWORD="$APP_PASS" -e PGAPPNAME="hikari_sim_4replicas" postgres \
  pgbench -U "$APP_ROLE" -n -c 40 -j 4 -T "$DURATION_SEC" -f /tmp/db019_mixed.sql "$TEST_DB" \
  | tr -d '\r' > "$S2_DIR/pgbench.txt" 2>&1

wait "$MON_PID"
cat "$S2_DIR/pgbench.txt"
cat "$S2_DIR/summary.txt"

# -----------------------------------------------------------------------------
# Cenario S3: Verificacao controlada de saturacao de limite, reserva admin e timeouts
# -----------------------------------------------------------------------------
S3_DIR="$EVIDENCE_BASE/s3-guardrails"
rm -rf "$S3_DIR"
mkdir -p "$S3_DIR"

echo "=== [DB-019] 5. Executando Cenario S3: Guardrails de saturacao, slots reservados e timeouts ==="
{
  echo "# Cenario S3 — Guardrails de Conexao, Slots Reservados e Timeouts"
  echo ""

  # 5.1 Limite de conexoes de role nao-superuser preserva acesso administrativo/monitoramento
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$ADMIN_USER" -d postgres -c \
    "ALTER ROLE $APP_ROLE CONNECTION LIMIT 3;" >/dev/null

  echo "## 3.1 Exaustao controlada da role da aplicacao sem afetar monitoramento administrativo"
  set +e
  EXHAUST_OUT="$(docker compose exec -T -e PGPASSWORD="$APP_PASS" -e PGAPPNAME="hikari_overlimit_probe" postgres \
    pgbench -U "$APP_ROLE" -n -c 5 -j 2 -T 2 -f /tmp/db019_read.sql "$TEST_DB" 2>&1 | tr -d '\r')"
  EXHAUST_RC=$?
  set -e
  echo "pgbench_overlimit_exit_code=$EXHAUST_RC"
  printf '%s\n' "$EXHAUST_OUT" | grep -E 'FATAL:|connection limit exceeded|client .* aborted' | head -n 5 || true

  # Confirma que a conexao administrativa continua operacional no mesmo instante
  ADMIN_ALIVE="$(docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$ADMIN_USER" -d "$TEST_DB" -Atc "SELECT 'admin_monitoring_alive=true';" | tr -d '\r')"
  echo "$ADMIN_ALIVE"

  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$ADMIN_USER" -d postgres -c \
    "ALTER ROLE $APP_ROLE CONNECTION LIMIT -1;" >/dev/null
  echo ""

  # 5.2 Verificacao de idle_in_transaction_session_timeout encerrando transacao abandonada
  echo "## 3.2 Encerramento automatico de sessao abandonada em idle in transaction"
  echo "server_idle_in_transaction_session_timeout=$(docker compose exec -T postgres psql -U "$ADMIN_USER" -d "$TEST_DB" -Atc "SHOW idle_in_transaction_session_timeout;" | tr -d '\r')"
  set +e
  IDLE_TX_OUT="$(docker compose exec -T -e PGPASSWORD="$APP_PASS" postgres psql -U "$APP_ROLE" -d "$TEST_DB" <<'SQL' 2>&1 | tr -d '\r'
SET idle_in_transaction_session_timeout = '600ms';
BEGIN;
SELECT 1;
\! sleep 1
SELECT 2;
SQL
)"
  set -e
  printf '%s\n' "$IDLE_TX_OUT" | grep -E 'FATAL:|idle-in-transaction timeout|server closed the connection' | head -n 4 || true
  echo ""

  # 5.3 Verificacao de lock_timeout abortando espera bloqueante antes de esgotar o pool
  echo "## 3.3 Aborto controlado de espera de lock via lock_timeout"
  echo "server_lock_timeout=$(docker compose exec -T postgres psql -U "$ADMIN_USER" -d "$TEST_DB" -Atc "SHOW lock_timeout;" | tr -d '\r')"

  # Sessao 1 segura lock exclusivo em uma linha por 3 segundos em background
  docker compose exec -T postgres psql -U "$ADMIN_USER" -d "$TEST_DB" -c \
    "BEGIN; UPDATE academic_pi.project SET updated_at = now() WHERE id = 'b0000000-0000-4000-8000-000000000101'; SELECT pg_sleep(3); ROLLBACK;" >/dev/null 2>&1 &
  LOCK_HOLDER_PID=$!
  sleep 1

  # Captura sessao bloqueada / evento de espera e aborto por lock_timeout na Sessao 2
  set +e
  LOCK_WAIT_OUT="$(docker compose exec -T -e PGPASSWORD="$APP_PASS" postgres psql -v ON_ERROR_STOP=1 -U "$APP_ROLE" -d "$TEST_DB" <<'SQL' 2>&1 | tr -d '\r'
SET lock_timeout = '700ms';
UPDATE academic_pi.project SET updated_at = now() WHERE id = 'b0000000-0000-4000-8000-000000000101';
SQL
)"
  LOCK_WAIT_RC=$?
  set -e
  wait "$LOCK_HOLDER_PID" || true
  echo "lock_wait_exit_code=$LOCK_WAIT_RC"
  printf '%s\n' "$LOCK_WAIT_OUT" | grep -E 'ERROR:|canceling statement due to lock timeout' | head -n 4 || true
} > "$S3_DIR/guardrails_verification.txt"

cat "$S3_DIR/guardrails_verification.txt"

docker compose exec -T postgres rm -f /tmp/db019_read.sql /tmp/db019_mixed.sql >/dev/null 2>&1 || true

echo "=== [DB-019] Suite local de carga e guardrails de pool concluida com sucesso! ==="
