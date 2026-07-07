#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${PROJECT_ROOT}/plaid-backend/.env"

usage() {
  echo "Usage: $0 transactions|accounts-only"
}

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

case "$1" in
  transactions)
    desired="true"
    ;;
  accounts-only)
    desired="false"
    ;;
  *)
    usage
    exit 1
    ;;
esac

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing plaid-backend/.env. Create it before switching local Plaid mode."
  exit 1
fi

tmp_file="$(mktemp)"
if grep -Eq '^PLAID_TRANSACTIONS_ENABLED=' "${ENV_FILE}"; then
  awk -v value="${desired}" '
    BEGIN { updated = 0 }
    /^PLAID_TRANSACTIONS_ENABLED=/ {
      print "PLAID_TRANSACTIONS_ENABLED=" value
      updated = 1
      next
    }
    { print }
    END {
      if (!updated) {
        print "PLAID_TRANSACTIONS_ENABLED=" value
      }
    }
  ' "${ENV_FILE}" > "${tmp_file}"
else
  cat "${ENV_FILE}" > "${tmp_file}"
  printf '\nPLAID_TRANSACTIONS_ENABLED=%s\n' "${desired}" >> "${tmp_file}"
fi

mv "${tmp_file}" "${ENV_FILE}"

echo "Updated local plaid-backend/.env only."
echo "PLAID_TRANSACTIONS_ENABLED=${desired}"
echo "Restart the local backend for this to take effect."
echo "Render/TestFlight were not changed."

