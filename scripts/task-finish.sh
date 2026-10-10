#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RUN_RELEASE=false
FAILED=0

usage() {
  echo "Usage: $0 [--release]"
}

case "${1:-}" in
  "")
    ;;
  --release)
    RUN_RELEASE=true
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

run_required_check() {
  local label="$1"
  shift

  echo
  echo "${label}:"
  if "$@"; then
    echo "PASS: ${label}"
  else
    echo "FAIL: ${label}" >&2
    FAILED=1
  fi
}

cd "${PROJECT_ROOT}"

echo "Caldera task finish"
echo
echo "Repository status:"
git status --short --branch

echo
echo "Changed files:"
git status --short

run_required_check "repository validation (git diff --check)" git diff --check

# validate.sh also builds Release Candidate. Routine checks build Debug only;
# tests and exact-candidate validation are separate commands.
run_required_check "Debug build" "${SCRIPT_DIR}/build-debug.sh"

if [[ "${RUN_RELEASE}" == true ]]; then
  # This simulator build does not establish archive/TestFlight readiness.
  run_required_check "Release Candidate simulator build" "${SCRIPT_DIR}/build-release.sh"
fi

echo
echo "Final repository state:"
git status --short --branch

if [[ "${FAILED}" -ne 0 ]]; then
  echo "Task finish checks failed." >&2
  exit 1
fi

echo "All required task finish checks passed."
