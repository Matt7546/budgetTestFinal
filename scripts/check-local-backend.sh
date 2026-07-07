#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_CONFIG="${PROJECT_ROOT}/budgetTest/App/AppConfig.swift"
ENV_FILE="${PROJECT_ROOT}/plaid-backend/.env"

extract_debug_url() {
  sed -n '/#if DEBUG/,/#else/p' "${APP_CONFIG}" |
    sed -n 's/.*apiBaseURL: URL(string: "\([^"]*\)").*/\1/p' |
    head -n 1
}

get_env_value() {
  local key="$1"
  local line
  line="$(grep -E "^${key}=" "${ENV_FILE}" | tail -n 1 || true)"
  line="${line#*=}"
  line="${line%\"}"
  line="${line#\"}"
  line="${line%\'}"
  line="${line#\'}"
  printf '%s' "${line}"
}

request() {
  local method="$1"
  local path="$2"
  local token="${3:-}"
  local body_file
  local status
  body_file="$(mktemp)"

  set +e
  if [[ -n "${token}" ]]; then
    status="$(curl -sS -m 12 -o "${body_file}" -w "%{http_code}" \
      -X "${method}" \
      -H "x-app-api-key: ${APP_API_KEY}" \
      -H "Authorization: Bearer ${token}" \
      "${BACKEND_URL}${path}")"
  else
    status="$(curl -sS -m 12 -o "${body_file}" -w "%{http_code}" \
      -X "${method}" \
      -H "x-app-api-key: ${APP_API_KEY}" \
      "${BACKEND_URL}${path}")"
  fi
  curl_exit=$?
  set -e

  if [[ "${curl_exit}" -ne 0 ]]; then
    status="000"
  fi

  printf '%s\n' "${status}"
  cat "${body_file}"
  rm -f "${body_file}"
}

json_token() {
  sed -n 's/.*"session_token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1
}

BACKEND_URL="${BACKEND_URL:-$(extract_debug_url)}"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing plaid-backend/.env. Cannot read APP_API_KEY."
  exit 1
fi

APP_API_KEY="$(get_env_value APP_API_KEY)"

if [[ -z "${APP_API_KEY}" ]]; then
  echo "APP_API_KEY is missing from plaid-backend/.env."
  exit 1
fi

echo "Checking local backend: ${BACKEND_URL}"
echo "No secret values will be printed."
echo

capabilities="$(request GET /api/capabilities)"
cap_status="$(printf '%s\n' "${capabilities}" | head -n 1)"
cap_body="$(printf '%s\n' "${capabilities}" | tail -n +2)"

echo "Capabilities: HTTP ${cap_status}"
printf '%s\n' "${cap_body}"
case "${cap_status}" in
  200) echo "Backend reachable." ;;
  401|503) echo "APP_API_KEY is missing or mismatched between app/backend." ;;
  000) echo "Backend not reachable. Check IP, port, and whether npm start is running." ;;
  *) echo "Unexpected capabilities status." ;;
esac

echo
dev_auth="$(request POST /api/auth/development)"
dev_status="$(printf '%s\n' "${dev_auth}" | head -n 1)"
dev_body="$(printf '%s\n' "${dev_auth}" | tail -n +2)"
dev_token="$(printf '%s\n' "${dev_body}" | json_token)"

echo "Development auth: HTTP ${dev_status}"
case "${dev_status}" in
  200) echo "OK. Local dev sign-in is enabled." ;;
  409) echo "Local dev sign-in is disabled. Add DEV_AUTH_ENABLED=true to plaid-backend/.env and restart the backend." ;;
  401|503) echo "APP_API_KEY is missing/mismatched or auth is not configured." ;;
  404) echo "Wrong backend, stale backend, wrong IP, or route not mounted." ;;
  000) echo "Backend not reachable." ;;
  *) echo "Unexpected dev auth status." ;;
esac

echo
transactions="$(request GET /api/transactions "${dev_token}")"
tx_status="$(printf '%s\n' "${transactions}" | head -n 1)"
tx_body="$(printf '%s\n' "${transactions}" | tail -n +2)"

echo "Transactions: HTTP ${tx_status}"
if printf '%s\n' "${tx_body}" | grep -q '"transactions_enabled"[[:space:]]*:[[:space:]]*false'; then
  echo "Transaction mode: disabled/no-op."
elif printf '%s\n' "${tx_body}" | grep -q '"transactions_enabled"[[:space:]]*:[[:space:]]*true'; then
  echo "Transaction mode: enabled."
elif [[ "${tx_status}" == "409" ]] && printf '%s\n' "${tx_body}" | grep -q '"transactions_disabled"'; then
  echo "Transaction mode: disabled/no-op."
elif [[ "${tx_status}" == "409" ]] && printf '%s\n' "${tx_body}" | grep -q '"not_linked"'; then
  echo "Transaction mode: enabled, but no Plaid Item is linked for this user."
else
  echo "Transaction mode: unclear. Response body follows:"
  printf '%s\n' "${tx_body}"
fi

echo
echo "Next steps:"
echo "- 404 usually means wrong backend URL, stale backend, wrong IP, or old server process."
echo "- 409 on dev auth means DEV_AUTH_ENABLED is missing/false or backend was not restarted."
echo "- 401/503 usually means APP_API_KEY is missing/mismatched."

