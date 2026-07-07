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

url_host() {
  printf '%s\n' "$1" | sed -E 's#^[a-zA-Z]+://([^/:]+).*#\1#'
}

has_env_key() {
  local key="$1"
  [[ -f "${ENV_FILE}" ]] && grep -Eq "^${key}=" "${ENV_FILE}"
}

debug_url="$(extract_debug_url)"
debug_host="$(url_host "${debug_url}")"
mac_ip="$(ipconfig getifaddr en0 2>/dev/null || true)"

echo "Starting Caldera local backend"
echo
echo "Current Mac IP (en0): ${mac_ip:-unavailable}"
echo "Debug backend URL: ${debug_url}"

if [[ -n "${mac_ip}" && "${debug_host}" == "${mac_ip}" ]]; then
  echo "Debug backend IP matches current Mac IP."
else
  echo "WARNING: Debug backend host (${debug_host}) does not match current Mac IP (${mac_ip:-unavailable})."
  echo "If testing on a physical device, update Debug URL or keep the device on the same network as the configured Mac."
fi

echo
if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing plaid-backend/.env. Create it from plaid-backend/.env.example first."
  exit 1
fi

missing=0
for key in PLAID_CLIENT_ID PLAID_SECRET PLAID_ENV PORT APP_API_KEY; do
  if has_env_key "${key}"; then
    echo "- ${key}: present"
  else
    echo "- ${key}: missing"
    missing=1
  fi
done

if ! has_env_key DEV_AUTH_ENABLED; then
  echo "- DEV_AUTH_ENABLED: missing (Debug local dev sign-in needs DEV_AUTH_ENABLED=true)"
fi

if [[ "${missing}" -ne 0 ]]; then
  echo "Required local backend keys are missing. No secret values were printed."
  exit 1
fi

echo
echo "Physical devices must be on the same network and must be able to reach ${debug_url}."
echo "No secret values were printed."
echo

cd "${PROJECT_ROOT}/plaid-backend"
npm start

