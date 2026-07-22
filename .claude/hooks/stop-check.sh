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

# Skip the full gate when there is nothing to check, or when every changed
# path is docs/tasks/markdown: a docs-only session should not pay for a full
# lint+typecheck+test run. `git status --porcelain` also reports untracked
# files, so they are covered by the same classification.
changed="$(git status --porcelain 2>/dev/null || true)"
skip=1
if [ -n "$changed" ]; then
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    # porcelain v1: "XY path" (2-char status + 1 space, then path). Renames
    # are "XY old -> new"; take the destination path.
    path="${line:3}"
    path="${path##*-> }"
    case "$path" in
      *.md|docs/*|tasks/*) ;;
      *) skip=0 ;;
    esac
  done <<< "$changed"
fi
[ "$skip" -eq 1 ] && exit 0

FAILED=0
MSG=""
LOG_DIR="$(mktemp -d)"
trap 'rm -rf "$LOG_DIR"' EXIT

# Capture each check's output and surface the tail on failure, so the agent
# sees *what* failed instead of just "lint failed."
run_check() {
  local name="$1"
  shift
  local out="$LOG_DIR/${name// /-}.log"
  if ! "$@" >"$out" 2>&1; then
    FAILED=1
    MSG+=$'\n'"--- ${name} failed. Last 30 lines of output: ---"$'\n'"$(tail -30 "$out")"$'\n'
  fi
}

# Use Makefile if available
if [ -f "Makefile" ] && grep -q "^test:" Makefile; then
  run_check "make test" make test

# TypeScript / JavaScript — auto-detect pnpm via lockfile or packageManager field.
# yarn / bun are not auto-detected (YAGNI); customize per-project if needed.
elif [ -f "package.json" ]; then
  if [ -f "pnpm-lock.yaml" ] || grep -q '"packageManager"\s*:\s*"pnpm@' package.json 2>/dev/null; then
    run_check lint pnpm lint
    run_check typecheck pnpm typecheck
    run_check tests pnpm test
  else
    run_check lint npm run lint
    run_check typecheck npm run typecheck
    run_check tests npm test
  fi

# Python
elif [ -f "pyproject.toml" ] || [ -f "setup.py" ]; then
  run_check lint ruff check .
  run_check tests python -m pytest

# Go
elif [ -f "go.mod" ]; then
  run_check lint golangci-lint run
  run_check tests go test ./...

# Rust
elif [ -f "Cargo.toml" ]; then
  run_check lint cargo clippy
  run_check tests cargo test
fi

if [ "$FAILED" -eq 1 ]; then
  MSG+=$'\n'"lint/typecheck/test の設定を緩めたりテストを削除して通すのは禁止。コードを直すこと。直せない場合は原因を報告して停止してよい。"
  jq -n --arg reason "Do not stop yet:${MSG}" '{
    decision: "block",
    reason: $reason
  }'
fi
