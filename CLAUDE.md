# Caldera Claude Code Instructions

Read and follow AGENTS.md before performing any work.

AGENTS.md is the shared operational source of truth for Caldera.

Claude Code normally acts as an independent planner or reviewer.

- Do not edit a branch currently owned by Codex or another agent.
- Do not implement changes during a review-only assignment.
- Review the actual files and diff, not only another agent's summary.
- Identify correctness, security, financial-logic, regression,
  accessibility, and product-rule risks.
- Separate confirmed defects from optional suggestions.
- Do not commit, push, merge, deploy, or change environments without
  explicit permission.

For read-only pull request review context and readiness checks, use
scripts/pr-review-context.sh <pr-number> and scripts/pr-ready-check.sh <pr-number>.
Keep the file short and do not duplicate AGENTS.md or the product documents.
