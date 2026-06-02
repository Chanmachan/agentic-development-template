#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/profile.sh"
hook_profile_skip protect-config

# Block Write/Edit/MultiEdit on lint/type/format/build configs, secrets, lockfiles,
# and version pins. Intent: "Fix the code, not the config." — never silence errors
# by loosening config; never edit machine-managed files.
#
# Evaluation order matters:
#   1. *.example / *.sample / *.template suffix → allow (industry-standard template files)
#   2. .env or .env.<env> (exact basename) → block (secrets)
#   3. PROTECTED_PATTERNS substring → block (configs, lockfiles, version pins)
#   4. otherwise → allow

INPUT="$(cat)"
FILE_PATH="$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')"

basename="${FILE_PATH##*/}"

# 1. *.example / *.sample / *.template are industry-standard suffixes for
# safe-to-commit template files. Allow them even if the rest of the name
# matches a protected pattern (e.g. .env.example, docker-compose.example.yml).
if [[ "$basename" == *.example || "$basename" == *.sample || "$basename" == *.template ]]; then
  exit 0
fi

# 2. .env-specific check: basename must be exactly .env or start with .env.
# Prevents false positives on names like .environment or foo.env.
if [[ "$basename" == ".env" || "$basename" == ".env."* ]]; then
  echo "BLOCKED: $FILE_PATH is a protected env file. Fix the code, not the config." >&2
  exit 2
fi

# 3. Generic protected patterns (substring match against full path)
PROTECTED_PATTERNS=(
  # Lint / format / type / build configs
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
  # Lockfiles — never hand-edit; let package managers regenerate
  "pnpm-lock.yaml"
  "package-lock.json"
  "yarn.lock"
  "Cargo.lock"
  "poetry.lock"
  "Pipfile.lock"
  "Gemfile.lock"
  "go.sum"
  # Language / tool version pins
  ".node-version"
  ".python-version"
  ".ruby-version"
  ".tool-versions"
  # Git internals
  ".git/"
)

for pattern in "${PROTECTED_PATTERNS[@]}"; do
  if [[ "$FILE_PATH" == *"$pattern"* ]]; then
    echo "BLOCKED: $FILE_PATH is a protected config file. Fix the code, not the config." >&2
    exit 2
  fi
done

exit 0
