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

# 4. null / bool coercion + auto-`updated` default
bash "$SCRIPT" upsert t3 note=null status= done=true >/dev/null
got="$(bash "$SCRIPT" get t3)"
assert_match '"note": null' "$got"
assert_match '"status": null' "$got"  # empty string -> null
assert_match '"done": true' "$got"    # bool
assert_match '"updated": "20' "$got"  # updated auto-set to today's YYYY-...

# 5. malformed line is skipped (not fatal) and preserved verbatim
printf '%s\n' '{ this is not json' >>"$REG"
out="$(bash "$SCRIPT" upsert t4 status=planned 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: upsert aborted on malformed line (rc=$rc)"; fail=1; }
assert_match "warning: skipping malformed registry line" "$out"
assert_match '{ this is not json' "$(cat "$REG")"   # bad line kept for manual repair
assert_match '"id": "t4"' "$(cat "$REG")"           # new task still written

# 6. cross-id non-interference: after all the upserts above, t1 is still a single
#    line and the other ids coexist (no id collisions / accidental overwrites).
c1="$(grep -c '"id": "t1"' "$REG")"
[ "$c1" -eq 1 ] || { echo "FAIL: expected 1 line for t1 after all upserts, got $c1"; fail=1; }
for id in t1 t2 t3 t4; do
  [ "$(grep -c "\"id\": \"$id\"" "$REG")" -eq 1 ] || { echo "FAIL: $id not present exactly once"; fail=1; }
done

# 7. lint: valid registry passes
mkdir -p tasks
cat >"$REG" <<'EOF'
{"id": "lint-ok", "status": "planned", "todo": "tasks/lint-ok-todo.md"}
EOF
touch tasks/lint-ok-todo.md
lint_out="$(bash "$SCRIPT" lint 2>&1)"; lint_rc=$?
[ "$lint_rc" -eq 0 ] || { echo "FAIL: lint should pass on valid registry (rc=$lint_rc)"; echo "$lint_out"; fail=1; }
assert_match "OK: 1 tasks" "$lint_out"

# 8. lint: invalid JSON
printf '%s\n' 'not json' >"$REG"
set +e
lint_out="$(bash "$SCRIPT" lint 2>&1)"
lint_rc=$?
set -e
[ "$lint_rc" -eq 1 ] || { echo "FAIL: lint should fail on invalid JSON (rc=$lint_rc)"; fail=1; }
assert_match "FAIL: line 1: invalid JSON" "$lint_out"

# 9. lint: duplicate id
cat >"$REG" <<'EOF'
{"id": "dup", "status": "planned", "todo": "tasks/dup-todo.md"}
{"id": "dup", "status": "planned", "todo": "tasks/dup-todo.md"}
EOF
touch tasks/dup-todo.md
set +e
lint_out="$(bash "$SCRIPT" lint 2>&1)"
lint_rc=$?
set -e
[ "$lint_rc" -eq 1 ] || { echo "FAIL: lint should fail on duplicate id (rc=$lint_rc)"; fail=1; }
assert_match "FAIL: line 2: duplicate id 'dup'" "$lint_out"

# 10. lint: invalid status
cat >"$REG" <<'EOF'
{"id": "bad-status", "status": "wip", "todo": "tasks/bad-status-todo.md"}
EOF
touch tasks/bad-status-todo.md
set +e
lint_out="$(bash "$SCRIPT" lint 2>&1)"
lint_rc=$?
set -e
[ "$lint_rc" -eq 1 ] || { echo "FAIL: lint should fail on invalid status (rc=$lint_rc)"; fail=1; }
assert_match "FAIL: line 1: invalid status 'wip'" "$lint_out"

# 11. lint: status=done requires done path
cat >"$REG" <<'EOF'
{"id": "done-missing", "status": "done", "todo": "tasks/done-missing-todo.md"}
EOF
set +e
lint_out="$(bash "$SCRIPT" lint 2>&1)"
lint_rc=$?
set -e
[ "$lint_rc" -eq 1 ] || { echo "FAIL: lint should fail when status=done without done field (rc=$lint_rc)"; fail=1; }
assert_match "FAIL: line 1: status=done but done field is null/missing" "$lint_out"

