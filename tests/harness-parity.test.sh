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
  ".claude/hooks/git-guard.sh:.codex/hooks/git-guard.sh"
)

# suggest-compact.mjs is deliberately NOT paired: the two harnesses gate it at
# different profiles (.claude = standard and strict, .codex = strict only), so
# byte-equality would be the wrong invariant. Any other divergence between the
# two copies is unguarded — check it by hand when editing either one.

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


# .codex/rules/ must not contain .md (ADR 0008 (d)); missing dir PASSes.
CODEX_RULES_DIR="$REPO_ROOT/.codex/rules"
CODEX_RULES_HINT="Codex .codex/rules/ is for .rules (Starlark execpolicy) only — .md is not read. Keep rules in .claude/rules/ and reference them from AGENTS.md."

if [ -d "$CODEX_RULES_DIR" ]; then
  found_md=0
  _codex_rules_find="$(mktemp)"
  if find -L "$CODEX_RULES_DIR/" -iname '*.md' -print0 >"$_codex_rules_find"; then
    while IFS= read -r -d '' md; do
      found_md=1
      bad "unexpected .md under .codex/rules/: $md — $CODEX_RULES_HINT"
    done <"$_codex_rules_find"
    if [ "$found_md" -eq 0 ]; then
      ok ".codex/rules/ has no .md files"
    fi
  else
    bad "find failed while scanning .codex/rules/ — $CODEX_RULES_HINT"
  fi
  rm -f "$_codex_rules_find"
else
  ok ".codex/rules/ absent (expected)"
fi

echo
echo "----------------------------------------"
echo "PASS=$PASS  FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
