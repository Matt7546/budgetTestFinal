# Caldera Git Workflow

Use Git to keep Caldera work scoped, reviewable, and reversible. Product rules
live in [PRODUCT_RULES.md](PRODUCT_RULES.md); environment selection lives in
[ENVIRONMENT_WORKFLOW.md](ENVIRONMENT_WORKFLOW.md).

## Start and Scope

Begin every task with:

```sh
./scripts/task-start.sh
```

Work from a scoped GitHub issue or a clearly stated task with explicit
guardrails and acceptance criteria. Inspect the current branch, tracking state,
and working tree before editing.

`main` is the source of truth. A push to `main` may trigger a Render backend
deploy, so pushes must be intentional.

## Branches

Small documentation, copy, or tightly scoped low-risk UI changes may stay on
the current branch when the task allows it. Create a focused branch for:

- Financial formulas or Available to Spend behavior.
- Backend routes, storage, rate limiting, or deployment work.
- Plaid products, capabilities, consent, or endpoints.
- Authentication, sessions, or multi-user scoping.
- SwiftData schemas or migrations.
- Signing, Release, or public-launch hardening.
- Lab infrastructure or experiments.

```sh
git switch -c feature/short-name
```

Lab experiments must be branch-backed and use `Caldera Lab Local`. They do
not belong in routine Debug or production behavior.

## Finish and Commit

For normal tasks:

```sh
./scripts/task-finish.sh
```

For risky or production-facing changes:

```sh
./scripts/task-finish.sh --release
```

Inspect the complete diff, then stage only the intended files:

```sh
git add path/to/intended-file another/intended-file
git diff --cached
git commit -m "Short specific message"
```

Do not use broad staging when unrelated work is present. Do not commit, push,
merge, deploy, or change environments unless the active task explicitly
permits it.

## Merge and Cleanup

After validation and review:

```sh
git switch main
git merge branch-name
git branch -d branch-name
```

Delete a branch only after confirming its intended work is merged or no longer
needed. Never force-delete or discard work without understanding what will be
lost.

## Push and Render

```sh
git push origin branch-name
```

Push only when validation passes, the changes are complete, and GitHub should
become the source of truth. Backend changes require extra care because Render
deploys the `plaid-backend` service from the GitHub repository. Confirm the
intended branch and deployment behavior before pushing or merging.

Local `.env` values and Render variables are separate. Git operations do not
authorize environment changes.

## Rollback

Prefer the least destructive option:

1. If uncommitted work is wrong, correct it or remove only the intended lines.
2. If a local commit is wrong, make a corrective commit; rewrite history only
   with clear intent.
3. If a pushed change is wrong, create a revert commit and push it
   intentionally.
4. For backend rollbacks, verify Render deployment status and service health.

Avoid destructive commands on `main`. Preserve unrelated user work.

Forks are not currently needed; use focused branches in this repository.
