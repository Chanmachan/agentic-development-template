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

# Like run_hook but keeps stdout and stderr separate, so a "quiet fail-open"
# assertion (no stray stdout on the allow path) isn't masked by 2>&1 merging.
run_hook_split() { # $1=hook path $2=json -> $RC, $OUT (stdout only)
  OUT="$(printf '%s' "$2" | bash "$1" 2>/dev/null)"
  RC=$?
}

for HOOK in "${HOOKS[@]}"; do
  label="${HOOK#"$REPO_ROOT"/}"
  echo "$label (deny cases)"
  for p in "/repo/.env" "/repo/.env.local" "/repo/.ENV" "/repo/tsconfig.json" \
           "/repo/pnpm-lock.yaml" "/repo/.env " "/repo/.env/" \
           "/repo/apps/.git/config" "/repo/packages/api/pnpm-lock.yaml" \
           "/repo/.env.sample" "/repo/.env.template"; do
    run_hook "$HOOK" '{"tool_input":{"file_path":"'"$p"'"}}'
    [ "$RC" -eq 2 ] && ok "deny $p" || bad "$p should deny (rc=$RC out=$OUT)"
  done

  # Guard self-protection (ADR 0008 A1): the guard's own files, and the shared
  # classification lib it depends on, must refuse edits — a single edit to any
  # of these could neuter every write-protection check. PROTECTED_PATTERNS uses
  # substring matching, so these two cases exercise both the shared lib and one
  # harness's own hook copy; the .cursor copy is exercised in
  # scripts/test-cursor-hooks.sh instead (its own protect-config.sh guard).
  for p in "/repo/scripts/lib/protected.sh" "/repo/.claude/hooks/protect-config.sh"; do
    run_hook "$HOOK" '{"tool_input":{"file_path":"'"$p"'"}}'
    [ "$RC" -eq 2 ] && ok "deny guard self-edit $p" || bad "$p should deny (rc=$RC out=$OUT)"
  done

  # Self-protection perimeter (ADR 0009): the expansion of PROTECTED_PATTERNS
  # to cover the FULL hook perimeter, not just protect-config.sh/stop-check.sh/
  # lib/protected.sh. Representative subset per harness-wiring file and
  # hook-script pattern, plus the shared lib.profile.sh pattern.
  for p in "/repo/.claude/hooks/worktree-setup.sh" "/repo/.claude/settings.json" \
           "/repo/.cursor/hooks.json" "/repo/.codex/hooks.json" \
           "/repo/.claude/hooks/lib/profile.sh" "/repo/.cursor/hooks/lib/profile.sh" \
           "/repo/.claude/hooks/git-guard.sh" "/repo/.codex/hooks/git-guard.sh"; do
    run_hook "$HOOK" '{"tool_input":{"file_path":"'"$p"'"}}'
    [ "$RC" -eq 2 ] && ok "deny guard perimeter $p" || bad "$p should deny (rc=$RC out=$OUT)"
  done

  echo "$label (allow cases)"
  # .env.sample / .env.template are DENIED above, not allowed: they narrow the
  # old inline "*.example/*.sample/*.template allow" rule deliberately —
  # .env.example is the single canonical safe-to-share template name (see ADR
  # 0006 §5 / ADR 0008). tsconfig.json.example still allows: the suffix
  # override applies to non-.env config templates, exercising that the
  # *.example/*.sample/*.template precedence still wins over PROTECTED_PATTERNS
  # (tsconfig.json) for those.
  for p in "/repo/.env.example" "/repo/foo.env" "/repo/src/ok.ts" "/repo/tsconfig.json.example"; do
    run_hook "$HOOK" '{"tool_input":{"file_path":"'"$p"'"}}'
    [ "$RC" -eq 0 ] && ok "allow $p" || bad "$p should allow (rc=$RC out=$OUT)"
  done

  # Perimeter precision (ADR 0009 A1): ".claude/settings.json" is the full
  # relative path, not a bare "settings.json" substring — a settings.json that
  # lives OUTSIDE .claude/ (e.g. a downstream project's .vscode/settings.json)
  # must stay ALLOWED. Pinned here so a future edit can't accidentally widen
  # the pattern back to a bare substring and start over-blocking.
  run_hook "$HOOK" '{"tool_input":{"file_path":"/repo/.vscode/settings.json"}}'
  [ "$RC" -eq 0 ] && ok "allow /repo/.vscode/settings.json (outside .claude/)" || bad "/repo/.vscode/settings.json should allow (rc=$RC out=$OUT)"

  # Same precision for the hooks.json entries: ".codex/hooks.json" and
  # ".cursor/hooks.json" are anchored FULL relative paths, not a bare
  # "hooks.json" substring -- a downstream project's unrelated hooks.json
  # (outside .codex/ and .cursor/) must stay ALLOWED. Pinned here so a future
  # edit can't accidentally widen the pattern back to a bare substring.
  run_hook "$HOOK" '{"tool_input":{"file_path":"/repo/some-tool/hooks.json"}}'
  [ "$RC" -eq 0 ] && ok "allow /repo/some-tool/hooks.json (outside .codex/.cursor)" || bad "/repo/some-tool/hooks.json should allow (rc=$RC out=$OUT)"

  echo "$label (edge cases)"
  run_hook "$HOOK" 'not json'
  [ "$RC" -eq 0 ] && ok "malformed stdin fails open (allow)" || bad "malformed stdin should fail open, rc=$RC out=$OUT"

  run_hook_split "$HOOK" 'not json'
  { [ "$RC" -eq 0 ] && [ -z "$OUT" ]; } && ok "malformed stdin is quiet on stdout" || bad "malformed stdin should produce no stdout, rc=$RC out=$OUT"

  run_hook "$HOOK" '{"tool_input":{"file_path":""}}'
  [ "$RC" -eq 0 ] && ok "empty path allows" || bad "empty path should allow, rc=$RC out=$OUT"

  run_hook "$HOOK" '{"tool_input":{"file_path":"/repo/.env"}}'
  echo "$OUT" | grep -q 'protected config/secret file' && ok "deny message mentions protected file reason" || bad "deny message should mention reason, out=$OUT"

  # Profile-gate wiring regression guard: HOOK_PROFILE=minimal must actually
  # turn protect-config into a no-op (protect-config is only in
  # minimal/standard/strict's later tiers, not minimal — see lib/profile.sh),
  # so a write that would otherwise be denied goes through.
  OUT="$(printf '%s' '{"tool_input":{"file_path":"/repo/.env"}}' | HOOK_PROFILE=minimal bash "$HOOK" 2>&1)"
  RC=$?
  [ "$RC" -eq 0 ] && ok "HOOK_PROFILE=minimal allows .env write (gate skipped)" || bad "HOOK_PROFILE=minimal should skip protect-config, rc=$RC out=$OUT"
