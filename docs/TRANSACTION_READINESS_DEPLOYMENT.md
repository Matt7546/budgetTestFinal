# Transaction Readiness Deployment Runbook

This is an operator checklist, not authorization to deploy or change an
environment. Use Sandbox or an isolated staging environment for verification
until a production rollout is separately approved. Do not log access tokens,
transaction details, or account balances.

## Backend behavior

- `POST /api/plaid/webhook` is registered in `plaid-backend/index.js` before
  JSON parsing so the signed raw body can be verified. It does not use the app
  API key; it requires Plaid's `Plaid-Verification` signature. The handler
  checks ES256, environment, body hash, the key obtained from
  `/webhook_verification_key/get`, and a five-minute issue-time limit.
- Configure `PLAID_WEBHOOK_URL` as the full public **HTTPS** URL ending in
  `/api/plaid/webhook`. `configuredWebhookURL` rejects non-HTTPS URLs. New
  Transactions-enabled Link tokens include that URL. During an authenticated
  `GET /api/transactions`, an existing Item receives it via
  `/item/webhook/update` if `/item/get` reports a different URL. A
  `WEBHOOK_UPDATE_ACKNOWLEDGED` event proves only that the URL changed.
- An Item linked at least 24 hours earlier with no recorded historical proof
  and a valid provider transaction-update timestamp is probed on an
  authenticated transactions request. An older JSON Item with no stored link
  date can also be probed; its age is not silently synthesized. After a
  successfully recorded probe, subsequent probes are spaced by 24 hours.
  The probe calls `/transactions/sync` without a cursor and requests one
  update. This is the documented initial Sync request, not a `cursor: "now"`
  migration; the returned transaction row and cursor are discarded. Caldera
  continues to use `/transactions/get` for its authoritative transaction
  snapshot. Only the exact provider response status
  `HISTORICAL_UPDATE_COMPLETE`, or a verified completion webhook, records
  historical readiness. `NOT_READY`, `INITIAL_UPDATE_COMPLETE`, unknown,
  missing, or failed responses remain ineligible. A later authenticated
  request retries an incomplete probe after the interval; it does not require
  a new transaction webhook, deleting the Item, or relinking the bank.
- Provider readiness and `/item/get` transaction
  `last_successful_update` are independent. Both must fit the accepted
  snapshot before automatic suggestions or Bill matches can be eligible.

Plaid documents Sync's `transactions_update_status` as carrying the same
update information as transaction webhooks and as useful for missed webhooks.
The Sync API documents an omitted cursor as starting with the first update;
`cursor: "now"` is restricted to migration, so the status-only probe does not
use it: <https://plaid.com/docs/api/products/transactions/>.

## Webhook verification resource contract (F13)

The actual route order is CORS → webhook admission → bounded raw JSON parser
→ JWT/header/claim and body-hash rejection → retained-verification permit
→ exact-key lookup → ES256 signature
and age verification → authenticated JSON/event validation → existing exact
active Item/owner readiness handling. The general app/API limiter and app
authentication still apply to ordinary API routes, not provider callbacks.
Startup policy validation still precedes app/store/provider construction.

- One always-enabled, process-wide fixed-window budget admits at most 300
  webhook attempts per 60 seconds and 32 open HTTP requests. Rejection is 429 with
  `Retry-After`, before parsing or key work. It remains enabled when
  `RATE_LIMIT_ENABLED=false`. Missing/oversized verification headers reject
  with 401; the header bound is 4 KiB. The raw body bound is 64 KiB (413 when
  exceeded), with compression disabled (400); business logic never runs on
  parser failure.
- A separate process-lifetime pool permits at most 32 retained verification
  callers. Each caller acquires before key lookup, including a same-`kid`
  single-flight join or cache-hit signature verification. Full capacity rejects
  promptly with 503 / `Retry-After: 30`, without a queue, additional key waiter,
  provider call, or readiness mutation. Malformed/old JWTs and mismatched claimed
  body hashes reject before acquisition. The permit releases exactly once in
  verification's `finally`, not on HTTP close. A disconnected caller can thus
  still occupy a permit while awaiting a shared key fetch; freeing its open
  HTTP slot does not free its verification work. Already-started verification
  continues, and a valid signed event may still complete the unchanged
  idempotent readiness handling after disconnect. Invalid events never do.
  This lease bounds verification, not subsequent authenticated storage work.
