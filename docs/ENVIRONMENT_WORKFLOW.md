# Caldera Environment Workflow

This is the source of truth for how Caldera development environments fit together.

## Xcode Scheme Presets

Use these shared schemes in Xcode:

- `Caldera Debug Local`: Debug build. Use for local backend work, Plaid Sandbox, local dev auth, and DEBUG-only QA tools. Lab is hidden. Not for TestFlight.
- `Caldera Lab Local`: Debug build. Use only for branch-backed experiments and Lab prototypes. Uses local backend, Plaid Sandbox, and local dev auth. Not for TestFlight.
- `Caldera Release Candidate`: Release build. Use for final local device QA and TestFlight archive preparation with Render, Plaid Production, and real Sign in with Apple.

The existing `budgetTest` scheme remains as a fallback, but day-to-day work should prefer the named Caldera schemes.

## A. Environment Matrix

| Environment | Backend URL | Plaid environment | Auth method | Config lives in | When to use | What can go wrong | How to verify |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Debug Simulator | `http://10.0.0.244:3001` | Sandbox | Local dev auth | `budgetTest/App/AppConfig.swift`, `plaid-backend/.env` | Daily local iOS work | Local backend not running, wrong IP, missing `APP_API_KEY`, `DEV_AUTH_ENABLED=false` | `./scripts/env-status.sh`, `./scripts/check-local-backend.sh` |
| Debug physical device | `http://10.0.0.244:3001` | Sandbox | Local dev auth | `budgetTest/App/AppConfig.swift`, `plaid-backend/.env` | Real-device UI and Plaid Sandbox checks | Phone not on same network, Mac IP changed, stale backend | `./scripts/env-status.sh`, open Settings Environment in app |
| Release local device | `https://plaid-backend-2wqb.onrender.com` | Production | Sign in with Apple | `budgetTest/App/AppConfig.swift`, Render env vars | Final local release smoke checks | Production backend unavailable, real auth required | Build Release, confirm Settings has no Debug tools |
| Internal TestFlight | `https://plaid-backend-2wqb.onrender.com` | Production | Sign in with Apple | Release build, Render env vars | Internal beta | Render deploy drift, Plaid Production credentials, auth config | TestFlight app plus Render logs |
| Trusted external TestFlight | `https://plaid-backend-2wqb.onrender.com` | Production | Sign in with Apple | Release build, Render env vars | Outside testers | Same as Internal TestFlight, plus cost exposure | `./scripts/check-render-backend.sh` before upload |
| Render backend | Public Render service | Production | Required app API key and real sessions | Render dashboard env vars | TestFlight backend | Env var mistakes, accidental deploy from GitHub `main` | `./scripts/check-render-backend.sh` |
| Local backend | Debug URL in AppConfig | Sandbox | Local dev auth when enabled | `plaid-backend/.env` | Local development and Sandbox tests | `.env` missing keys, old node process, wrong port | `./scripts/run-local-backend.sh` |
| Lab | Same as Debug build | Sandbox in Debug | Same as Debug | `Caldera Lab Local` scheme with `CALDERA_LAB=1` | Prototype exploration only | Accidentally moving Lab ideas into normal Debug or production | Debug Local and Release builds must not show Lab |

## B. Switch To This Means This

### Switch to Debug

Means:

- Choose the `Caldera Debug Local` scheme in Xcode.
- The app uses the local backend URL from `budgetTest/App/AppConfig.swift`.
- The local backend must be running.
- The backend should use Plaid Sandbox.
- The app can use local dev auth.
- DEBUG-only QA tools can appear.
- Lab is hidden; use `Caldera Lab Local` for experiments.

Verify:

```sh
./scripts/env-status.sh
./scripts/check-local-backend.sh
```

### Switch to Lab

Means:

- Choose the `Caldera Lab Local` scheme in Xcode.
- The app uses the same local Debug backend and Plaid Sandbox expectations.
- Local dev auth remains available.
- The Lab tab and prototype-only tools are visible.
- Use this only on branch-backed experiments, not routine QA.

Verify:

```sh
./scripts/build-lab.sh
```

Rule:

Experimental ideas belong in branches and the Caldera Lab Local scheme, not in the normal Debug QA workflow.

### Switch to Release

Means:

- Choose the `Caldera Release Candidate` scheme in Xcode.
- The app uses the Render backend.
- The backend is expected to use Plaid Production.
- The app uses real Sign in with Apple.
- Lab and local dev auth are hidden.

Verify:

```sh
./scripts/build-release.sh
./scripts/check-render-backend.sh
```

### Switch to TestFlight

Means:

- Release behavior.
- Render backend.
- Plaid Production.
- Real Sign in with Apple.
- No Debug tools, Lab, or local dev auth.

### Switch Render `PLAID_TRANSACTIONS_ENABLED=false`

Means:

- Release and TestFlight backend behavior changes.
- New Link tokens may attempt Accounts-only mode.
- This should not be done until Plaid confirms Accounts-only Link is supported.
- Existing linked Items may need disconnect/relink testing.

Do not change this casually.

### Switch local `PLAID_TRANSACTIONS_ENABLED=false`

Means:

- Local Sandbox test only.
- Release and TestFlight are unaffected.
- Used to prove the app can run without transaction calls.

Use:

```sh
./scripts/set-local-plaid-mode.sh accounts-only
```

Then restart the local backend.

### Push to GitHub `main`

Means:

- Source of truth updates.
- Render may deploy if backend files changed.
- Backend changes should be pushed only after validation and intent.

### Use Lab

Means:

- Choose `Caldera Lab Local`.
- DEBUG-only experimentation.
- Branch-backed experiments only.
- Never production.
- Never TestFlight.

## C. Daily Development Workflow

### Small UI or copy fix

1. Current branch is okay.
2. Make the change.
3. Run `./scripts/validate.sh`.
4. Do a quick device check if needed.
5. Commit.
6. Push when stable.

### Risky backend, Plaid, or auth change

1. Create a branch.
2. Make the change.
3. Run local backend checks.
4. Run backend tests.
5. Run `./scripts/validate.sh`.
6. Commit.
7. Merge only if stable.
8. Push intentionally.

### Release candidate

1. Be on `main`.
2. Confirm clean git status.
3. Run `./scripts/validate.sh`.
4. Run a Release build.
5. Smoke QA on device.
6. Prepare release notes.
7. Archive and upload.

## D. What Not To Touch Casually

- Render env vars.
- Plaid products.
- `budgetTest/Services/Plaid/PlaidService.swift`.
- Auth, sessions, and token storage.
- SwiftData schemas.
- Financial calculators.
- Release backend URL.
- Local dev auth production guards.
- Lab gating.

