#!/usr/bin/env bash
# HOOK_PROFILE gate for Cursor hooks (copy of .claude/hooks/lib/profile.sh).
#
# Kept aligned with the Claude/Codex version on purpose: the three harnesses
# (.claude, .codex, .cursor) each carry their own copy rather than sharing one
# lib, so a reader can reason about each in isolation (ADR 0005 §Decision).
#
# Usage (source-only — do not execute directly):
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/profile.sh"
#   hook_profile_skip post-lint
#
# Profile membership (per ADR 0003; Cursor adds protect-read/protect-shell as
# sibling guards of protect-config):
#   minimal  : post-lint
#   standard : post-lint, protect-config, protect-read, protect-shell, stop-check  (default)
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
        post-lint|protect-config|protect-read|protect-shell|stop-check) ;;
        *) exit 0 ;;
      esac
      ;;
    strict)
      ;;
    *)
      echo "WARN: unknown HOOK_PROFILE='$profile' (expected minimal|standard|strict); treating as standard" >&2
      case "$hook_name" in
        post-lint|protect-config|protect-read|protect-shell|stop-check) ;;
        *) exit 0 ;;
      esac
      ;;
  esac
}
