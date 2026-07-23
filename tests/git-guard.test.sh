#!/usr/bin/env bash
# Fixture tests for the .claude/.codex git-guard.sh PreToolUse(Bash) hooks.
#
# Both hooks receive Claude-Code-style PreToolUse JSON on stdin
# ({"tool_input":{"command":...}}) and block via exit 2 + stderr message.
# Branch-dependent rules (commit on main, force-push while on main) are
# exercised against throwaway git repos in mktemp dirs, so the test never
# depends on — or mutates — this repo's own checkout.
#
# HOOK_PROFILE is pinned to strict so a developer's exported profile can't
# turn git-guard into a no-op and make assertions pass vacuously; profile
# membership itself (standard on, minimal off) gets its own cases.
#
# Run: bash tests/git-guard.test.sh
set -uo pipefail
export HOOK_PROFILE=strict
unset ALLOW_MAIN_COMMIT 2>/dev/null

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS=("$REPO_ROOT/.claude/hooks/git-guard.sh" "$REPO_ROOT/.codex/hooks/git-guard.sh")

PASS=0
FAIL=0
ok()  { printf '  \033[32mPASS\033[0m %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAIL=$((FAIL + 1)); }

json_cmd() { # $1=shell command -> PreToolUse JSON on stdout
  jq -cn --arg c "$1" '{"tool_input":{"command":$c}}'
}

run_hook() { # $1=hook path $2=cwd $3=raw stdin -> $RC, $OUT
  OUT="$(cd "$2" && printf '%s' "$3" | bash "$1" 2>&1)"
  RC=$?
}

# Fixture repos: one checked out on main, one on a feature branch. No commits
# are needed — `git branch --show-current` works right after `git init -b`.
MAIN_REPO="$(mktemp -d)"
FEAT_REPO="$(mktemp -d)"
trap 'rm -rf "$MAIN_REPO" "$FEAT_REPO"' EXIT
git -C "$MAIN_REPO" init -q -b main
git -C "$FEAT_REPO" init -q -b main
git -C "$FEAT_REPO" switch -q -c feature/x

for HOOK in "${HOOKS[@]}"; do
  label="${HOOK#"$REPO_ROOT"/}"

  if [ ! -f "$HOOK" ]; then
    bad "$label is missing"
    continue
  fi

  echo "$label (block cases, on main)"
  for c in 'git commit --no-verify -m "msg"' \
           'git commit -n -m "msg"' \
           'git commit -m "msg"' \
           'git push --force origin main' \
           'git push -f origin main'; do
    run_hook "$HOOK" "$MAIN_REPO" "$(json_cmd "$c")"
    { [ "$RC" -eq 2 ] && printf '%s' "$OUT" | grep -q 'BLOCKED by git-guard'; } \
      && ok "block: $c" || bad "should block: $c (rc=$RC out=$OUT)"
  done

  echo "$label (block cases, on feature branch)"
  for c in 'git commit --no-verify -m "msg"' \
           'git commit -n' \
           'git push --force origin main'; do
    run_hook "$HOOK" "$FEAT_REPO" "$(json_cmd "$c")"
    [ "$RC" -eq 2 ] && ok "block: $c" || bad "should block: $c (rc=$RC out=$OUT)"
  done

  echo "$label (allow cases)"
  # ALLOW_MAIN_COMMIT=1 escape hatch: as a command prefix and as hook env.
  run_hook "$HOOK" "$MAIN_REPO" "$(json_cmd 'ALLOW_MAIN_COMMIT=1 git commit -m "docs tweak"')"
  [ "$RC" -eq 0 ] && ok "allow: ALLOW_MAIN_COMMIT=1 prefix on main" \
    || bad "ALLOW_MAIN_COMMIT=1 prefix should allow commit on main (rc=$RC out=$OUT)"

  OUT="$(cd "$MAIN_REPO" && printf '%s' "$(json_cmd 'git commit -m "docs tweak"')" | ALLOW_MAIN_COMMIT=1 bash "$HOOK" 2>&1)"
  RC=$?
  [ "$RC" -eq 0 ] && ok "allow: ALLOW_MAIN_COMMIT=1 in hook env on main" \
    || bad "ALLOW_MAIN_COMMIT=1 env should allow commit on main (rc=$RC out=$OUT)"

  for c in 'git commit -m "feat: normal commit"' \
           'git push origin feature/x' \
           'git status && git diff'; do
    run_hook "$HOOK" "$FEAT_REPO" "$(json_cmd "$c")"
    [ "$RC" -eq 0 ] && ok "allow: $c (feature branch)" \
      || bad "should allow on feature branch: $c (rc=$RC out=$OUT)"
  done

  echo "$label (parser bypass regressions)"
  # Each of these was a reproduced bypass of the original split/strip parser:
  # git global options before the subcommand, bundled short-flag clusters,
  # quote-aware separators/options, and the escape hatch read out of quoted
  # message text.
  for c in 'git -c user.email=x@y commit --no-verify -m "msg"' \
           'git commit -qn -m "msg"' \
           'git push -fv origin main'; do
    run_hook "$HOOK" "$MAIN_REPO" "$(json_cmd "$c")"
    [ "$RC" -eq 2 ] && ok "block: $c" || bad "should block: $c (rc=$RC out=$OUT)"
  done

  for c in 'git commit -m "topic; detail" --no-verify' \
           'git commit "--no-verify" -m "msg"'; do
    run_hook "$HOOK" "$FEAT_REPO" "$(json_cmd "$c")"
    [ "$RC" -eq 2 ] && ok "block: $c (feature branch)" \
      || bad "should block regardless of quoting: $c (rc=$RC out=$OUT)"
  done

  # Escape hatch must only count as a real leading env-assignment, never as
  # text inside a quoted argument.
  run_hook "$HOOK" "$MAIN_REPO" "$(json_cmd 'git commit -m "set ALLOW_MAIN_COMMIT=1 for docs"')"
  [ "$RC" -eq 2 ] && ok "block: ALLOW_MAIN_COMMIT=1 inside message text does not unlock main" \
    || bad "escape hatch in message text should not unlock main (rc=$RC out=$OUT)"

  # git -C <dir> moves the commit's repo just like a shell cd — the branch
  # check must follow it (both variants: -C is git-level, not shell-level).
  run_hook "$HOOK" "$FEAT_REPO" "$(json_cmd "git -C $MAIN_REPO commit -m \"msg\"")"
  [ "$RC" -eq 2 ] && ok "block: git -C <main checkout> commit (from feature branch)" \
    || bad "git -C into main checkout should block commit (rc=$RC out=$OUT)"

  # Newline is a command separator like ';' — a git segment after a non-git
  # line must still be scanned.
  run_hook "$HOOK" "$FEAT_REPO" "$(json_cmd 'echo hi
