#!/usr/bin/env bash
# Fixture tests for the upgraded .claude/.codex protect-config.sh guards.
#
# Both hooks receive Claude-Code-style PreToolUse JSON on stdin
# ({"tool_input":{"file_path":...}}) and block via exit 2 + stderr message
# (see .claude/hooks/protect-config.sh / .codex/hooks/protect-config.sh).
# Classification now comes from the shared scripts/lib/protected.sh
# (is_protected_path), so every case here is run against BOTH copies to
# confirm the backport behaves identically in each harness.
#
# HOOK_PROFILE is pinned to strict so a developer's exported profile can't
# turn protect-config into a no-op and make assertions pass vacuously.
#
# Run: bash tests/protect-config.test.sh
set -uo pipefail
export HOOK_PROFILE=strict

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS=("$REPO_ROOT/.claude/hooks/protect-config.sh" "$REPO_ROOT/.codex/hooks/protect-config.sh")

PASS=0
FAIL=0
ok()  { printf '  \033[32mPASS\033[0m %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAIL=$((FAIL + 1)); }

run_hook() { # $1=hook path $2=json -> $RC, $OUT
  OUT="$(printf '%s' "$2" | bash "$1" 2>&1)"
  RC=$?
}

for HOOK in "${HOOKS[@]}"; do
  label="${HOOK#"$REPO_ROOT"/}"
  echo "$label (deny cases)"
  for p in "/repo/.env" "/repo/.env.local" "/repo/.ENV" "/repo/tsconfig.json" \
           "/repo/pnpm-lock.yaml" "/repo/.env " "/repo/.env/"; do
    run_hook "$HOOK" '{"tool_input":{"file_path":"'"$p"'"}}'
    [ "$RC" -eq 2 ] && ok "deny $p" || bad "$p should deny (rc=$RC out=$OUT)"
  done

  echo "$label (allow cases)"
  for p in "/repo/.env.example" "/repo/foo.env" "/repo/src/ok.ts"; do
    run_hook "$HOOK" '{"tool_input":{"file_path":"'"$p"'"}}'
    [ "$RC" -eq 0 ] && ok "allow $p" || bad "$p should allow (rc=$RC out=$OUT)"
  done

  echo "$label (edge cases)"
  run_hook "$HOOK" 'not json'
  [ "$RC" -eq 0 ] && ok "malformed stdin fails open (allow)" || bad "malformed stdin should fail open, rc=$RC out=$OUT"

  run_hook "$HOOK" '{"tool_input":{"file_path":""}}'
  [ "$RC" -eq 0 ] && ok "empty path allows" || bad "empty path should allow, rc=$RC out=$OUT"

  run_hook "$HOOK" '{"tool_input":{"file_path":"/repo/.env"}}'
  echo "$OUT" | grep -q 'protected config/secret file' && ok "deny message mentions protected file reason" || bad "deny message should mention reason, out=$OUT"
done

echo
echo "----------------------------------------"
echo "PASS=$PASS  FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
