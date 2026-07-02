# External TestFlight Readiness Audit

Date: 2026-07-02  
Project audited: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal`  
Scope: report-only audit for external TestFlight readiness. No app/backend behavior changes were made in this pass.

## A. Executive Summary

**Verdict: CONDITIONAL GO for trusted external TestFlight only. NO-GO for broad external testing.**

Caldera is much closer to external-readiness than the earlier internal build. The iOS app now has Sign in with Apple, Keychain session restore, signed-out bank-data gating, local financial data cleanup on explicit sign out, Delete Account, Disconnect All Banks, manual-only Plaid refresh, Release/Debug URL separation, and Release builds that hide the Debug Lab tab. The backend has user-scoped Plaid routes, Postgres-backed encrypted Plaid Item storage, hashed opaque sessions, Apple identity-token verification, account deletion, and disconnect hardening.

The main remaining risk is not a compile failure; it is release safety and operational verification. Before inviting any real external testers, verify live Render environment values and the App Store Connect review path. A single misconfigured backend env, especially `AUTH_MODE` falling back to `personal`, would be a P0 user-data isolation problem.

Recommended path: **trusted external testers only**, after completing the P0 verification checklist below. Do not open broad external testing until local data scoping, rate limiting, legal terms, and App Review reviewer access are hardened.

Validation actually run:

- Backend `node --check index.js`: passed.
- Backend `npm run test:user-scope`: passed.
- Backend `npm run test:crypto`: passed.
- Backend `npm run test:auth`: passed.
- Backend `npm run test:delete-account`: passed.
- Backend `npm run test:postgres-store`: skipped locally because `DATABASE_URL` and `TOKEN_ENCRYPTION_KEY` were unavailable.
- Xcode project list: passed with scheme `budgetTest`.
- iOS Debug generic device build: passed.
- iOS Release generic device build: passed.
- iOS Release archive: passed.

Needs manual verification:

- Live Render `/api/health` with production env.
- Actual TestFlight upload/export signing. The local archive succeeded, but the CLI archive log used an Apple Development signing identity/profile.
- Sign in with Apple on the uploaded TestFlight binary.
- Real Plaid Production Link, OAuth return, account refresh, transactions, disconnect, and delete account against Render.
- Privacy/support URLs content accuracy.

## B. P0 Blockers

### P0-1: Verify Render is truly in authenticated, encrypted, production mode before external testers

The backend code still defaults to personal compatibility mode when `AUTH_MODE` is unset. This is intentional for development/backward compatibility, but unsafe for external testers if Render is misconfigured.

Required live Render health result before inviting external testers:

```json
{
  "plaid_env": "production",
  "storage_driver": "postgres",
  "auth_mode": "required",
  "redirect_uri_configured": true
}
```

Also verify Render env includes:

- `AUTH_MODE=required`
- `TOKEN_STORE_DRIVER=postgres`
- `DATABASE_URL` configured
- `TOKEN_ENCRYPTION_KEY` configured and valid
- `APPLE_CLIENT_ID=com.matthewthomas.caldera`
- `APP_API_KEY` configured
- Plaid Production `PLAID_CLIENT_ID` / `PLAID_SECRET`

Evidence:

- `AUTH_MODE` defaults to `personal`: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/plaid-backend/authConfig.js:3`
- Plaid protected routes use `resolvePlaidAuth`: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/plaid-backend/index.js:316`, `:352`, `:396`, `:504`, `:564`
- Required mode rejects missing bearer tokens: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/plaid-backend/authMiddleware.js:74`
- Health reports `plaid_env`, `storage_driver`, and `auth_mode`: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/plaid-backend/index.js:199`

### P0-2: Verify App Store Connect/TestFlight review can complete Sign in with Apple and Plaid flow

External TestFlight builds may be reviewed. The app requires Sign in with Apple before bank sync, and Plaid Production linking needs real institution credentials or a documented reviewer path. If Apple review cannot sign in and reach a non-broken state, external testing can be delayed/rejected.

Required before external submission:

- App Review/TestFlight notes must explain that bank linking uses Plaid Production.
- Provide a reviewer-safe path if no real bank credentials are available: sign in with Apple, skip bank linking, use local planning features, and explain bank-data screens show sign-in/connect prompts.
- Verify Sign in with Apple entitlement and backend `APPLE_CLIENT_ID` match the bundle ID.

Evidence:

- iOS Sign in with Apple entitlement exists: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/budgetTest/Caldera.entitlements:5`
- Bundle ID is `com.matthewthomas.caldera`: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/budgetTest.xcodeproj/project.pbxproj:383`
- Backend verifies Apple `aud` against `APPLE_CLIENT_ID`: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/plaid-backend/appleTokenVerifier.js:110`
- Bank features are gated signed out: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/budgetTest/App/AppConfig.swift:43`

## C. P1 Should-Fix Before External Testers

### P1-1: Current deployment target is iOS 26.1

The app builds and archives with `MinimumOSVersion = 26.1`. That may be intentional in this 2026 toolchain, but it will exclude any tester not on iOS 26.1 or newer. For external TestFlight, explicitly decide whether this is acceptable.

Evidence:

- Deployment target set to `26.1`: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/budgetTest.xcodeproj/project.pbxproj:347`
- Release app `Info.plist` produced `MinimumOSVersion = 26.1` during validation.

