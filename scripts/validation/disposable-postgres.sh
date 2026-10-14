#!/usr/bin/env bash
set -euo pipefail

# Each invocation owns a NEW cluster and empty database. Never accept a caller URL.
if [[ "${CALDERA_DISPOSABLE_POSTGRES_CONFIRM:-}" != disposable-loopback-cluster ]]; then
  echo "Explicit disposable Postgres test authorization is required." >&2
  exit 64
fi
case "${1:-}" in chain) TEST_COMMAND=test:postgres-store ;; startup) TEST_COMMAND=test:startup-postgres ;; *) exit 64 ;; esac
VALIDATION_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATION_PG_BIN="${CALDERA_POSTGRES_BIN:-}"
for VALIDATION_TOOL in initdb pg_ctl createdb; do
  if [[ ! -x "$VALIDATION_PG_BIN/$VALIDATION_TOOL" ]]; then
    echo "Existing PostgreSQL binaries are required; no database was created." >&2
    exit 64
  fi
done
# Required dependencies must resolve in this worktree, not via another NODE_PATH.
env -i PATH="$PATH" node -e '
const path = require("node:path");
for (const name of ["express", "pg", "jose", "plaid", "express-rate-limit"]) {
  const resolved = require.resolve(name, { paths: [process.argv[1]] });
  if (!resolved.startsWith(path.join(process.argv[1], "node_modules") + path.sep)) process.exit(1);
}' "$VALIDATION_ROOT/plaid-backend"

if [[ "$1" == chain ]]; then
  # Run every declared non-Postgres npm test component in its original order,
  # with no DB authorization, URL, encryption key, or inherited configuration.
  env -i PATH="$PATH" CALDERA_SUITE_REPORT_DIR="${CALDERA_SUITE_REPORT_DIR:-}" \
    CALDERA_SUITE_RUN_ID="${CALDERA_SUITE_RUN_ID:-}" \
    NODE_OPTIONS="--require=$VALIDATION_ROOT/scripts/validation/contained-network.cjs" \
    node "$VALIDATION_ROOT/scripts/validation/backend-test-chain.js"
fi

VALIDATION_CLUSTER="$(mktemp -d "${TMPDIR:-/tmp}/caldera-pg-test-XXXXXXXX")"
VALIDATION_STARTED=0
cleanup() {
  local validation_status=$?
  trap - EXIT INT TERM
  if [[ "$VALIDATION_STARTED" == 1 ]]; then
    if ! "$VALIDATION_PG_BIN/pg_ctl" -D "$VALIDATION_CLUSTER/data" -m immediate -w stop >/dev/null 2>&1; then
      echo "Disposable server shutdown failed; its cluster was retained." >&2
      exit 1
    fi
  fi
  # Exact directory created by this invocation; never an existing DB or broad path.
  node -e 'const fs=require("node:fs"),path=require("node:path"),os=require("node:os");
const root=fs.realpathSync(process.argv[1]);
if (!path.basename(root).startsWith("caldera-pg-test-") ||
    ![fs.realpathSync(os.tmpdir()),fs.realpathSync("/tmp")].includes(path.dirname(root)) ||
    fs.statSync(root).uid !== process.getuid()) process.exit(1);
fs.rmSync(root,{recursive:true});' "$VALIDATION_CLUSTER" || validation_status=1
  exit "$validation_status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
VALIDATION_PORT="$(node -e 'const net=require("node:net");const s=net.createServer();
s.listen(0,"127.0.0.1",()=>{console.log(s.address().port);s.close();});')"
VALIDATION_DB="caldera_validation_$(node -e 'console.log(require("node:crypto").randomBytes(8).toString("hex"))')"
VALIDATION_KEY="$(node -e 'console.log(require("node:crypto").randomBytes(32).toString("base64"))')"
env -i PATH="$PATH" LC_ALL=C "$VALIDATION_PG_BIN/initdb" -D "$VALIDATION_CLUSTER/data" \
  -U caldera_validation --auth=trust --no-locale >"$VALIDATION_CLUSTER/init.log" 2>&1
VALIDATION_STARTED=1
if ! env -i PATH="$PATH" LC_ALL=C "$VALIDATION_PG_BIN/pg_ctl" -D "$VALIDATION_CLUSTER/data" \
  -l "$VALIDATION_CLUSTER/server.log" \
  -o "-h 127.0.0.1 -p $VALIDATION_PORT -c unix_socket_directories=''" -w start >/dev/null; then
  # This cluster has no credentials or application data. Preserve startup errors
  # in the private raw log; filtered CI artifacts never include these lines.
  tail -n 15 "$VALIDATION_CLUSTER/server.log" >&2
  if [[ ! -e "$VALIDATION_CLUSTER/data/postmaster.pid" ]]; then VALIDATION_STARTED=0; fi
  exit 1
fi
env -i PATH="$PATH" LC_ALL=C "$VALIDATION_PG_BIN/createdb" -h 127.0.0.1 -p "$VALIDATION_PORT" \
  -U caldera_validation "$VALIDATION_DB"
cd "$VALIDATION_ROOT/plaid-backend"
run_guarded() {
  env -i PATH="$PATH" TMPDIR="$(dirname "$VALIDATION_CLUSTER")" \
    DATABASE_URL="postgresql://caldera_validation@127.0.0.1:$VALIDATION_PORT/$VALIDATION_DB" \
    TOKEN_ENCRYPTION_KEY="$VALIDATION_KEY" \
    CALDERA_POSTGRES_TEST_CONFIRM=disposable-loopback-cluster \
    CALDERA_POSTGRES_TEST_DATABASE="$VALIDATION_DB" \
    CALDERA_POSTGRES_TEST_CLUSTER_DIR="$VALIDATION_CLUSTER" \
    CALDERA_SUITE_REPORT_DIR="${CALDERA_SUITE_REPORT_DIR:-}" \
    CALDERA_SUITE_RUN_ID="${CALDERA_SUITE_RUN_ID:-}" \
    NODE_OPTIONS="--require=$VALIDATION_ROOT/scripts/validation/contained-network.cjs" "$@"
}
# Read-only proof of the live server and empty database precedes the exact
# storage/startup command. Each command also retains its own pre-write guards.
run_guarded node "$VALIDATION_ROOT/scripts/validation/postgres-preflight.js"
run_guarded node "$VALIDATION_ROOT/scripts/validation/backend-test-chain.js" "$TEST_COMMAND"
