#!/usr/bin/env bash
# Shared protected-path logic for the .cursor/ guard hooks.
#
# Sourced by all six .cursor hooks: the three blockable guards —
# protect-config.sh (preToolUse:Write), protect-read.sh (beforeReadFile),
# protect-shell.sh (beforeShellExecution) — use the matching rules; post-lint.sh
# and stop-check.sh source it only for the shared hook_debug() helper;
# enforce-model.sh (beforeSubmitPrompt) sources it for hook_debug() and deny().
# The hardened rules thus live in exactly one place. (Many consumers justify a
# shared lib here, unlike profile.sh which is intentionally copied per harness.)
#
# Two notions of "protected":
#   - is_protected_path : config integrity + secrets. Used to block WRITES
#     (editing tsconfig/lockfiles/.env etc. is refused).
#   - is_secret_path    : secrets only. Used to block READS and shell access —
#     reading tsconfig.json is legitimate, reading .env is a leak.

# Config/integrity files whose EDIT we refuse (substring match on full path).
# Kept in sync with .claude/hooks/protect-config.sh PROTECTED_PATTERNS.
PROTECTED_PATTERNS=(
  ".eslintrc"
  "eslint.config"
  "biome.json"
  "tsconfig.json"
  "tsconfig.base.json"
  "pyproject.toml"
  "lefthook.yml"
  ".prettierrc"
  ".golangci.yml"
  "Cargo.toml"
  ".swiftlint.yml"
  ".pre-commit-config.yaml"
  "pnpm-lock.yaml"
  "package-lock.json"
  "yarn.lock"
  "Cargo.lock"
  "poetry.lock"
  "Pipfile.lock"
  "Gemfile.lock"
  "go.sum"
  ".node-version"
  ".python-version"
  ".ruby-version"
  ".tool-versions"
  ".git/"
)

# Opt-in raw-input capture for verifying Cursor's real payload shapes per event.
# No-op unless CURSOR_HOOK_DEBUG is set to a writable path.
hook_debug() { # $1=event label, $2=raw stdin
  [ -n "${CURSOR_HOOK_DEBUG:-}" ] && printf '=== %s ===\n%s\n' "$1" "$2" >> "$CURSOR_HOOK_DEBUG" 2>/dev/null || true
}

# Normalize a path so trivial variants can't dodge exact-match checks:
# strip trailing slashes (".env/") and trailing whitespace (".env ").
_normalize_path() { # $1=path -> echoes normalized
  local fp="$1"
  while [ "${fp%/}" != "$fp" ]; do fp="${fp%/}"; done
  fp="${fp%"${fp##*[![:space:]]}"}"
  printf '%s' "$fp"
}

# True (0) if the basename is a secret env file: .env or .env.* EXCEPT
# .env.example. Case-insensitive (macOS APFS resolves .ENV to .env).
_is_env_secret() { # $1=lowercased basename
  local b="$1"
  [ "$b" = ".env.example" ] && return 1
  [ "$b" = ".env" ] && return 0
  [ "${b#.env.}" != "$b" ] && return 0
  return 1
}

# True (0) if reading/exposing this path leaks a secret.
is_secret_path() { # $1=path
  local fp fp_lc base_lc
  fp="$(_normalize_path "$1")"
  [ -z "$fp" ] && return 1
  fp_lc="$(printf '%s' "$fp" | tr '[:upper:]' '[:lower:]')"
  base_lc="${fp_lc##*/}"

  _is_env_secret "$base_lc" && return 0

  # Cloud/SSH credential material identified by directory + name (bare
  # "credentials" is intentionally NOT matched — it is a common non-file word).
  # Both the anchored (leading dir, e.g. "/home/u/.aws/credentials") and bare
  # relative (e.g. ".aws/credentials") forms are matched — a relative reference
  # has no leading "/" for "*/..." to catch.
  case "$fp_lc" in
    .aws/credentials | */.aws/credentials | \
    .aws/credentials.* | */.aws/credentials.* | \
    .ssh/id_* | */.ssh/id_*) return 0 ;;
  esac

  case "$base_lc" in
    *.pem | *.key | *.p8 | *.p12 | *.pfx | id_rsa | id_ed25519 | id_ecdsa | \
    credentials.json | .pgpass | .netrc | .npmrc) return 0 ;;
  esac
  return 1
}

# True (0) if editing this path must be refused (config integrity OR secret).
is_protected_path() { # $1=path
  local fp base base_lc pattern
  fp="$(_normalize_path "$1")"
  [ -z "$fp" ] && return 1
  base="${fp##*/}"
  base_lc="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')"

  # .env family first (secrets), case-insensitive, .env.example exempt.
  # Reuse _is_env_secret so the rule has one source of truth; a non-.env
  # basename falls through unmatched to the generic checks below.
  _is_env_secret "$base_lc" && return 0

  # Generic safe-to-share template suffixes for non-env config.
  case "$base" in
    *.example | *.sample | *.template) return 1 ;;
  esac

  for pattern in "${PROTECTED_PATTERNS[@]}"; do
    case "$fp" in
      *"$pattern"*) return 0 ;;
    esac
  done
  return 1
}

# Emit a Cursor deny response (stdout JSON) and exit. Exit 0 because the docs say
# exit 0 + JSON is the structured path; exit 2 is the message-less equivalent.
deny() { # $1=agent_message, $2=user_message
  jq -n --arg a "$1" --arg u "$2" '{permission:"deny", agent_message:$a, user_message:$u}'
  exit 0
}
