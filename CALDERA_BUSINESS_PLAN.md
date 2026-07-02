# Caldera Business and Product Plan

Date: 2026-07-02  
Status: planning document for external TestFlight, launch readiness, product roadmap, and backend hardening.

## 1. Executive Summary

Caldera is a personal finance planning app focused on one core promise:

> Help people know what is truly available to spend after money is set aside for cushion, goals, upcoming expenses, and debt payoff.

The product is not trying to be a full budgeting spreadsheet, investment dashboard, or bank replacement. The wedge is clarity: one calm daily number, backed by a simple money story.

Current state:

- Internal TestFlight: functionally live and stable enough for personal/internal use.
- Trusted external TestFlight: close, but should wait for final live backend verification, App Store Connect upload verification, and a small legal/support polish pass.
- Broad external TestFlight: not ready yet.
- Public App Store launch: not ready yet.

Recommended next business move:

- Run a controlled trusted external TestFlight with a small group.
- Treat the test as a product-validation sprint, not a growth launch.
- Measure whether users understand and trust "Available to Spend."
- Harden backend operations and privacy controls before scaling.

## 2. Mission, Vision, and Positioning

### Mission

Make personal cash flow feel calm, understandable, and actionable.

### Vision

Caldera becomes the place where a person can open the app and instantly understand:

- What they can safely spend today.
- What money is already set aside.
- What obligations are coming.
- What progress they are making toward goals and debt payoff.

### Positioning

Caldera is a "protected money" planner.

It combines:

- Bank-connected cash visibility.
- Cash Cushion.
- Savings Goals.
- Upcoming Expenses.
- Debt Payoff planning.
- Timeline-based cash flow.

The language should remain plain:

- Available to Spend
- Set Aside
- Cash Cushion
- Goals
- Upcoming Expenses
- Debt Payoff
- Covered
- Needs X
- Short by X

Avoid public-facing language that sounds technical or scary:

- Allocation engine
- Forecast model
- Protected balance
- Bucket
- Safe to Spend
- Reserve

## 3. Business Goals and Objectives

### 0-30 Days: Trusted External TestFlight

Goal: validate the core money story with a small set of trusted testers.

Objectives:

- Ship one external TestFlight build to trusted testers only.
- Confirm Sign in with Apple, Plaid Production, account refresh, delete account, and disconnect all banks work outside the developer device.
- Validate that users understand "Available to Spend."
- Validate whether Dashboard, Savings, Timeline, More, and Linked Accounts feel coherent.
- Collect qualitative feedback on confusion, trust, and missing setup guidance.

Success criteria:

- 10-25 trusted testers invited.
- 70%+ can complete sign in and onboarding without help.
- 60%+ of users who are comfortable with Plaid can link at least one institution.
- 70%+ can explain what Available to Spend means after using the app.
- No P0 privacy/security incidents.
- No cross-user bank data leakage.
- Delete Account and Disconnect All Banks work in production.

### 30-90 Days: External Beta Polish

Goal: make the product understandable, safe, and reliable enough for a larger beta.

Objectives:

- Finish Terms and privacy language.
- Add backend rate limiting and operational monitoring.
- Improve Plaid error handling and refresh transparency.
- Decide local data strategy: clear-on-sign-out only vs owner-scoped local data.
- Polish first-run setup, insights, debt payoff, and amount entry flows.
- Add analytics or privacy-safe event tracking for onboarding and setup completion.

Success criteria:

- 50-150 external testers.
- Fewer than 10% of testers get stuck before seeing the Dashboard.
- Support issues are mostly product clarity, not auth/Plaid breakage.
- Backend has health monitoring and failure alerts.
- No stale bank data visible while signed out.

### 3-6 Months: Launch Candidate

Goal: turn Caldera from a promising beta into a public-ready app.

Objectives:

- Complete local data scoping or backend-synced user data model.
- Add Plaid webhooks or a more robust refresh strategy.
- Add per-institution disconnect.
- Add public-ready privacy, Terms, support, and account deletion documentation.
- Build a stable release process with versioning, release notes, and rollback runbooks.
- Decide pricing and packaging.

Success criteria:

- Broad external beta is safe.
- App Store review path is clear.
- Retention and user trust metrics justify public launch.
- Backend can support many users without shared-state risks.

### 6-12 Months: Public Launch and Monetization

Goal: launch publicly with a focused, paid or freemium product.

Objectives:

- Introduce paid plan if user value is validated.
- Add household/collaborative planning only if requested strongly.
- Add deeper debt payoff plans.
- Add transaction-aware insights only after core cash-flow trust is strong.
- Build support and incident-response process.

Success criteria:

