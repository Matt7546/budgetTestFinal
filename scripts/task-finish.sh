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

# validate.sh also runs Release. Keep it unchanged as the full validation
# entry point, but call the existing Debug build directly here so the default
# finish path does not run Release unnecessarily.
run_required_check "Debug build" "${SCRIPT_DIR}/build-debug.sh"

if [[ "${RUN_RELEASE}" == true ]]; then
  # Keep an explicit final Release build available when requested.
  run_required_check "explicit Release build" "${SCRIPT_DIR}/build-release.sh"
fi

echo
echo "Final repository state:"
git status --short --branch

if [[ "${FAILED}" -ne 0 ]]; then
  echo "Task finish checks failed." >&2
  exit 1
fi

echo "All required task finish checks passed."
