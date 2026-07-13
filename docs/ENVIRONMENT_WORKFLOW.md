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
