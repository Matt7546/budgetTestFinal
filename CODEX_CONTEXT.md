# Caldera Codex Context

## Project Roots

- Active project path: `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal`
- Do not edit: `/Users/matthewthomas/Documents/BudgetApp`

## Current Product Terms

Use these terms in user-facing UI:

- Available to Spend
- Set Aside
- Cash Cushion
- Savings Goals
- Upcoming Expenses
- Debt Payoff
- Timeline
- Bank Sync

Avoid these old/internal terms in user-facing UI:

- protected
- reserve
- bucket
- obligations
- planner
- safe to spend

Internal code may still use older names where refactoring would be risky.

## Compact Project Map

- Production Dashboard: `budgetTest/Views/Dashboard/NewDashboardView.swift`
- Modular Dashboard Lab: `budgetTest/Views/Lab/ModularDashboardLabView.swift`
- Savings/Set Aside overview: `budgetTest/Views/Goals/SavingsGoalsView.swift`
- Timeline: `budgetTest/Views/Planner/PlannerView.swift`
- Debt Payoff editor: `budgetTest/Views/Goals/DebtPayoffBucketEditorView.swift`
- Settings/More: `budgetTest/Views/Settings/SettingsView.swift`
- Tutorial: `budgetTest/Views/Shared/CalderaTutorialView.swift`
- Contextual help: `budgetTest/Views/Shared/ContextHelpButton.swift`
- Amount entry: `budgetTest/Views/Shared/AmountEntryField.swift`
- Plaid service: `budgetTest/Services/Plaid/PlaidService.swift`
- Backend: `plaid-backend/`

## Default Codex Workflow

- Small UI and bug fixes can use the current branch.
- Use branches/PRs only for risky Lab, backend, auth, Plaid, SwiftData, formula, or release-hardening work.
- Keep changes scoped. Avoid unrelated refactors.
- Build and report results.
- Suggest a commit message, but do not commit unless explicitly asked.

## Product Direction

- Product rules live in `docs/PRODUCT_RULES.md`.
- Check future feature and UI work against Caldera's north star: making Available to Spend simpler, clearer, and more useful.

## Standard Scope Guard

UI-only. Do not change formulas, SwiftData schemas, Plaid/backend/auth, signing, or unrelated screens.

## Lab Rule

DEBUG-only. Production Dashboard and Release/TestFlight UI must remain unchanged.
