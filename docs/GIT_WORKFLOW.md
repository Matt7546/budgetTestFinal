# Caldera Git Workflow

Use Git to keep Caldera changes understandable and reversible.

## Main

`main` is the current source of truth for the app and backend. A push to `main` may trigger a Render backend deploy, so backend changes should be pushed intentionally.

Small UI polish, docs, and low-risk bug fixes can happen on the current branch. Risky backend, auth, Plaid, SwiftData, formula, release-hardening, or Lab infrastructure work should use a branch.

## Check State

```sh
git status --short
git branch --show-current
```

## Create A Branch

```sh
git checkout -b feature/name
```

Use a branch when:

- Changing backend routes or auth.
- Changing Plaid products or endpoints.
- Touching SwiftData schemas.
- Touching financial formulas.
- Preparing a risky Lab experiment.
- Hardening for public release.

You usually do not need a branch when:

- Editing docs.
- Adjusting simple copy.
- Making tightly scoped UI polish.
- Fixing a small visual bug.

## Commit

```sh
git add .
git commit -m "message"
```

Use short, specific messages:

```sh
git commit -m "Document Caldera environment workflow"
git commit -m "Polish Timeline empty state copy"
git commit -m "Gate Plaid transactions behind config"
```

## Merge

```sh
git checkout main
git merge branch-name
```

Run validation before pushing:

```sh
./scripts/validate.sh
```

## Delete A Branch

After merge:

```sh
git branch -d branch-name
```

## Emergency Discard Branch

If a branch is bad and should be abandoned:

```sh
git checkout main
git branch -D branch-name
```

Do not use destructive commands on `main` unless you are intentionally undoing work and understand what will be lost.

## Push

```sh
git push origin main
```

Push when:

- Validation passes.
- Backend changes are intended to deploy.
- You are ready for GitHub to become the source of truth.

Do not push when:

- Local backend work is half-finished.
- Plaid/Auth changes have not been tested.
- You are unsure whether Render will deploy a backend change.


## Lab Experiments

Experimental ideas belong in branches and the Caldera Lab Local scheme, not in the normal Debug QA workflow. Use `Caldera Debug Local` for real app QA and `Caldera Lab Local` only when you intentionally want prototype tabs or Lab-only UI visible.

## Render And GitHub

Render deploys from the GitHub repo `Matt7546/budgetTestFinal`, service `plaid-backend`. Treat a push to `main` as potentially deployable backend code.

Render env vars are separate from Git. Changing `.env` locally does not change Render. Changing Render env vars does not change Git.

## Rollback

Preferred order:

1. If the bad work is only on a branch, delete the branch.
2. If the bad work is committed locally but not pushed, create a new corrective commit or reset only with clear intent.
3. If the bad work was pushed and deployed, make a revert commit and push intentionally.
4. Check Render deploy status after backend rollbacks.

## Forks

Forks are not needed right now. Use branches in the current repo for risky work.

