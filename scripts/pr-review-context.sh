#!/usr/bin/env bash
set -euo pipefail

export GH_PAGER=cat
export GIT_PAGER=cat
export PAGER=cat

usage() {
  echo "Usage: $0 <pr-number>" >&2
  exit 64
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

[[ $# -eq 1 && $1 =~ ^[0-9]+$ ]] || usage

CURRENT_DIRECTORY=$PWD
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPOSITORY_ROOT="$(git -C "$CURRENT_DIRECTORY" rev-parse --show-toplevel 2>/dev/null)" ||
  fail "Run this script from inside a Git repository."
[[ "$REPOSITORY_ROOT" == "$PROJECT_ROOT" ]] ||
  fail "Run this script from inside the Caldera repository."

GH_BIN="$(command -v gh || true)"
if [[ -z "$GH_BIN" ]]; then
  for candidate in /opt/homebrew/bin/gh /usr/local/bin/gh "$HOME/.local/bin/gh"; do
    [[ -x "$candidate" ]] && GH_BIN=$candidate && break
  done
fi
[[ -n "$GH_BIN" ]] || fail "GitHub CLI (gh) is required."
"$GH_BIN" auth status >/dev/null 2>&1 || fail "GitHub CLI is not authenticated. Run gh auth login."

ORIGIN_URL="$(git -C "$REPOSITORY_ROOT" remote get-url origin 2>/dev/null)" ||
  fail "The Caldera repository needs an origin remote."
REPOSITORY="$(printf '%s' "$ORIGIN_URL" | sed -E 's#^(https?://|git@|ssh://git@)github.com[:/]##; s#\.git$##')"
[[ "$REPOSITORY" == */* ]] || fail "Could not determine owner/repository from origin."

PR_NUMBER=$1
PR_DATA="$("$GH_BIN" pr view "$PR_NUMBER" --repo "$REPOSITORY" \
  --json title,number,url,state,isDraft,mergeable,baseRefName,headRefName,headRefOid,changedFiles,additions,deletions \
  --template '{{.title}}{{"\t"}}{{.number}}{{"\t"}}{{.url}}{{"\t"}}{{.state}}{{"\t"}}{{.isDraft}}{{"\t"}}{{.mergeable}}{{"\t"}}{{.baseRefName}}{{"\t"}}{{.headRefName}}{{"\t"}}{{.headRefOid}}{{"\t"}}{{.changedFiles}}{{"\t"}}{{.additions}}{{"\t"}}{{.deletions}}')" ||
  fail "Could not read pull request #$PR_NUMBER."
IFS=$'\t' read -r PR_TITLE PR_ID PR_URL PR_STATE PR_DRAFT PR_MERGEABLE PR_BASE PR_HEAD PR_SHA PR_FILES PR_ADDITIONS PR_DELETIONS <<< "$PR_DATA"

LOCAL_BRANCH="$(git -C "$REPOSITORY_ROOT" branch --show-current)"
WORKTREE_STATUS="$(git -C "$REPOSITORY_ROOT" status --short)"
[[ -n "$LOCAL_BRANCH" ]] || LOCAL_BRANCH="detached HEAD"

echo "Caldera PR review context"
echo "Current directory: $CURRENT_DIRECTORY"
echo "Repository root: $REPOSITORY_ROOT"
echo "Repository: $REPOSITORY"
echo "Local branch: $LOCAL_BRANCH"
if [[ -n "$WORKTREE_STATUS" ]]; then
  echo "Working tree: changes present"
  printf '%s\n' "$WORKTREE_STATUS"
else
  echo "Working tree: clean"
fi
echo
echo "Pull request"
echo "Title: $PR_TITLE"
echo "Number: #$PR_ID"
echo "URL: $PR_URL"
echo "State: $PR_STATE"
echo "Draft: $PR_DRAFT"
echo "Mergeability: $PR_MERGEABLE"
echo "Base branch: $PR_BASE"
echo "Head branch: $PR_HEAD"
echo "Head commit: $PR_SHA"
echo
echo "Linked issues"
set +e
LINKED_ISSUES="$("$GH_BIN" pr view "$PR_NUMBER" --repo "$REPOSITORY" --json closingIssuesReferences \
  --template '{{range .closingIssuesReferences}}- #{{.number}} ({{.url}}){{"\n"}}{{end}}' 2>/dev/null)"
LINKED_ISSUES_STATUS=$?
set -e
if [[ "$LINKED_ISSUES_STATUS" -ne 0 ]]; then
  echo "Unavailable."
elif [[ -n "$LINKED_ISSUES" ]]; then
  printf '%s\n' "$LINKED_ISSUES"
else
  echo "None."
fi
echo
echo "Commits"
"$GH_BIN" pr view "$PR_NUMBER" --repo "$REPOSITORY" --json commits \
  --template '{{range .commits}}- {{.oid}} {{.messageHeadline}}{{"\n"}}{{end}}' ||
  echo "Unavailable."
echo
echo "Changed files"
"$GH_BIN" pr view "$PR_NUMBER" --repo "$REPOSITORY" --json files \
  --template '{{range .files}}- {{.path}} (+{{.additions}} -{{.deletions}}){{"\n"}}{{end}}' ||
  echo "Unavailable."
echo
echo "Diff statistics: $PR_FILES files, +$PR_ADDITIONS, -$PR_DELETIONS"
echo
echo "Submitted reviews"
set +e
SUBMITTED_REVIEWS="$("$GH_BIN" pr view "$PR_NUMBER" --repo "$REPOSITORY" --json reviews \
  --template '{{range .reviews}}- {{.author.login}}: {{.state}} ({{.submittedAt}}){{"\n"}}{{end}}' 2>/dev/null)"
SUBMITTED_REVIEWS_STATUS=$?
set -e
if [[ "$SUBMITTED_REVIEWS_STATUS" -ne 0 ]]; then
  echo "Unavailable."
elif [[ -n "$SUBMITTED_REVIEWS" ]]; then
  printf '%s\n' "$SUBMITTED_REVIEWS"
else
  echo "None."
fi

echo
echo "Unresolved review threads"
THREAD_QUERY='query($owner:String!,$repo:String!,$number:Int!){repository(owner:$owner,name:$repo){pullRequest(number:$number){reviewThreads(first:100){nodes{isResolved comments(first:1){nodes{path line author{login}}}}}}}}'
OWNER="$(printf '%s' "$REPOSITORY" | cut -d/ -f1)"
REPO_NAME="$(printf '%s' "$REPOSITORY" | cut -d/ -f2)"
UNRESOLVED_THREADS="$("$GH_BIN" api graphql -f query="$THREAD_QUERY" -F owner="$OWNER" -F repo="$REPO_NAME" -F number="$PR_NUMBER" \
  --jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved | not)] | length' 2>/dev/null || true)"
if [[ "$UNRESOLVED_THREADS" =~ ^[0-9]+$ ]]; then
  if [[ "$UNRESOLVED_THREADS" -eq 0 ]]; then
    echo "None."
  else
    echo "$UNRESOLVED_THREADS unresolved thread(s):"
    "$GH_BIN" api graphql -f query="$THREAD_QUERY" -F owner="$OWNER" -F repo="$REPO_NAME" -F number="$PR_NUMBER" \
      --template '{{range .data.repository.pullRequest.reviewThreads.nodes}}{{if not .isResolved}}- {{(index .comments.nodes 0).author.login}}: {{(index .comments.nodes 0).path}} line {{(index .comments.nodes 0).line}}{{"\n"}}{{end}}{{end}}' ||
      echo "Details unavailable."
  fi
else
  echo "Unavailable (the GitHub GraphQL response did not include review-thread data)."
fi

echo
echo "GitHub checks"
set +e
CHECKS_OUTPUT="$("$GH_BIN" pr checks "$PR_NUMBER" --repo "$REPOSITORY" --json name,state,workflow,link \
  --template '{{range .}}- {{.name}}: {{.state}}{{if .workflow}} [{{.workflow}}]{{end}}{{"\n"}}{{end}}' 2>&1)"
CHECKS_STATUS=$?
set -e
if [[ "$CHECKS_OUTPUT" == *"no checks reported"* || -z "$CHECKS_OUTPUT" ]]; then
  echo "No checks reported. No GitHub Actions checks exist or are available for this PR."
elif [[ "$CHECKS_STATUS" -ne 0 ]]; then
  echo "Check status unavailable: $CHECKS_OUTPUT"
else
  printf '%s\n' "$CHECKS_OUTPUT"
fi

echo
echo "Claude review reminder"
echo "- Read CLAUDE.md and AGENTS.md."
echo "- Review the actual PR diff."
echo "- Classify findings as Blocking, Should Fix, Optional, or No Issue."
echo "- Do not edit during a review-only assignment."