# 12. lint: todo file must exist (non-done tasks)
cat >"$REG" <<'EOF'
{"id": "no-todo", "status": "planned", "todo": "tasks/missing-todo.md"}
EOF
set +e
lint_out="$(bash "$SCRIPT" lint 2>&1)"
lint_rc=$?
set -e
[ "$lint_rc" -eq 1 ] || { echo "FAIL: lint should fail when todo file missing (rc=$lint_rc)"; fail=1; }
assert_match "FAIL: line 1: todo is not a file: tasks/missing-todo.md" "$lint_out"

# 13. lint: missing registry file
rm -f "$REG"
lint_out="$(bash "$SCRIPT" lint 2>&1)"; lint_rc=$?
[ "$lint_rc" -eq 0 ] || { echo "FAIL: lint should pass on missing registry (rc=$lint_rc)"; fail=1; }
assert_match "OK: 0 tasks" "$lint_out"

# 14. lint: empty (0-byte) registry file
: >"$REG"
set +e
lint_out="$(bash "$SCRIPT" lint 2>&1)"
lint_rc=$?
set -e
[ "$lint_rc" -eq 0 ] || { echo "FAIL: lint should pass on 0-byte registry (rc=$lint_rc)"; fail=1; }
assert_match "OK: 0 tasks" "$lint_out"

# 15. lint: whitespace-only registry file
printf '\n  \n' >"$REG"
set +e
lint_out="$(bash "$SCRIPT" lint 2>&1)"
lint_rc=$?
set -e
[ "$lint_rc" -eq 0 ] || { echo "FAIL: lint should pass on whitespace-only registry (rc=$lint_rc)"; fail=1; }
assert_match "OK: 0 tasks" "$lint_out"

# 16. lint: non-dict JSON row (null) — must error, not traceback
printf '%s\n' 'null' >"$REG"
set +e
lint_out="$(bash "$SCRIPT" lint 2>&1)"
lint_rc=$?
set -e
[ "$lint_rc" -eq 1 ] || { echo "FAIL: lint should fail on non-dict row (rc=$lint_rc)"; fail=1; }
assert_match "FAIL: line 1: invalid row" "$lint_out"

# 17. lint: missing status vs null status vs invalid enum
cat >"$REG" <<'EOF'
{"id": "no-status", "todo": "tasks/no-status-todo.md"}
{"id": "null-status", "status": null, "todo": "tasks/null-status-todo.md"}
EOF
touch tasks/no-status-todo.md tasks/null-status-todo.md
set +e
lint_out="$(bash "$SCRIPT" lint 2>&1)"
lint_rc=$?
set -e
[ "$lint_rc" -eq 1 ] || { echo "FAIL: lint should fail on missing/null status (rc=$lint_rc)"; fail=1; }
assert_match "FAIL: line 1: missing status" "$lint_out"
assert_match "FAIL: line 2: status is null" "$lint_out"

# 18. lint: non-done row requires non-empty todo; directory path is not a file
mkdir -p tasks
cat >"$REG" <<'EOF'
{"id": "no-todo", "status": "planned"}
{"id": "null-todo", "status": "planned", "todo": null}
{"id": "dir-todo", "status": "planned", "todo": "tasks"}
EOF
set +e
lint_out="$(bash "$SCRIPT" lint 2>&1)"
lint_rc=$?
set -e
[ "$lint_rc" -eq 1 ] || { echo "FAIL: lint should fail on missing/null/dir todo (rc=$lint_rc)"; fail=1; }
assert_match "FAIL: line 1: missing or empty todo" "$lint_out"
assert_match "FAIL: line 2: missing or empty todo" "$lint_out"
assert_match "FAIL: line 3: todo is not a file: tasks" "$lint_out"

# 19. lint: wrong field types must error, not traceback
cat >"$REG" <<'EOF'
{"id": ["x"], "status": "planned", "todo": "tasks/wrong-id-todo.md"}
{"id": "bad-status", "status": [], "todo": "tasks/bad-status-todo.md"}
{"id": "bad-todo", "status": "planned", "todo": {"path": "tasks/bad-todo-todo.md"}}
{"id": "done-bool", "status": "done", "done": true, "todo": "tasks/done-bool-todo.md"}
EOF
touch tasks/wrong-id-todo.md tasks/bad-status-todo.md tasks/bad-todo-todo.md tasks/done-bool-todo.md
set +e
lint_out="$(bash "$SCRIPT" lint 2>&1)"
lint_rc=$?
set -e
[ "$lint_rc" -eq 1 ] || { echo "FAIL: lint should fail on wrong field types (rc=$lint_rc)"; echo "$lint_out"; fail=1; }
assert_match "FAIL: line 1: invalid row (id must be str" "$lint_out"
assert_match "FAIL: line 2: invalid row (status must be str" "$lint_out"
assert_match "FAIL: line 3: invalid row (todo must be str" "$lint_out"
assert_match "FAIL: line 4: invalid row (done must be str" "$lint_out"

