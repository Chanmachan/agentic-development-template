#!/usr/bin/env bash
# Test for scripts/check-doc-health.sh broken-pointer detection.
# Runs the hook against fixture AGENTS.md/CLAUDE.md in a temp dir and asserts
# that slash commands, brace expansion, and shell snippets are not reported,
# while truly missing path-like references still are.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO_ROOT/scripts/check-doc-health.sh"

CLEANUP_DIRS=""
cleanup() { rm -rf $CLEANUP_DIRS; }
trap cleanup EXIT

TMP="$(mktemp -d)"
CLEANUP_DIRS="$CLEANUP_DIRS $TMP"

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

# ── Section 2: ADR staleness thresholds ──────────────────────────────────────
# Set up a fixture docs/adr/ with ADRs at known ages.

TMP2="$(mktemp -d)"
CLEANUP_DIRS="$CLEANUP_DIRS $TMP2"

mkdir -p "$TMP2/docs/adr"

# Helper: generate a date N days ago in YYYY-MM-DD format (bash 3.2 compatible)
days_ago() {
  local n="$1"
  if date -v -"${n}"d +%Y-%m-%d 2>/dev/null; then
    return
  fi
  # GNU date fallback
  date -d "$n days ago" +%Y-%m-%d
}

DATE_10=$(days_ago 10)
DATE_20=$(days_ago 20)
DATE_35=$(days_ago 35)

cat >"$TMP2/docs/adr/0001-old.md" <<EOF
# ADR 0001
- Last-validated: $DATE_10
EOF

cat >"$TMP2/docs/adr/0002-warn.md" <<EOF
# ADR 0002
- Last-validated: $DATE_20
EOF

cat >"$TMP2/docs/adr/0003-error.md" <<EOF
# ADR 0003
- Last-validated: $DATE_35
EOF

# 2a. Default thresholds: warn=14, error=30
# 10 days → no message; 20 days → WARN; 35 days → ERROR
output2a="$(cd "$TMP2" && bash "$HOOK" 2>&1 || true)"
fail2=0

if grep -qF "0001-old" <<<"$output2a"; then
  echo "FAIL [2a]: 10-day ADR should not appear with default thresholds"
  fail2=1
fi
if ! grep -q "WARN.*0002-warn" <<<"$output2a"; then
  echo "FAIL [2a]: 20-day ADR should WARN with default thresholds (WARN_DAYS=14)"
  fail2=1
fi
if ! grep -q "ERROR.*0003-error" <<<"$output2a"; then
  echo "FAIL [2a]: 35-day ADR should ERROR with default thresholds (ERROR_DAYS=30)"
  fail2=1
fi

if [ "$fail2" -ne 0 ]; then
  echo "---"
  echo "Actual output [2a]:"
  echo "$output2a"
  exit 1
fi
echo "OK: default thresholds warn=14 / error=30"

# 2b. Env-configurable overrides: DOC_HEALTH_WARN_DAYS=8 DOC_HEALTH_ERROR_DAYS=15
# 10 days → WARN (>=8); 20 days → ERROR (>=15); 35 days → ERROR
output2b="$(cd "$TMP2" && DOC_HEALTH_WARN_DAYS=8 DOC_HEALTH_ERROR_DAYS=15 bash "$HOOK" 2>&1 || true)"
fail3=0

if ! grep -q "WARN.*0001-old\|ERROR.*0001-old" <<<"$output2b"; then
  echo "FAIL [2b]: 10-day ADR should WARN with DOC_HEALTH_WARN_DAYS=8"
  fail3=1
fi
if ! grep -q "ERROR.*0002-warn" <<<"$output2b"; then
  echo "FAIL [2b]: 20-day ADR should ERROR with DOC_HEALTH_ERROR_DAYS=15"
  fail3=1
fi

if [ "$fail3" -ne 0 ]; then
  echo "---"
  echo "Actual output [2b]:"
  echo "$output2b"
  exit 1
fi
echo "OK: env-override thresholds DOC_HEALTH_WARN_DAYS=8 DOC_HEALTH_ERROR_DAYS=15"

# ── Section 3: 0000-prefixed ADRs excluded from staleness check ───────────────
TMP3="$(mktemp -d)"
CLEANUP_DIRS="$CLEANUP_DIRS $TMP3"

mkdir -p "$TMP3/docs/adr"

DATE_OLD=$(days_ago 60)
cat >"$TMP3/docs/adr/0000-adr-template.md" <<EOF
# ADR 0000: Template
- Last-validated: $DATE_OLD
EOF

output3="$(cd "$TMP3" && bash "$HOOK" 2>&1 || true)"
fail4=0

if grep -qF "0000-adr-template" <<<"$output3"; then
  echo "FAIL [3]: 0000-prefixed ADR template should be excluded from staleness check"
  fail4=1
fi

if [ "$fail4" -ne 0 ]; then
  echo "---"
  echo "Actual output [3]:"
  echo "$output3"
  exit 1
fi
echo "OK: 0000-prefixed ADR template excluded from staleness check"
