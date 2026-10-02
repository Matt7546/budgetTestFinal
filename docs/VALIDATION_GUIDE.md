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
| `npm test` from `plaid-backend` | The default backend chain listed below **only when each completes**, including a real disposable Postgres storage check | Separate deployed-startup Postgres check, iOS tests, real Plaid delivery, production configuration |
| `npm run test:startup` from `plaid-backend` | Synthetic startup-policy/selection tests, unsafe-config rejection through real index.js, and contained local Express startup | Real Postgres startup or deployed credentials |
| `npm run test:startup-postgres` from `plaid-backend` | Real index.js/Express/store startup and normal migrations against a guarded fresh disposable Postgres database; required auth and disabled dev auth | Existing application DB safety, live provider/Apple credentials, or rollout approval |

The backend `npm test` chain is: rate limiting, user scope, crypto,
authentication, startup policy/contained Express startup, account deletion, Item lifecycle Express/JSON races,
card-payment details, Item recovery,
transactions, evidence, and Postgres storage. The Postgres step now exits
nonzero when its required environment, dependency, cluster proof, or execution
is missing. It never reports a skip as a pass. The script checks the storage
seam; it is not a substitute for real Express middleware composition tests.
No tracked GitHub Actions workflow runs this chain automatically.

F12's `test:startup` child processes execute the actual `index.js`, not a second
server implementation. They use an empty temporary working directory, synthetic
configuration only, catch-all outbound connection rejection, and instrumentation
that binds listeners to ephemeral loopback ports. Unsafe config must produce no
app/store/provider-client/listen event or persistence file. A deliberate SDK
transport attempt is rejected before its external socket can connect, proving
the interceptor is active. A schema-failure injection checks fail-before-listen
and safe error logging; it is not a real storage outage.

`test:startup-postgres` additionally executes the real Postgres and auth stores
and migrations under the F14 authorization/server-identity/empty-DB guards.
It uses Sandbox configuration with synthetic provider/Apple values and verifies
no provider request is attempted. Do not substitute a missing/skipped database
run for this evidence. See `ENVIRONMENT_WORKFLOW.md` for the deployment contract.
The contained child derives only the current OS username for the default local
DB role; it does not inherit PGUSER, PGPASSWORD, or application credentials.
An explicit role in the guarded DATABASE_URL takes precedence.
The standalone check requires its **own fresh empty database**: it leaves the
schema in place, so running `test:postgres-store` or repeating this check against
that same database must reject. For a release sequence, run the full backend
chain on one fresh database and `test:startup-postgres` on another newly created
empty database in the same separately authorized disposable cluster. Neither
command may target an existing application database. F12 focused validation is
not execution of the full release chain.

For F2, `npm run test:item-lifecycle-races` exercises the production route
handlers with real Express and authentication middleware, intercepted provider
calls, explicit barriers, and a reopened JSON store. Disconnect/deletion refuse
to begin while an exchange lease exists; a new exchange cannot start after
removal begins. A failed exchange-save compensation retains an owner-scoped,
encrypted recovery record or the exact exchange lease and blocks a false
completed removal. The route regression injects a functioning lifecycle store
but failed Item save, failed recovery write, and uncertain provider removal;
deletion is refused and the lease survives reopening. It also covers a real
store save followed by a lost response: the exact Item and `item_saved` marker
prevent compensating provider removal. The Postgres store writes that marker
and computes the response count inside the Item transaction. On a thrown save,
owner-row-locked verification distinguishes an exact committed Item from a
definite rollback; failed or conflicting verification leaves the lease fenced.
No count is fabricated to make an exchange appear successful. The JSON driver
supports one writer process only: synchronous file updates do not
establish multi-process serialization. The guarded Postgres check uses a
second store instance, real Express handlers, and database row locks to verify
the persisted gate. It requires a new empty database for every execution.
Neither check contacts Plaid or establishes provider behavior. Migration
`004_item_lifecycle.sql` is additive and applied by normal Postgres-backed
backend startup before affected routes are available. Existing JSON token records remain
plaintext as before; new exchange-result and recovery tokens are encrypted with
a locally persisted recovery key. A missing/corrupt key with existing encrypted
obligations blocks new exchange rather than being replaced. No background
provider removal retry, lease expiry, or destructive retry is introduced.

## F2 interrupted-exchange reconciliation

