#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SECRETS_FILE="${PROJECT_ROOT}/Config/Secrets.xcconfig"
RENDER_URL="https://plaid-backend-2wqb.onrender.com"

get_xcconfig_value() {
  local key="$1"
  local line
  line="$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "${SECRETS_FILE}" 2>/dev/null | tail -n 1 || true)"
  line="${line#*=}"
  line="$(printf '%s' "${line}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  printf '%s' "${line}"
}

request() {
  local method="$1"
  local path="$2"
  local body_file
  local status
  body_file="$(mktemp)"

  set +e
  status="$(curl -sS -m 15 -o "${body_file}" -w "%{http_code}" \
    -X "${method}" \
    -H "x-app-api-key: ${APP_API_KEY}" \
    "${RENDER_URL}${path}")"
  curl_exit=$?
  set -e

  if [[ "${curl_exit}" -ne 0 ]]; then
    status="000"
  fi

  printf '%s\n' "${status}"
  cat "${body_file}"
  rm -f "${body_file}"
}

APP_API_KEY="${APP_API_KEY:-}"
if [[ -z "${APP_API_KEY}" && -f "${SECRETS_FILE}" ]]; then
  APP_API_KEY="$(get_xcconfig_value APP_API_KEY)"
fi

if [[ -z "${APP_API_KEY}" ]]; then
  echo "APP_API_KEY is required. Set it in the environment or Config/Secrets.xcconfig."
  exit 1
fi

echo "Checking Render backend: ${RENDER_URL}"
echo "No secret values will be printed."
echo

capabilities="$(request GET /api/capabilities)"
cap_status="$(printf '%s\n' "${capabilities}" | head -n 1)"
cap_body="$(printf '%s\n' "${capabilities}" | tail -n +2)"

echo "Capabilities: HTTP ${cap_status}"
printf '%s\n' "${cap_body}"

if [[ "${cap_status}" == "200" ]]; then
  echo "Render reachable."
else
  echo "Render check did not succeed. Confirm APP_API_KEY, Render service health, and network access."
  exit 1
fi

echo
if printf '%s\n' "${cap_body}" | grep -q '"transactions_enabled"[[:space:]]*:[[:space:]]*true'; then
  echo "WARNING: Render reports Transactions enabled."
  echo "Do not change Render PLAID_TRANSACTIONS_ENABLED without explicit intent and Plaid confirmation."
elif printf '%s\n' "${cap_body}" | grep -q '"transactions_enabled"[[:space:]]*:[[:space:]]*false'; then
  echo "Render reports Transactions disabled."
else
  echo "Unable to determine transaction mode from capabilities response."
fi

echo
echo "Optional transactions endpoint check:"
transactions="$(request GET /api/transactions)"
tx_status="$(printf '%s\n' "${transactions}" | head -n 1)"
tx_body="$(printf '%s\n' "${transactions}" | tail -n +2)"
echo "Transactions: HTTP ${tx_status}"
if printf '%s\n' "${tx_body}" | grep -q '"transactions_enabled"[[:space:]]*:[[:space:]]*false'; then
  echo "Transactions endpoint is disabled/no-op."
elif [[ "${tx_status}" == "401" ]]; then
  echo "Transactions endpoint requires user auth. That is expected for production."
elif [[ "${tx_status}" == "409" ]]; then
  echo "Transactions endpoint returned 409. It may be disabled or no linked Item exists for the checked auth context."
else
  echo "Transactions endpoint returned status ${tx_status}."
fi

