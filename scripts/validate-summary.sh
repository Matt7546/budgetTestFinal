#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_PATH="/tmp/caldera-validate-latest.log"

cd "${PROJECT_ROOT}"

if "${SCRIPT_DIR}/validate.sh" >"${LOG_PATH}" 2>&1; then
    printf 'Validation log: %s\n' "${LOG_PATH}"
    printf 'Result: PASSED\n'
    grep -E '\*\* (BUILD|TEST) SUCCEEDED \*\*|BUILD SUCCEEDED|TEST SUCCEEDED' "${LOG_PATH}" | tail -n 4 || true
    exit 0
fi

status=$?

printf 'Validation log: %s\n' "${LOG_PATH}"
printf 'Result: FAILED\n'
printf '\nErrors:\n'
grep -n -E 'error:|fatal error:|\*\* (BUILD|TEST) FAILED \*\*|BUILD FAILED|TEST FAILED' "${LOG_PATH}" | tail -n 40 || true
printf '\nLast 80 log lines:\n'
tail -n 80 "${LOG_PATH}"

exit "${status}"
