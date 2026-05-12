#!/usr/bin/env bash
# Test for scripts/check-doc-health.sh broken-pointer detection.
# Runs the hook against fixture AGENTS.md/CLAUDE.md in a temp dir and asserts
# that slash commands, brace expansion, and shell snippets are not reported,
# while truly missing path-like references still are.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO_ROOT/scripts/check-doc-health.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat >"$TMP/AGENTS.md" <<'EOF'
# Fixture
- ideas: `idea/`
- existing: `docs/`
EOF

cat >"$TMP/CLAUDE.md" <<'EOF'
# Fixture
- Slash command: `/clear`
- Slash command: `/compact`
- Slash command: `/fix-review`
- Brace expansion: `contexts/{a,b,c}.md`
- Shell snippet: `claude --append-system-prompt "$(cat contexts/dev.md)"`
- Real broken pointer: `nonexistent/dir/file.md`
EOF

# Ensure idea/ and docs/ exist relative to TMP so the fixture refs resolve
mkdir -p "$TMP/idea" "$TMP/docs"

cd "$TMP"
output="$(bash "$HOOK" 2>&1 || true)"

fail=0
assert_no_match() {
  local pattern="$1"
  if grep -qF "$pattern" <<<"$output"; then
    echo "FAIL: expected no match for: $pattern"
    fail=1
  fi
}
assert_match() {
  local pattern="$1"
  if ! grep -qF "$pattern" <<<"$output"; then
    echo "FAIL: expected match for: $pattern"
    fail=1
  fi
}

assert_no_match "Broken pointer in CLAUDE.md: /clear"
assert_no_match "Broken pointer in CLAUDE.md: /compact"
assert_no_match "Broken pointer in CLAUDE.md: /fix-review"
assert_no_match "Broken pointer in CLAUDE.md: contexts/{a,b,c}.md"
assert_no_match 'Broken pointer in CLAUDE.md: claude --append-system-prompt'
assert_match "Broken pointer in CLAUDE.md: nonexistent/dir/file.md"

if [ "$fail" -ne 0 ]; then
  echo "---"
  echo "Actual output:"
  echo "$output"
  exit 1
fi
echo "OK: doc-health pointer check filters slash commands / brace / shell snippets"
