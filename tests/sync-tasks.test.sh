#!/usr/bin/env bash
# Test for scripts/sync-tasks.sh — the tasks.jsonl registry helper.
# Drives the script inside a throwaway git repo (it resolves the registry via
# `git rev-parse --git-common-dir`) and asserts the documented behaviors:
#   - round-trip: upsert then get returns the same fields
#   - id-keyed merge: a later partial upsert preserves prior fields and never
#     appends a second line for the same id (the core invariant)
#   - `pr` int-coercion vs leading-zero / numeric-string preservation
#   - null / bool coercion
#   - a malformed registry line is skipped (with a warning), not fatal, and kept

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/sync-tasks.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Throwaway git repo so the script's git-common-dir resolution works.
git -C "$TMP" init -q
cd "$TMP"

REG="$TMP/tasks/tasks.jsonl"

fail=0
assert_match() {
  local pattern="$1" haystack="$2"
  if ! grep -qF "$pattern" <<<"$haystack"; then
    echo "FAIL: expected to find: $pattern"
    fail=1
  fi
}
assert_no_match() {
  local pattern="$1" haystack="$2"
  if grep -qF "$pattern" <<<"$haystack"; then
    echo "FAIL: expected NOT to find: $pattern"
    fail=1
  fi
}

# 1. round-trip
bash "$SCRIPT" upsert t1 title="First task" status=planned todo=tasks/t1-todo.md >/dev/null
got="$(bash "$SCRIPT" get t1)"
assert_match '"id": "t1"' "$got"
assert_match '"title": "First task"' "$got"
assert_match '"status": "planned"' "$got"

# 2. id-keyed merge: partial update keeps prior fields, no duplicate line
bash "$SCRIPT" upsert t1 status=in_progress >/dev/null
got="$(bash "$SCRIPT" get t1)"
assert_match '"title": "First task"' "$got"   # preserved
assert_match '"status": "in_progress"' "$got" # updated
count="$(grep -c '"id": "t1"' "$REG")"
[ "$count" -eq 1 ] || { echo "FAIL: expected 1 line for t1, got $count"; fail=1; }

# 3. pr int-coercion vs string preservation (leading zero / long digit string)
bash "$SCRIPT" upsert t2 pr=12 branch=12345 todo=007 >/dev/null
got="$(bash "$SCRIPT" get t2)"
assert_match '"pr": 12' "$got"        # int, unquoted
assert_no_match '"pr": "12"' "$got"   # not a string
assert_match '"branch": "12345"' "$got"
assert_match '"todo": "007"' "$got"   # leading zero intact

# 4. null / bool coercion
bash "$SCRIPT" upsert t3 note=null status= done=true >/dev/null
got="$(bash "$SCRIPT" get t3)"
assert_match '"note": null' "$got"
assert_match '"status": null' "$got"  # empty string -> null
assert_match '"done": true' "$got"    # bool

# 5. malformed line is skipped (not fatal) and preserved verbatim
printf '%s\n' '{ this is not json' >>"$REG"
out="$(bash "$SCRIPT" upsert t4 status=planned 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: upsert aborted on malformed line (rc=$rc)"; fail=1; }
assert_match "warning: skipping malformed registry line" "$out"
assert_match '{ this is not json' "$(cat "$REG")"   # bad line kept for manual repair
assert_match '"id": "t4"' "$(cat "$REG")"           # new task still written

if [ "$fail" -ne 0 ]; then
  echo "---"
  echo "Registry contents:"
  cat "$REG" 2>/dev/null || true
  exit 1
fi
echo "OK: sync-tasks registry upsert/get — merge, coercion, malformed-line resilience"
