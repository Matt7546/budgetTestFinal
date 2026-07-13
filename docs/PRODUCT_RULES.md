# Caldera Product Rules

These are non-negotiable execution rules. Product strategy, audience,
priorities, and success signals live in
[PRODUCT_BRIEF.md](PRODUCT_BRIEF.md).

## Terminology

Approved user-facing terms:

- Available to Spend
- Set Aside
- Cash Cushion
- Savings Goals
- Upcoming Expenses
- Payment Plans
- Plan Ahead
- Review Updates
- Bank Sync

Do not use these as user-facing labels:

- protected
- reserve
- bucket
- obligations
- planner
- liability
- amortization
- safe to spend

The Product Brief may use “safe to spend” descriptively when explaining the
promise behind Available to Spend; it is never a product label. Internal model,
type, color, and file names do not establish user-facing terminology.

Use **Payment Plans**, not Debt Payoff. Use **Plan Ahead**, not Timeline or
Planner, in user-facing language.

## Page Purposes

- **Dashboard:** Can I spend money today without hurting future plans?
- **Set Aside:** What money have I intentionally kept out of spending?
- **Plan Ahead:** What is coming up, what is covered, and what still needs
  money?
- **Review Updates:** What detected or suggested changes need my decision?
- **More / Settings:** Manage Account & Bank Sync, linked accounts, planning
  settings, preferences, help, privacy, and account actions.

Bank Sync and account management belong in More / Settings. Do not describe a
separate production Accounts tab.

Keep one primary purpose and one primary action per screen when possible.

## Available to Spend Rules

- Available to Spend is Caldera's primary product output and must remain clear.
- It may use eligible linked cash balances only when the existing trust and
  user-scope rules permit them.
- Set Aside amounts reduce Available to Spend virtually; no money moves.
- Expected income must not increase today's Available to Spend before a real
  linked-account deposit arrives.
- Never change formulas, account eligibility, or confidence behavior as an
  incidental feature change.

## Set Aside Rules

- Set Aside is virtual planning inside Caldera.
- Money stays in the user's financial account.
- Caldera does not hold, transfer, or pay money.
- Cash Cushion, Savings Goals, Upcoming Expenses, and Payment Plans are
  distinct reasons to keep money out of everyday spending.
- Do not silently create, change, release, resolve, or delete Set Aside plans.

## Payment Plan Rules

- Payment Plans help users plan money for a card or other payment.
- They must not imply Caldera makes payments or changes real balances.
- Plaid-derived statement, minimum-payment, due-date, balance, or payment
  information is review context, not authority to overwrite a plan.
- Keep Payment Plans simple; defer full loan calculators and complex
  debt-management features.

## Plan Ahead Rules

Plan Ahead should answer:

- What is due soon?
- What is already Set Aside?
- What still needs money?
- What needs attention?

Prefer calm language such as **Covered**, **Still needs $X**, **$X set aside**,
and **Due [date]**. Avoid unexplained technical or alarming forecast language.

## Dashboard Rules

- Available to Spend stays visually dominant.
- Show one clear next step, not every possible action.
- Keep customization Lab-only until the core experience is proven.
- Do not turn Dashboard into a configurable control center or add clutter that
  belongs in Plan Ahead, Review Updates, or Settings.

## Design Rules

- Calm, spacious, understandable, and premium.
- Prefer plain language and focused decisions over exhaustive information.
- Fewer strong cards are better than many weak cards.
- Use square tiles for simple numbers and wide cards for context or action.
- Empty space is acceptable when the page is clear.
- Review-first automation is preferred; never silently modify financial plans.

## Feature Deferral Rules

Defer unless clearly required to improve Available to Spend, Set Aside, or
planning clarity:

- Full transaction categorization or subscription management.
- AI insights or advanced analytics.
- Full loan amortization or complex forecasting.
- Editable production Dashboard widgets.
- More tabs or duplicative navigation.
- Features added only because competitors provide them.

Before proceeding, ask: does this make Caldera simpler, clearer, and more
trustworthy for understanding Available to Spend? If not, defer it or keep the
experiment in Lab.
