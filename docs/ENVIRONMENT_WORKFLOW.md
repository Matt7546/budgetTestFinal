# Caldera Environment Workflow

This is the sole source of truth for selecting Caldera development and release
environments. Plaid-specific capability and testing guidance lives in
[PLAID_ENVIRONMENT_WORKFLOW.md](PLAID_ENVIRONMENT_WORKFLOW.md).

Start every task with:

```sh
./scripts/task-start.sh
```

It runs repository preflight and environment status checks. For routine task
completion, use `./scripts/task-finish.sh`. For production-facing, release,
backend, Plaid, authentication, signing, or environment work, use
`./scripts/task-finish.sh --release`.

## Scheme Presets

- `Caldera Debug Local`: Debug build for the local backend, Plaid Sandbox,
  local development authentication, and DEBUG-only QA tools. Lab is hidden.
- `Caldera Lab Local`: Debug build for branch-backed experiments and Lab
  prototypes. It uses the local backend and Plaid Sandbox. Never use it for
  TestFlight.
- `Caldera Release Candidate`: Release build for final local device QA and
  TestFlight archive preparation with Render, Plaid Production, and real Sign
  in with Apple.

The legacy `budgetTest` scheme remains a fallback. Prefer the named Caldera
schemes.

## Environment Matrix

| Environment | Backend | Plaid | Authentication | Use |
| --- | --- | --- | --- | --- |
| Debug Simulator | Local URL configured in `AppConfig` | Sandbox | Local development auth | Routine local iOS work |
| Debug physical device | Local URL configured in `AppConfig` | Sandbox | Local development auth | Device UI and Sandbox QA |
| Lab | Same local Debug backend | Sandbox | Local development auth | Branch-backed prototypes only |
| Release Candidate | Render URL configured in `AppConfig` | Production | Sign in with Apple | Final release smoke checks |
| TestFlight | Render | Production | Sign in with Apple | Internal or trusted external beta |
| Render backend | Public Render service | Production | App API key and real sessions | TestFlight backend |

`budgetTest/App/AppConfig.swift` contains the configured local and Release
backend URLs. A local address can change with the development network, so do
not copy a fixed local IP into workflow steps. `./scripts/env-status.sh`
reports the configured URLs and warns when the local backend host differs from
the Mac's current IP.

## Local Secrets and API Key

Debug and Release read `APP_API_KEY` through the Xcode build settings:

1. Create or update `Config/Secrets.xcconfig`.
2. Add the local value as `APP_API_KEY = ...`.
3. Keep `Config/Secrets.xcconfig` out of Git; it is intentionally ignored.

Never hardcode API keys, Plaid client IDs, Plaid secrets, session credentials,
or other secrets in Swift, JavaScript, Xcode project files, scripts, or
documentation. Do not print secret values during diagnostics.

Render environment variables are managed separately from local
`plaid-backend/.env`. Changing one does not change the other.

## Backend startup safety contract

`plaid-backend/startupPolicy.js` validates configuration after dotenv loading
and **before** Express app creation, Item/session-store creation, development
auth activation, or listening. Missing/unknown identity and invalid settings
exit nonzero; startup never silently falls back to personal auth, JSON storage,
or Sandbox. Lower-level compatibility helpers remain usable by local tooling,
but the HTTP server requires explicit `AUTH_MODE`, `TOKEN_STORE_DRIVER`, and
`PLAID_ENV` in every environment.

Deployed safety applies if **any** of these is present:

