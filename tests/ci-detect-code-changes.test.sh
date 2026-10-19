#!/usr/bin/env bash
# Test for scripts/ci-detect-code-changes.sh.
# Builds throwaway git repos and asserts the code=true|false decision for
# docs-only, mixed, rename, root-vs-nested markdown, push, and fail-safe cases.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/ci-detect-code-changes.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0
ZERO="0000000000000000000000000000000000000000"

g() { git -C "$REPO" -c user.email=t@example.com -c user.name=t "$@"; }

new_repo() {
  REPO="$(mktemp -d "$TMP/repo.XXXXXX")"
  git -C "$REPO" init -q -b main
  mkdir -p "$REPO/scripts" "$REPO/docs" "$REPO/foo"
  echo 'echo hi' >"$REPO/scripts/x.sh"
  echo 'a' >"$REPO/docs/a.md"
  echo 'r' >"$REPO/README.md"
  echo 'f' >"$REPO/foo/README.md"
  g add -A
  g commit -q -m "chore: base"
  BASE="$(g rev-parse HEAD)"
}

commit_all() {
  g add -A
  g commit -q -m "chore: change"
  HEAD_="$(g rev-parse HEAD)"
}

run_detect() {
  local event="$1" base="$2" head="$3"
  OUTFILE="$TMP/github_output"
  : >"$OUTFILE"
  (cd "$REPO" && GITHUB_EVENT_NAME="$event" BASE_SHA="$base" HEAD_SHA="$head" GITHUB_OUTPUT="$OUTFILE" bash "$SCRIPT" >"$TMP/stdout" 2>&1)
}

assert_code() {
  local label="$1" want="$2"
  local got
  got="$(grep '^code=' "$OUTFILE" | tail -1 || true)"
  if [ "$got" = "code=$want" ]; then
    echo "OK: $label -> code=$want"
  else
    echo "FAIL: $label: expected code=$want, got '${got:-<none>}'"
    cat "$TMP/stdout"
    fail=1
  fi
}

new_repo
echo 'b' >>"$REPO/docs/a.md"
echo 'new' >"$REPO/docs/b.md"
echo 'r2' >>"$REPO/README.md"
mkdir -p "$REPO/idea" "$REPO/research"
echo 'i' >"$REPO/idea/i.txt"
echo 'r' >"$REPO/research/r.txt"
commit_all
run_detect pull_request "$BASE" "$HEAD_"
assert_code "docs-only PR" false

new_repo
echo 'b' >>"$REPO/docs/a.md"
echo 'echo bye' >>"$REPO/scripts/x.sh"
commit_all
run_detect pull_request "$BASE" "$HEAD_"
assert_code "docs plus one code file" true

new_repo
g mv scripts/x.sh docs/x.sh
commit_all
run_detect pull_request "$BASE" "$HEAD_"
assert_code "rename scripts/x.sh to docs/x.sh" true

new_repo
echo 'r2' >>"$REPO/README.md"
commit_all
run_detect pull_request "$BASE" "$HEAD_"
assert_code "root README.md only" false

new_repo
echo 'f2' >>"$REPO/foo/README.md"
commit_all
run_detect pull_request "$BASE" "$HEAD_"
assert_code "nested foo/README.md" true

new_repo
echo 'b' >>"$REPO/docs/a.md"
commit_all
run_detect push "$BASE" "$HEAD_"
assert_code "push docs-only" false

new_repo
echo 'echo bye' >>"$REPO/scripts/x.sh"
commit_all
run_detect push "$BASE" "$HEAD_"
assert_code "push with code change" true

new_repo
echo 'b' >>"$REPO/docs/a.md"
commit_all
run_detect push "$ZERO" "$HEAD_"
assert_code "push with all-zero before" true

run_detect push "" "$HEAD_"
assert_code "push with empty before" true

run_detect workflow_dispatch "$BASE" "$HEAD_"
assert_code "unknown event" true

run_detect pull_request "$BASE" "$HEAD_"
assert_code "pull_request docs-only after fail-safe cases" false

run_detect pull_request "1111111111111111111111111111111111111111" "$HEAD_"
assert_code "unreachable base SHA" true

run_detect pull_request "$BASE" "1111111111111111111111111111111111111111"
assert_code "unreachable head SHA" true

run_detect pull_request "$HEAD_" "$HEAD_"
assert_code "empty change list" true

if [ "$fail" -ne 0 ]; then
  echo "ci-detect-code-changes tests FAILED"
  exit 1
fi
echo "ci-detect-code-changes tests passed"
