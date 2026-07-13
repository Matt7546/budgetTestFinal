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

blocked() {
  echo "BLOCKED: $*" >&2
  exit 2
}

unresolved() {
  echo "UNRESOLVED: $*" >&2
  exit 3
}

nonempty_line_count() {
  if [[ -z "$1" ]]; then
    printf '0\n'
  else
    printf '%s\n' "$1" | awk 'NF { count++ } END { print count + 0 }'
  fi
}

extract_closing_issue_numbers() {
  printf '%s\n' "$1" |
    tr '[:upper:]' '[:lower:]' |
    grep -Eo '(^|[^[:alpha:]])(close|closes|closed|fix|fixes|fixed|resolve|resolves|resolved)[[:space:]]+#[0-9]+' |
    sed -E 's/.*#//' |
    sort -u || true
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
[[ "$REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] ||
  fail "Could not determine a supported owner/repository from origin."
OWNER="$(printf '%s' "$REPOSITORY" | cut -d/ -f1)"

PR_NUMBER=$1
PR_DATA="$("$GH_BIN" pr view "$PR_NUMBER" --repo "$REPOSITORY" --json state,isDraft,title \
  --jq '[.state, .isDraft, .title] | @tsv')" ||
  fail "Could not read pull request #$PR_NUMBER."
IFS=$'\t' read -r PR_STATE PR_DRAFT PR_TITLE <<< "$PR_DATA"
PR_BODY="$("$GH_BIN" pr view "$PR_NUMBER" --repo "$REPOSITORY" --json body --jq '.body // ""')" ||
  fail "Could not read the body for pull request #$PR_NUMBER."

[[ "$PR_STATE" == "OPEN" ]] || blocked "Pull request #$PR_NUMBER is $PR_STATE, not OPEN."
[[ "$PR_DRAFT" == "false" ]] || blocked "Pull request #$PR_NUMBER is still a draft."

echo "Running PR readiness check for #$PR_NUMBER..."
set +e
"$SCRIPT_DIR/pr-ready-check.sh" "$PR_NUMBER"
READINESS_STATUS=$?
set -e
case "$READINESS_STATUS" in
  0) ;;
  2) blocked "Pull request #$PR_NUMBER did not pass readiness checks." ;;
  *) fail "PR readiness check failed with exit code $READINESS_STATUS." ;;
esac

ISSUE_NUMBERS="$(extract_closing_issue_numbers "$PR_BODY")"
ISSUE_COUNT="$(nonempty_line_count "$ISSUE_NUMBERS")"
if [[ "$ISSUE_COUNT" -eq 0 ]]; then
  unresolved "No closing issue reference found. Add one Closes, Fixes, or Resolves #N reference."
elif [[ "$ISSUE_COUNT" -ne 1 ]]; then
  unresolved "Multiple closing issue references found. Choose one issue before updating a Project item."
fi
ISSUE_NUMBER="$ISSUE_NUMBERS"

ISSUE_DATA="$("$GH_BIN" issue view "$ISSUE_NUMBER" --repo "$REPOSITORY" --json number,title,url \
  --jq '[.number, .title, .url] | @tsv')" ||
  unresolved "Issue #$ISSUE_NUMBER could not be resolved in $REPOSITORY."
IFS=$'\t' read -r RESOLVED_ISSUE_NUMBER ISSUE_TITLE ISSUE_URL <<< "$ISSUE_DATA"
[[ "$RESOLVED_ISSUE_NUMBER" == "$ISSUE_NUMBER" ]] ||
  unresolved "Issue #$ISSUE_NUMBER does not belong to $REPOSITORY."

PROJECT_MATCHES="$("$GH_BIN" project list --owner "$OWNER" --limit 100 --format json \
  --jq '.projects[] | select(.title == "Caldera Development") | [.number, .id] | @tsv')" ||
  fail "Could not list GitHub Projects. The token needs Projects access with the project scope."
PROJECT_COUNT="$(nonempty_line_count "$PROJECT_MATCHES")"
if [[ "$PROJECT_COUNT" -eq 0 ]]; then
  unresolved "No user Project titled Caldera Development was found."
