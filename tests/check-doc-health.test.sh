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

# 2a. Default thresholds: warn=14, error=30 (both WARN-only; exit 0)
# 10 days → no message; 20 days → WARN; 35 days → WARN (non-blocking)
output2a="$(cd "$TMP2" && bash "$HOOK" 2>&1)"; rc2a=$?
fail_2a=0

[ "$rc2a" -eq 0 ] || { echo "FAIL [2a]: staleness WARN should not fail (rc=$rc2a)"; fail_2a=1; }
if grep -qF "0001-old" <<<"$output2a"; then
  echo "FAIL [2a]: 10-day ADR should not appear with default thresholds"
  fail_2a=1
fi
if ! grep -q "WARN.*0002-warn" <<<"$output2a"; then
  echo "FAIL [2a]: 20-day ADR should WARN with default thresholds (WARN_DAYS=14)"
  fail_2a=1
fi
if ! grep -q "WARN.*0003-error" <<<"$output2a"; then
  echo "FAIL [2a]: 35-day ADR should WARN (non-blocking) with default thresholds (ERROR_DAYS=30)"
  fail_2a=1
fi
if grep -q "ERROR.*0003-error" <<<"$output2a"; then
  echo "FAIL [2a]: 35-day ADR should not ERROR — staleness is WARN-only"
  fail_2a=1
fi

if [ "$fail_2a" -ne 0 ]; then
  echo "---"
  echo "Actual output [2a]:"
  echo "$output2a"
  exit 1
fi
echo "OK: default thresholds warn=14 / error=30"

# 2b. Env-configurable overrides: DOC_HEALTH_WARN_DAYS=8 DOC_HEALTH_ERROR_DAYS=15
# Reuses the TMP2 fixture from 2a (same three ADRs at 10/20/35 days) but with
# tighter thresholds, to prove the env vars actually move the boundary.
# 10 days → WARN only (>=8, <15); 20 days → WARN (>=15); 35 days → WARN (non-blocking)
output2b="$(cd "$TMP2" && DOC_HEALTH_WARN_DAYS=8 DOC_HEALTH_ERROR_DAYS=15 bash "$HOOK" 2>&1)"; rc2b=$?
fail_2b=0

[ "$rc2b" -eq 0 ] || { echo "FAIL [2b]: staleness WARN should not fail (rc=$rc2b)"; fail_2b=1; }
if ! grep -q "WARN.*0001-old" <<<"$output2b"; then
  echo "FAIL [2b]: 10-day ADR should WARN with DOC_HEALTH_WARN_DAYS=8"
  fail_2b=1
fi
if grep -q "ERROR.*0001-old" <<<"$output2b"; then
  echo "FAIL [2b]: 10-day ADR should not ERROR — staleness is WARN-only"
  fail_2b=1
fi
if ! grep -q "WARN.*0002-warn" <<<"$output2b"; then
  echo "FAIL [2b]: 20-day ADR should WARN with DOC_HEALTH_ERROR_DAYS=15"
  fail_2b=1
fi
if ! grep -q "WARN.*0003-error" <<<"$output2b"; then
  echo "FAIL [2b]: 35-day ADR should WARN (non-blocking) with DOC_HEALTH_ERROR_DAYS=15"
  fail_2b=1
fi

if [ "$fail_2b" -ne 0 ]; then
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
fail_3=0

if grep -qF "0000-adr-template" <<<"$output3"; then
  echo "FAIL [3]: 0000-prefixed ADR template should be excluded from staleness check"
  fail_3=1
fi

if [ "$fail_3" -ne 0 ]; then
  echo "---"
  echo "Actual output [3]:"
  echo "$output3"
  exit 1
fi
echo "OK: 0000-prefixed ADR template excluded from staleness check"

# ── Section 4: -ge boundary fixtures (exactly 13/14/29/30 days) ──────────────
# Locks the documented semantics: diff_days -ge ERROR_DAYS → WARN (non-blocking),
# diff_days -ge WARN_DAYS → WARN, otherwise silent. Default thresholds (14/30).
TMP4="$(mktemp -d)"
CLEANUP_DIRS="$CLEANUP_DIRS $TMP4"

mkdir -p "$TMP4/docs/adr"

DATE_13=$(days_ago 13)
DATE_14=$(days_ago 14)
DATE_29=$(days_ago 29)
DATE_30=$(days_ago 30)

