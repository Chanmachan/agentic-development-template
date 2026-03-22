#!/usr/bin/env bash
set -euo pipefail

input="$(cat)"
file="$(jq -r '.tool_input.file_path // .tool_input.path // empty' <<< "$input")"
[ -z "$file" ] && exit 0

diag=""

case "$file" in
  # -------------------------------------------------------
  # TypeScript / JavaScript (enabled by default)
  # Requires: biome, oxlint
  #   npm install -D @biomejs/biome oxlint
  # -------------------------------------------------------
  *.ts|*.tsx|*.js|*.jsx)
    if ! command -v biome &>/dev/null; then
      echo "ERROR: biome is not installed. Run: npm install -D @biomejs/biome" >&2
      exit 1
    fi
    if ! command -v oxlint &>/dev/null; then
      echo "ERROR: oxlint is not installed. Run: npm install -D oxlint" >&2
      exit 1
    fi
    biome format --write "$file" >/dev/null 2>&1 || true
    oxlint --fix "$file" >/dev/null 2>&1 || true
    diag="$(oxlint "$file" 2>&1 | head -20 || true)"
    ;;

  # -------------------------------------------------------
  # Python (uncomment to enable)
  # Requires: ruff
  #   pip install ruff
  # -------------------------------------------------------
  # *.py)
  #   if ! command -v ruff &>/dev/null; then
  #     echo "ERROR: ruff is not installed. Run: pip install ruff" >&2
  #     exit 1
  #   fi
  #   ruff format "$file" >/dev/null 2>&1 || true
  #   ruff check --fix "$file" >/dev/null 2>&1 || true
  #   diag="$(ruff check "$file" 2>&1 | head -20 || true)"
  #   ;;

  # -------------------------------------------------------
  # Go (uncomment to enable)
  # Requires: gofumpt, golangci-lint
  #   brew install gofumpt golangci-lint
  # -------------------------------------------------------
  # *.go)
  #   if ! command -v gofumpt &>/dev/null; then
  #     echo "ERROR: gofumpt is not installed. Run: brew install gofumpt" >&2
  #     exit 1
  #   fi
  #   gofumpt -w "$file" >/dev/null 2>&1 || true
  #   diag="$(golangci-lint run "$file" 2>&1 | head -20 || true)"
  #   ;;

  # -------------------------------------------------------
  # Rust (uncomment to enable)
  # Requires: rustfmt, cargo (via rustup)
  #   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
  # -------------------------------------------------------
  # *.rs)
  #   rustfmt "$file" >/dev/null 2>&1 || true
  #   diag="$(cargo clippy 2>&1 | head -20 || true)"
  #   ;;

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