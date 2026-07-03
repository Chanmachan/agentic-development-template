#!/usr/bin/env bash
# Cursor preToolUse adapter (matcher: "Write"): refuse edits to protected config
# and secret files BEFORE the write happens.
#
# Wiring note: Cursor's preToolUse matches on tool TYPE ("Write"/"Read"/"Shell"/
# "MCP:*"), not a lowercase verb — an earlier version matched "edit|write|..."
# and never fired. Deny is returned as a structured JSON response (see lib deny()).
#
# .env* has no git/CI backstop (gitignored), so refusing the write here — plus
# protect-read (no leak via reads) and protect-shell (no leak/write via shell) —
# is how the Cursor harness reaches Claude-equivalent protection without a
# generic "before edit" hook.
set -euo pipefail

DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$DIR/lib/profile.sh"
hook_profile_skip protect-config
source "$DIR/lib/protected.sh"

INPUT="$(cat)"
hook_debug preToolUse "$INPUT"

# Cursor's preToolUse path field is unconfirmed (no live capture yet), so read
# several plausible keys and flatten array values (a multi-file write must not
# smuggle a protected path past a single-path check).
candidates="$(printf '%s' "$INPUT" | jq -r '
  [ .tool_input.file_path, .tool_input.path, .tool_input.target_file,
    .file_path, .path, .args.path, .args.file_path ]
  | map(select(. != null))
  | map(if type == "array" then .[] else . end)
  | .[]' 2>/dev/null)" || candidates=""

while IFS= read -r fp; do
  [ -z "$fp" ] && continue
  if is_protected_path "$fp"; then
    deny "Refused to edit $fp: it is a protected config/secret file. Fix the code, not the config." \
         "Blocked edit to protected file: $fp"
  fi
done <<< "$candidates"

exit 0