elif [[ "$PROJECT_COUNT" -ne 1 ]]; then
  unresolved "Multiple user Projects titled Caldera Development were found."
fi
IFS=$'\t' read -r PROJECT_NUMBER PROJECT_ID <<< "$PROJECT_MATCHES"

STATUS_FIELD_MATCHES="$("$GH_BIN" project field-list "$PROJECT_NUMBER" --owner "$OWNER" --limit 100 --format json \
  --jq '.fields[] | select(.name == "Status" and .type == "ProjectV2SingleSelectField") | .id')" ||
  fail "Could not list fields for Project Caldera Development."
STATUS_FIELD_COUNT="$(nonempty_line_count "$STATUS_FIELD_MATCHES")"
if [[ "$STATUS_FIELD_COUNT" -eq 0 ]]; then
  unresolved "Project Caldera Development has no Status single-select field."
elif [[ "$STATUS_FIELD_COUNT" -ne 1 ]]; then
  unresolved "Project Caldera Development has multiple Status single-select fields."
fi
STATUS_FIELD_ID="$STATUS_FIELD_MATCHES"

VERIFY_OPTION_MATCHES="$("$GH_BIN" project field-list "$PROJECT_NUMBER" --owner "$OWNER" --limit 100 --format json \
  --jq '.fields[] | select(.id == "'"$STATUS_FIELD_ID"'") | .options[] | select(.name == "Verify") | .id')" ||
  fail "Could not read Status options for Project Caldera Development."
VERIFY_OPTION_COUNT="$(nonempty_line_count "$VERIFY_OPTION_MATCHES")"
if [[ "$VERIFY_OPTION_COUNT" -eq 0 ]]; then
  unresolved "Project Caldera Development has no Verify Status option."
elif [[ "$VERIFY_OPTION_COUNT" -ne 1 ]]; then
  unresolved "Project Caldera Development has multiple Verify Status options."
fi
VERIFY_OPTION_ID="$VERIFY_OPTION_MATCHES"

ITEM_MATCHES="$("$GH_BIN" project item-list "$PROJECT_NUMBER" --owner "$OWNER" --limit 100 --format json \
  --jq '.items[] | select(.content.type == "Issue" and .content.number == '"$ISSUE_NUMBER"' and .content.repository == "'"$REPOSITORY"'") | [.id, (.status // "")] | @tsv')" ||
  fail "Could not list items in Project Caldera Development."
ITEM_COUNT="$(nonempty_line_count "$ITEM_MATCHES")"
if [[ "$ITEM_COUNT" -eq 0 ]]; then
  unresolved "Issue #$ISSUE_NUMBER is not already in Project Caldera Development."
elif [[ "$ITEM_COUNT" -ne 1 ]]; then
  unresolved "Issue #$ISSUE_NUMBER resolves to multiple Project items."
fi
IFS=$'\t' read -r PROJECT_ITEM_ID OLD_STATUS <<< "$ITEM_MATCHES"

if [[ "$OLD_STATUS" != "Verify" ]]; then
  "$GH_BIN" project item-edit --id "$PROJECT_ITEM_ID" --project-id "$PROJECT_ID" \
    --field-id "$STATUS_FIELD_ID" --single-select-option-id "$VERIFY_OPTION_ID" >/dev/null ||
    fail "Could not update the linked issue's Project Status to Verify."
fi

FINAL_STATUS="$("$GH_BIN" project item-list "$PROJECT_NUMBER" --owner "$OWNER" --limit 100 --format json \
  --jq '.items[] | select(.id == "'"$PROJECT_ITEM_ID"'") | .status')" ||
  fail "Could not verify the updated Project item."
[[ "$FINAL_STATUS" == "Verify" ]] ||
  fail "Project item status verification failed; expected Verify, found $FINAL_STATUS."

echo
echo "Success"
echo "PR: #$PR_NUMBER $PR_TITLE"
echo "Issue: #$ISSUE_NUMBER $ISSUE_TITLE"
echo "Project: Caldera Development"
if [[ -n "$OLD_STATUS" ]]; then
  echo "Old status: $OLD_STATUS"
else
  echo "Old status: unset"
fi
echo "New status: Verify"