Recommendation: if the intended tester base includes older iPhones/iOS versions, lower the deployment target only after checking APIs used by the redesigned app.

### P1-2: Release from a clean, reviewed commit

The current worktree is dirty with many modified files, including finance-sensitive areas. A dirty working tree is risky for external releases because the uploaded binary may not correspond to a stable commit or reviewed diff.

Observed modified files include:

- `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/budgetTest/Models/Planner/PlannerForecastCalculator.swift`
- `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/budgetTest/Services/Plaid/PlaidService.swift`
- `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/budgetTest/Views/Goals/SavingsGoalsView.swift`
- `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/budgetTest/Views/Planner/PlannerForecast.swift`
- `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/budgetTest/Views/Settings/SettingsView.swift`

Recommendation: review the full diff, run tests/builds from the final state, then tag or commit the exact external candidate.

### P1-3: App-level `APP_API_KEY` is bundled in the app and must be treated as public

The Release app bundle includes an `APP_API_KEY` value in `Info.plist`. That is normal if the key is used as a lightweight app gate, but it is not secret once shipped. Security must rely on Bearer session auth, Plaid tokens staying backend-only, and per-user authorization.

Evidence:

- `Info.plist` injects `$(APP_API_KEY)`: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/budgetTest/Info.plist:5`
- App attaches `x-app-api-key` and Bearer token separately: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/budgetTest/App/AppConfig.swift:98`
- Backend treats API key as a route gate: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/plaid-backend/index.js:101`

Recommendation: do not document or reason about `APP_API_KEY` as a secret. Keep `AUTH_MODE=required` and monitor backend abuse.

### P1-4: Backend has permissive CORS and no obvious rate limiting

`app.use(cors())` allows broad browser origins. Because mobile API requests are gated by API key plus Bearer auth in required mode, this is not automatically a P0, but public/external exposure should be tightened.

Evidence:

- Open CORS middleware: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/plaid-backend/index.js:29`
- No rate-limit middleware found in backend dependencies or `index.js`.

Recommendation: before broad external/public launch, add rate limits to auth and Plaid routes, restrict CORS to known origins if browser clients are expected, and keep native app flows unaffected.

### P1-5: Local SwiftData records are device-global; privacy depends on explicit cleanup

The current v1 strategy clears local financial data on explicit Sign Out and Delete Account. That is acceptable for a trusted external pilot, but not enough for broad multi-user/shared-device support.

Evidence:

- SwiftData models do not include owner/user fields: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/budgetTest/Models/Goals/SavingsGoalPersistence.swift:4`, `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/budgetTest/Models/Planner/PlannerEvent.swift:14`, `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/budgetTest/Models/Planner/EventAllocation.swift:4`, `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/budgetTest/Models/Goals/DebtPayoffBucket.swift:43`
- Sign out clears SwiftData financial models: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/budgetTest/Services/Plaid/PlaidService.swift:1410`
- Settings sign-out confirmation warns and calls cleanup: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/budgetTest/Views/Settings/SettingsView.swift:130`

Recommendation: for external trusted testers, keep the current cleanup strategy and document “do not share device accounts.” Before broad public launch, add owner scoping or a stronger account-switch strategy.

### P1-6: Terms are still a placeholder

The app has a Privacy Policy link and Support link, but Terms are shown as a placeholder. This may be acceptable for internal builds, but it weakens external review/public readiness.

Evidence:

- Privacy URL exists: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/budgetTest/Views/Settings/SettingsView.swift:32`
- Support URL exists: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/budgetTest/Views/Settings/SettingsView.swift:36`
- Terms placeholder: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/budgetTest/Views/Settings/SettingsView.swift:794`

Recommendation: add real Terms before broad external/public testing. For a small trusted external pilot, disclose that Terms are pending if you proceed.

