# Caldera Agent Guide

The only active repository is:
`/Users/matthewthomas/Desktop/CalderaBetaApp`.

Never edit these obsolete project locations:

- `/Users/matthewthomas/Desktop/PolishedBudgetTest/budgetTestFinal`
- `/Users/matthewthomas/Desktop/budgetApp`
- `/Users/matthewthomas/Documents/BudgetApp`
- `/Users/matthewthomas/Desktop/Xcode Projects/budgetTestFinal`

Caldera virtually delegates funds before spending while keeping **Available to
Spend** clear. It does not move, hold, or pay money.

Use approved product terms: Available to Spend, Set Aside, Cash Cushion,
Savings Goals, Upcoming Expenses, Payment Plans, Plan Ahead, and Review Updates.
Read [docs/PRODUCT_RULES.md](docs/PRODUCT_RULES.md) before product work and
[docs/GIT_WORKFLOW.md](docs/GIT_WORKFLOW.md) before Git or branch work. Before
changing backend targets or Plaid environments, read
[docs/ENVIRONMENT_WORKFLOW.md](docs/ENVIRONMENT_WORKFLOW.md) and
[docs/PLAID_ENVIRONMENT_WORKFLOW.md](docs/PLAID_ENVIRONMENT_WORKFLOW.md).

Inspect the existing implementation before editing. Treat financial formulas,
SwiftData schemas, Plaid, authentication, multi-user scoping, backend storage,
rate limiting, transactions, liabilities, signing, and release settings as
high risk. Use the repository's existing validation and build scripts.

Do not commit, push, merge, deploy, or change environments without explicit
permission. Final reports must include a summary, files changed, behavior
changed, checks run, warnings, uncertainties, and a suggested commit message.
