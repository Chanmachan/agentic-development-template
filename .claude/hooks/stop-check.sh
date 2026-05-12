#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/profile.sh"
hook_profile_skip stop-check

# Prevent infinite loop when stop hook re-triggers itself
input="$(cat)"
if echo "$input" | jq -e '.stop_hook_active // false' >/dev/null 2>&1; then
  active="$(echo "$input" | jq -r '.stop_hook_active // false')"
  [ "$active" = "true" ] && exit 0
fi

FAILED=0
MSG=""

# Use Makefile if available
if [ -f "Makefile" ] && grep -q "^test:" Makefile; then
  make test >/dev/null 2>&1 || { FAILED=1; MSG="make test failed."; }

# TypeScript / JavaScript
elif [ -f "package.json" ]; then
  npm run lint >/dev/null 2>&1 || { FAILED=1; MSG+=" lint failed."; }
  npm test >/dev/null 2>&1 || { FAILED=1; MSG+=" tests failed."; }

# Python
elif [ -f "pyproject.toml" ] || [ -f "setup.py" ]; then
  ruff check . >/dev/null 2>&1 || { FAILED=1; MSG+=" lint failed."; }
  python -m pytest >/dev/null 2>&1 || { FAILED=1; MSG+=" tests failed."; }

# Go
elif [ -f "go.mod" ]; then
  golangci-lint run >/dev/null 2>&1 || { FAILED=1; MSG+=" lint failed."; }
  go test ./... >/dev/null 2>&1 || { FAILED=1; MSG+=" tests failed."; }

# Rust
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