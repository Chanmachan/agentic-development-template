#!/usr/bin/env bash
# Cursor beforeReadFile adapter (matcher: "Read"|"TabRead"): refuse to read
# secret files so their contents never enter the agent's context.
#
# READ-protection is scoped to *secrets* only (is_secret_path) — reading
# tsconfig.json etc. is legitimate and must stay allowed. This guard has no
# equivalent in the Claude/Codex harnesses: Cursor can pre-block reads, so the
# .cursor harness closes the .env-leak vector more cleanly than Claude can.
set -euo pipefail

DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$DIR/lib/profile.sh"
hook_profile_skip protect-read
source "$DIR/lib/protected.sh"

INPUT="$(cat)"
hook_debug beforeReadFile "$INPUT"

# Docs: beforeReadFile input carries `file_path`. Read defensively anyway.
fp="$(printf '%s' "$INPUT" | jq -r '.file_path // .tool_input.file_path // .path // empty' 2>/dev/null)" || fp=""

if [ -n "$fp" ] && is_secret_path "$fp"; then
  deny "Refused to read $fp: it is a secret file. Do not load its contents." \
       "Blocked read of secret file: $fp"
fi

exit 0