cat >"$TMP4/docs/adr/0001-d13.md" <<EOF
# ADR: 13 days
- Last-validated: $DATE_13
EOF
cat >"$TMP4/docs/adr/0002-d14.md" <<EOF
# ADR: 14 days
- Last-validated: $DATE_14
EOF
cat >"$TMP4/docs/adr/0003-d29.md" <<EOF
# ADR: 29 days
- Last-validated: $DATE_29
EOF
cat >"$TMP4/docs/adr/0004-d30.md" <<EOF
# ADR: 30 days
- Last-validated: $DATE_30
EOF

output4="$(cd "$TMP4" && bash "$HOOK" 2>&1)"; rc4=$?
fail_4=0

[ "$rc4" -eq 0 ] || { echo "FAIL [4]: staleness WARN should not fail (rc=$rc4)"; fail_4=1; }
if grep -qF "0001-d13" <<<"$output4"; then
  echo "FAIL [4]: 13-day ADR should be silent (below WARN_DAYS=14)"
  fail_4=1
fi
if ! grep -q "WARN.*0002-d14" <<<"$output4"; then
  echo "FAIL [4]: exactly 14-day ADR should WARN (-ge WARN_DAYS)"
  fail_4=1
fi
if grep -q "ERROR.*0002-d14" <<<"$output4"; then
  echo "FAIL [4]: exactly 14-day ADR should not ERROR — staleness is WARN-only"
  fail_4=1
fi
if ! grep -q "WARN.*0003-d29" <<<"$output4"; then
  echo "FAIL [4]: exactly 29-day ADR should WARN"
  fail_4=1
fi
if grep -q "ERROR.*0003-d29" <<<"$output4"; then
  echo "FAIL [4]: exactly 29-day ADR should not ERROR — staleness is WARN-only"
  fail_4=1
fi
if ! grep -q "WARN.*0004-d30" <<<"$output4"; then
  echo "FAIL [4]: exactly 30-day ADR should WARN (-ge ERROR_DAYS, non-blocking)"
  fail_4=1
fi
if grep -q "ERROR.*0004-d30" <<<"$output4"; then
  echo "FAIL [4]: exactly 30-day ADR should not ERROR — staleness is WARN-only"
  fail_4=1
fi

if [ "$fail_4" -ne 0 ]; then
  echo "---"
  echo "Actual output [4]:"
  echo "$output4"
  exit 1
fi
echo "OK: -ge boundary semantics — 13d silent, 14d WARN, 29d WARN-not-ERROR, 30d WARN (non-blocking)"

# ── Section 5: non-numeric threshold env falls back, gate stays enabled ──────
# Reuses the TMP2 fixture (0003-error.md is 35 days old). A garbage
# DOC_HEALTH_ERROR_DAYS must not silently disable the staleness gate: the
# script should WARN about the bad value and still fall back to the default
# (30), so the 35-day ADR still warns (non-blocking).
output5="$(cd "$TMP2" && DOC_HEALTH_ERROR_DAYS=abc bash "$HOOK" 2>&1)"; rc5=$?
fail_5=0

[ "$rc5" -eq 0 ] || { echo "FAIL [5]: staleness WARN should not fail (rc=$rc5)"; fail_5=1; }
if ! grep -qi "DOC_HEALTH_ERROR_DAYS" <<<"$output5"; then
  echo "FAIL [5]: non-numeric DOC_HEALTH_ERROR_DAYS should produce a fallback WARN"
  fail_5=1
fi
if ! grep -q "WARN.*0003-error" <<<"$output5"; then
  echo "FAIL [5]: 35-day ADR must still WARN — gate must not be silently disabled"
  fail_5=1
fi
if grep -q "ERROR.*0003-error" <<<"$output5"; then
  echo "FAIL [5]: 35-day ADR should not ERROR — staleness is WARN-only"
  fail_5=1
fi

if [ "$fail_5" -ne 0 ]; then
  echo "---"
  echo "Actual output [5]:"
  echo "$output5"
  exit 1
fi
echo "OK: non-numeric DOC_HEALTH_ERROR_DAYS falls back to default and gate stays enabled"

# ── Section 6: extended pointer scan (skills/rules/contexts) ─────────────────
TMP6="$(mktemp -d)"
CLEANUP_DIRS="$CLEANUP_DIRS $TMP6"

mkdir -p "$TMP6/.claude/skills/demo" "$TMP6/.claude/rules" "$TMP6/contexts" "$TMP6/docs"

cat >"$TMP6/.claude/skills/demo/SKILL.md" <<'EOF'
# Demo skill
- Placeholder: `tasks/<id>-todo.md`
- Glob pattern: `tasks/done/*.md`
- Broken: `missing/skill-ref.md`
- Existing: `docs/`
EOF

