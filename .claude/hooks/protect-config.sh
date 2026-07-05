#!/usr/bin/env bash
set -euo pipefail

DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$DIR/lib/profile.sh"
hook_profile_skip protect-config
LIB="$DIR/../../scripts/lib/protected.sh"

# Fail CLOSED (not open) if the shared classification lib can't be loaded: a
# missing/broken lib means we can no longer tell protected paths from ordinary
# ones, and this hook's whole job is refusing edits — silently allowing
# everything through would defeat it. exit 2 is Claude Code's blocking signal
# (exit 1 here would be treated as non-blocking and the edit would proceed).
#
# `set +e`/`set -e` bracket the source call because bash treats "file not
# found" in a special builtin like `source` as a fatal shell error that
# exits immediately under `set -e` even inside an `if !`/`||` guard (a
# long-standing bash quirk, reproducible on the bash 3.2 shipped with macOS) —
# so the failure has to be caught with errexit off, not with a conditional.
set +e
source "$LIB" 2>/dev/null
LIB_RC=$?
set -e
if [ "$LIB_RC" -ne 0 ] || ! declare -F is_protected_path >/dev/null 2>&1; then
  echo "BLOCKED: failed to load shared protected-path lib ($LIB); failing closed." >&2
  exit 2
fi

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
