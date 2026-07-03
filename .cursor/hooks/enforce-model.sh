#!/usr/bin/env bash
# Cursor beforeSubmitPrompt adapter: deny prompts sent with a non-Composer model.
#
# Goal: keep every Composer session on the "Auto + Composer" included pool.
# When Auto is selected the resolved slug varies per generation, so the policy
# is prefix-based: allow anything whose slug starts with CURSOR_REQUIRED_MODEL_PREFIX
# (default "composer"), deny everything else.
#
# Fail-open policy: if the payload carries no model field at all (payload drift /
# older Cursor version), the hook allows the prompt so the session is never bricked
# by a schema change. The missing-field event is captured via hook_debug for later
# verification.
#
# Env overrides (style of CURSOR_STOP_LOOP_LIMIT):
#   CURSOR_REQUIRED_MODEL_PREFIX  — prefix to require (default: "composer").
#                                   Set to empty string to disable enforcement.
#
# Response shape: {permission:"deny", agent_message, user_message} — the same
# structured deny used by all control-capable events in this harness (see
# lib/protected.sh deny()). beforeSubmitPrompt is listed as control-capable in the
# Cursor docs; the exact field name is unconfirmed live — see README §実機確認.
set -euo pipefail

DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$DIR/lib/profile.sh"
hook_profile_skip enforce-model
source "$DIR/lib/protected.sh"

INPUT="$(cat)"
hook_debug beforeSubmitPrompt "$INPUT"

# Allow-all fast path: empty prefix disables enforcement.
REQUIRED_PREFIX="${CURSOR_REQUIRED_MODEL_PREFIX:-composer}"
if [ -z "$REQUIRED_PREFIX" ]; then
  exit 0
fi

# Extract model slug. Fall back to model_id if model is absent or empty.
model="$(printf '%s' "$INPUT" | jq -r '
  if (.model // "" | length) > 0 then .model
  elif (.model_id // "" | length) > 0 then .model_id
  else ""
  end' 2>/dev/null)" || model=""

# Fail-open: if no model field in payload, log and allow.
if [ -z "$model" ]; then
  hook_debug beforeSubmitPrompt-no-model "$INPUT"
  exit 0
fi

# Case-insensitive prefix check.
model_lc="$(printf '%s' "$model" | tr '[:upper:]' '[:lower:]')"
prefix_lc="$(printf '%s' "$REQUIRED_PREFIX" | tr '[:upper:]' '[:lower:]')"

if [ "${model_lc#"$prefix_lc"}" = "$model_lc" ]; then
  # Slug does NOT start with the required prefix — deny.
  deny \
    "Model '$model' is not allowed. Switch to Composer 2.5 (IDE: pick Composer 2.5 in the model picker; CLI: cursor-agent --model composer-2.5). The current session will use the Composer included pool." \
    "Blocked: model '$model' is not Composer. IDE: set model to Composer 2.5 in the picker. CLI: cursor-agent --model composer-2.5."
fi

exit 0