# 20. parent: upsert places it right after branch
rm -f "$REG"
bash "$SCRIPT" upsert par title=Parent status=in_progress branch=feature/p todo=tasks/par-todo.md >/dev/null
bash "$SCRIPT" upsert kid title=Kid status=planned parent=par todo=tasks/kid-todo.md >/dev/null
bash "$SCRIPT" upsert dn title=Done status=done done=tasks/done/dn.md >/dev/null
kid_keys="$(python3 -c 'import json,sys; print(",".join(json.loads(sys.argv[1]).keys()))' "$(bash "$SCRIPT" get kid)")"
assert_match "status,branch,parent,pr,todo" "$kid_keys"

# 21. inflight: filters done, fixed key order, tolerates malformed line
printf '%s\n' '{ not json' >>"$REG"
out="$(bash "$SCRIPT" inflight)"
assert_match '"id": "par"' "$out"
assert_match '"id": "kid"' "$out"
assert_no_match '"id": "dn"' "$out"
[ "$(wc -l <<<"$out" | tr -d ' ')" -eq 2 ] || { echo "FAIL: inflight expected 2 lines"; fail=1; }
keys="$(python3 -c 'import json,sys; print(",".join(json.loads(sys.stdin.readline()).keys()))' <<<"$out")"
[ "$keys" = "id,title,status,branch,pr,parent,todo,updated,note" ] || { echo "FAIL: inflight keys: $keys"; fail=1; }

# 22. inflight: missing registry -> no output, exit 0
rm -f "$REG"
out="$(bash "$SCRIPT" inflight)"; rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] || { echo "FAIL: inflight on missing registry (rc=$rc)"; fail=1; }

# 23. lint: parent accepted when valid / null / absent
touch tasks/p-todo.md tasks/c-todo.md tasks/n-todo.md tasks/a-todo.md
cat >"$REG" <<'EOF'
{"id": "p", "status": "planned", "todo": "tasks/p-todo.md"}
{"id": "c", "status": "planned", "parent": "p", "todo": "tasks/c-todo.md"}
{"id": "n", "status": "planned", "parent": null, "todo": "tasks/n-todo.md"}
{"id": "a", "status": "planned", "todo": "tasks/a-todo.md"}
EOF
lint_out="$(bash "$SCRIPT" lint 2>&1)"; lint_rc=$?
[ "$lint_rc" -eq 0 ] || { echo "FAIL: lint should accept valid parent (rc=$lint_rc)"; echo "$lint_out"; fail=1; }

# 24. lint: dangling, self and non-string parent
cat >"$REG" <<'EOF'
{"id": "p", "status": "planned", "todo": "tasks/p-todo.md"}
{"id": "c", "status": "planned", "parent": "ghost", "todo": "tasks/c-todo.md"}
{"id": "n", "status": "planned", "parent": "n", "todo": "tasks/n-todo.md"}
{"id": "a", "status": "planned", "parent": 5, "todo": "tasks/a-todo.md"}
EOF
set +e
lint_out="$(bash "$SCRIPT" lint 2>&1)"
lint_rc=$?
set -e
[ "$lint_rc" -eq 1 ] || { echo "FAIL: lint should reject bad parent (rc=$lint_rc)"; fail=1; }
assert_match "FAIL: line 2: parent 'ghost' is not an existing task id" "$lint_out"
assert_match "FAIL: line 3: parent 'n' is the row itself" "$lint_out"
assert_match "FAIL: line 4: invalid row (parent must be str or null" "$lint_out"

if [ "$fail" -ne 0 ]; then
  echo "---"
  echo "Registry contents:"
  cat "$REG" 2>/dev/null || true
  exit 1
fi
echo "OK: sync-tasks registry upsert/get — merge, coercion, malformed-line resilience, lint"
