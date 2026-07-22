#!/usr/bin/env bash
# PreToolUse(Bash) guard: block a small set of git footguns that AGENTS.md
# already forbids in prose but had no machine enforcement for:
#   (a) `git commit --no-verify` / `git commit -n` (skips lefthook)
#   (b) direct `git commit` while on `main` (unless ALLOW_MAIN_COMMIT=1,
#       either in the hook's env or as an env-assignment prefix on the command)
#   (c) `git push --force`/`-f` that targets `main` (word match) or is issued
#       while `main` is checked out
#
# Detection is segment-based: the command string is split on newlines and
# `;`/`&`/`|`, and rules only apply to segments whose command position is
# `git ...` (optionally after VAR=val prefixes). Quoted substrings are stripped
# before flag detection so a commit message containing " -n " or a mention of
# `git commit -n` inside e.g. `echo '...'` does not false-positive. This is
# not a full shell parser — it is deliberately conservative-but-simple.
#
# Fails open (exit 0) on anything unexpected — missing jq, unparseable JSON,
# no git repo, etc. — so a hook bug never blocks unrelated development.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/profile.sh"
hook_profile_skip git-guard

input="$(cat)"

command_str="$(jq -r '.tool_input.command // empty' <<< "$input" 2>/dev/null)" || exit 0
[ -z "$command_str" ] && exit 0

branch="$(git branch --show-current 2>/dev/null || true)"

segments="$(printf '%s\n' "$command_str" | tr ';&|' '\n')"

while IFS= read -r seg; do
  [ -z "$seg" ] && continue

  # ALLOW_MAIN_COMMIT=1 may arrive as an env-assignment prefix on the command
  # itself rather than in this hook's environment — honor both.
  allow_main="${ALLOW_MAIN_COMMIT:-}"
  if printf '%s' "$seg" | grep -Eq '(^|[[:space:]])ALLOW_MAIN_COMMIT=1([[:space:]]|$)'; then
    allow_main=1
  fi

  # Trim leading whitespace and leading VAR=value assignments, then require
  # `git` in command position — quoted mentions inside other commands pass.
  s="$(printf '%s' "$seg" | sed -E 's/^[[:space:]]+//; s/^([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*//')"
  case "$s" in
    git\ *|git) ;;
    *) continue ;;
  esac

  # Strip single/double-quoted substrings before flag/word detection so
  # commit-message text never triggers the flag rules.
  s_noq="$(printf '%s' "$s" | sed -E "s/\"[^\"]*\"//g; s/'[^']*'//g")"

  if printf '%s' "$s_noq" | grep -Eq '^git[[:space:]]+commit([[:space:]]|$)'; then
    # (a) --no-verify / bare -n flag
    if printf '%s' "$s_noq" | grep -Eq -- '(--no-verify([[:space:]]|$|=)|[[:space:]]-n([[:space:]]|$))'; then
      echo "BLOCKED by git-guard: 'git commit --no-verify'/'-n' is forbidden (AGENTS.md Quality gates: never skip hooks). Fix the underlying lint/typecheck/test failure instead." >&2
      exit 2
    fi
    # (b) direct commit on main
    if [ "$branch" = "main" ] && [ "$allow_main" != "1" ]; then
      echo "BLOCKED by git-guard: direct 'git commit' on main is forbidden (AGENTS.md: implementation work goes on a feature branch). Prefix the command with ALLOW_MAIN_COMMIT=1 to override for an intentional docs/chore commit on main." >&2
      exit 2
    fi
  fi

  # (c) force-push targeting main (word match, so 'domain' etc. don't count),
  # or any force-push issued while main is the checked-out branch.
  if printf '%s' "$s_noq" | grep -Eq '^git[[:space:]]+push([[:space:]]|$)' \
    && printf '%s' "$s_noq" | grep -Eq -- '(--force([[:space:]]|$|-)|[[:space:]]-f([[:space:]]|$))'; then
    if printf '%s' "$s_noq" | grep -Eq '(^|[^[:alnum:]_])main([^[:alnum:]_]|$)' || [ "$branch" = "main" ]; then
      echo "BLOCKED by git-guard: force-push targeting 'main' (or issued while on main) is forbidden." >&2
      exit 2
    fi
  fi
done <<< "$segments"

exit 0
