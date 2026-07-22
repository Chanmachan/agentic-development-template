#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/profile.sh"
hook_profile_skip post-lint

input="$(cat)"
file="$(jq -r '.tool_input.file_path // .tool_input.path // empty' <<< "$input")"
[ -z "$file" ] && exit 0

# Skip files that resolve outside this repo (e.g. scratchpad/session temp
# dirs). Compare physical paths: `git rev-parse --show-toplevel` resolves
# symlinks, so the file's directory (`cd -P`: physical traversal, a logical
# `cd` would let `in-repo-link/../` escape undetected) and any symlinked
# final component (readlink loop) must be resolved the same way — otherwise
# macOS's /var -> /private/var symlink makes in-repo files look "outside",
# and an in-repo symlink to an outside file would look "inside". Relative
# paths resolve against the hook's cwd, so `../escape.ts`-style paths are
# caught too. Unresolvable paths fail closed (skip): a missing directory
# can't be linted, and a final component still symlinked after the hop bound
# (long chain / cycle) has an unknown true target that must not be linted
# under its in-repo name.
repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -n "$repo_root" ]; then
  real_dir="$(cd -P "$(dirname -- "$file")" 2>/dev/null && pwd -P)" || real_dir=""
  [ -z "$real_dir" ] && exit 0
  real_file="$real_dir/$(basename -- "$file")"
  hops=0
  while [ -L "$real_file" ] && [ "$hops" -lt 8 ]; do
    target="$(readlink "$real_file")" || break
    case "$target" in
      /*) ;;
      *) target="$(dirname -- "$real_file")/$target" ;;
    esac
    real_dir="$(cd -P "$(dirname -- "$target")" 2>/dev/null && pwd -P)" || real_dir=""
    [ -z "$real_dir" ] && exit 0
    real_file="$real_dir/$(basename -- "$target")"
    hops=$((hops + 1))
  done
  [ -L "$real_file" ] && exit 0
  case "$real_file" in
    "$repo_root"/*) ;;
    *) exit 0 ;;
  esac
fi

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