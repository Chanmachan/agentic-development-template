#!/usr/bin/env bash
# Drift gate for files that are intentionally kept byte-identical across the
# .claude and .codex harnesses (ADR 0006 §2: each harness keeps its own copy
# of these scripts for standalone readability, rather than sharing a single
# file — but that only stays safe if the copies never diverge).
#
# If this test fails, someone edited one copy without updating its sibling.
# Fix: copy the file you intended to change over its pair (or vice versa) so
# both harnesses stay in sync, then re-run this test.
#
# Run: bash tests/harness-parity.test.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASS=0
FAIL=0
ok()  { printf '  \033[32mPASS\033[0m %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAIL=$((FAIL + 1)); }

PAIRS=(
  ".claude/hooks/post-lint.sh:.codex/hooks/post-lint.sh"
  ".claude/hooks/stop-check.sh:.codex/hooks/stop-check.sh"
  ".claude/hooks/protect-config.sh:.codex/hooks/protect-config.sh"
  ".claude/hooks/lib/profile.sh:.codex/hooks/lib/profile.sh"
)

for pair in "${PAIRS[@]}"; do
  a="${pair%%:*}"
  b="${pair#*:}"
  a_path="$REPO_ROOT/$a"
  b_path="$REPO_ROOT/$b"

  if [ ! -f "$a_path" ]; then
    bad "$a is missing"
    continue
  fi
  if [ ! -f "$b_path" ]; then
    bad "$b is missing"
    continue
  fi

  if diff -q "$a_path" "$b_path" >/dev/null 2>&1; then
    ok "$a and $b are byte-identical"
  else
    bad "$a and $b have drifted — update both copies to match, then re-run this test. diff:
$(diff "$a_path" "$b_path")"
  fi
done


# ---------------------------------------------------------------------------
# Symlink verification (ADR 0008 (d)): .codex/rules/{git,tasks}.md are
# relative symlinks to .claude/rules/, not copies — drift is structurally
# impossible, but a broken/retargeted symlink (or someone replacing it with a
# real file that then diverges) would silently defeat that guarantee. Check
# both that the path resolves ([ -e ], which follows symlinks and fails on a
# dangling target) and that the resolved content matches its .claude/rules/
# counterpart byte-for-byte.
# ---------------------------------------------------------------------------
SYMLINK_PAIRS=(
  ".codex/rules/git.md:.claude/rules/git.md"
  ".codex/rules/tasks.md:.claude/rules/tasks.md"
)

for pair in "${SYMLINK_PAIRS[@]}"; do
  a="${pair%%:*}"
  b="${pair#*:}"
  a_path="$REPO_ROOT/$a"
  b_path="$REPO_ROOT/$b"

  if [ ! -e "$a_path" ]; then
    bad "$a does not resolve (missing or dangling symlink)"
    continue
  fi
  ok "$a resolves"

  if [ ! -f "$b_path" ]; then
    bad "$b is missing"
    continue
  fi

  if diff -q "$a_path" "$b_path" >/dev/null 2>&1; then
    ok "$a and $b are content-identical"
  else
    bad "$a and $b have drifted — $a should stay a symlink to $b. diff:
$(diff "$a_path" "$b_path")"
  fi
done

echo
echo "----------------------------------------"
echo "PASS=$PASS  FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