- Public App Store launch.
- Clear conversion path.
- Stable Plaid/backend operations.
- Low churn from confusion.
- Users repeatedly open Caldera before spending decisions.

## 4. How Close We Are

| Area | Current readiness | Notes |
| --- | ---: | --- |
| Internal TestFlight | 90% | Live and stable enough for personal/internal use. |
| Trusted external TestFlight | 75% | Close after Render/App Store Connect verification and legal/support polish. |
| Broad external TestFlight | 55% | Blocked by local data scoping, ops hardening, Terms, rate limiting, and reviewer path. |
| Public App Store launch | 40% | Needs compliance, backend operations, support process, and stronger multi-user local data handling. |
| Core product concept | 75% | Available to Spend, Set Aside, Cash Cushion, Goals, Upcoming Expenses, Debt Payoff are coherent. |
| Backend user isolation | 80% | Strong route/session/token design; must verify production env and add operational hardening. |
| Plaid reliability | 65% | Multi-item and manual refresh exist; needs webhooks, item health, better errors, and retry strategy. |
| Legal/compliance readiness | 35% | Privacy link exists; Terms and financial-advice disclaimer need work. |
| Monetization readiness | 20% | Value prop is forming, but pricing and packaging are not validated yet. |

## 5. Target Users

### Primary Persona: Cash-Flow Anxious Planner

Traits:

- Has income and bills but does not trust their bank balance.
- Wants to avoid accidental overspending.
- May use checking, savings, and credit cards.
- Wants clarity without maintaining a complex spreadsheet.

Primary need:

- "Tell me what I can spend without messing up upcoming bills or goals."

### Secondary Persona: Goal-Oriented Saver

Traits:

- Wants to save for trips, emergency fund, car, home, or other goals.
- Needs motivation and clear progress.
- Wants goals to reduce spendable cash mentally.

Primary need:

- "Show me what is already spoken for."

### Secondary Persona: Debt Payoff Planner

Traits:

- Has credit card debt, auto loans, student loans, mortgage, or personal loans.
- Wants to set aside payment money before it leaves the account.
- Needs to separate "payment planned" from "debt paid."

Primary need:

- "Help me plan debt payments without pretending the balance is already lower."

## 6. Product Pillars

### Pillar 1: Available to Spend

The top-level number users should trust.

It must be:

- Clear.
- Explainable.
- Stable.
- Easy to verify.

### Pillar 2: Money Set Aside

The reason Available to Spend is not just the bank balance.

Components:

- Cash Cushion.
- Goals.
- Upcoming Expenses.
- Debt Payoff.

### Pillar 3: Timeline

Shows how money changes as upcoming events happen.

It should answer:

- What is coming next?
- Is it covered?
- What happens after this expense?

### Pillar 4: Trust and Control

Users must know:

- When bank data last refreshed.
- How to disconnect banks.
- How to delete their account.
- What is local vs synced.
- That banking credentials are not stored in the app.

## 7. Likely Objections and Responses

### Objection: "Why not just use my bank app?"

Response:

Bank apps show balance. Caldera shows what is actually available after set-asides and upcoming obligations.

Product answer:

- Keep Available to Spend as the hero.
- Keep View Insights.
- Make "what shaped this number" easy to understand.

### Objection: "I already use Monarch, Copilot, YNAB, or Rocket Money."

Response:

Caldera is not trying to replace every budgeting workflow at launch. It is focused on protected money and daily spendability.

Product answer:

- Stay narrow.
- Do not chase every personal finance feature.
- Win with clarity, calm UI, and set-aside logic.

### Objection: "I do not trust giving a new app bank access."

Response:

Caldera uses Plaid for bank linking, keeps Plaid tokens on the backend, supports Disconnect All Banks, and supports Delete Account.

Product answer:

- Make privacy language visible.
- Show "Powered by Plaid."
- Show last synced timestamps.
- Make disconnect/delete easy to find.

### Objection: "Is this financial advice?"

Response:

No. Caldera is a planning and organization tool. It does not provide financial, investment, tax, or legal advice.

Product answer:

- Add a plain disclaimer in Legal/About and App Review notes.
- Avoid prescriptive claims like "you should pay this first" until advice/compliance is considered.

### Objection: "The number is negative. Did something break?"

Response:

Negative Available to Spend means set-asides and upcoming obligations exceed current available cash.

Product answer:

- Keep negative copy calm.
- Use "Short by X" instead of scary language.
- Keep View Insights clear.

### Objection: "Why does bank data update manually?"

Response:

Manual refresh reduces surprise, server cost, Plaid load, and device heat during early testing.

Product answer:

