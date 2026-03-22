#!/usr/bin/env bash
set -euo pipefail

input="$(cat)"
file="$(jq -r '.tool_input.file_path // .tool_input.path // empty' <<< "$input")"
[ -z "$file" ] && exit 0

diag=""

case "$file" in
  *.ts|*.tsx|*.js|*.jsx)
    npx biome format --write "$file" >/dev/null 2>&1 || true
    npx oxlint --fix "$file" >/dev/null 2>&1 || true
    diag="$(npx oxlint "$file" 2>&1 | head -20 || true)"
    ;;
  *.py)
    ruff format "$file" >/dev/null 2>&1 || true
    ruff check --fix "$file" >/dev/null 2>&1 || true
    diag="$(ruff check "$file" 2>&1 | head -20 || true)"
    ;;
  *.go)
    gofumpt -w "$file" >/dev/null 2>&1 || true
    diag="$(golangci-lint run "$file" 2>&1 | head -20 || true)"
    ;;
  *.rs)
    rustfmt "$file" >/dev/null 2>&1 || true
    diag="$(cargo clippy 2>&1 | head -20 || true)"
    ;;
  *) exit 0 ;;
esac

if [ -n "$diag" ]; then
  jq -Rn --arg msg "$diag" '{
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      additionalContext: $msg
    }
  }'
fi