cat >"$TMP6/.claude/rules/tasks.md" <<'EOF'
# Rules fixture
- Upsert: `bash scripts/sync-tasks.sh upsert <id> status=...`
- Existing: `docs/`
EOF

cat >"$TMP6/contexts/dev.md" <<'EOF'
# Context fixture
- Brace: `contexts/{dev,review}.md`
- Broken: `missing/context-ref.md`
EOF

output6="$(cd "$TMP6" && bash "$HOOK" 2>&1)"; rc6=$?
fail_6=0

[ "$rc6" -eq 0 ] || { echo "FAIL [6]: pointer WARN should not fail (rc=$rc6)"; fail_6=1; }
assert_no_match6() {
  local pattern="$1"
  if grep -qF "$pattern" <<<"$output6"; then
    echo "FAIL [6]: expected no match for: $pattern"
    fail_6=1
  fi
}
assert_match6() {
  local pattern="$1"
  if ! grep -qF "$pattern" <<<"$output6"; then
    echo "FAIL [6]: expected match for: $pattern"
    fail_6=1
  fi
}

assert_no_match6 "Broken pointer in .claude/skills/demo/SKILL.md: tasks/<id>-todo.md"
assert_no_match6 "Broken pointer in .claude/skills/demo/SKILL.md: tasks/done/*.md"
assert_no_match6 "Broken pointer in .claude/rules/tasks.md: bash scripts/sync-tasks.sh upsert <id> status=..."
assert_no_match6 "Broken pointer in contexts/dev.md: contexts/{dev,review}.md"
assert_match6 "Broken pointer in .claude/skills/demo/SKILL.md: missing/skill-ref.md"
assert_match6 "Broken pointer in contexts/dev.md: missing/context-ref.md"

if [ "$fail_6" -ne 0 ]; then
  echo "---"
  echo "Actual output [6]:"
  echo "$output6"
  exit 1
fi
echo "OK: extended pointer scan hits broken refs and skips glob/placeholder patterns"

# ── Section 7: skip URI, line-number annotations, and example patterns ────────
TMP7="$(mktemp -d)"
CLEANUP_DIRS="$CLEANUP_DIRS $TMP7"

mkdir -p "$TMP7/docs"

cat >"$TMP7/AGENTS.md" <<'EOF'
# Fixture
- URI: `https://github.com/owner/repo/pull/123`
- Branch ellipsis: `feature/...`
- Branch ellipsis: `fix/...`
- Line-number annotation: `missing/file.md:42`
- Example directory: `__tests__/`
- Branch example: `feature/issue_234/custom-notification-timing`
- Branch example: `chore/add-cursor-rules`
- Placeholder: `path/to/file.ext`
- Real broken pointer: `missing/example-ref.md`
- Broken directory pointer: `missing/directory/`
- Broken docs path: `docs/missing-directory/`
EOF

output7="$(cd "$TMP7" && bash "$HOOK" 2>&1)"; rc7=$?
fail_7=0

[ "$rc7" -eq 0 ] || { echo "FAIL [7]: pointer WARN should not fail (rc=$rc7)"; fail_7=1; }
assert_no_match7() {
  local pattern="$1"
  if grep -qF "$pattern" <<<"$output7"; then
    echo "FAIL [7]: expected no match for: $pattern"
    fail_7=1
  fi
}
assert_match7() {
  local pattern="$1"
  if ! grep -qF "$pattern" <<<"$output7"; then
    echo "FAIL [7]: expected match for: $pattern"
    fail_7=1
  fi
}

assert_no_match7 "Broken pointer in AGENTS.md: https://github.com/owner/repo/pull/123"
assert_no_match7 "Broken pointer in AGENTS.md: feature/..."
assert_no_match7 "Broken pointer in AGENTS.md: fix/..."
assert_no_match7 "Broken pointer in AGENTS.md: missing/file.md:42"
assert_no_match7 "Broken pointer in AGENTS.md: __tests__/"
assert_no_match7 "Broken pointer in AGENTS.md: feature/issue_234/custom-notification-timing"
assert_no_match7 "Broken pointer in AGENTS.md: chore/add-cursor-rules"
assert_no_match7 "Broken pointer in AGENTS.md: path/to/file.ext"
assert_match7 "Broken pointer in AGENTS.md: missing/example-ref.md"
assert_match7 "Broken pointer in AGENTS.md: missing/directory/"
assert_match7 "Broken pointer in AGENTS.md: docs/missing-directory/"

if [ "$fail_7" -ne 0 ]; then
  echo "---"
  echo "Actual output [7]:"
  echo "$output7"
  exit 1
fi
echo "OK: pointer scan skips URI / line-number / example patterns"