- A single verifier lives for the process lifetime. Its exact, case-sensitive
  provider `kid` cache holds at most 16 validated ES256/P-256 public keys, with
  LRU eviction and a five-minute monotonic TTL. Known provider `expired_at`
  expires the key sooner. Expired entries are pruned on lookup and cannot be
  used; malformed/mismatched/expired responses are never cached. This TTL is
  Caldera's revalidation policy, not a provider guarantee that expiration or
  revocation cannot change during it. A new `kid` fetches its own key without
  restart; cached keys never waive signature, five-minute JWT age, or
  constant-time raw-body hash checks. JWT/JWK handling uses pinned `jose`.
- Concurrent same-`kid` misses share one fetch. At most two distinct key
  fetches may be outstanding; there is no queue of additional IDs. The real
  SDK request has a three-second timeout and cancellation deadline, a 16 KiB
  response bound, no redirects, and no internal retry. Timeout/network failure
  or saturation returns 503 with `Retry-After: 30`, not authenticated success.
  All waiters fail closed. A transport that ignores abort retains its slot
  until it actually settles; late results never cache. This favors bounded
  resource use over availability if the transport is broken.
- The four separate bounds are 32 open HTTP requests, 32 retained verification
  callers, two outstanding provider key fetches, and 16 cached public keys.
  None substitutes for another; same-key coalescing bounds provider calls but
  does not by itself bound retained callers.
- This is not an edge/DDoS guarantee. All these limits are per process and
  reset on restart; scaling multiplies aggregate limits, and a fixed window
  can allow a boundary burst. An attacker can exhaust the shared budget and
  temporarily delay legitimate deliveries. There is deliberately no
  attacker-address map or source-IP allowlist: Render proxy settings and
  `X-Forwarded-For` are not signature evidence. Transport/edge connection and
  slow-body limits remain separate hosting responsibilities; their live
  settings are unverified. Never raise these bounds or weaken verification
  merely to hide delivery failures.

