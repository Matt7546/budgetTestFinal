#!/usr/bin/env bash
set -euo pipefail

export GH_PAGER=cat
export GIT_PAGER=cat
export PAGER=cat

usage() {
  echo "Usage: $0 <pr-number>" >&2
  exit 2
}

fail() {
  echo "BLOCKED: $*"
  exit 1
}

pass() {
  echo "PASS: $*"
}

warning() {
  echo "WARNING: $*"
  WARNINGS=$((WARNINGS + 1))
}

blocked() {
  echo "BLOCKED: $*"
  BLOCKERS=$((BLOCKERS + 1))
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
  --json state,isDraft,mergeable,baseRefName,headRefName,headRefOid,mergedAt \
  --template '{{.state}}{{"\t"}}{{.isDraft}}{{"\t"}}{{.mergeable}}{{"\t"}}{{.baseRefName}}{{"\t"}}{{.headRefName}}{{"\t"}}{{.headRefOid}}{{"\t"}}{{.mergedAt}}')" ||
  fail "Could not read pull request #$PR_NUMBER."
IFS=$'\t' read -r PR_STATE PR_DRAFT PR_MERGEABLE PR_BASE PR_HEAD PR_SHA PR_MERGED_AT <<< "$PR_DATA"

BLOCKERS=0
WARNINGS=0
LOCAL_BRANCH="$(git -C "$REPOSITORY_ROOT" branch --show-current)"
WORKTREE_STATUS="$(git -C "$REPOSITORY_ROOT" status --short)"
[[ -n "$LOCAL_BRANCH" ]] || LOCAL_BRANCH="detached HEAD"

echo "Caldera PR readiness check"
echo "Repository root: $REPOSITORY_ROOT"
echo "Repository: $REPOSITORY"
echo "Local branch: $LOCAL_BRANCH"
if [[ -z "$WORKTREE_STATUS" ]]; then
  pass "Working tree is clean."
else
  warning "Working tree has local changes."
  printf '%s\n' "$WORKTREE_STATUS"
fi

if [[ "$LOCAL_BRANCH" == "main" ]]; then
  if git -C "$REPOSITORY_ROOT" show-ref --verify --quiet refs/remotes/origin/main; then
    LOCAL_MAIN="$(git -C "$REPOSITORY_ROOT" rev-parse main)"
    REMOTE_MAIN="$(git -C "$REPOSITORY_ROOT" rev-parse origin/main)"
    if [[ "$LOCAL_MAIN" == "$REMOTE_MAIN" ]]; then
      pass "Local main matches origin/main."
    else
      warning "Local main does not match origin/main."
    fi
  else
    warning "origin/main is not available locally for comparison."
  fi
else
  warning "Local main comparison skipped because main is not checked out."
fi

echo
echo "Pull request"
echo "State: $PR_STATE"
echo "Draft: $PR_DRAFT"
echo "Mergeability: $PR_MERGEABLE"
echo "Base branch: $PR_BASE"
echo "Head branch: $PR_HEAD"
echo "Head commit: $PR_SHA"
if [[ "$PR_STATE" == "CLOSED" && -z "$PR_MERGED_AT" ]]; then
  blocked "Pull request is closed without being merged."
elif [[ "$PR_STATE" == "MERGED" || -n "$PR_MERGED_AT" ]]; then
  pass "Pull request is merged."
elif [[ "$PR_STATE" == "OPEN" ]]; then
  pass "Pull request is open."
else
  warning "Pull request state is $PR_STATE."
fi
if [[ "$PR_DRAFT" == "true" ]]; then
  blocked "Pull request is still a draft."
else
  pass "Pull request is not a draft."
fi
case "$PR_MERGEABLE" in
  CONFLICTING|NOT_MERGEABLE) blocked "GitHub reports the pull request as $PR_MERGEABLE." ;;
  MERGEABLE) pass "GitHub reports the pull request as mergeable." ;;
  *)
    if [[ "$PR_STATE" == "MERGED" || -n "$PR_MERGED_AT" ]]; then
      warning "Mergeability is $PR_MERGEABLE for the merged pull request."
    else
      warning "GitHub has not provided a definitive mergeability result ($PR_MERGEABLE)."
    fi
    ;;
esac

echo
echo "Changed files"
"$GH_BIN" pr view "$PR_NUMBER" --repo "$REPOSITORY" --json files \
  --template '{{range .files}}- {{.path}} (+{{.additions}} -{{.deletions}}){{"\n"}}{{end}}' ||
  warning "Changed-file details are unavailable."