- Show last updated timestamp.
- Explain manual refresh during TestFlight.
- Add better refresh automation later with Plaid webhooks.

### Objection: "Debt Payoff looks like it lowers my debt."

Response:

Debt Payoff is money set aside for a future payment. It does not reduce the debt balance until a real payment/transaction happens.

Product answer:

- Keep wording: "set aside" and "payment planned."
- Never subtract set-aside funds from debt balance.
- Add explicit copy on debt cards and edit screens.

## 8. Feature Roadmap

### v0.9: External TestFlight Candidate

Focus: trust, clarity, and setup completion.

Planned/active features:

- Redesigned onboarding.
- Dashboard View Insights.
- Setup checklist.
- Linked Accounts last synced timestamp.
- Manual Plaid refresh.
- Delete Account.
- Disconnect All Banks.
- Debt Payoff v2 foundations.
- Unified editor modal pattern.
- Semantic icons/colors.

Should finish before trusted external testers:

- Verify Render production auth/storage env.
- Verify TestFlight upload and Sign in with Apple.
- Verify Plaid Production linking from TestFlight.
- Add real Terms or clearly limit to trusted pilot.
- Add "not financial advice" language.

### v1.0: Public-Ready Core

Focus: make the core app safe and explainable for strangers.

Feature priorities:

- Owner-scoped local data or stronger local account-switch strategy.
- Better empty states and setup completion.
- More robust Plaid error handling.
- Per-institution disconnect.
- Plaid webhooks for item health and updates.
- Basic analytics/telemetry for setup funnel and refresh failures.
- Support and legal polish.

### v1.1: Debt Payoff Expansion

Focus: make debt payoff useful without overpromising.

Features:

- Debt type selection:
  - Linked credit card.
  - Auto loan.
  - Mortgage.
  - Student loan.
  - Personal loan.
  - Other debt.
- Credit card path:
  - Use Plaid-linked current balance when available.
  - Allow set-aside up to current balance/payment target.
- Manual loan paths:
  - Starting balance.
  - Start date.
  - End date.
  - Monthly payment.
  - Optional interest rate.
  - Progress toward loan completion.
- Clear "planned payment" language.

### v1.2: Smarter Timeline and Set-Aside Planning

Features:

- Better recurring expense editing.
- Per-event set-aside recommendations.
- Calendar-style upcoming view.
- Optional pay-date/income cadence.
- Better partial coverage states.
- Improved "After this expense" explanations.

### v2.0: Multi-Device and Collaboration

Only after the single-user product is trusted.

Features:

- Backend-synced user-created planning data.
- Multi-device restore.
- Household/shared planning.
- Export/delete user data tooling.
- More granular privacy controls.

## 9. Critical Backend Changes

### Backend P0 Before Trusted External TestFlight

1. Verify Render environment.

Required:

- `AUTH_MODE=required`
- `TOKEN_STORE_DRIVER=postgres`
- `PLAID_ENV=production`
- `APPLE_CLIENT_ID=com.matthewthomas.caldera`
- `DATABASE_URL` present
- `TOKEN_ENCRYPTION_KEY` present
- `APP_API_KEY` present

2. Verify live health route.

Expected:

- `plaid_env=production`
- `storage_driver=postgres`
- `auth_mode=required`
- `redirect_uri_configured=true`

3. Verify Delete Account in production.

Must confirm:

- Removes only current user's Plaid Items.
- Revokes all current user's sessions.
- Soft-deletes/anonymizes only current user.
- Allows future re-sign-up with Apple.

4. Verify Disconnect All Banks in production.

Must confirm:

- Removes all active Plaid Items for current user.
- Does not affect another user.
- Returns removed/failed counts.
- iOS clears account cache on success.

### Backend P1 Before Broad External TestFlight

1. Rate limiting.

Add limits to:

- `/api/auth/apple`
- `/api/auth/me`
- `/api/create_link_token`
- `/api/exchange_public_token`
- `/api/accounts`
- `/api/transactions`
- `/api/disconnect`
- `DELETE /api/account`

2. Observability.

Add safe metrics/logging:

- Auth success/failure count.
- Plaid link token creation failures.
- Public token exchange failures.
- Account refresh failures by error code.
- Transaction refresh failures by error code.
- Delete account failures.
- Disconnect partial failures.

Never log:

- Access tokens.
- Public tokens.
- Apple identity tokens.
- Session tokens.
- Authorization headers.
- Database URL.
- Encryption key.
- Raw transaction names/amounts in backend logs.

3. Plaid webhooks.

Add webhook support for:

- Item errors.
- Transactions updates.
- Institution/login repair states.

This will eventually allow safer background refresh without relying only on manual pulls.

