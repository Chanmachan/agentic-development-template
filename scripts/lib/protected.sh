#!/usr/bin/env bash
# Shared protected-path CLASSIFICATION logic. Single source of truth for
# PROTECTED_PATTERNS and the path-classification functions, consumed by all
# three harnesses (.claude, .codex, .cursor). Response SHAPING (deny JSON vs.
# exit-2/stderr, etc.) is intentionally NOT here — it stays per-harness because
# each tool's hook contract differs (see .claude/hooks/protect-config.sh,
# .codex/hooks/protect-config.sh, .cursor/hooks/lib/protected.sh).
#
# Two notions of "protected":
#   - is_protected_path : config integrity + secrets. Used to block WRITES
#     (editing tsconfig/lockfiles/.env etc. is refused).
#   - is_secret_path    : secrets only. Used to block READS and shell access —
#     reading tsconfig.json is legitimate, reading .env is a leak.

# Config/integrity files whose EDIT we refuse (substring match on full path).
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
  # Guard self-protection (ADR 0008 (f)): refuse edits to the guard's own
  # files so a single edit can't neuter every write-protection check. These
  # are substring matches, so each pattern covers all three harnesses' copies
  # in one line (e.g. "protect-config.sh" matches .claude/, .codex/, AND
  # .cursor/hooks/protect-config.sh) plus the shared lib itself.
  "lib/protected.sh"
  "protect-config.sh"
  "stop-check.sh"
  # ADR 0009 (self-protection perimeter): the rest of the hook perimeter --
  # every remaining hook script, the shared profile-gating lib, and the two
  # hook-WIRING files (.claude/settings.json, .cursor/hooks.json,
  # .codex/hooks.json) that decide which scripts run at all. A single
  # unguarded edit to any of these is equally a persistence/neutering path
  # as editing protect-config.sh itself: e.g. rewriting .claude/settings.json
  # to drop the PreToolUse entry disables every guard without touching a
  # single guard file. ".claude/settings.json" is the FULL relative path
  # (not bare "settings.json") so this does not over-match unrelated
  # settings.json files a downstream project might have (e.g.
  # .vscode/settings.json) -- verified against this repo's tree at the time
  # this was added; re-check if a new settings.json-named file is
  # introduced elsewhere in .claude/.
  "worktree-setup.sh"
  "post-lint.sh"
  "protect-read.sh"
  "protect-shell.sh"
  "enforce-model.sh"
  "lib/profile.sh"
  "suggest-compact.mjs"
  "hooks.json"
  ".claude/settings.json"
)

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
