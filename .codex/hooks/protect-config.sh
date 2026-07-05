#!/usr/bin/env bash
set -euo pipefail

DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$DIR/lib/profile.sh"
hook_profile_skip protect-config
source "$DIR/../../scripts/lib/protected.sh"

# Block Write/Edit/MultiEdit on lint/type/format/build configs, secrets, lockfiles,
# and version pins. Intent: "Fix the code, not the config." — never silence errors
# by loosening config; never edit machine-managed files.
#
# Classification is delegated to is_protected_path() (scripts/lib/protected.sh),
# the shared source of truth also used by the other two harnesses. It evaluates:
#   1. .env / .env.<env> (case-insensitive, normalized) → block, EXCEPT
#      .env.example → allow
#   2. *.example / *.sample / *.template suffix → allow (industry-standard
#      template files, e.g. tsconfig.json.example)
#   3. PROTECTED_PATTERNS substring → block (configs, lockfiles, version pins)
#   4. otherwise → allow

INPUT="$(cat)"
FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null)" || FILE_PATH=""

if is_protected_path "$FILE_PATH"; then
  echo "BLOCKED: $FILE_PATH is a protected config/secret file. Fix the code, not the config." >&2
  exit 2
fi

exit 0
