# Caldera Product Brief

## Product Purpose

Caldera helps people virtually delegate funds before spending while maintaining
a clear, trustworthy **Available to Spend** amount. It turns a bank balance
into a calmer planning decision: what remains after the money a person intends
to set aside for future needs.

Caldera does not hold, move, transfer, or pay money. It helps people plan
around money that remains in their real bank accounts.

## User Problem

Seeing money in an account does not answer the question, “Can I spend this?”
Part of that balance may already have a purpose: an upcoming expense, a savings
intention, a Cash Cushion, or a credit-card payment that needs planning.
Keeping those intentions in mind manually can be tiring and uncertain.

Caldera helps users see the relationship between cash they can count, money
they have Set Aside, and what is coming next—without asking them to maintain a
detailed accounting system.

## Target User

Caldera is for people who:

- Want financial clarity without traditional budgeting complexity.
- Mentally separate money but struggle to keep that system current.
- Feel anxious about upcoming expenses or credit-card payments.
- Prefer calm guidance over detailed accounting.
- Need confidence before making spending decisions.

The product is not defined by a specific age, income, or occupation. Its fit is
about the need for a simpler way to make everyday spending decisions.

## Core Promise

At any moment, Caldera should help users understand what is safe to spend after
accounting for the money they intend to set aside.

In product language, the user-facing expression of that promise is **Available
to Spend**. Caldera should make the reasoning behind that amount understandable
enough to trust.

## Product Principles

- **Available to Spend is the primary product output.** It is the anchor for
  spending decisions.
- **Set Aside is virtual planning, not money movement.** The money stays in
  the user's account; Caldera keeps planned amounts out of Available to Spend.
- **One primary purpose per screen.** Each experience should answer a clear
  question rather than become a general-purpose finance dashboard.
- **Financial information should feel calm, simple, and understandable.**
  Plain language, focused actions, and space are part of the product.
- **Automation should generally be review-first.** Suggestions can reduce
  effort, but users should stay in control.
- **Caldera should not silently modify financial plans.** Trust and
  transparency matter more than appearing fully automatic.
- **Credit-card payments are planned payments.** Payment Plans should make
  those needs visible without turning Caldera into complex debt management.

See [PRODUCT_RULES.md](PRODUCT_RULES.md) for detailed terminology, behavioral
rules, and feature boundaries.

## Primary Product Experiences

**Dashboard and Available to Spend** provide the clearest answer to the
everyday question: “Can I spend money today without hurting future plans?” The
Dashboard should keep that answer prominent and offer one useful next step.

**Set Aside** is the home for money intentionally kept out of spending. It
brings together the distinct reasons a user may plan ahead:

- **Cash Cushion** for flexible extra money.
- **Savings Goals** for things the user is saving toward.
- **Upcoming Expenses** for planned bills and near-term needs.
- **Payment Plans** for planned payments, including credit-card payments.

**Plan Ahead** shows what is coming up, what is covered, what still needs
money, and what needs attention. It is a planning view, not a ledger.

**Expected Income** lets a user record a planning estimate for an upcoming
payday. It can inform future planning, but it is not included in Available to
Spend until money arrives in a linked account.

**Review Updates** is the decision surface for detected or suggested changes.
It should help users understand what deserves review while preserving
review-first control.

**Bank linking and synchronization** connect eligible account balances so
Caldera can estimate Available to Spend. Bank Sync should clearly communicate
freshness, confidence, and any reason the estimate may be incomplete.

**Settings and account management** provide a calm place to manage Bank Sync,
expected-income planning, preferences, help, privacy, and account actions.

## Current Strategic Priorities

1. Increase trust in Available to Spend.
2. Reduce manual setup and maintenance where doing so preserves user control.
3. Improve credit-card Payment Plan transparency.
4. Make synchronization and suggested updates understandable.
5. Preserve simplicity as automation grows.
6. Improve tester feedback and product analytics.
7. Prepare for broader external TestFlight testing and an eventual public
   launch.

## Non-Goals for the Current Product Stage

- Holding or transferring money.
- Paying bills or credit cards.
- Full bookkeeping or accounting.
- Investment portfolio management.
- Tax preparation.
- Complex debt-management coaching.
- Silent, fully automatic changes to user plans.
- Adding features solely because competitors offer them.

## Product Decision Test

Before advancing a new idea, ask:

- Does it improve trust in Available to Spend?
- Does it reduce meaningful user effort?
- Is it understandable without financial expertise?
- Does it belong on an existing screen?
- Does it duplicate another feature?
- Can it be review-first rather than silently automatic?
- Does it increase complexity more than user value?
- Could it make users incorrectly believe Caldera controls or moves money?

## Success Signals

Useful product signals include:

- Onboarding completion.
- Successful account linking.
- Creation of at least one Set Aside plan.
- Understanding and use of Available to Spend.
- Continued use after initial setup.
- Engagement with Plan Ahead and Review Updates.
- Acceptance or dismissal of suggested updates.
- Reduced need for manual correction.
- Positive tester feedback about clarity, trust, and calmness.

These signals should guide learning, not become targets without additional
product and measurement work.

## Near-Term Product Questions

- Is every main screen clearly supporting Available to Spend?
- Are Set Aside, Plan Ahead, and Review Updates sufficiently distinct?
- Is Payment Plans the clearest terminology and location for credit-card
  payments?
- Which manual actions can safely become suggestions?
- Is the current navigation still optimal after recent feature growth?
- Which information belongs on the Dashboard versus secondary screens?
- What is required before broader external TestFlight testing?

Update this brief when Caldera's central purpose, target user, primary
experiences, or strategic priorities materially change.
