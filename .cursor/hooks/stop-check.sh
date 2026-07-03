#!/usr/bin/env bash
# Cursor stop adapter: run the project's lint/typecheck/test gate when the agent
# tries to finish; if anything fails, tell it to keep going.
#
# Ported from .claude/hooks/stop-check.sh. Two contract differences vs Claude:
#   1. Output: Cursor's stop hook injects extra instructions via
#      {"followup_message": "..."} (Claude used {"decision":"block","reason":...}).
#   2. Loop guard: Cursor re-fires this hook after each injected followup, so we
#      guard with the input's `loop_count` (Claude used `stop_hook_active`).
#      At/over CURSOR_STOP_LOOP_LIMIT we stay silent so the agent can actually
#      stop, instead of looping forever on a gate it cannot satisfy.
#
# Scope = full (lint + typecheck + test), matching the Claude/Codex harness for
# parity. If Composer's iteration feels slow, narrowing stop to lint+typecheck
# (leaving tests to pre-push) is the documented fallback.
set -euo pipefail

DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$DIR/lib/profile.sh"
hook_profile_skip stop-check
source "$DIR/lib/protected.sh"

input="$(cat)"
hook_debug stop "$input"

# Prevent infinite followup loops: once we have nudged the agent
# CURSOR_STOP_LOOP_LIMIT times, let it stop even if checks still fail.
LOOP_LIMIT="${CURSOR_STOP_LOOP_LIMIT:-2}"
# `|| loop_count=0` so a jq parse error (malformed stdin) reaches the numeric
# fallback below instead of aborting under `set -e`. The regex then guards
# against valid-but-non-numeric values (e.g. "abc", null) before the integer
# comparison, which would otherwise be a fatal arithmetic error.
loop_count="$(echo "$input" | jq -r '.loop_count // 0' 2>/dev/null)" || loop_count=0
[[ "$loop_count" =~ ^[0-9]+$ ]] || loop_count=0
if [ "$loop_count" -ge "$LOOP_LIMIT" ]; then
  exit 0
fi

FAILED=0
MSG=""

# Use Makefile if available
if [ -f "Makefile" ] && grep -q "^test:" Makefile; then
  make test >/dev/null 2>&1 || { FAILED=1; MSG="make test failed."; }

# TypeScript / JavaScript — auto-detect pnpm via lockfile or packageManager field.
elif [ -f "package.json" ]; then
  if [ -f "pnpm-lock.yaml" ] || grep -q '"packageManager"\s*:\s*"pnpm@' package.json 2>/dev/null; then
    pnpm lint >/dev/null 2>&1 || { FAILED=1; MSG+=" lint failed."; }
    pnpm typecheck >/dev/null 2>&1 || { FAILED=1; MSG+=" typecheck failed."; }
    pnpm test >/dev/null 2>&1 || { FAILED=1; MSG+=" tests failed."; }
  else
    npm run lint >/dev/null 2>&1 || { FAILED=1; MSG+=" lint failed."; }
    npm run typecheck >/dev/null 2>&1 || { FAILED=1; MSG+=" typecheck failed."; }
    npm test >/dev/null 2>&1 || { FAILED=1; MSG+=" tests failed."; }
  fi

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
  jq -n --arg msg "Do not stop yet:${MSG}" '{ followup_message: $msg }'
fi
