#!/usr/bin/env bash
# Cursor beforeShellExecution adapter: refuse shell commands that touch secret
# files, closing the obvious bypass of the Read/Write tool guards (e.g.
# `cat .env`, `echo X >> .env`, `vim .env`, `cat ~/.ssh/id_rsa`).
#
# Consistency: rather than its own regex, this tokenizes the command into
# path-like words and reuses `is_secret_path` from lib/protected.sh — so the
# shell guard agrees exactly with the read/write guards (case-insensitive,
# .env.example exempt, .env.local / .ENV / .env.example.local blocked).
#
# This is a high-signal speed bump, NOT a complete sandbox: textual scanning of
# the raw command can be evaded by shell quoting/escaping (`cat .e"n"v`) or
# indirection. The real backstop for writes/reads is the Write/Read tool guards;
# this catches the common, direct shell vector.
set -euo pipefail

DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$DIR/lib/profile.sh"
hook_profile_skip protect-shell
source "$DIR/lib/protected.sh"

INPUT="$(cat)"
hook_debug beforeShellExecution "$INPUT"

command="$(printf '%s' "$INPUT" | jq -r '.command // empty' 2>/dev/null)" || command=""
[ -z "$command" ] && exit 0

# Extract word tokens and let is_secret_path decide each. is_secret_path only
# matches secret-shaped names (.env*, *.pem/*.key/*.p8…, id_rsa/id_ed25519,
# credentials.json, .npmrc, .aws/.ssh paths) — none of which are common prose
# words — so scanning every token is safe and catches dotless secrets like a
# bare `cat id_rsa`. (Bare "credentials" was deliberately dropped from the list.)
tokens="$(printf '%s' "$command" | grep -oE '[A-Za-z0-9._/~+-]+' 2>/dev/null)" || tokens=""
while IFS= read -r tok; do
  [ -z "$tok" ] && continue
  if is_secret_path "$tok"; then
    deny "Refused to run a shell command referencing a secret file ($tok): $command" \
         "Blocked shell command touching a secret file: $tok"
  fi
done <<< "$tokens"

exit 0
