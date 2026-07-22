#!/usr/bin/env bash
# Cursor afterFileEdit adapter: format the just-edited file in place.
#
# Ported from .claude/hooks/post-lint.sh. afterFileEdit is an OBSERVE-ONLY event
# in Cursor (it cannot block and Cursor ignores the hook's stdout), so unlike the
# Claude version we do NOT emit a hookSpecificOutput JSON blob — the only useful
# effect here is the in-place format side effect. Lint diagnostics that need to
# reach the agent are surfaced by stop-check instead.
#
# Input field name differs from Claude; read defensively (see protect-config.sh).
set -euo pipefail

DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$DIR/lib/profile.sh"
hook_profile_skip post-lint
source "$DIR/lib/protected.sh"

input="$(cat)"
hook_debug afterFileEdit "$input"
# `|| file=""` so malformed/unparseable stdin degrades to a no-op instead of
# aborting the script under `set -e` (jq exits non-zero on a parse error).
file="$(jq -r '
  .tool_input.file_path // .tool_input.path //
  .file_path // .path //
  .args.path // .args.file_path //
  empty' <<< "$input" 2>/dev/null)" || file=""
[ -z "$file" ] && exit 0

# Skip absolute paths outside this repo (e.g. scratchpad/session temp dirs);
# relative paths pass through and are classified by extension below. Compare
# symlink-resolved paths: `git rev-parse --show-toplevel` returns the physical
# path, so $file's directory is resolved the same way — otherwise macOS's
# /var -> /private/var symlink makes in-repo files look "outside" whenever
# $TMPDIR-style paths are involved.
repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -n "$repo_root" ]; then
  case "$file" in
    /*)
      real_file_dir="$(cd "$(dirname "$file")" 2>/dev/null && pwd -P)" || real_file_dir=""
      real_file="${real_file_dir:+$real_file_dir/$(basename "$file")}"
      real_file="${real_file:-$file}"
      case "$real_file" in
        "$repo_root"/*) ;;
        *) exit 0 ;;
      esac
      ;;
  esac
fi

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
    biome format --write -- "$file" >/dev/null 2>&1 || true
    oxlint --fix -- "$file" >/dev/null 2>&1 || true
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
  #   ;;

  # -------------------------------------------------------
  # Go (uncomment to enable)
  # Requires: gofumpt
  #   brew install gofumpt
  # -------------------------------------------------------
  # *.go)
  #   if ! command -v gofumpt &>/dev/null; then
  #     echo "ERROR: gofumpt is not installed. Run: brew install gofumpt" >&2
  #     exit 1
  #   fi
  #   gofumpt -w "$file" >/dev/null 2>&1 || true
  #   ;;

  # -------------------------------------------------------
  # Rust (uncomment to enable)
  # Requires: rustfmt, cargo (via rustup)
  #   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
  # -------------------------------------------------------
  # *.rs)
  #   rustfmt "$file" >/dev/null 2>&1 || true
  #   ;;

  *) exit 0 ;;
esac

exit 0
