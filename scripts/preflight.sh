#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${PROJECT_ROOT}"

echo "pwd:"
pwd

echo
echo "git root:"
git rev-parse --show-toplevel

echo
echo "branch:"
git branch --show-current || git rev-parse --short HEAD

echo
echo "xcode project:"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
    xcodebuild -list -project budgetTest.xcodeproj

echo
echo "git status --short:"
git status --short
