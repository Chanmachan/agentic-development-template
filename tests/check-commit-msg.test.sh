#!/usr/bin/env bash
# Test for scripts/check-commit-msg.sh.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/check-commit-msg.sh"

PASS=0
FAIL=0
CLEANUP_DIRS=""
cleanup() { rm -rf $CLEANUP_DIRS; }
trap cleanup EXIT

TMP="$(mktemp -d)"
CLEANUP_DIRS="$CLEANUP_DIRS $TMP"
PLAIN="$TMP/plain"
mkdir -p "$PLAIN"
(cd "$PLAIN" && git init -q)

ok() { echo "PASS: $1"; PASS=$((PASS + 1)); }
ng() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

# run_case <name> <expected exit 0|1> <printf-format message> [grep pattern for output]
run_case() {
  local name=$1 expected=$2 content=$3 pattern=${4:-} dir=${5:-$PLAIN}
  local f="$TMP/msg" out rc
  printf "$content" >"$f"
  out="$(cd "$dir" && bash "$SCRIPT" "$f" 2>&1)"
  rc=$?
  if [ "$expected" = 0 ] && [ "$rc" -ne 0 ]; then ng "$name (expected accept, got rc=$rc: $out)"; return; fi
  if [ "$expected" = 1 ] && [ "$rc" -ne 1 ]; then ng "$name (expected reject, got rc=$rc)"; return; fi
  if [ -n "$pattern" ] && ! printf '%s' "$out" | grep -qE "$pattern"; then
    ng "$name (output missing /$pattern/: $out)"
    return
  fi
  ok "$name"
}

run_case "valid single line" 0 'feat: add thing\n'
run_case "valid without trailing newline" 0 'fix: correct thing'
run_case "trailing blank lines" 0 'docs: update readme\n\n  \n\n'
run_case "bad prefix" 1 'feature: add thing\n' 'must follow'
run_case "empty description" 1 'feat: \n' 'must follow'
run_case "scope is not allowed" 1 'feat(scope): add thing\n' 'must follow'
run_case "bang is not allowed" 1 'feat!: add thing\n' 'must follow'
run_case "body line" 1 'feat: add thing\n\nmore detail\n' 'single line'
run_case "footer line" 1 'feat: add thing\nCloses: #1\n' 'single line'
run_case "Merge with body" 0 "Merge branch 'a' into b\n\nSomething\n"
run_case "Revert with body" 0 'Revert "feat: add thing"\n\nThis reverts commit abc.\n'
run_case "editor comment lines" 0 'feat: add thing\n\n# Please enter the commit message for your changes.\n#\n# On branch x\n'
run_case "comment lines before blank" 0 'feat: add thing\n# hint\n\n'
run_case "scissors then diff" 0 'feat: add thing\n\n# ------------------------ >8 ------------------------\n# Do not modify or remove the line above.\ndiff --git a/x b/x\n+added\n'
run_case "body before scissors still rejected" 1 'feat: add thing\nbody\n# ------------------------ >8 ------------------------\ndiff --git a/x b/x\n' 'single line'
run_case "plain text after comment lines rejected" 1 'feat: add thing\nplain text\n# c\n' 'single line'
run_case "Co-Authored-By" 1 'feat: add thing\n\nCo-Authored-By: A <a@example.com>\n' 'agent trailers'
run_case "co-authored-by lowercase" 1 'feat: add thing\nco-authored-by: A <a@example.com>\n' 'agent trailers'
run_case "Claude-Session" 1 'feat: add thing\n\nClaude-Session: abc\n' 'agent trailers'
run_case "session URL" 1 'feat: add thing\n\nhttps://claude.ai/code/session_abc123\n' 'agent trailers'

CUSTOM="$TMP/custom"
mkdir -p "$CUSTOM"
(cd "$CUSTOM" && git init -q && git config core.commentChar ';')
run_case "custom commentChar honoured" 0 'feat: add thing\n\n; Please enter the commit message\n; more\n' '' "$CUSTOM"
run_case "default # is content under custom commentChar" 1 'feat: add thing\n# not a comment here\n' 'single line' "$CUSTOM"

AUTO="$TMP/auto"
mkdir -p "$AUTO"
(cd "$AUTO" && git init -q && git config core.commentChar auto)
run_case "commentChar auto falls back to #" 0 'feat: add thing\n# hint\n' '' "$AUTO"

out="$(bash "$SCRIPT" 2>&1)"
rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'usage'; then ok "missing argument fails with usage"; else ng "missing argument (rc=$rc: $out)"; fi

E2E="$TMP/e2e"
mkdir -p "$E2E"
(
  cd "$E2E"
  git init -q
  git config user.email t@example.com
  git config user.name t
  git config commit.gpgsign false
  printf '#!/bin/sh\nexec bash "%s" "$1"\n' "$SCRIPT" >.git/hooks/commit-msg
  chmod +x .git/hooks/commit-msg
  echo a >a.txt
  git add a.txt
  printf 'feat: add a\n\n# Please enter the commit message for your changes.\n#\n' >"$TMP/e2e.msg"
)
if (cd "$E2E" && git commit -q --cleanup=verbatim -F "$TMP/e2e.msg" >/dev/null 2>&1); then
  ok "e2e: commit with comment lines passes through hook"
else
  ng "e2e: commit with comment lines passes through hook"
fi
(cd "$E2E" && echo b >b.txt && git add b.txt)
printf 'feat: add b\n\nbody\n' >"$TMP/e2e2.msg"
if (cd "$E2E" && git commit -q -F "$TMP/e2e2.msg" >/dev/null 2>&1); then
  ng "e2e: body is rejected by hook"
else
  ok "e2e: body is rejected by hook"
fi

echo "---"
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