git commit --no-verify')"
  [ "$RC" -eq 2 ] && ok "block: --no-verify in newline-separated second command" \
    || bad "newline-separated git segment should be scanned (rc=$RC out=$OUT)"

  echo "$label (parser false-positive fixes)"
  # -m consumes the next token as the MESSAGE, even if it looks like a flag.
  run_hook "$HOOK" "$FEAT_REPO" "$(json_cmd 'git commit -m --no-verify')"
  [ "$RC" -eq 0 ] && ok "allow: git commit -m --no-verify (flag-looking message arg)" \
    || bad "-m argument must not be scanned as a flag (rc=$RC out=$OUT)"

  # Force-push target comes from the destination refspec, not a substring
  # scan — feature/main-refactor is not main.
  run_hook "$HOOK" "$FEAT_REPO" "$(json_cmd 'git push --force origin feature/main-refactor')"
  [ "$RC" -eq 0 ] && ok "allow: force-push to feature/main-refactor (feature branch)" \
    || bad "force-push to feature/main-refactor should allow (rc=$RC out=$OUT)"

  # …while a refspec whose DESTINATION is main still blocks.
  run_hook "$HOOK" "$FEAT_REPO" "$(json_cmd 'git push --force origin HEAD:main')"
  [ "$RC" -eq 2 ] && ok "block: force-push HEAD:main (feature branch)" \
    || bad "force-push with dst main should block (rc=$RC out=$OUT)"

  echo "$label (no false positives from quoted text)"
  # Flag-looking text inside quotes, and `git` not in command position, must
  # not trigger the block rules.
  for c in 'git commit -m "explain why --no-verify is forbidden"' \
           'git commit -m "mention -n here"' \
           'echo "git commit --no-verify"'; do
    run_hook "$HOOK" "$FEAT_REPO" "$(json_cmd "$c")"
    [ "$RC" -eq 0 ] && ok "allow: $c" || bad "quoted text should not block: $c (rc=$RC out=$OUT)"
  done

  if [ "$label" = ".claude/hooks/git-guard.sh" ]; then
    echo "$label (cd-prefix branch resolution)"
    # The .claude variant resolves the branch in the dir a leading `cd` moves
    # into, so a `cd <feature-worktree> && git commit` issued from a main
    # checkout is not false-blocked …
    run_hook "$HOOK" "$MAIN_REPO" "$(json_cmd "cd $FEAT_REPO && git commit -m \"msg\"")"
    [ "$RC" -eq 0 ] && ok "allow: cd <feature worktree> && git commit (from main checkout)" \
      || bad "cd into feature worktree should not false-block (rc=$RC out=$OUT)"

    # … and the reverse — cd'ing into a main checkout — is still blocked.
    run_hook "$HOOK" "$FEAT_REPO" "$(json_cmd "cd $MAIN_REPO && git commit -m \"msg\"")"
    [ "$RC" -eq 2 ] && ok "block: cd <main checkout> && git commit (from feature branch)" \
      || bad "cd into main checkout should block commit (rc=$RC out=$OUT)"

    # cd is tracked PER SEGMENT, in order — a later feature-worktree cd must
    # not launder an earlier main-worktree commit (reproduced bypass of the
    # original last-cd-wins resolution).
    run_hook "$HOOK" "$FEAT_REPO" "$(json_cmd "cd $MAIN_REPO && git commit -m \"a\" && cd $FEAT_REPO && git commit -m \"b\"")"
    [ "$RC" -eq 2 ] && ok "block: main-worktree commit before a later feature-worktree cd" \
      || bad "per-segment cd tracking should block the first commit (rc=$RC out=$OUT)"
  fi

  echo "$label (fail-open edge cases)"
  run_hook "$HOOK" "$FEAT_REPO" 'not json'
  [ "$RC" -eq 0 ] && ok "malformed stdin fails open (allow)" \
    || bad "malformed stdin should fail open (rc=$RC out=$OUT)"

  run_hook "$HOOK" "$FEAT_REPO" ''
  [ "$RC" -eq 0 ] && ok "empty stdin fails open (allow)" \
    || bad "empty stdin should fail open (rc=$RC out=$OUT)"

  run_hook "$HOOK" "$FEAT_REPO" '{"tool_input":{}}'
  [ "$RC" -eq 0 ] && ok "missing command field fails open (allow)" \
    || bad "missing command should fail open (rc=$RC out=$OUT)"

  echo "$label (profile gating)"
  # standard must include git-guard (this PR's membership change) …
  OUT="$(cd "$MAIN_REPO" && printf '%s' "$(json_cmd 'git commit --no-verify')" | HOOK_PROFILE=standard bash "$HOOK" 2>&1)"
  RC=$?
  [ "$RC" -eq 2 ] && ok "HOOK_PROFILE=standard blocks --no-verify" \
    || bad "HOOK_PROFILE=standard should keep git-guard active (rc=$RC out=$OUT)"

  # … while minimal turns it into a no-op.
  OUT="$(cd "$MAIN_REPO" && printf '%s' "$(json_cmd 'git commit --no-verify')" | HOOK_PROFILE=minimal bash "$HOOK" 2>&1)"
  RC=$?
  [ "$RC" -eq 0 ] && ok "HOOK_PROFILE=minimal skips git-guard" \
    || bad "HOOK_PROFILE=minimal should skip git-guard (rc=$RC out=$OUT)"
done

echo
echo "----------------------------------------"
echo "PASS=$PASS  FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
