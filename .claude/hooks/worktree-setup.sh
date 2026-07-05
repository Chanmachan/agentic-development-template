#!/usr/bin/env bash
# SessionStart / SubagentStart hook: auto-run sync-local-docs.sh so a fresh
# git worktree gets its tasks/ symlink without the manual step documented in
# AGENTS.md / README ("Worktree setup"). See ADR 0009.
#
# Why SessionStart/SubagentStart and NOT WorktreeCreate (verified against
# code.claude.com/docs/en/hooks, 2026-07-06): WorktreeCreate REPLACES Claude
# Code's own git-worktree-creation behavior for `--worktree` / `isolation:
# "worktree"` — the hook itself is responsible for running `git worktree add`
# and printing the new path to stdout, and ANY non-zero exit fails creation
# outright (not just exit 2, unlike almost every other hook event). A hook
# that only ran this setup script and exited 0 — without performing the add
# or printing a path — would satisfy "exit 0" but never create the worktree
# and never emit the required path, silently breaking `--worktree` and
# `isolation: "worktree"` project-wide. The exact input field carrying the
# worktree path also isn't documented with a verbatim schema, so a correct
# replacement (re-implementing `git worktree add` faithfully) can't be done
# safely without live verification against a real payload.
#
# SessionStart/SubagentStart are the safe alternative: purely additive
# ("Context only" — no decision/blocking control), and exit 2 is swallowed
# ("Claude doesn't see it, the session or subagent proceeds" per docs) so a
# failure here can never affect worktree creation or the session/subagent
# itself. `cwd` is confirmed to be the worktree's own directory when a
# session starts inside one, but this script does not rely on that — it
# derives the worktree root from its own on-disk location instead, so it is
# correct regardless of the hook's invocation cwd.
#
# Deliberately NOT profile-gated (runs in every HOOK_PROFILE, unlike the
# other hooks in this directory): this is one-time environment setup
# (symlinking tasks/), not a behavior guardrail. Skipping it in `minimal`
# would leave prototyping worktrees without task tracking, defeating the
# point of automating the step.

# No `set -e`: a failure anywhere in this script must never surface as a
# non-zero exit. SessionStart/SubagentStart can't block regardless, but a
# non-zero exit still renders a "hook error" notice in the transcript, and
# silent, best-effort setup is the whole point here.
set -u

# Drain stdin so Claude Code never blocks on an unread hook input pipe.
cat >/dev/null 2>&1

# Resolve the worktree root from this script's own path (two levels up from
# .claude/hooks/), not from $PWD — this makes the sync target correct
# regardless of what cwd the hook was actually invoked with.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
if [ -z "$SCRIPT_DIR" ]; then
  exit 0
fi
WORKTREE_ROOT="$(cd "$SCRIPT_DIR/../.." 2>/dev/null && pwd)"
if [ -z "$WORKTREE_ROOT" ] || [ ! -f "$WORKTREE_ROOT/scripts/sync-local-docs.sh" ]; then
  exit 0
fi

(cd "$WORKTREE_ROOT" && bash scripts/sync-local-docs.sh) >/dev/null 2>&1

exit 0
