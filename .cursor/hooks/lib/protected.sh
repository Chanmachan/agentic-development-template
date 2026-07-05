#!/usr/bin/env bash
# Thin per-harness wrapper around the shared protected-path classification lib
# (scripts/lib/protected.sh — single source of truth for PROTECTED_PATTERNS,
# is_protected_path, is_secret_path). This file keeps only what response
# SHAPING for the .cursor harness needs: hook_debug() (raw payload capture)
# and deny() (Cursor's {"permission":"deny",...} JSON contract).
#
# Sourced by all six .cursor hooks: the three blockable guards —
# protect-config.sh (preToolUse:Write), protect-read.sh (beforeReadFile),
# protect-shell.sh (beforeShellExecution) — use the classification functions;
# post-lint.sh and stop-check.sh source it only for the shared hook_debug()
# helper; enforce-model.sh (beforeSubmitPrompt) sources it for hook_debug()
# and deny().

_PROTECTED_LIB="$(dirname "${BASH_SOURCE[0]}")/../../../scripts/lib/protected.sh"

# Fail CLOSED if the shared classification lib can't be loaded: without it none
# of the three blockable guards (protect-config/read/shell) can tell protected
# paths from ordinary ones, so silently continuing would defeat them. deny()
# below isn't defined yet at this point (it's defined further down in this
# same file), so the deny response is hand-rolled here instead of calling it.
#
# `set +e`/`set -e` bracket the source call because bash treats "file not
# found" in a special builtin like `source` as a fatal shell error that exits
# immediately under the caller's `set -e` regardless of `if`/`||` guards (a
# long-standing quirk, reproducible on the bash 3.2 shipped with macOS) — the
# failure has to be caught with errexit off, not with a conditional.
set +e
source "$_PROTECTED_LIB" 2>/dev/null
_PROTECTED_LIB_RC=$?
set -e
if [ "$_PROTECTED_LIB_RC" -ne 0 ] || ! declare -F is_protected_path >/dev/null 2>&1; then
  echo "BLOCKED: failed to load shared protected-path lib ($_PROTECTED_LIB); failing closed." >&2
  jq -n \
    --arg a "Security guard library failed to load; refusing to proceed until this is fixed." \
    --arg u "Blocked: protected-path guard library is missing or broken." \
    '{permission:"deny", agent_message:$a, user_message:$u}' 2>/dev/null || \
    printf '%s\n' '{"permission":"deny","agent_message":"Security guard library failed to load; refusing to proceed until this is fixed.","user_message":"Blocked: protected-path guard library is missing or broken."}'
  exit 0
fi

# Opt-in raw-input capture for verifying Cursor's real payload shapes per event.
# No-op unless CURSOR_HOOK_DEBUG is set to a writable path.
hook_debug() { # $1=event label, $2=raw stdin
  [ -n "${CURSOR_HOOK_DEBUG:-}" ] && printf '=== %s ===\n%s\n' "$1" "$2" >> "$CURSOR_HOOK_DEBUG" 2>/dev/null || true
}

# Emit a Cursor deny response (stdout JSON) and exit. Exit 0 because the docs say
# exit 0 + JSON is the structured path; exit 2 is the message-less equivalent.
deny() { # $1=agent_message, $2=user_message
  jq -n --arg a "$1" --arg u "$2" '{permission:"deny", agent_message:$a, user_message:$u}'
  exit 0
}
