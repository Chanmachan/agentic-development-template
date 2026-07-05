#!/usr/bin/env bash
# Test for the repo's top-level .gitignore.
# Copies the real .gitignore into a throwaway git repo and asserts, via
# `git check-ignore`, that secrets/env files, direnv files, local task
# tracking, and personal-scope notes are ignored, while example/template
# files and ordinary source files are not.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GITIGNORE="$REPO_ROOT/.gitignore"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

git -C "$TMP" init -q
cp "$GITIGNORE" "$TMP/.gitignore"
cd "$TMP"

fail=0

assert_ignored() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  : >"$path"
  if git check-ignore -q "$path"; then
    echo "OK: $path is ignored"
  else
    echo "FAIL: expected $path to be ignored"
    fail=1
  fi
}

assert_not_ignored() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  : >"$path"
  if git check-ignore -q "$path"; then
    echo "FAIL: expected $path to NOT be ignored"
    fail=1
  else
    echo "OK: $path is not ignored"
  fi
}

assert_ignored ".env"
assert_ignored "sub/dir/.env.production"
assert_not_ignored ".env.example"
assert_ignored ".envrc"
assert_ignored "tasks/x.md"
assert_ignored "CLAUDE.local.md"
assert_not_ignored "src/app.ts"

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "OK: .gitignore covers secrets/.envrc/tasks/local-notes and spares examples/source"
