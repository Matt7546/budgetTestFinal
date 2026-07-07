#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_CONFIG="${PROJECT_ROOT}/budgetTest/App/AppConfig.swift"
DEFAULT_IMAC_URL="http://10.0.0.244:3001"
write=false

usage() {
  echo "Usage: $0 [--write] current-mac|imac|http://x.x.x.x:3001"
  echo
  echo "Dry-run by default. Pass --write to update AppConfig.swift."
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
  exit 1
fi

if [[ "${1:-}" == "--write" ]]; then
  write=true
  shift
fi

target="${1:-}"

case "${target}" in
  current-mac)
    mac_ip="$(ipconfig getifaddr en0 2>/dev/null || true)"
    if [[ -z "${mac_ip}" ]]; then
      echo "Could not determine current Mac IP from en0."
      exit 1
    fi
    new_url="http://${mac_ip}:3001"
    ;;
  imac)
    new_url="${DEFAULT_IMAC_URL}"
    ;;
  http://*:3001|https://*:3001)
    new_url="${target}"
    ;;
  *)
    usage
    exit 1
    ;;
esac

current_url="$(
  sed -n '/#if DEBUG/,/#else/p' "${APP_CONFIG}" |
    sed -n 's/.*apiBaseURL: URL(string: "\([^"]*\)").*/\1/p' |
    head -n 1
)"
release_url="$(
  sed -n '/#else/,/#endif/p' "${APP_CONFIG}" |
    sed -n 's/.*apiBaseURL: URL(string: "\([^"]*\)").*/\1/p' |
    head -n 1
)"

echo "Current Debug backend URL: ${current_url}"
echo "New Debug backend URL:     ${new_url}"
echo "Release backend URL:       ${release_url}"

if [[ "${write}" != true ]]; then
  echo
  echo "Dry run only. Re-run with --write to update AppConfig.swift."
  exit 0
fi

python3 - "$APP_CONFIG" "$new_url" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
new_url = sys.argv[2]
text = path.read_text()
start = text.index("#if DEBUG")
end = text.index("#else", start)
debug_block = text[start:end]

old_line_start = debug_block.index('apiBaseURL: URL(string: "')
old_url_start = old_line_start + len('apiBaseURL: URL(string: "')
old_url_end = debug_block.index('")!', old_url_start)
updated_block = (
    debug_block[:old_url_start]
    + new_url
    + debug_block[old_url_end:]
)
path.write_text(text[:start] + updated_block + text[end:])
PY

echo
echo "Updated Debug backend URL only."
echo "This is a source-code change. Commit or revert it intentionally."
echo "Release backend URL was not changed."