An exchange lease belongs to an exact backend owner, operation UUID, and owner
generation. It stores creation time, a SHA-256 digest of the ephemeral public
token (not a replay credential), and the Link session ID when the iOS client
supplies it. The iOS Link-success path now sends that ID; older clients may not.
`prepared` means the durable lease was written before request dispatch.
`dispatch_uncertain` is written before the Plaid await, so it covers both a
crash before dispatch and a sent request whose response was not durably saved.
Do not infer which from this state. `result_recorded` retains the exact Item ID,
encrypted access token, and exchange request ID when returned. A crash between
the provider response and this write remains `dispatch_uncertain` with no local
token. `item_saved` is written with the exact active Item and token in one
store update/transaction; it is the durable evidence needed before a saved
acknowledgment. A matching row without this marker does not prove that this
exchange saved it. `removal_confirmed` retains the removal request ID after a resolved
`/item/remove` response and before the local lease acknowledgment. A separate
encrypted recovery record names its originating lease when responsibility is
transferred. If the result write failed, that exact linked recovery record can
supply the encrypted Item token when confirmed removal is durably recorded.
All these obligations block disconnect and account deletion.

This is an exceptional, authorized operator procedure, not an API exposed to
the app. Preserve the raw store/DB and a case record before acting; identify
the backend environment, exact owner, lease UUID/generation, Link session ID,
Item ID (if present), and provider request IDs. Use restricted storage access
and the store's `getItemExchangeLeases(owner)` only in a controlled process;
never print, log, email, or put a token in command-line arguments. Do not copy
an encrypted JSON record without its existing recovery key. A local UUID or
public-token hash is **not** a Plaid lookup key. Plaid documents Link session,
Item, and request IDs as support identifiers, but does not document exchange
replay or Item lookup/removal by the public token.

1. For `prepared` or `dispatch_uncertain` without a recorded token, use the
   Link session ID and any securely retained provider request evidence to
   investigate with Plaid Dashboard/support. Do not replay the public token or
   infer absence from timeout, age, an empty local Item table, or session loss.
   If the exact provider outcome and a safe removal/credential path cannot be
   established, keep the lease and block deletion. Plaid support is an
   escalation, **not** a guaranteed way to recover a missing access token.
2. For `item_saved`, the store's `finishItemExchange` with `kind: "saved"`
   verifies the exact owner/lease and active Item ID **and token** before
   releasing it. For `result_recorded`, a matching active row alone is
   ambiguous: preserve the lease and investigate; do not manually mark it
   saved or remove a possibly active provider Item. When an exact outcome is
   established as not saved, an authorized operator may use the recorded
   access token to call Plaid `/item/remove`. Only after a successful response
   with its request ID, persist `removal_confirmed` through
   `markItemExchangeRemovalConfirmed` for that owner, lease, and Item, then
   call `finishItemExchange` with `kind: "removed"`. A timeout or ambiguous
   error, including a malformed success body without a request ID, is not
   confirmation; keep the lease.
3. If an exchange-linked removal-recovery record was durably written, the
   exact owner/lease/Item/token comparison permits `kind: "recovery"` transfer.
   This removes only the lease; the recovery record still blocks deletion.
   Clear that record only after confirmed removal of its exact provider Item.
4. For `removal_confirmed`, verify the recorded Item and removal request ID,
   then finish only that exact owner/lease/generation. A failed local finish
   leaves the fence; never clear a different or newer lease. A stale, wrong-
   owner, or wrong-generation attempt is rejected. If the provider evidence is
   incomplete, leave the obligation and escalate rather than manually deleting
   rows or treating it as a completed account deletion.

Plaid's documented `/item/public_token/exchange` returns an access token,
Item ID, and request ID; `/item/remove` requires the access token and its
current response returns a request ID. There is no atomic transaction across
Plaid and either local store. See [Items API](https://plaid.com/docs/api/items/),
[API identifiers](https://plaid.com/docs/api/), and
[Plaid support identifiers](https://support.plaid.com/hc/en-us/articles/15374015366807-How-do-I-provide-troubleshooting-identifiers-on-support-cases).

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
LC_ALL=C "$CALDERA_PG_BIN/initdb" -D "$CALDERA_TEST_CLUSTER_ROOT/data" --auth-local=trust --auth-host=trust --no-instructions --encoding=UTF8 --locale=C
LC_ALL=C "$CALDERA_PG_BIN/pg_ctl" -D "$CALDERA_TEST_CLUSTER_ROOT/data" -o "-c listen_addresses=127.0.0.1 -p $CALDERA_TEST_PORT -k $CALDERA_TEST_CLUSTER_ROOT" -l "$CALDERA_TEST_CLUSTER_ROOT/postgres.log" start
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
