#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${PROJECT_ROOT}"

echo "Caldera task start"
echo
echo "Repository preflight:"
"${SCRIPT_DIR}/preflight.sh"

echo
echo "Latest commits:"
git --no-pager log -5 --oneline --decorate

echo
echo "Branch tracking:"
git for-each-ref \
  --format='%(refname:short) -> %(upstream:short) %(upstream:trackshort)' \
  "refs/heads/$(git branch --show-current)"

echo
echo "Environment status:"
"${SCRIPT_DIR}/env-status.sh"

echo
echo "Available workflow scripts:"
find "${SCRIPT_DIR}" -maxdepth 1 -type f -name '*.sh' -print |
  sed "s#${PROJECT_ROOT}/##" |
  sort

echo
echo "Backend tooling:"
if [[ -f "${PROJECT_ROOT}/plaid-backend/package.json" ]]; then
  echo "plaid-backend/package.json: present"
else
  echo "plaid-backend/package.json: absent"
fi

if command -v node >/dev/null 2>&1; then
  echo "node: $(node --version)"
else
  echo "node: unavailable"
fi

if command -v npm >/dev/null 2>&1; then
  echo "npm: $(npm --version)"
else
  echo "npm: unavailable"
fi
