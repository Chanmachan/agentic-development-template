#!/usr/bin/env bash
# Fixture tests for the .claude/.codex stop-check.sh gate.
#
# Both copies read Claude-style Stop JSON on stdin and block by printing
# {"decision":"block","reason":...} (tests/harness-parity.test.sh keeps them
# byte-identical, but every case still runs against both copies to catch a
# drifted pair before parity does).
#
# Determinism: the pnpm toolchain is shadowed by a fake on a temp PATH, and
# each case runs inside a seeded mktemp git repo so both the language routing
# and the docs-only skip classification are fixed by the fixture, not the
# host cwd.
#
# HOOK_PROFILE is pinned to strict so a developer's exported profile can't
# turn stop-check into a no-op and make assertions pass vacuously.
#
# Run: bash tests/stop-check.test.sh
set -uo pipefail
export HOOK_PROFILE=strict

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS=("$REPO_ROOT/.claude/hooks/stop-check.sh" "$REPO_ROOT/.codex/hooks/stop-check.sh")

PASS=0
FAIL=0
ok()  { printf '  \033[32mPASS\033[0m %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAIL=$((FAIL + 1)); }

git_quiet() { git -c user.email=test@example.com -c user.name=test "$@" >/dev/null 2>&1; }

# Fixture: a committed pnpm project whose fake pnpm prints 40 numbered lines
# (OUT_01..OUT_40) before exiting $1, so the last-30-lines truncation of the
# block reason is observable (OUT_11..OUT_40 kept, OUT_01..OUT_10 cut).
make_fixture() { # $1=pnpm exit code
  local dir; dir="$(mktemp -d)"
  echo '{}' > "$dir/package.json"; : > "$dir/pnpm-lock.yaml"
  mkdir "$dir/bin"
  printf '#!/usr/bin/env bash\nfor i in $(seq -w 1 40); do echo "OUT_$i"; done\nexit %s\n' "$1" > "$dir/bin/pnpm"
  chmod +x "$dir/bin/pnpm"
  git_quiet -C "$dir" init
  git_quiet -C "$dir" add -A
  git_quiet -C "$dir" commit -m fixture
  echo "$dir"
}

run_stop() { # $1=hook path $2=fixture dir $3=json -> $RC, $OUT
  OUT="$(cd "$2" && printf '%s' "$3" | PATH="$2/bin:$PATH" bash "$1" 2>/dev/null)"
  RC=$?
}
is_block() { echo "$OUT" | grep -qE '"decision": *"block"'; }

for HOOK in "${HOOKS[@]}"; do
  label="${HOOK#"$REPO_ROOT"/}"
  echo "$label"

  # --- failing checks with a pending code change: block + output tail -------
  FAILDIR="$(make_fixture 1)"
  echo 'x' > "$FAILDIR/src.ts"

  run_stop "$HOOK" "$FAILDIR" '{"stop_hook_active":true}'
  { [ "$RC" -eq 0 ] && [ -z "$OUT" ]; } && ok "stop_hook_active short-circuits" || bad "stop_hook_active should be silent (rc=$RC out=$OUT)"

  run_stop "$HOOK" "$FAILDIR" '{"stop_hook_active":false}'
  { is_block && echo "$OUT" | grep -q 'Do not stop yet'; } && ok "failing checks block" || bad "failing should block (out=$OUT)"
  echo "$OUT" | grep -q 'lint failed' && ok "block reason names the failing check" || bad "reason should name failing check (out=$OUT)"
  { echo "$OUT" | grep -q 'OUT_40' && echo "$OUT" | grep -q 'OUT_11'; } && ok "block reason includes failing output tail" || bad "reason should include output tail (out=$OUT)"
  echo "$OUT" | grep -q 'OUT_10' && bad "reason should truncate to last 30 lines (OUT_10 leaked)" || ok "output tail is truncated to last 30 lines"
  echo "$OUT" | grep -q '設定を緩め' && ok "block reason forbids loosening configs/deleting tests" || bad "reason should forbid config loosening (out=$OUT)"
  rm -rf "$FAILDIR"

  # --- clean tree / docs-only changes: skip the gate entirely ---------------
  SKIPDIR="$(make_fixture 1)"
  run_stop "$HOOK" "$SKIPDIR" '{"stop_hook_active":false}'
  { [ "$RC" -eq 0 ] && [ -z "$OUT" ]; } && ok "clean tree skips checks" || bad "clean tree should skip (rc=$RC out=$OUT)"

  mkdir -p "$SKIPDIR/docs" "$SKIPDIR/tasks"
  echo 'n' > "$SKIPDIR/note.md"
  echo 'n' > "$SKIPDIR/docs/adr.txt"
  echo 'n' > "$SKIPDIR/tasks/todo.txt"
  run_stop "$HOOK" "$SKIPDIR" '{"stop_hook_active":false}'
  { [ "$RC" -eq 0 ] && [ -z "$OUT" ]; } && ok "md/docs/tasks-only changes skip checks" || bad "docs-only should skip (rc=$RC out=$OUT)"

  echo 'x' > "$SKIPDIR/src.ts"
  run_stop "$HOOK" "$SKIPDIR" '{"stop_hook_active":false}'
  is_block && ok "docs + one code change still runs the gate" || bad "mixed change should block (out=$OUT)"
  rm -rf "$SKIPDIR"

  # --- porcelain edge cases: renames and quote-worthy paths -----------------
  # A staged rename reports two paths (dest + source); a code→docs rename
  # removes code, so classifying only the destination would wrongly skip.
  RENDIR="$(make_fixture 1)"
  echo 'x' > "$RENDIR/src.ts"
  git_quiet -C "$RENDIR" add -A
  git_quiet -C "$RENDIR" commit -m seed
  mkdir -p "$RENDIR/docs"
  git_quiet -C "$RENDIR" mv src.ts docs/src.md
  run_stop "$HOOK" "$RENDIR" '{"stop_hook_active":false}'
  is_block && ok "code-to-docs rename still runs the gate" || bad "code-to-docs rename should block (out=$OUT)"
  git_quiet -C "$RENDIR" commit -m mv1
  echo 'n' > "$RENDIR/note.md"
  git_quiet -C "$RENDIR" add -A
  git_quiet -C "$RENDIR" commit -m note
  git_quiet -C "$RENDIR" mv note.md docs/note.txt
  run_stop "$HOOK" "$RENDIR" '{"stop_hook_active":false}'
  { [ "$RC" -eq 0 ] && [ -z "$OUT" ]; } && ok "docs-to-docs rename skips checks" || bad "docs-to-docs rename should skip (rc=$RC out=$OUT)"
  rm -rf "$RENDIR"

  # Human-format porcelain C-quotes paths with spaces or non-ASCII bytes
  # (' M "a b.md"'), which would defeat the *.md classification; the -z
  # format reports them raw.
  QDIR="$(make_fixture 1)"
  echo 'n' > "$QDIR/a b.md"
  echo 'n' > "$QDIR/日本語.md"
  git_quiet -C "$QDIR" add -A
  git_quiet -C "$QDIR" commit -m seed
  echo 'edit' >> "$QDIR/a b.md"
  echo 'edit' >> "$QDIR/日本語.md"
  run_stop "$HOOK" "$QDIR" '{"stop_hook_active":false}'
  { [ "$RC" -eq 0 ] && [ -z "$OUT" ]; } && ok "md paths with spaces/non-ASCII skip checks" || bad "quote-worthy md paths should skip (rc=$RC out=$OUT)"
  rm -rf "$QDIR"

  # --- passing checks: silent ----------------------------------------------
  PASSDIR="$(make_fixture 0)"
  echo 'x' > "$PASSDIR/src.ts"
  run_stop "$HOOK" "$PASSDIR" '{"stop_hook_active":false}'
  { [ "$RC" -eq 0 ] && [ -z "$OUT" ]; } && ok "passing checks stay silent" || bad "passing should be silent (rc=$RC out=$OUT)"
  rm -rf "$PASSDIR"
done

echo
echo "----------------------------------------"
echo "PASS=$PASS  FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