Plaid documents exact-key lookup, expiration-aware caching, signature/age/hash
verification in [webhook verification](https://plaid.com/docs/api/webhooks/webhook-verification/).
Its [retry policy](https://plaid.com/docs/api/webhooks/) retries failures and
honors `Retry-After` on 429. Rate-limited or unavailable verification must remain
retryable; a 204 still does not by itself prove that a completion was applied.
Inspect HTTP outcomes and Plaid delivery logs without logging JWTs, raw bodies,
keys, or tokens. F13 uses intercepted signed fixtures only; it does not rerun
or replace the earlier accepted real-Sandbox delivery evidence.

## Schema and rollout order

1. Confirm the target backend environment and store driver. Do not copy local
   `.env` values to Render. Deployed startup now requires explicit
   `AUTH_MODE=required`, `TOKEN_STORE_DRIVER=postgres`, disabled development
   auth, and the prerequisites in [the backend startup safety contract](ENVIRONMENT_WORKFLOW.md#backend-startup-safety-contract).
   Verify the intended service's settings before authorizing rollout; this
   repository change does not establish its live configuration. With Postgres, backend startup
   calls `plaidItemStore.ensureSchema()` **before** `app.listen`. That method
   applies `migrations/001_create_plaid_item_store.sql` and then the additive
   `migrations/003_transaction_readiness.sql` (`historical_ready_at` and
   `historical_recovery_started_at`) and `004_item_lifecycle.sql`. There is no separate migration command
   for 003 in this repository. After token-store initialization, the separate
   auth-store initialization applies `002_create_auth_tables.sql` when that
   store is used; both complete before the listener starts. Startup fails
   rather than serving requests if a required migration fails. Confirm the
   deployed database role can perform the
   additive `ALTER TABLE` and normal backup/recovery procedures exist. With
   the JSON store, readiness fields are saved atomically in that store; SQL
   migration 003 does not apply. Do not turn on
   `MIGRATE_JSON_TOKEN_STORE_ON_START` without a separate migration decision.
2. Deploy the compatible backend **before** the iOS build. Supply the full
   environment-appropriate `PLAID_WEBHOOK_URL` and verify the public route is
   reachable. The repository Dockerfile uses `npm install --omit=dev` and
   `npm start`; no Render build configuration is tracked here, so confirm the
   hosting settings rather than assuming that Dockerfile is in use.
3. Only after backend startup and signed-delivery checks pass, roll out iOS.
   An older iOS build ignores additional response metadata. A newer iOS build
   against an older backend cannot obtain provider evidence and therefore
   suppresses automatic transaction suggestions while retaining readable
   cached data. This rollout does not change financial formulas.

## Sandbox or isolated-staging verification

1. Use Sandbox Plaid credentials, a non-production backend/store, and a
   public HTTPS webhook URL for that environment. Use a Sandbox Item that
   supports Transactions. Confirm `/item/get` reports the configured URL for
   a new Item. For an existing Item, make an authenticated
   `/api/transactions` request and confirm `/item/get` subsequently reports
   the updated URL. Do not treat the update acknowledgement as readiness.
2. Use Plaid's Sandbox-only `/sandbox/item/fire_webhook` with
   `webhook_code: "SYNC_UPDATES_AVAILABLE"` for that Item to verify signed
   delivery. Check Plaid Dashboard webhook logs and the backend HTTP result:
   a valid handled delivery returns 204; an invalid signature returns 401;
   a readiness-store failure returns 503. A 204 can also mean a valid event
   was not a completion event or not an active Item, so inspect readiness
   evidence separately. Do not assume a Sandbox-triggered event has
   `historical_update_complete: true`.
3. For missed-webhook recovery, use an already-initialized Sandbox test Item
   whose local readiness is unknown, without sending it through Link again.
   Intercepted-provider regressions cover a configured URL, an initial
   `INITIAL_UPDATE_COMPLETE` response, then a later
   `HISTORICAL_UPDATE_COMPLETE` response. In staging, verify the authenticated
   `/api/transactions` response for that owner and exact Item changes from
   `item_evidence[].historical_ready: false` to `true` only when Plaid's Sync
   status actually becomes complete. Verify the successful `/transactions/get`
   snapshot and provider update timestamp independently. Do not force a local
   readiness marker or infer completion from an empty snapshot.

Plaid's Sandbox webhook endpoint and signature procedure are documented at
<https://plaid.com/docs/api/sandbox/> and
<https://plaid.com/docs/api/webhooks/webhook-verification/>.

## Waiting states and diagnostics

- Missing `PLAID_WEBHOOK_URL`, an Item younger than the probe threshold,
  missing/invalid provider update time, failed `/item/get`,
  incomplete/unknown Sync status, or failed webhook delivery leaves automatic
  transaction evidence unavailable. Cached transaction history remains
  readable. On the next eligible authenticated request, an incomplete probe
  is retried after the interval; no background sweep runs.
- Check Plaid Dashboard webhook delivery logs, Item webhook URL and
  Transactions update status, backend 401/503 responses, and the
  owner-scoped `item_evidence` in a non-production transactions response.
  On Postgres, `historical_ready_at` and
  `historical_recovery_started_at` distinguish proof from an attempted probe.
  The app's Bank Sync surface reports waiting/stale evidence; it does not
  claim a recent local fetch proves provider freshness.
- If the provider never reports historical completion, Caldera remains
  fail-closed. Investigate Item health, Transactions consent/capability,
  webhook delivery, and Plaid status before proposing user action.

## Rollback

The additive 003 columns may remain after a backend rollback; do not drop
them or erase readiness data during an incident. Prefer rolling back to the
previous readiness-capable backend while keeping the signed webhook route
available. Rolling back to a backend without that route causes Plaid webhook
delivery failures and leaves newer iOS builds fail-closed for automation;
coordinate such a rollback and any webhook URL changes explicitly. Neither
rollback nor production configuration changes are authorized by this file.
