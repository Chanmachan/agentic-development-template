#!/usr/bin/env bash
# Profile-gate tests for the .claude/.codex suggest-compact.mjs hooks.
#
# The hook receives Claude-Code-style PreToolUse JSON on stdin
# ({"transcript_path":...}) and, when the active profile includes it and the
# transcript byte-estimate exceeds the threshold, emits a
# hookSpecificOutput.additionalContext warning on stdout. Every case runs
# against BOTH copies so the harnesses cannot drift behaviorally
# (byte-identity is separately enforced by tests/harness-parity.test.sh).
#
# Run: bash tests/suggest-compact.test.sh
set -uo pipefail

# Pin the threshold so a developer's exported override can't skew the
# over/under fixtures below.
export SUGGEST_COMPACT_THRESHOLD=140000

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS=("$REPO_ROOT/.claude/hooks/suggest-compact.mjs" "$REPO_ROOT/.codex/hooks/suggest-compact.mjs")

PASS=0
FAIL=0
ok()  { printf '  \033[32mPASS\033[0m %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAIL=$((FAIL + 1)); }

if ! command -v node >/dev/null 2>&1; then
  echo "FAIL: node is required to run suggest-compact tests" >&2
  exit 1
fi

FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT

# Estimate is bytes/2, so 300000 bytes (~150k est tokens) is over the 140k
# threshold and 1000 bytes is comfortably under.
head -c 300000 /dev/zero | tr '\0' 'x' > "$FIXTURE/big.jsonl"
head -c 1000 /dev/zero | tr '\0' 'x' > "$FIXTURE/small.jsonl"

run_hook() { # $1=hook path $2=profile $3=transcript -> $RC, $OUT (stdout), $ERR (stderr)
  OUT="$(printf '{"transcript_path":"%s"}' "$3" \
    | HOOK_PROFILE="$2" node "$1" 2>"$FIXTURE/stderr")"
  RC=$?
  ERR="$(cat "$FIXTURE/stderr")"
}

for HOOK in "${HOOKS[@]}"; do
  label="${HOOK#"$REPO_ROOT"/}"
  echo "$label"

  run_hook "$HOOK" minimal "$FIXTURE/big.jsonl"
  [ "$RC" -eq 0 ] && [ -z "$OUT" ] && [ -z "$ERR" ] \
    && ok "minimal: silent even over threshold" \
    || bad "minimal should be silent (rc=$RC out=$OUT err=$ERR)"

  for profile in standard strict; do
    run_hook "$HOOK" "$profile" "$FIXTURE/big.jsonl"
    case "$OUT" in
      *'"additionalContext":"[suggest-compact]'*)
        [ "$RC" -eq 0 ] && ok "$profile: warns over threshold" \
          || bad "$profile: over threshold should exit 0 (rc=$RC)" ;;
      *) bad "$profile: should emit additionalContext warning over threshold (rc=$RC out=$OUT)" ;;
    esac

    run_hook "$HOOK" "$profile" "$FIXTURE/small.jsonl"
    [ "$RC" -eq 0 ] && [ -z "$OUT" ] \
      && ok "$profile: silent below threshold" \
      || bad "$profile: below threshold should be silent (rc=$RC out=$OUT)"
  done

  # Fail-soft parity with lib/profile.sh (ADR 0003 §1): unknown profile
  # values warn on stderr and still behave as standard.
  run_hook "$HOOK" bogus "$FIXTURE/big.jsonl"
  case "$ERR" in
    *"unknown HOOK_PROFILE='bogus'"*)
      [ "$RC" -eq 0 ] && ok "unknown profile warns on stderr" \
        || bad "unknown profile should exit 0 (rc=$RC)" ;;
    *) bad "unknown profile should warn on stderr (rc=$RC err=$ERR)" ;;
  esac
  case "$OUT" in
    *'"additionalContext":"[suggest-compact]'*)
      [ "$RC" -eq 0 ] && ok "unknown profile runs as standard" \
        || bad "unknown profile should exit 0 (rc=$RC)" ;;
    *) bad "unknown profile should run as standard (rc=$RC out=$OUT)" ;;
  esac

  # Empty is how an unset HOOK_PROFILE often surfaces through shell layers;
  # like ${HOOK_PROFILE:-standard} in lib/profile.sh it must default to
  # standard with no unknown-profile warning.
  run_hook "$HOOK" "" "$FIXTURE/big.jsonl"
  case "$OUT" in
    *'"additionalContext":"[suggest-compact]'*)
      [ "$RC" -eq 0 ] && [ -z "$ERR" ] \
        && ok "empty profile: silently runs as standard" \
        || bad "empty profile should exit 0 with no stderr (rc=$RC err=$ERR)" ;;
    *) bad "empty profile should run as standard (rc=$RC out=$OUT)" ;;
  esac
done

echo
echo "----------------------------------------"
echo "PASS=$PASS  FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
