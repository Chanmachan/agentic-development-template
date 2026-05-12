#!/usr/bin/env bash
# HOOK_PROFILE gate for Claude Code hooks.
#
# Usage (source-only — do not execute directly):
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/profile.sh"
#   hook_profile_skip post-lint
#
# Profile membership (per ADR 0003):
#   minimal  : post-lint
#   standard : post-lint, protect-config, stop-check     (default)
#   strict   : all hooks
#
# If the current hook is not in the active profile, this function calls `exit 0`
# so the hook becomes a no-op. The active profile is read from $HOOK_PROFILE.

hook_profile_skip() {
  local hook_name="$1"
  local profile="${HOOK_PROFILE:-standard}"

  case "$profile" in
    minimal)
      [[ "$hook_name" == "post-lint" ]] || exit 0
      ;;
    standard)
      case "$hook_name" in
        post-lint|protect-config|stop-check) ;;
        *) exit 0 ;;
      esac
      ;;
    strict)
      ;;
    *)
      echo "WARN: unknown HOOK_PROFILE='$profile' (expected minimal|standard|strict); treating as standard" >&2
      case "$hook_name" in
        post-lint|protect-config|stop-check) ;;
        *) exit 0 ;;
      esac
      ;;
  esac
}