- `RENDER=true` or a nonempty `RENDER_SERVICE_ID` (Render's
  [documented platform signals](https://render.com/docs/environment-variables));
  a false/missing flag cannot weaken a present service identity.
- `NODE_ENV=production`.
- `PLAID_ENV=production`, even with a development NODE_ENV.

A deployed Sandbox/staging service has the same auth/storage safety contract
as production; Sandbox does not permit development-auth bypass on Render.
Required deployed configuration:

- `AUTH_MODE=required` and `TOKEN_STORE_DRIVER=postgres`.
- Explicit `PLAID_ENV=sandbox`, `development`, or `production` for the intended
  provider environment; production rollout uses `production`.
- Valid Postgres `DATABASE_URL` and the existing valid 32-byte base64
  `TOKEN_ENCRYPTION_KEY`. Do not rotate the key or use a new key for an existing
  encrypted store as part of rollout.
- `APP_API_KEY`, `PLAID_CLIENT_ID`, `PLAID_SECRET`, and `APPLE_CLIENT_ID`.
- `DEV_AUTH_ENABLED` absent/false; a requested true value rejects startup.

These checks establish configuration shape, not credential validity, database
provenance, or provider connectivity. Normal Postgres/auth migrations must then
succeed **before** listening. Startup database errors log safe configuration
names rather than raw driver errors/connection credentials. An unknown
NODE_ENV, malformed Render flag, or invalid Plaid/auth/store value rejects;
no raw supplied values are included in policy errors.
Production Plaid alone does not infer a hosting proxy: rate-limit proxy defaults
still use the hosting/NODE_ENV signals, not just the provider environment.

Local compatibility is recognized only with `NODE_ENV=development` or `test`,
non-production Plaid, and no deployed signal. Explicit personal/JSON remains
supported there; development auth may be explicitly enabled. Local optional
or required auth still requires `DATABASE_URL`, as before. Local Postgres
also requires its encryption key. `.env.example` is **local-only** and now
declares `NODE_ENV=development`; do not copy it to Render. Existing local
`.env` files need the explicit identity and modes before the next startup.

No live Render configuration was inspected or changed. Before an authorized
deployment, verify all required variables and DB migration permissions in the
intended service; do not deploy this change expecting compatibility fallbacks
to keep an incompletely configured service available. JSON-to-Postgres import
remains separately opt-in via `MIGRATE_JSON_TOKEN_STORE_ON_START=true`; this
policy does not turn it on or migrate an existing JSON store automatically.

## Run the Local Backend

From the repository root:

```sh
cd plaid-backend
npm install
npm start
```

Use `npm install` when dependencies are not already installed or the package
lock changed. For local Sandbox work, `plaid-backend/.env` should use Sandbox
credentials and `PLAID_ENV=sandbox`. Render should use Production credentials
and `PLAID_ENV=production` for Release and TestFlight.

The repository also provides:

```sh
./scripts/run-local-backend.sh
./scripts/check-local-backend.sh
./scripts/check-render-backend.sh
```

## Switching Environments

### Debug Local

Select `Caldera Debug Local`, verify with `./scripts/task-start.sh`, start
the local backend, and use Plaid Sandbox. DEBUG-only QA tools may appear; Lab
must remain hidden.

### Lab Local

Select `Caldera Lab Local` only on a branch created for an experiment. Verify
with `./scripts/build-lab.sh`. Lab code must stay gated by `CALDERA_LAB=1`
and must not appear in Debug Local, Release, or TestFlight.

### Release Candidate and TestFlight

Select `Caldera Release Candidate`. The app uses Render, Plaid Production,
and real Sign in with Apple; local development auth, Lab, and DEBUG-only tools
must be absent. Before production-facing work finishes, run:

```sh
./scripts/task-finish.sh --release
./scripts/check-render-backend.sh
```

Archiving, uploading, deploying, or changing Render still requires explicit
permission.

## Plaid Mode Changes

Plaid products and capability flags affect cost, consent, and product behavior.
Read [PLAID_ENVIRONMENT_WORKFLOW.md](PLAID_ENVIRONMENT_WORKFLOW.md) before
changing them.

Changing a local Plaid flag affects local Sandbox work only after restarting
the backend. Changing a Render Plaid flag affects Release and TestFlight.
Never copy local Sandbox credentials or local-development authentication
settings to Render.

Do not change Render Plaid mode casually. Accounts-only Link must be confirmed
against the active Plaid agreement and tested before enabling it in production.

## High-Risk Boundaries

Do not change these as part of routine environment work:

- Render variables or deployment settings.
- Plaid products, consent, or capability gates.
- `PlaidService`, backend routes, rate limiting, or token storage.
- Authentication, sessions, or local-auth production guards.
- SwiftData schemas or user scoping.
- Financial formulas or transaction automation.
- Signing, bundle identifiers, Release URLs, or Xcode release settings.
- Lab gating.

A push to GitHub `main` may deploy backend changes through Render. Follow
[GIT_WORKFLOW.md](GIT_WORKFLOW.md) and push intentionally.