### P1-7: Distribution export/upload signing still needs manual verification

Debug build, Release build, and archive succeeded. However, the CLI Release build/archive logs used an Apple Development identity/profile. Xcode Organizer may re-sign on upload/export, but this audit did not verify App Store Connect upload.

Evidence:

- Signing settings are automatic with Team `HT5R7T5J34`: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/budgetTest.xcodeproj/project.pbxproj:367`
- Release archive succeeded in validation.
- Archive log showed `Signing Identity: Apple Development`.

Recommendation: use Xcode Organizer to validate/distribute to App Store Connect, confirm distribution signing, and confirm the uploaded build appears in TestFlight processing.

## D. P2 Polish

1. Add a concise “not financial advice” sentence in About/Legal or onboarding. The app is positioned as planning, but external users may interpret it as financial guidance.
2. Improve TestFlight reviewer notes and screenshots after upload, especially the signed-out state, Linked Accounts, and Delete Account.
3. Add backend monitoring/alerts for repeated `401`, Plaid failures, and account deletion failures.
4. Add automated UI smoke tests for signed-out launch, Sign in with Apple mock state, Linked Accounts empty state, and More privacy/delete entry points.
5. Consider a per-institution disconnect flow later. Current wording correctly says Disconnect All Banks, but users may eventually expect individual institution management.
6. Consider a lower iOS target if product APIs allow it.
7. Replace Terms placeholder before wider external/public launch.

## E. Exact Evidence

### Backend auth and user isolation

- Auth mode supports `personal`, `optional`, and `required`, defaulting to `personal`: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/plaid-backend/authConfig.js:1`
- Request user ID never comes from client body/query; required mode requires `req.user.id`: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/plaid-backend/authMiddleware.js:20`
- Bearer token extraction and session lookup happen in middleware: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/plaid-backend/authMiddleware.js:36`
- Plaid Link token uses scoped `client_user_id`: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/plaid-backend/index.js:316`
- Public token exchange saves by resolved user ID: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/plaid-backend/index.js:367`
- Accounts and transactions fetch only `getUserItems(userId)`: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/plaid-backend/index.js:504`, `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/plaid-backend/index.js:564`

### Backend token/session storage

- Postgres token store requires DB URL and encryption key: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/plaid-backend/plaidItemStore.js:18`
- Access tokens use AES-256-GCM with 32-byte base64 key validation: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/plaid-backend/tokenCrypto.js:3`
- Postgres store decrypts tokens only when fetching user items for Plaid API calls: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/plaid-backend/postgresPlaidItemStore.js:43`
- Plaid item schema is user-scoped and unique by `(user_id, plaid_item_id)`: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/plaid-backend/migrations/001_create_plaid_item_store.sql:7`
- Session tokens are random opaque values and stored as SHA-256 hashes: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/plaid-backend/sessionCrypto.js:5`, `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/plaid-backend/sessionStore.js:92`
- Deleted users have `apple_sub`, email, and full name cleared: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/plaid-backend/sessionStore.js:198`

### Backend delete/disconnect

- Disconnect removes active Plaid Items for authenticated user only and returns counts: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/plaid-backend/index.js:395`
- Delete Account requires session auth and calls account lifecycle deletion: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/plaid-backend/index.js:437`
- Account lifecycle calls Plaid `itemRemove`, soft-disconnects items, revokes sessions, and soft-deletes user: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/plaid-backend/accountLifecycle.js:12`

### iOS auth, gating, and cleanup

- Release backend points to Render Production; Debug points to local sandbox: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/budgetTest/App/AppConfig.swift:12`
- Bank data requires authenticated session: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/budgetTest/App/AppConfig.swift:43`
- Backend requests attach both `x-app-api-key` and optional Bearer token: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/budgetTest/App/AppConfig.swift:98`
- AuthManager stores session in Keychain and restores with `/api/auth/me`: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/budgetTest/Services/Auth/AuthManager.swift:196`
- Keychain item uses `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/budgetTest/Services/Auth/KeychainSessionStore.swift:59`
- PlaidService hides bank data while signed out: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/budgetTest/Services/Plaid/PlaidService.swift:197`
- Protected bank route calls guard on missing session: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/budgetTest/Services/Plaid/PlaidService.swift:301`, `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/budgetTest/Services/Plaid/PlaidService.swift:662`
- `401 unauthorized` maps to auth-required state: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/budgetTest/Services/Plaid/PlaidService.swift:1097`
- Local financial cleanup deletes caches and SwiftData financial records: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/budgetTest/Services/Plaid/PlaidService.swift:1410`
- Sign out confirmation calls cleanup before sign out: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/budgetTest/Views/Settings/SettingsView.swift:130`
- Delete Account requires typed `DELETE`: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/budgetTest/Views/Settings/SettingsView.swift:805`