4. Per-institution disconnect.

Current backend disconnect is intentionally "all banks." Add per-item disconnect before users have multiple institutions at scale.

5. Database backup and migration plan.

Render Postgres needs:

- Backup policy.
- Restore drill.
- Migration runbook.
- Env var rotation runbook.

6. CORS tightening.

Current backend uses permissive CORS. For native app-only traffic, this is not the core security layer, but broad external/public launch should tighten it.

7. API versioning.

Before adding more clients or changing response shapes:

- Add `/api/v1/...` or explicit compatibility rules.
- Keep old endpoints stable during TestFlight.

### Backend P2 Before Public Launch

1. Backend-synced planning data.

Decide whether to move user-created data from device-only SwiftData into backend tables:

- Goals.
- Cash Cushion.
- Upcoming Expenses.
- Event set-asides.
- Debt Payoff.
- Settings.

This enables multi-device and safer account switching.

2. Transaction cache.

Cache minimal Plaid transaction/account data if needed for performance and webhook sync.

Must design carefully:

- User-scoped.
- Encrypted or minimized.
- Delete-account compliant.
- No raw sensitive logs.

3. Billing and entitlement backend.

If monetizing:

- App Store subscriptions.
- User entitlement table.
- Receipt validation or StoreKit 2 server-side strategy.

4. Admin support tooling.

Build limited internal tools for:

- Viewing user status without sensitive financial data.
- Resending account repair guidance.
- Confirming delete/disconnect state.
- Debugging auth/session failures safely.

## 10. Product Metrics

### Activation Metrics

- Completed onboarding.
- Signed in with Apple.
- Connected at least one bank.
- Created Cash Cushion.
- Created first goal.
- Added first upcoming expense.
- Added first debt payoff item.
- Opened View Insights.

### Trust Metrics

- User can explain Available to Spend.
- User believes the number is accurate.
- User understands Set Aside.
- User knows how to refresh bank data.
- User knows how to disconnect/delete.

### Retention Metrics

- Day 1 return.
- Day 7 return.
- Weekly manual refresh.
- Weekly Timeline check.
- Goals/debt update frequency.

### Reliability Metrics

- Auth failures.
- Plaid link failures.
- Account refresh failures.
- Transaction refresh failures.
- Delete account failures.
- Disconnect partial failures.

## 11. Monetization Hypotheses

Do not monetize before trust is validated.

Possible pricing:

- Free external beta.
- Later: monthly subscription around a small personal-finance utility price point.
- Possible annual discount.
- Consider free mode for manual planning, paid mode for bank sync, only after user feedback.

Value users might pay for:

- Always-current Available to Spend.
- Timeline clarity.
- Protected/set-aside planning.
- Debt payoff planning.
- Multi-device sync.
- Better recurring bills and account health monitoring.

Risks:

- Users may expect full budgeting/category tracking if asked to pay too soon.
- Plaid-connected finance apps need high trust before conversion.
- Support burden rises quickly with bank connection issues.

## 12. Recommended Next 10 Tasks

1. Verify Render health and env values for required auth/Postgres/Plaid Production.
2. Upload a TestFlight candidate from Xcode Organizer and verify distribution signing.
3. Run a fresh-install TestFlight QA with real Sign in with Apple and Plaid Production.
4. Add a simple "not financial advice" statement in Legal/About.
5. Replace or finalize Terms placeholder for external testers.
6. Decide whether iOS `26.1` deployment target is intentional.
7. Add backend rate limiting for auth and Plaid routes.
8. Add backend safe operational metrics/log alerts.
9. Design local data owner scoping vs backend sync migration.
10. Run trusted external TestFlight with a small group and collect structured feedback.

## 13. Open Decisions

### Product

- Is the first public product "Available to Spend" or "Protection Center"?
- Should Debt Payoff be positioned as part of Savings or as its own future pillar?
- Should Timeline be mostly bills or broader cash-flow planning?
- How much manual data entry is acceptable before bank-connected automation improves?

### Business

- Free beta length.
- Subscription vs one-time purchase vs freemium.
- Ideal launch audience.
- Support channel and response expectations.

### Backend

- Keep planning data local longer, or migrate to backend sooner?
- Add Plaid webhooks before or after broad external beta?
- Add per-institution disconnect before broad external beta?
- What monitoring stack should be used for Render?

## 14. Current Bottom Line

Caldera has a strong product direction and a working technical foundation. The strongest business thesis is:

> People do not need another bank balance. They need to know what money is actually free after life has already made claims on it.

The app is close enough for a careful trusted external TestFlight, but not ready for broad external or public launch until backend operations, legal language, local data scoping, and review/upload readiness are hardened.

