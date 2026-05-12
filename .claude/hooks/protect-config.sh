#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/profile.sh"
hook_profile_skip protect-config

INPUT="$(cat)"
FILE_PATH="$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')"

PROTECTED_PATTERNS=(
  ".eslintrc"
  "eslint.config"
  "biome.json"
  "tsconfig.json"
  "pyproject.toml"
  "lefthook.yml"
  ".prettierrc"
  ".golangci.yml"
  "Cargo.toml"
  ".swiftlint.yml"
  ".pre-commit-config.yaml"
  ".env"
  ".env."
  ".git/"
)

for pattern in "${PROTECTED_PATTERNS[@]}"; do
  if [[ "$FILE_PATH" == *"$pattern"* ]]; then
    echo "BLOCKED: $FILE_PATH is a protected config file. Fix the code, not the config." >&2
    exit 2
  fi
done

exit 0