### iOS Release/debug separation and assets

- Bottom tabs are Dashboard, Savings, Timeline, More; Lab is DEBUG-only: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/budgetTest/ContentView.swift:72`
- Developer QA section is DEBUG-only: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/budgetTest/Views/Settings/SettingsView.swift:89`
- App icon asset set is configured in project: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/budgetTest.xcodeproj/project.pbxproj:362`
- AppIcon includes required iPhone/iPad/marketing images: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/budgetTest/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Sign in with Apple and associated domains entitlements exist: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/budgetTest/Caldera.entitlements:5`
- Associated domain is `applinks:plaid-backend-2wqb.onrender.com`: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/budgetTest/Caldera.entitlements:9`

### Secrets/source-control hygiene

- `Config/Secrets.xcconfig`, `.env`, token store, and `node_modules/` are ignored: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal/.gitignore:4`
- `git ls-files` showed only `Config/AppConfig.xcconfig` among secret/config names; local `Config/Secrets.xcconfig` and `plaid-backend/.env` are not tracked.
- Local `plaid-backend/.env` and `plaid-backend/node_modules` exist on disk; keep them untracked.

### Validation evidence

- Backend checks passed: `node --check index.js`, `npm run test:user-scope`, `npm run test:crypto`, `npm run test:auth`, `npm run test:delete-account`.
- `npm run test:postgres-store` skipped locally because DB env vars were absent.
- `xcodebuild -list -project budgetTest.xcodeproj` succeeded and found schemes `budgetTest` and `budgetTest 1`.
- Debug build succeeded with `xcodebuild -project budgetTest.xcodeproj -scheme budgetTest -configuration Debug -destination generic/platform=iOS`.
- Release build succeeded with `xcodebuild -project budgetTest.xcodeproj -scheme budgetTest -configuration Release -destination generic/platform=iOS`.
- Release archive succeeded with `xcodebuild -project budgetTest.xcodeproj -scheme budgetTest -configuration Release -destination generic/platform=iOS -archivePath /private/tmp/caldera-readiness.xcarchive archive`.
- Release binary scan did not find `PrototypeLab`, `Developer QA`, `Debug-only`, `Local Sandbox`, `PLAID_SECRET`, `TOKEN_ENCRYPTION_KEY`, `DATABASE_URL`, raw `access_token`, or raw `public_token`. It did find expected production strings such as the Render URL and API route names.

## F. Recommended Release Path

**Choose: trusted testers only.**

Do not go broad external yet. Invite a small group of trusted external testers after:

1. Live Render health confirms `auth_mode=required`, `storage_driver=postgres`, `plaid_env=production`.
2. A real TestFlight upload/export is completed through Xcode Organizer/App Store Connect.
3. Sign in with Apple and Plaid Production linking are manually verified from the uploaded TestFlight build.
4. Delete Account and Disconnect All Banks are manually verified against the production backend.
5. Testers are told this is an early external pilot and should not share devices/accounts.

Why not broad external:

- Local SwiftData records are not user-scoped yet.
- Rate limiting/CORS hardening is not done.
- Terms are a placeholder.
- The iOS 26.1 minimum target may exclude a meaningful tester slice.
- App Review/Plaid reviewer path still needs careful setup.

## G. External TestFlight Checklist

### Backend/Render

- [ ] Confirm `/api/health` returns `plaid_env=production`.
- [ ] Confirm `/api/health` returns `storage_driver=postgres`.
- [ ] Confirm `/api/health` returns `auth_mode=required`.
- [ ] Confirm `APPLE_CLIENT_ID=com.matthewthomas.caldera`.
- [ ] Confirm `TOKEN_ENCRYPTION_KEY` is present and rotated/stored safely.
- [ ] Confirm `DATABASE_URL` points to production Render Postgres.
- [ ] Confirm Plaid Production env vars are present.
- [ ] Confirm no `.env`, token store, or database dumps are committed.
- [ ] Confirm backend logs do not print Plaid tokens, Apple tokens, session tokens, DB URLs, or encryption keys.

### iOS build/upload

