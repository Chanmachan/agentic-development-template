#!/usr/bin/env bash
# Fixture tests for .claude/hooks/ (and the mirrored .codex/ ports).
# Run: bash tests/hooks.test.sh
set -uo pipefail
unset SUGGEST_COMPACT_THRESHOLD SUGGEST_COMPACT_WINDOW HOOK_PROFILE

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NODE="${NODE:-node}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
ok()  { printf '  \033[32mPASS\033[0m %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAIL=$((FAIL + 1)); }

# usage_line <input> <cache_read> <cache_creation> [extra_json]
usage_line() {
  printf '{"type":"assistant"%s,"message":{"usage":{"input_tokens":%s,"cache_read_input_tokens":%s,"cache_creation_input_tokens":%s}}}\n' \
    "${4:-}" "$1" "$2" "$3"
}

# filler_line <bytes> — a record with no usage, used to inflate the file size
filler_line() {
  printf '{"type":"user","message":{"content":"%s"}}\n' "$(head -c "$1" /dev/zero | tr '\0' 'x')"
}

run_hook() { # $1=hook path, $2=transcript path -> $RC, $OUT
  OUT="$(printf '{"transcript_path":"%s"}' "$2" | "$NODE" "$REPO_ROOT/$1" 2>/dev/null)"
  RC=$?
}
warned() { echo "$OUT" | grep -q 'suggest-compact'; }

# ---------------------------------------------------------------------------
# suggest-compact.mjs — warn on REAL context tokens, not transcript file size
# ---------------------------------------------------------------------------
for HOOK in .claude/hooks/suggest-compact.mjs .codex/hooks/suggest-compact.mjs; do
  echo "$HOOK"
  # .codex port is strict-only; .claude port runs on standard.
  export HOOK_PROFILE=strict

  T="$TMP/fat-file-small-context.jsonl"
  { filler_line 2000000; usage_line 500 40000 1000; } >"$T"
  run_hook "$HOOK" "$T"
  { [ "$RC" -eq 0 ] && ! warned; } && ok "2MB transcript, 41.5k real tokens -> silent" \
    || bad "file size must not drive the estimate, rc=$RC out=$OUT"

  T="$TMP/over.jsonl"
  usage_line 2000 700000 50000 >"$T"
  run_hook "$HOOK" "$T"
  { [ "$RC" -eq 0 ] && warned; } && ok "752k real tokens -> warns" \
    || bad "should warn over default threshold, rc=$RC out=$OUT"
  echo "$OUT" | grep -q '752,000' && ok "reports the real token total" \
    || bad "expected 752,000 in message, out=$OUT"

  T="$TMP/under-default.jsonl"
  usage_line 0 650000 0 >"$T"
  run_hook "$HOOK" "$T"
  { [ "$RC" -eq 0 ] && ! warned; } && ok "650k -> silent (default threshold 700k)" \
    || bad "650k must not warn under a 1M window, rc=$RC out=$OUT"

  T="$TMP/over-default.jsonl"
  usage_line 0 750000 0 >"$T"
  run_hook "$HOOK" "$T"
  { [ "$RC" -eq 0 ] && warned; } && ok "750k -> warns (default threshold 700k)" \
    || bad "750k must warn, rc=$RC out=$OUT"

  export SUGGEST_COMPACT_THRESHOLD=100000
  run_hook "$HOOK" "$TMP/fat-file-small-context.jsonl"
  { [ "$RC" -eq 0 ] && ! warned; } && ok "threshold override honored (41.5k < 100k)" \
    || bad "override should keep it silent, rc=$RC out=$OUT"
  export SUGGEST_COMPACT_THRESHOLD=40000
  run_hook "$HOOK" "$TMP/fat-file-small-context.jsonl"
  { [ "$RC" -eq 0 ] && warned; } && ok "threshold override honored (41.5k > 40k)" \
    || bad "override should warn, rc=$RC out=$OUT"
  unset SUGGEST_COMPACT_THRESHOLD

  export SUGGEST_COMPACT_THRESHOLD=not-a-number
  run_hook "$HOOK" "$TMP/fat-file-small-context.jsonl"
  { [ "$RC" -eq 0 ] && ! warned; } && ok "garbage threshold falls back to the default" \
    || bad "NaN threshold must not warn on everything, rc=$RC out=$OUT"
  unset SUGGEST_COMPACT_THRESHOLD

  export SUGGEST_COMPACT_WINDOW=200000
  T="$TMP/small-window.jsonl"
  usage_line 0 150000 0 >"$T"
  run_hook "$HOOK" "$T"
  { [ "$RC" -eq 0 ] && warned; } && ok "window override rescales the default (150k > 70% of 200k)" \
    || bad "200k window should warn at 150k, rc=$RC out=$OUT"
  unset SUGGEST_COMPACT_WINDOW

  T="$TMP/after-compact.jsonl"
  { usage_line 0 900000 0; usage_line 0 30000 0; } >"$T"
  run_hook "$HOOK" "$T"
  { [ "$RC" -eq 0 ] && ! warned; } && ok "post-compact drop -> silent (last usage, not peak)" \
    || bad "should read the latest usage, rc=$RC out=$OUT"

  T="$TMP/sidechain.jsonl"
  { usage_line 0 30000 0; usage_line 0 900000 0 ',"isSidechain":true'; } >"$T"
  run_hook "$HOOK" "$T"
  { [ "$RC" -eq 0 ] && ! warned; } && ok "sidechain usage ignored" \
    || bad "subagent usage must not count, rc=$RC out=$OUT"

  T="$TMP/big-tail.jsonl"
  { usage_line 0 750000 0; filler_line 900000; } >"$T"
  run_hook "$HOOK" "$T"
  { [ "$RC" -eq 0 ] && warned; } && ok "usage found behind a 900KB trailing record" \
    || bad "tail window too small, rc=$RC out=$OUT"

  T="$TMP/no-usage.jsonl"
  filler_line 100 >"$T"
  run_hook "$HOOK" "$T"
  { [ "$RC" -eq 0 ] && ! warned; } && ok "no usage record -> silent" \
    || bad "should fail quiet, rc=$RC out=$OUT"

  run_hook "$HOOK" "$TMP/does-not-exist.jsonl"
  { [ "$RC" -eq 0 ] && ! warned; } && ok "missing transcript -> silent" \
    || bad "should fail quiet, rc=$RC out=$OUT"

  OUT="$(printf 'not json' | "$NODE" "$REPO_ROOT/$HOOK" 2>/dev/null)"; RC=$?
  { [ "$RC" -eq 0 ] && ! warned; } && ok "malformed stdin -> silent" \
    || bad "should fail quiet, rc=$RC out=$OUT"

  export HOOK_PROFILE=minimal
  run_hook "$HOOK" "$TMP/over.jsonl"
  { [ "$RC" -eq 0 ] && ! warned; } && ok "HOOK_PROFILE=minimal -> silent" \
    || bad "minimal must no-op, rc=$RC out=$OUT"
  unset HOOK_PROFILE
done

# ---------------------------------------------------------------------------
# git-guard.sh — block main commits / --no-verify / force-push at main, and
# judge the branch where the git command will actually run (the `cd` chain),
# without letting quoted text move that judgement.
# ---------------------------------------------------------------------------

# A throwaway repo on a feature branch, standing in for a sibling worktree.
GG_WT="$TMP/gg-worktree"
mkdir -p "$GG_WT"
git -C "$GG_WT" init -q
git -C "$GG_WT" config user.email hooks@test
git -C "$GG_WT" config user.name hooks
git -C "$GG_WT" commit -q --allow-empty -m init
git -C "$GG_WT" checkout -q -b feature/probe

# A throwaway repo on main, standing in for the checkout the hook runs from.
GG_MAIN="$TMP/gg-main"
mkdir -p "$GG_MAIN"
git -C "$GG_MAIN" init -q -b main
git -C "$GG_MAIN" config user.email hooks@test
git -C "$GG_MAIN" config user.name hooks
git -C "$GG_MAIN" commit -q --allow-empty -m init

guard() { # $1=hook path, $2=command string -> $RC (run from a main checkout)
  OUT="$(cd "$GG_MAIN" && printf '{"tool_input":{"command":%s}}' \
    "$(printf '%s' "$2" | jq -Rs .)" | bash "$REPO_ROOT/$1" 2>&1)"
  RC=$?
}
blocked() { [ "$RC" -eq 2 ]; }

for HOOK in .claude/hooks/git-guard.sh .codex/hooks/git-guard.sh; do
  echo "$HOOK"
  export HOOK_PROFILE=strict

  guard "$HOOK" "git commit -m x"
  blocked && ok "plain commit on main -> blocked" \
    || bad "main commit must block, rc=$RC out=$OUT"

  guard "$HOOK" "git commit --no-verify -m x"
  blocked && ok "--no-verify -> blocked" || bad "must block, rc=$RC out=$OUT"

  guard "$HOOK" "git push --force origin main"
  blocked && ok "force-push at main -> blocked" || bad "must block, rc=$RC out=$OUT"

  # The false block this hook existed to fix: the commit lands in a sibling
  # worktree on a feature branch, not in the checkout the hook runs from.
  guard "$HOOK" "cd $GG_WT && git commit -m x"
  { ! blocked; } && ok "cd <feature worktree> && commit -> allowed" \
    || bad "false block on worktree commit, rc=$RC out=$OUT"

  # Relative `cd`s must compose, or the same false block comes back.
  guard "$HOOK" "cd $(dirname "$GG_WT") && cd $(basename "$GG_WT") && git commit -m x"
  { ! blocked; } && ok "relative cd chain composes -> allowed" \
    || bad "cd chain not composed, rc=$RC out=$OUT"

  # A path inside the commit message must NOT move the branch lookup, or the
  # guard can be talked out of protecting main.
  guard "$HOOK" "git commit -m 'ported from $GG_WT'"
  blocked && ok "path quoted in message does not move the lookup -> blocked" \
    || bad "quoted path moved branch resolution, rc=$RC out=$OUT"

  # Unresolvable targets must fail closed, not fall through to allow.
  guard "$HOOK" "cd $TMP/gg-does-not-exist && git commit -m x"
  blocked && ok "nonexistent cd target -> fails closed" \
    || bad "must fail closed, rc=$RC out=$OUT"

  guard "$HOOK" "cd && git commit -m x"
  blocked && ok "bare cd -> fails closed" || bad "must fail closed, rc=$RC out=$OUT"

  # Escape hatch and non-git commands stay unaffected.
  guard "$HOOK" "ALLOW_MAIN_COMMIT=1 git commit -m x"
  { ! blocked; } && ok "ALLOW_MAIN_COMMIT=1 -> allowed" \
    || bad "override ignored, rc=$RC out=$OUT"

  guard "$HOOK" "echo 'git commit --no-verify'"
  { ! blocked; } && ok "git mentioned inside echo -> allowed" \
    || bad "false positive on quoted mention, rc=$RC out=$OUT"

  unset HOOK_PROFILE
done

# ---------------------------------------------------------------------------
# suggest-compact profile gate — the two ports are deliberately NOT identical
# (and so are excluded from tests/harness-parity.test.sh): .claude runs on
# standard and strict, .codex on strict only. The suite above pins both to
# strict, which would hide a regression in exactly that difference.
# ---------------------------------------------------------------------------
echo "suggest-compact profile gate"

T="$TMP/profile-gate.jsonl"
usage_line 0 750000 0 >"$T"

export HOOK_PROFILE=standard
run_hook .claude/hooks/suggest-compact.mjs "$T"
{ [ "$RC" -eq 0 ] && warned; } && ok ".claude at standard -> warns" \
  || bad ".claude must run on standard, rc=$RC out=$OUT"

run_hook .codex/hooks/suggest-compact.mjs "$T"
{ [ "$RC" -eq 0 ] && ! warned; } && ok ".codex at standard -> silent (strict-only port)" \
  || bad ".codex must be gated off on standard, rc=$RC out=$OUT"
unset HOOK_PROFILE

echo
printf 'passed %d, failed %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