echo
echo "GitHub checks"
set +e
CHECKS_OUTPUT="$("$GH_BIN" pr checks "$PR_NUMBER" --repo "$REPOSITORY" --json name,state,workflow,link \
  --template '{{range .}}- {{.name}}{{"\t"}}{{.state}}{{"\t"}}{{.workflow}}{{"\n"}}{{end}}' 2>&1)"
CHECKS_STATUS=$?
set -e
if [[ "$CHECKS_OUTPUT" == *"no checks reported"* || -z "$CHECKS_OUTPUT" ]]; then
  warning "No GitHub Actions checks are reported for this pull request."
elif [[ "$CHECKS_STATUS" -ne 0 ]]; then
  warning "GitHub check status is unavailable: $CHECKS_OUTPUT"
else
  printf '%s\n' "$CHECKS_OUTPUT"
  while IFS=$'\t' read -r CHECK_NAME CHECK_STATE CHECK_WORKFLOW; do
    case "$CHECK_STATE" in
      SUCCESS|PASS|SKIPPING|NEUTRAL) pass "Check $CHECK_NAME is $CHECK_STATE." ;;
      PENDING|QUEUED|IN_PROGRESS|WAITING) warning "Check $CHECK_NAME is still $CHECK_STATE." ;;
      FAILURE|ERROR|CANCELLED|TIMED_OUT|ACTION_REQUIRED) blocked "Check $CHECK_NAME is $CHECK_STATE." ;;
      *) warning "Check $CHECK_NAME has state $CHECK_STATE." ;;
    esac
  done <<< "$CHECKS_OUTPUT"
  if ! printf '%s\n' "$CHECKS_OUTPUT" | awk -F '\t' '$3 != "" { found=1 } END { exit found ? 0 : 1 }'; then
    warning "No GitHub Actions workflow name was reported; checks may be external."
  fi
fi

echo
echo "Unresolved review threads"
THREAD_QUERY='query($owner:String!,$repo:String!,$number:Int!){repository(owner:$owner,name:$repo){pullRequest(number:$number){reviewThreads(first:100){nodes{isResolved comments(first:1){nodes{body path line author{login}}}}}}}}'
OWNER="$(printf '%s' "$REPOSITORY" | cut -d/ -f1)"
REPO_NAME="$(printf '%s' "$REPOSITORY" | cut -d/ -f2)"
THREAD_COUNT="$("$GH_BIN" api graphql -f query="$THREAD_QUERY" -F owner="$OWNER" -F repo="$REPO_NAME" -F number="$PR_NUMBER" \
  --jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved | not)] | length' 2>/dev/null || true)"
if [[ "$THREAD_COUNT" =~ ^[0-9]+$ ]]; then
  if [[ "$THREAD_COUNT" -eq 0 ]]; then
    pass "No unresolved review threads."
  else
    THREAD_DETAILS="$("$GH_BIN" api graphql -f query="$THREAD_QUERY" -F owner="$OWNER" -F repo="$REPO_NAME" -F number="$PR_NUMBER" \
      --template '{{range .data.repository.pullRequest.reviewThreads.nodes}}{{if not .isResolved}}- {{(index .comments.nodes 0).author.login}}: {{(index .comments.nodes 0).path}} line {{(index .comments.nodes 0).line}}: {{(index .comments.nodes 0).body}}{{"\n"}}{{end}}{{end}}' 2>/dev/null || true)"
    printf '%s\n' "$THREAD_DETAILS"
    if printf '%s\n' "$THREAD_DETAILS" | grep -Eiq '(^|[[:space:]#-])(blocking|blocker)([[:space:]:-]|$)'; then
      blocked "Unresolved review thread is explicitly marked blocking."
    else
      warning "$THREAD_COUNT unresolved review thread(s) need human classification."
    fi
  fi
else
  warning "Unresolved review-thread data is unavailable."
fi

echo
echo "Human checklist"
echo "- [ ] Required local tests/builds passed"
echo "- [ ] Independent review completed"
echo "- [ ] Accepted findings resolved"
echo "- [ ] Relevant simulator/device QA completed"
echo "- [ ] Product owner approved merge"
echo
if [[ "$BLOCKERS" -gt 0 ]]; then
  echo "BLOCKED: $BLOCKERS blocker(s), $WARNINGS warning(s)."
  exit 2
elif [[ "$WARNINGS" -gt 0 ]]; then
  echo "WARNING: No blockers detected; $WARNINGS warning(s) require human attention."
else
  echo "PASS: No blockers or warnings detected."
fi
