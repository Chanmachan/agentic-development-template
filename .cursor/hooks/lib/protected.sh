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

source "$(dirname "${BASH_SOURCE[0]}")/../../../scripts/lib/protected.sh"

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