done

# ---------------------------------------------------------------------------
# Fail-closed on a missing shared lib (ADR 0008 B): copy each hook + its
# lib/profile.sh into an isolated temp dir WITHOUT scripts/lib/protected.sh,
# so the relative `source .../scripts/lib/protected.sh` in the hook resolves
# to nothing. A benign, otherwise-allowed path must still be BLOCKED (exit 2)
# instead of silently falling through to "allow" — the guard's only job is
# refusing writes, so an unloadable classification lib must fail closed.
echo "fail-closed: shared lib missing"
for HOOK in "${HOOKS[@]}"; do
  label="${HOOK#"$REPO_ROOT"/}"
  rel="${HOOK#"$REPO_ROOT"/}" # e.g. .claude/hooks/protect-config.sh — kept at
                               # the same depth as the real repo so the hook's
                               # own "../../scripts/lib/..." relative source
                               # resolves under $FIXTURE, not above it.
  hook_dir="$(dirname "$rel")" # .claude/hooks

  FIXTURE="$(mktemp -d)"
  mkdir -p "$FIXTURE/$hook_dir/lib"
  cp "$HOOK" "$FIXTURE/$rel"
  cp "$REPO_ROOT/$hook_dir/lib/profile.sh" "$FIXTURE/$hook_dir/lib/profile.sh"
  # Deliberately no scripts/lib/protected.sh under $FIXTURE.

  OUT="$(printf '%s' '{"tool_input":{"file_path":"/repo/src/ok.ts"}}' | bash "$FIXTURE/$rel" 2>&1)"
  RC=$?
  [ "$RC" -eq 2 ] && ok "$label: missing shared lib fails closed (exit 2)" || bad "$label: missing shared lib should block, rc=$RC out=$OUT"
  rm -rf "$FIXTURE"
done

echo
echo "----------------------------------------"
echo "PASS=$PASS  FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