- [ ] Decide whether iOS minimum target `26.1` is intentional for external testers.
- [ ] Review/commit/tag the exact release candidate.
- [ ] Increment build number if uploading another TestFlight build.
- [ ] Archive in Xcode Organizer.
- [ ] Validate distribution signing/App Store Connect upload.
- [ ] Confirm uploaded binary has Sign in with Apple and associated domains entitlements.
- [ ] Confirm Release has no Lab tab and no Developer QA section.
- [ ] Confirm Release points to `https://plaid-backend-2wqb.onrender.com`.
- [ ] Confirm the bundled `APP_API_KEY` is expected and treated as public.

### Fresh install QA

- [ ] Fresh install opens onboarding.
- [ ] Onboarding does not show mock financial values.
- [ ] Enter app signed out.
- [ ] Dashboard shows signed-out bank-data prompt, not stale bank values.
- [ ] More shows Sign in with Apple.
- [ ] Sign in with Apple succeeds.
- [ ] Keychain session restores after force close/reopen.

### Plaid QA

- [ ] Signed out Plaid Link is disabled/gated.
- [ ] Signed in Linked Accounts opens Plaid Link.
- [ ] Link first institution; accounts appear.
- [ ] Link second institution; first accounts remain.
- [ ] Manual refresh updates account timestamp only on success.
- [ ] Transactions refresh if expected.
- [ ] Dashboard/Savings/Timeline values update after refresh.
- [ ] 401 expired session maps to sign-in-required state.

### Privacy/delete/disconnect QA

- [ ] Sign Out confirmation appears.
- [ ] Cancel Sign Out preserves local data.
- [ ] Confirm Sign Out clears local financial data and Keychain session.
- [ ] Delete Account requires typed `DELETE`.
- [ ] Cancel Delete Account does nothing.
- [ ] Successful Delete Account signs out and clears local data.
- [ ] Signing in again after delete creates a clean account.
- [ ] Disconnect All Banks wording is used.
- [ ] Disconnect All Banks clears cached bank data but leaves local planning data.

### Functional QA

- [ ] Dashboard Available to Spend positive state.
- [ ] Dashboard Available to Spend negative state.
- [ ] View Insights sheet opens and values do not change formulas.
- [ ] Savings Cash Cushion add/use works.
- [ ] Create/edit/delete Savings Goal works.
- [ ] Create/edit Upcoming Expense works.
- [ ] Timeline event rows and detail/set-aside flows work.
- [ ] Debt Payoff create/edit works for linked credit card and manual debt.
- [ ] Keyboard Done/dismiss works in numeric fields.
- [ ] Light and dark mode are readable.
- [ ] Small iPhone layout does not clip critical controls.

### App Store/TestFlight metadata

- [ ] Privacy Policy URL opens and accurately describes Plaid, Apple sign-in, local financial data, and deletion.
- [ ] Support URL opens and includes contact method.
- [ ] Terms placeholder accepted for trusted external pilot, or replaced before broader testing.
- [ ] TestFlight “What to Test” explains this is an early planning/bank-sync test.
- [ ] Reviewer notes include Sign in with Apple and Plaid instructions.

## H. Suggested App Review/TestFlight Notes

Suggested TestFlight review notes:

```text
Caldera is a personal finance planning app. Testers sign in with Apple, then may connect bank accounts through Plaid Production to view account balances and plan money set aside for a Cash Cushion, Goals, Upcoming Expenses, and Debt Payoff.

Bank connection is optional for review. If you do not have test bank credentials available, you can still open the app, complete onboarding, sign in with Apple, and view the signed-in empty states. Bank-related screens will prompt to connect accounts through Plaid.

The app supports:
- Sign in with Apple
- Plaid bank linking
- Manual Plaid data refresh from More > Linked Accounts
- Disconnect All Banks
- Delete Account
- Local planning features for Goals, Upcoming Expenses, Cash Cushion, and Debt Payoff

Delete Account disconnects bank connections on the backend, revokes sessions, and clears local financial data from the device. Sign Out clears local financial data from the device but does not delete the backend account.

This app is for personal budgeting and planning. It does not provide financial, investment, tax, or legal advice.
```

Suggested tester “What to Test”:

```text
Please test:
1. Fresh install and onboarding.
2. Sign in with Apple.
3. Connect one or more bank/card accounts with Plaid.
4. Manually refresh Plaid data from More > Linked Accounts.
5. Check Dashboard Available to Spend, Savings, Timeline, and More.
6. Create a Cash Cushion, Savings Goal, Upcoming Expense, and Debt Payoff item.
7. Try Sign Out, then sign back in.
8. Try Disconnect All Banks if you are comfortable reconnecting.
9. Report confusing wording, incorrect balances, layout issues, or any place stale bank data appears while signed out.
```

