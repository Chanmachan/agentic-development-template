#!/usr/bin/env bash
# Fixture tests for the .cursor/ hook adapters.
#
# These hooks have no git/CI backstop for their *immediate* feedback role, and
# the JSON I/O contract differs from the .claude/.codex versions, so the
# adapter-specific logic (block decisions, loop guard, file-type routing) is
# verified here without needing a live Cursor session.
#
# Cursor blockable hooks return {"permission":"deny",...} on stdout (exit 0).
# Determinism: pnpm/make/biome/oxlint are shadowed by fakes on a temp PATH, and
# stop-check cases run inside a seeded mktemp dir so branch routing is fixed by
# the fixture, not the host cwd.
#
# HOOK_PROFILE is pinned to strict so a developer's exported profile can't turn
# the gated hooks into no-ops and make assertions pass vacuously.
#
# Run: bash scripts/test-cursor-hooks.sh
set -uo pipefail
export HOOK_PROFILE=strict

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_DIR="$REPO_ROOT/.cursor/hooks"

PASS=0
FAIL=0
ok()  { printf '  \033[32mPASS\033[0m %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAIL=$((FAIL + 1)); }

run_hook() { # $1=script $2=json -> $RC, $OUT
  OUT="$(printf '%s' "$2" | bash "$HOOKS_DIR/$1" 2>/dev/null)"
  RC=$?
}
is_deny() { echo "$OUT" | grep -qE '"permission": *"deny"'; }

# ---------------------------------------------------------------------------
# protect-config.sh — preToolUse(Write): deny edits to protected/secret files
# ---------------------------------------------------------------------------
echo "protect-config.sh (write block)"
for p in "/repo/.env" "/repo/.env.local" "/repo/.env.template" "/repo/.env.sample" "/repo/tsconfig.json" \
         "/repo/pnpm-lock.yaml" "/repo/apps/web/.git/config" "/repo/.env/" "/repo/.ENV"; do
  run_hook protect-config.sh '{"tool_input":{"file_path":"'"$p"'"}}'
  { [ "$RC" -eq 0 ] && is_deny; } && ok "deny write $p" || bad "write $p should deny, rc=$RC out=$OUT"
done
for p in "/repo/.env.example" "/repo/apps/web/src/foo.ts" "/repo/foo.env" "/repo/config.json.template"; do
  run_hook protect-config.sh '{"tool_input":{"file_path":"'"$p"'"}}'
  { [ "$RC" -eq 0 ] && ! is_deny; } && ok "allow write $p" || bad "write $p should allow, rc=$RC out=$OUT"
done

# Guard self-protection (ADR 0008 A1): the .cursor copy of protect-config.sh
# plus the shared classification lib and stop-check.sh (this harness's own
# guard files) must refuse edits to themselves — a single edit to any of them
# could neuter every write-protection check. The .claude/scripts-lib cases are
# covered in tests/protect-config.test.sh; this exercises the .cursor copies.
for p in "/repo/.cursor/hooks/stop-check.sh" "/repo/.cursor/hooks/lib/protected.sh" "/repo/scripts/lib/protected.sh"; do
  run_hook protect-config.sh '{"tool_input":{"file_path":"'"$p"'"}}'
  { [ "$RC" -eq 0 ] && is_deny; } && ok "deny guard self-edit $p" || bad "$p should deny, rc=$RC out=$OUT"
done
run_hook protect-config.sh '{"tool_input":{"file_path":["/repo/src/ok.ts","/repo/.env"]}}'
is_deny && ok "array write with .env element denied" || bad "array .env should deny, out=$OUT"
run_hook protect-config.sh '{"file_path":"/repo/.env"}'
is_deny && ok "top-level file_path fallback denied" || bad "top-level .env should deny, out=$OUT"
run_hook protect-config.sh '{"path":"/repo/.env"}'
is_deny && ok "top-level path fallback denied" || bad "top-level path .env should deny, out=$OUT"
run_hook protect-config.sh '{"tool_input":{"target_file":"/repo/.env"}}'
is_deny && ok "tool_input.target_file fallback denied" || bad "tool_input.target_file .env should deny, out=$OUT"
run_hook protect-config.sh '{"tool_input":{"file_path":"/repo/.env "}}'
is_deny && ok "trailing-space .env still denied (normalization)" || bad "trailing-space .env should deny, out=$OUT"
run_hook protect-config.sh 'not json'
{ [ "$RC" -eq 0 ] && ! is_deny; } && ok "malformed stdin fails open (allow)" || bad "malformed should allow, rc=$RC out=$OUT"
{ [ "$RC" -eq 0 ] && [ -z "$OUT" ]; } && ok "malformed stdin is quiet on stdout" || bad "malformed stdin should produce no stdout, rc=$RC out=$OUT"
run_hook protect-config.sh '{"tool_input":{"file_path":""}}'
{ [ "$RC" -eq 0 ] && ! is_deny; } && ok "empty path allows (exit 0)" || bad "empty path should allow, rc=$RC out=$OUT"
run_hook protect-config.sh '{"tool_input":{"file_path":"/repo/.env"}}'
echo "$OUT" | grep -q 'protected config/secret file' && ok "deny message content mentions protected file reason" || bad "deny message should mention reason, out=$OUT"

# ---------------------------------------------------------------------------
# protect-read.sh — beforeReadFile: deny reading secrets, allow ordinary config
# ---------------------------------------------------------------------------
echo "protect-read.sh (secret read block)"
for p in "/repo/.env" "/repo/.env.production" "/repo/.ENV" "/repo/.env.example.local" \
         "/repo/certs/server.pem" "/repo/auth/key.p8" "/repo/id_rsa" "/repo/.npmrc" \
         "/home/u/.aws/credentials" ".aws/credentials" ".ssh/id_dsa"; do
  run_hook protect-read.sh '{"file_path":"'"$p"'"}'
  is_deny && ok "deny read $p" || bad "read $p should deny, rc=$RC out=$OUT"
done
for p in "/repo/.env.example" "/repo/tsconfig.json" "/repo/apps/web/src/foo.ts" "/repo/README.md" "/repo/credentials"; do
  run_hook protect-read.sh '{"file_path":"'"$p"'"}'
  { [ "$RC" -eq 0 ] && ! is_deny; } && ok "allow read $p" || bad "read $p should allow, rc=$RC out=$OUT"
done

# ---------------------------------------------------------------------------
# protect-shell.sh — beforeShellExecution: deny commands touching secrets
# ---------------------------------------------------------------------------
echo "protect-shell.sh (secret shell block)"
while IFS='|' read -r verdict cmd; do
  run_hook protect-shell.sh "$(printf '{"command":%s}' "$(jq -Rn --arg c "$cmd" '$c')")"
  if [ "$verdict" = deny ]; then
    is_deny && ok "deny shell: $cmd" || bad "shell should deny: $cmd (out=$OUT)"
  else
    { [ "$RC" -eq 0 ] && ! is_deny; } && ok "allow shell: $cmd" || bad "shell should allow: $cmd (out=$OUT)"
  fi
done <<'CASES'
deny|cat /repo/.env
deny|echo X >> .env
deny|cat .env.local
deny|cat .ENV
deny|cat .env.example.local
deny|cat ~/.ssh/id_rsa
deny|cat id_rsa
deny|cat certs/server.pem
deny|cat auth/key.p8
deny|cat ~/.aws/credentials
deny|cat .aws/credentials
deny|cat .ssh/id_dsa
allow|ls -la apps/web
allow|cat .env.example
allow|cat README.md
allow|grep TODO .environment-notes
allow|git commit -m "add credentials handling"
CASES

run_hook protect-shell.sh '{"command":""}'
{ [ "$RC" -eq 0 ] && ! is_deny; } && ok "empty command allows" || bad "empty command should allow, rc=$RC out=$OUT"
run_hook protect-shell.sh '{}'
{ [ "$RC" -eq 0 ] && ! is_deny; } && ok "missing command allows" || bad "missing command should allow, rc=$RC out=$OUT"
run_hook protect-shell.sh 'not json'
{ [ "$RC" -eq 0 ] && ! is_deny; } && ok "malformed stdin fails open (allow)" || bad "malformed stdin should allow, rc=$RC out=$OUT"

# ---------------------------------------------------------------------------
# Fail-closed on a missing shared lib (ADR 0008 B): copy each blockable guard
# + lib/profile.sh + lib/protected.sh (the thin wrapper) into an isolated temp
# dir WITHOUT scripts/lib/protected.sh, so the wrapper's relative source of
# the shared lib resolves to nothing. A benign, otherwise-allowed input must
# still be denied (deny JSON on stdout) instead of silently falling through.
# ---------------------------------------------------------------------------
echo "fail-closed: shared lib missing"
FIXTURE="$(mktemp -d)"
mkdir -p "$FIXTURE/.cursor/hooks/lib"
cp "$HOOKS_DIR/protect-config.sh" "$HOOKS_DIR/protect-read.sh" "$HOOKS_DIR/protect-shell.sh" "$FIXTURE/.cursor/hooks/"
cp "$HOOKS_DIR/lib/profile.sh" "$FIXTURE/.cursor/hooks/lib/profile.sh"
cp "$HOOKS_DIR/lib/protected.sh" "$FIXTURE/.cursor/hooks/lib/protected.sh"
# Deliberately no scripts/lib/protected.sh under $FIXTURE.

run_hook_fixture() { # $1=script $2=json -> $RC, $OUT
  OUT="$(printf '%s' "$2" | bash "$FIXTURE/.cursor/hooks/$1" 2>/dev/null)"
  RC=$?
}
run_hook_fixture protect-config.sh '{"tool_input":{"file_path":"/repo/src/ok.ts"}}'
{ [ "$RC" -eq 0 ] && is_deny; } && ok "protect-config.sh: missing shared lib fails closed (deny)" || bad "protect-config.sh missing lib should deny, rc=$RC out=$OUT"
run_hook_fixture protect-read.sh '{"file_path":"/repo/src/ok.ts"}'
{ [ "$RC" -eq 0 ] && is_deny; } && ok "protect-read.sh: missing shared lib fails closed (deny)" || bad "protect-read.sh missing lib should deny, rc=$RC out=$OUT"
run_hook_fixture protect-shell.sh '{"command":"ls -la"}'
{ [ "$RC" -eq 0 ] && is_deny; } && ok "protect-shell.sh: missing shared lib fails closed (deny)" || bad "protect-shell.sh missing lib should deny, rc=$RC out=$OUT"
rm -rf "$FIXTURE"

# ---------------------------------------------------------------------------
# post-lint.sh — afterFileEdit: format edited TS/JS, no-op for others
# ---------------------------------------------------------------------------
echo "post-lint.sh"
FAKEBIN="$(mktemp -d)"; BIOME_SENTINEL="$FAKEBIN/biome-ran"; OXLINT_SENTINEL="$FAKEBIN/oxlint-ran"
# post-lint.sh no-ops for files outside the repo it runs from, so this fixture
# is its own throwaway git repo — that makes $FAKEBIN itself the resolved repo
# root and keeps the "in-repo edit" path under test. mktemp lives under a
# symlinked path on macOS (/var -> /private/var), so these cases also verify
# the guard compares symlink-resolved paths.
git -C "$FAKEBIN" init -q
printf '#!/usr/bin/env bash\necho ran >> "%s"\nexit 0\n' "$BIOME_SENTINEL" > "$FAKEBIN/biome"; chmod +x "$FAKEBIN/biome"
printf '#!/usr/bin/env bash\necho ran >> "%s"\nexit 0\n' "$OXLINT_SENTINEL" > "$FAKEBIN/oxlint"; chmod +x "$FAKEBIN/oxlint"
run_postlint() { rm -f "$BIOME_SENTINEL" "$OXLINT_SENTINEL"; ( cd "$FAKEBIN" && printf '%s' "$1" | PATH="$FAKEBIN:$PATH" bash "$HOOKS_DIR/post-lint.sh" ) >/dev/null 2>&1; RC=$?; }
echo 'const x=1' > "$FAKEBIN/sample.ts"
run_postlint "$(printf '{"file_path":"%s"}' "$FAKEBIN/sample.ts")"
{ [ "$RC" -eq 0 ] && [ -f "$BIOME_SENTINEL" ] && [ -f "$OXLINT_SENTINEL" ]; } && ok ".ts edit invokes biome and oxlint" || bad ".ts edit should invoke both formatters (rc=$RC)"
echo 'const x: number = 1' > "$FAKEBIN/sample.tsx"
run_postlint "$(printf '{"file_path":"%s"}' "$FAKEBIN/sample.tsx")"
{ [ "$RC" -eq 0 ] && [ -f "$BIOME_SENTINEL" ] && [ -f "$OXLINT_SENTINEL" ]; } && ok ".tsx edit invokes biome and oxlint" || bad ".tsx edit should invoke both formatters (rc=$RC)"
run_postlint "$(printf '{"file_path":"%s/notes.md"}' "$FAKEBIN")"
{ [ "$RC" -eq 0 ] && [ ! -f "$BIOME_SENTINEL" ] && [ ! -f "$OXLINT_SENTINEL" ]; } && ok ".md edit is a no-op" || bad ".md edit should no-op (rc=$RC)"
# Repo-root guard: run from this repo with an absolute path into $FAKEBIN
# (outside this repo root) — the hook must skip it instead of formatting.
run_postlint_outside() { rm -f "$BIOME_SENTINEL" "$OXLINT_SENTINEL"; ( cd "$REPO_ROOT" && printf '%s' "$1" | PATH="$FAKEBIN:$PATH" bash "$HOOKS_DIR/post-lint.sh" ) >/dev/null 2>&1; RC=$?; }
run_postlint_outside "$(printf '{"file_path":"%s"}' "$FAKEBIN/sample.ts")"
{ [ "$RC" -eq 0 ] && [ ! -f "$BIOME_SENTINEL" ] && [ ! -f "$OXLINT_SENTINEL" ]; } && ok "absolute path outside repo root is a no-op" || bad "outside-repo edit should no-op (rc=$RC)"
# Explicit escape fixtures, independent of macOS's /var alias (absent on Linux
# CI): $OUTSIDE is a sibling temp dir holding the escape targets.
OUTSIDE="$(mktemp -d)"
echo 'const y=2' > "$OUTSIDE/escape.ts"
ln -s "$OUTSIDE/escape.ts" "$FAKEBIN/link.ts"
ln -s "$FAKEBIN" "$OUTSIDE/repo-alias"
run_postlint "$(printf '{"file_path":"../%s/escape.ts"}' "$(basename "$OUTSIDE")")"
{ [ "$RC" -eq 0 ] && [ ! -f "$BIOME_SENTINEL" ] && [ ! -f "$OXLINT_SENTINEL" ]; } && ok "relative path escaping repo root is a no-op" || bad "relative escape should no-op (rc=$RC)"
run_postlint "$(printf '{"file_path":"%s/link.ts"}' "$FAKEBIN")"
{ [ "$RC" -eq 0 ] && [ ! -f "$BIOME_SENTINEL" ] && [ ! -f "$OXLINT_SENTINEL" ]; } && ok "in-repo symlink to outside file is a no-op" || bad "symlink escape should no-op (rc=$RC)"
run_postlint '{"file_path":"sample.ts"}'
{ [ "$RC" -eq 0 ] && [ -f "$BIOME_SENTINEL" ] && [ -f "$OXLINT_SENTINEL" ]; } && ok "in-repo relative path still invokes formatters" || bad "in-repo relative path should format (rc=$RC)"
run_postlint "$(printf '{"file_path":"%s/repo-alias/sample.ts"}' "$OUTSIDE")"
{ [ "$RC" -eq 0 ] && [ -f "$BIOME_SENTINEL" ] && [ -f "$OXLINT_SENTINEL" ]; } && ok "in-repo file via symlinked dir still invokes formatters" || bad "symlinked-dir in-repo path should format (rc=$RC)"
rm -rf "$OUTSIDE"
run_postlint '{"hook_event_name":"afterFileEdit"}'
{ [ "$RC" -eq 0 ] && [ ! -f "$BIOME_SENTINEL" ] && [ ! -f "$OXLINT_SENTINEL" ]; } && ok "missing path is a no-op" || bad "missing path should no-op (rc=$RC)"
# Pin current behavior when the formatters are absent from PATH: post-lint.sh
# exits 1 with a stderr error and does not attempt to format (see its .ts|.tsx
# branch). jq must stay reachable (the hook needs it to parse stdin) while
# biome/oxlint stay absent. /usr/bin:/bin alone assumes a system jq at
# /usr/bin/jq, which isn't true on machines where jq is Homebrew-only (jq
# would vanish too, and the hook would fail before it even gets to the
# formatter check, exiting 0 instead of the expected 1). Pin jq into a
# dedicated dir on PATH instead so the case is deterministic regardless of
# where the host's jq lives.
JQ_BIN="$(command -v jq)" || { bad "jq not found on PATH; cannot run missing-formatter fixture"; JQ_BIN=""; }
JQPATH="$(mktemp -d)"
[ -n "$JQ_BIN" ] && ln -s "$JQ_BIN" "$JQPATH/jq"
run_postlint_nopath() { rm -f "$BIOME_SENTINEL" "$OXLINT_SENTINEL"; ( cd "$FAKEBIN" && printf '%s' "$1" | PATH="$JQPATH:/usr/bin:/bin" bash "$HOOKS_DIR/post-lint.sh" ) >/dev/null 2>&1; RC=$?; }
run_postlint_nopath "$(printf '{"file_path":"%s"}' "$FAKEBIN/sample.ts")"
{ [ "$RC" -eq 1 ] && [ ! -f "$BIOME_SENTINEL" ] && [ ! -f "$OXLINT_SENTINEL" ]; } && ok "missing formatter exits 1 without formatting (pinned)" || bad "missing-formatter behavior changed (rc=$RC)"
rm -rf "$FAKEBIN" "$JQPATH"

# ---------------------------------------------------------------------------
# stop-check.sh — stop: followup_message on failure, loop guard
# ---------------------------------------------------------------------------
echo "stop-check.sh"
make_toolchain() { # $1=exit code
  local dir; dir="$(mktemp -d)"; echo '{}' > "$dir/package.json"; : > "$dir/pnpm-lock.yaml"
  mkdir "$dir/bin"; local t
  for t in pnpm make; do printf '#!/usr/bin/env bash\nexit %s\n' "$1" > "$dir/bin/$t"; chmod +x "$dir/bin/$t"; done
  echo "$dir"
}
run_stop() { OUT="$(cd "$1" && printf '%s' "$2" | PATH="$1/bin:$PATH" bash "$HOOKS_DIR/stop-check.sh" 2>/dev/null)"; RC=$?; }
FAILDIR="$(make_toolchain 1)"
run_stop "$FAILDIR" '{"loop_count":0}'
{ echo "$OUT" | grep -q 'followup_message' && echo "$OUT" | grep -q 'Do not stop yet'; } && ok "failing checks emit followup" || bad "failing should emit followup (out=$OUT)"
run_stop "$FAILDIR" '{"loop_count":1}'
echo "$OUT" | grep -q 'followup_message' && ok "below limit still nudges" || bad "loop_count=1 should nudge (out=$OUT)"
run_stop "$FAILDIR" '{"loop_count":2}'
{ [ "$RC" -eq 0 ] && [ -z "$OUT" ]; } && ok "at limit short-circuits (silent)" || bad "loop guard should be silent (rc=$RC out=$OUT)"
run_stop "$FAILDIR" '{"loop_count":"abc"}'
echo "$OUT" | grep -q 'followup_message' && ok "non-numeric loop_count treated as 0" || bad "non-numeric should nudge (out=$OUT)"
export CURSOR_STOP_LOOP_LIMIT=3
run_stop "$FAILDIR" '{"loop_count":2}'
echo "$OUT" | grep -q 'followup_message' && ok "CURSOR_STOP_LOOP_LIMIT raises threshold (loop_count=2 nudges)" || bad "limit override should nudge (out=$OUT)"
unset CURSOR_STOP_LOOP_LIMIT
rm -rf "$FAILDIR"
PASSDIR="$(make_toolchain 0)"
run_stop "$PASSDIR" '{"loop_count":0}'
{ [ "$RC" -eq 0 ] && [ -z "$OUT" ]; } && ok "passing checks stay silent" || bad "passing should be silent (rc=$RC out=$OUT)"
rm -rf "$PASSDIR"

# Makefile routing: a Makefile with a `test:` target takes priority over
# package.json/pnpm/npm below it.
make_toolchain_makefile() { # $1=exit code
  local dir; dir="$(mktemp -d)"
  printf 'test:\n\techo test\n' > "$dir/Makefile"
  mkdir "$dir/bin"
  printf '#!/usr/bin/env bash\nexit %s\n' "$1" > "$dir/bin/make"; chmod +x "$dir/bin/make"
  echo "$dir"
}
MAKEDIR="$(make_toolchain_makefile 1)"
run_stop "$MAKEDIR" '{"loop_count":0}'
{ echo "$OUT" | grep -q 'followup_message' && echo "$OUT" | grep -q 'make test failed'; } && ok "Makefile routing: failing make test emits followup" || bad "Makefile routing should emit followup (out=$OUT)"
rm -rf "$MAKEDIR"

# npm fallback: package.json without a pnpm-lock.yaml / packageManager:pnpm
# field routes to npm run lint/typecheck/npm test.
make_toolchain_npm() { # $1=exit code
  local dir; dir="$(mktemp -d)"; echo '{}' > "$dir/package.json"
  mkdir "$dir/bin"
  printf '#!/usr/bin/env bash\nexit %s\n' "$1" > "$dir/bin/npm"; chmod +x "$dir/bin/npm"
  echo "$dir"
}
NPMDIR="$(make_toolchain_npm 1)"
run_stop "$NPMDIR" '{"loop_count":0}'
{ echo "$OUT" | grep -q 'followup_message' && echo "$OUT" | grep -q 'lint failed'; } && ok "npm fallback: failing npm run emits followup" || bad "npm fallback should emit followup (out=$OUT)"
rm -rf "$NPMDIR"

# ---------------------------------------------------------------------------
# enforce-model.sh — beforeSubmitPrompt: deny non-Composer models, allow Composer
# ---------------------------------------------------------------------------
echo "enforce-model.sh (model gate)"

# deny: gpt-5.5 (third-party slug)
run_hook enforce-model.sh '{"model":"gpt-5.5"}'
{ [ "$RC" -eq 0 ] && is_deny; } && ok "deny: gpt-5.5 (non-composer)" || bad "gpt-5.5 should deny (rc=$RC out=$OUT)"

# deny via model_id fallback: no `model` key at all
run_hook enforce-model.sh '{"model_id":"gpt-5.5"}'
{ [ "$RC" -eq 0 ] && is_deny; } && ok "deny: model_id fallback (no model key)" || bad "model_id fallback should deny (rc=$RC out=$OUT)"

# allow: composer-2.5
run_hook enforce-model.sh '{"model":"composer-2.5"}'
{ [ "$RC" -eq 0 ] && ! is_deny; } && ok "allow: composer-2.5" || bad "composer-2.5 should allow (rc=$RC out=$OUT)"

# allow: composer-2.5-fast
run_hook enforce-model.sh '{"model":"composer-2.5-fast"}'
{ [ "$RC" -eq 0 ] && ! is_deny; } && ok "allow: composer-2.5-fast" || bad "composer-2.5-fast should allow (rc=$RC out=$OUT)"

# allow: Composer-2.5 (case-insensitive)
run_hook enforce-model.sh '{"model":"Composer-2.5"}'
{ [ "$RC" -eq 0 ] && ! is_deny; } && ok "allow: Composer-2.5 (case-insensitive)" || bad "Composer-2.5 should allow (rc=$RC out=$OUT)"

# fail-open: no model field in payload
run_hook enforce-model.sh '{"hook_event_name":"beforeSubmitPrompt"}'
{ [ "$RC" -eq 0 ] && ! is_deny; } && ok "fail-open: missing model field allows" || bad "missing model should allow (rc=$RC out=$OUT)"

# CURSOR_REQUIRED_MODEL_PREFIX=claude: allows claude slug, denies composer
run_hook_env() { # $1=script $2=json $3=env-pair -> $RC, $OUT
  OUT="$(printf '%s' "$2" | env "$3" bash "$HOOKS_DIR/$1" 2>/dev/null)"
  RC=$?
}
run_hook_env enforce-model.sh '{"model":"claude-sonnet-4"}' "CURSOR_REQUIRED_MODEL_PREFIX=claude"
{ [ "$RC" -eq 0 ] && ! is_deny; } && ok "CURSOR_REQUIRED_MODEL_PREFIX=claude allows claude slug" || bad "claude slug should allow with prefix=claude (rc=$RC out=$OUT)"
run_hook_env enforce-model.sh '{"model":"composer-2.5"}' "CURSOR_REQUIRED_MODEL_PREFIX=claude"
{ [ "$RC" -eq 0 ] && is_deny; } && ok "CURSOR_REQUIRED_MODEL_PREFIX=claude denies composer slug" || bad "composer should deny with prefix=claude (rc=$RC out=$OUT)"

# empty CURSOR_REQUIRED_MODEL_PREFIX: allows everything
run_hook_env enforce-model.sh '{"model":"gpt-5.5"}' "CURSOR_REQUIRED_MODEL_PREFIX="
{ [ "$RC" -eq 0 ] && ! is_deny; } && ok "empty CURSOR_REQUIRED_MODEL_PREFIX allows all models" || bad "empty prefix should allow all (rc=$RC out=$OUT)"

# HOOK_PROFILE=minimal: hook is skipped (allow non-composer)
OUT="$(printf '{"model":"gpt-5.5"}' | HOOK_PROFILE=minimal bash "$HOOKS_DIR/enforce-model.sh" 2>/dev/null)"
RC=$?
{ [ "$RC" -eq 0 ] && ! is_deny; } && ok "HOOK_PROFILE=minimal skips hook (allows non-composer)" || bad "minimal profile should skip enforce-model (rc=$RC out=$OUT)"

# ---------------------------------------------------------------------------
# lib: CURSOR_HOOK_DEBUG capture + off-by-default
# ---------------------------------------------------------------------------
echo "lib (debug capture)"
DBG="$(mktemp)"; rm -f "$DBG"
printf '{"tool_input":{"file_path":"/repo/src/ok.ts"}}' | CURSOR_HOOK_DEBUG="$DBG" bash "$HOOKS_DIR/protect-config.sh" >/dev/null 2>&1
{ [ -f "$DBG" ] && grep -q 'preToolUse' "$DBG"; } && ok "CURSOR_HOOK_DEBUG captures raw input" || bad "debug capture should write input"
rm -f "$DBG"
run_hook protect-config.sh '{"tool_input":{"file_path":"/repo/src/ok.ts"}}'
{ [ "$RC" -eq 0 ] && ! is_deny; } && ok "debug off by default is a no-op" || bad "debug-off should no-op (rc=$RC)"

echo
echo "----------------------------------------"
echo "PASS=$PASS  FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
