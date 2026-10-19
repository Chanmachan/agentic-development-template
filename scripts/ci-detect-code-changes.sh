#!/usr/bin/env bash
# Emits code=true|false to $GITHUB_OUTPUT. false only when EVERY changed path is
# docs-only; any doubt fails safe to true so tests are never skipped on an
# incomplete or unverifiable change list.
# Inputs (env): GITHUB_EVENT_NAME, BASE_SHA, HEAD_SHA, GITHUB_OUTPUT.
set -uo pipefail

is_docs_only() {
  case "$1" in
    docs/* | idea/* | research/*) return 0 ;;
    */*) return 1 ;;
    *.md) return 0 ;;
    *) return 1 ;;
  esac
}

emit() {
  echo "code=$1" >>"$GITHUB_OUTPUT"
  echo "code=$1 ($2)"
}

fail_safe() {
  echo "::warning::detect-code-changes: $1 - falling back to full CI"
  emit true "$1"
  exit 0
}

is_commit() {
  [ -n "$1" ] && git rev-parse --verify -q "$1^{commit}" >/dev/null 2>&1
}

event="${GITHUB_EVENT_NAME:-}"
base="${BASE_SHA:-}"
head="${HEAD_SHA:-}"

case "$event" in
  pull_request) range="$base...$head" ;;
  push) range="$base..$head" ;;
  *) fail_safe "unexpected event: $event" ;;
esac

case "$base" in
  *[!0]*) ;;
  *) fail_safe "no usable base SHA" ;;
esac
is_commit "$base" || fail_safe "base SHA is not a reachable commit"
is_commit "$head" || fail_safe "head SHA is not a reachable commit"

files=$(git diff --name-only --no-renames "$range") || fail_safe "git diff failed"
[ -z "$files" ] && fail_safe "empty change list"

while IFS= read -r f; do
  if ! is_docs_only "$f"; then
    emit true "code change: $f"
    exit 0
  fi
done <<EOF
$files
EOF

emit false "docs-only change set"
