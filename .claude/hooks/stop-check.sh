#!/usr/bin/env bash
set -euo pipefail

# stop_hook_active チェック（無限ループ防止）
input="$(cat)"
if echo "$input" | jq -e '.stop_hook_active' >/dev/null 2>&1; then
  exit 0
fi

FAILED=0
MSG=""

# Makefileがあればmakeで統一
if [ -f "Makefile" ] && grep -q "^test:" Makefile; then
  make test >/dev/null 2>&1 || { FAILED=1; MSG="make test failed."; }
elif [ -f "package.json" ]; then
  npm run lint >/dev/null 2>&1 || { FAILED=1; MSG+=" lint failed."; }
  npm test >/dev/null 2>&1 || { FAILED=1; MSG+=" tests failed."; }
elif [ -f "pyproject.toml" ] || [ -f "setup.py" ]; then
  ruff check . >/dev/null 2>&1 || { FAILED=1; MSG+=" lint failed."; }
  python -m pytest >/dev/null 2>&1 || { FAILED=1; MSG+=" tests failed."; }
elif [ -f "go.mod" ]; then
  golangci-lint run >/dev/null 2>&1 || { FAILED=1; MSG+=" lint failed."; }
  go test ./... >/dev/null 2>&1 || { FAILED=1; MSG+=" tests failed."; }
elif [ -f "Cargo.toml" ]; then
  cargo clippy >/dev/null 2>&1 || { FAILED=1; MSG+=" lint failed."; }
  cargo test >/dev/null 2>&1 || { FAILED=1; MSG+=" tests failed."; }
fi

if [ "$FAILED" -eq 1 ]; then
  jq -n --arg reason "Do not stop yet:${MSG}" '{
    decision: "block",
    reason: $reason
  }'
fi