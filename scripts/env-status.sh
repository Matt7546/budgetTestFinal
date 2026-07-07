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

extract_release_url() {
  sed -n '/#else/,/#endif/p' "${APP_CONFIG}" |
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

cd "${PROJECT_ROOT}"

debug_url="$(extract_debug_url)"
release_url="$(extract_release_url)"
debug_host="$(url_host "${debug_url}")"
mac_ip="$(ipconfig getifaddr en0 2>/dev/null || true)"

echo "Caldera environment status"
echo
echo "Project root: ${PROJECT_ROOT}"
echo "Branch: $(git branch --show-current || git rev-parse --short HEAD)"
echo
echo "Git status:"
git status --short || true
echo
echo "Network:"
echo "Current Mac IP (en0): ${mac_ip:-unavailable}"
echo "Debug backend URL: ${debug_url}"
echo "Release backend URL: ${release_url}"

if [[ -n "${mac_ip}" && "${debug_host}" == "${mac_ip}" ]]; then
  echo "Debug backend IP matches current Mac IP."
else
  echo "WARNING: Debug backend host (${debug_host}) does not match current Mac IP (${mac_ip:-unavailable})."
fi

echo
echo "Local backend .env:"
if [[ -f "${ENV_FILE}" ]]; then
  echo "Found: plaid-backend/.env"
  echo "Key names only:"
  grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "${ENV_FILE}" |
    cut -d= -f1 |
    sort
else
  echo "Missing: plaid-backend/.env"
fi

echo
echo "Required/important local keys:"
for key in PLAID_ENV PORT APP_API_KEY DEV_AUTH_ENABLED PLAID_TRANSACTIONS_ENABLED PLAID_LIABILITIES_ENABLED; do
  if has_env_key "${key}"; then
    echo "- ${key}: present"
  else
    echo "- ${key}: missing"
  fi
done

echo
echo "No secret values were printed."

