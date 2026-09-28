# Caldera validation contract

Validation claims must name the checks that actually ran. A successful build
does not establish test, backend, database, provider, or deployment readiness.
Routine edits do not need every release gate.

## Commands and scope

| Command | Proves on success | Does not prove |
| --- | --- | --- |
| `./scripts/task-start.sh` | Repository preflight, Xcode project listing, and local environment inventory were readable | Build or test success |
| `git diff --check` | Tracked patch has no whitespace errors | Compiles or behaves correctly |
| `./scripts/task-finish.sh` | Diff check and Debug Local simulator build | iOS tests, Release build, backend, Postgres |
| `./scripts/task-finish.sh --release` | Diff check plus Debug Local and Release Candidate simulator builds | iOS tests, backend, Postgres, TestFlight |
| `./scripts/validate.sh` | Diff check plus Debug Local and Release Candidate simulator builds | Any test suite or release approval |
| `./scripts/validate-summary.sh` | Same build-only checks, summarized with the actual exit code | Any test suite or release approval |
| `node --test scripts/tests/validate-summary.test.js` | Wrapper success and distinct failure exit propagation | An actual Xcode build |
| `node --test plaid-backend/scripts/postgres-test-target.test.js` | Unsafe/missing Postgres targets are rejected before writes | A live database check |
| `xcodebuild -project budgetTest.xcodeproj -scheme 'Caldera Debug Local' -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' CODE_SIGNING_ALLOWED=NO test` | The scheme's iOS unit tests on that available simulator | Release tests, backend, provider behavior |
| `npm test` from `plaid-backend` | All declared backend suites **only when each completes**, including a real disposable Postgres check | iOS tests, real Plaid delivery, production configuration |

The backend `npm test` chain is: rate limiting, user scope, crypto,
authentication, account deletion, card-payment details, Item recovery,
transactions, evidence, and Postgres storage. The Postgres step now exits
nonzero when its required environment, dependency, cluster proof, or execution
is missing. It never reports a skip as a pass. The script checks the storage
seam; it is not a substitute for real Express middleware composition tests.
No tracked GitHub Actions workflow runs this chain automatically.

For a dependency-complete backend run in a fresh checkout, use the committed
lockfile with `cd plaid-backend && npm ci`. The backend Dockerfile currently
uses `npm install --omit=dev` for its runtime image; Docker startup is not a
validation run. Do not copy application or production `.env` values into a
test environment.

## Disposable Postgres requirement

`npm run test:postgres-store` requires all of:

- `CALDERA_POSTGRES_TEST_CONFIRM=disposable-loopback-cluster`.
- `CALDERA_POSTGRES_TEST_CLUSTER_DIR` pointing to a user-owned, newly created
  temporary `caldera-pg-test-*` directory with its `data` subdirectory.
- `CALDERA_POSTGRES_TEST_DATABASE` naming a new, empty
  `caldera_validation_<eight-or-more-lowercase-hex-digits>` database.
- `DATABASE_URL` naming that exact database at `127.0.0.1` on an explicit
  non-default port, without URL query overrides.
- `TOKEN_ENCRYPTION_KEY` containing a separate disposable test key.

Before schema SQL, the check connects read-only and confirms the actual
server reports the exact cluster data directory, loopback-only listening and
connection addresses, the exact database name, and no existing user tables.
An opt-in variable or database-name substring alone cannot authorize writes.
The script's test rows are removed on exit, but the operator must shut down
and dispose of the temporary cluster after validating its exact path. Never
point it at an existing Caldera application database.

Example for a Mac with the existing Homebrew PostgreSQL 17 installation;
choose an unused port and use a fresh cluster each run:

```sh
CALDERA_PG_BIN=/opt/homebrew/opt/postgresql@17/bin
CALDERA_TEST_CLUSTER_ROOT="$(mktemp -d /private/tmp/caldera-pg-test-XXXXXXXX)"
CALDERA_TEST_DB="caldera_validation_$(openssl rand -hex 6)"
CALDERA_TEST_PORT=55439
"$CALDERA_PG_BIN/initdb" -D "$CALDERA_TEST_CLUSTER_ROOT/data" --auth-local=trust --auth-host=trust --no-instructions
"$CALDERA_PG_BIN/pg_ctl" -D "$CALDERA_TEST_CLUSTER_ROOT/data" -o "-c listen_addresses=127.0.0.1 -p $CALDERA_TEST_PORT -k $CALDERA_TEST_CLUSTER_ROOT" -l "$CALDERA_TEST_CLUSTER_ROOT/postgres.log" start
"$CALDERA_PG_BIN/createdb" -h 127.0.0.1 -p "$CALDERA_TEST_PORT" "$CALDERA_TEST_DB"
export CALDERA_POSTGRES_TEST_CONFIRM=disposable-loopback-cluster
export CALDERA_POSTGRES_TEST_CLUSTER_DIR="$CALDERA_TEST_CLUSTER_ROOT"
export CALDERA_POSTGRES_TEST_DATABASE="$CALDERA_TEST_DB"
export DATABASE_URL="postgresql://127.0.0.1:$CALDERA_TEST_PORT/$CALDERA_TEST_DB"
export TOKEN_ENCRYPTION_KEY="$(node -e "process.stdout.write(require('node:crypto').randomBytes(32).toString('base64'))")"
cd plaid-backend
npm run test:postgres-store
"$CALDERA_PG_BIN/pg_ctl" -D "$CALDERA_TEST_CLUSTER_ROOT/data" stop
```

The command intentionally does not remove the cluster directory. Confirm the
stopped server and exact temporary path before disposing of it. Keep the test
key and URL out of logs and do not reuse a production database or credential.

For release readiness, also run the iOS tests, real Express composition tests,
the complete backend chain against a disposable database, and the separate
Sandbox webhook/Item-readiness checks required by the rollout runbook. Record
each command, commit, environment, result, and any skipped gate explicitly.
