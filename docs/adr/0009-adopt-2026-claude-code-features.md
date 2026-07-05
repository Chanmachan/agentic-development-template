# ADR 0009: Adopt 2026 Claude Code features (paths-scoped rules, worktree auto-sync, context skills)

- Status: Accepted
- Date: 2026-07-06
- Last-validated: 2026-07-06

## Context

Since ADR 0002/0003 established the Rules/Skills/Subagents/Hooks layering and the `contexts/*.md` +
`HOOK_PROFILE` design, Claude Code has shipped three features this repo hadn't adopted yet (verified against
`code.claude.com/docs/en/{memory,hooks,skills}` on 2026-07-06):

1. **Path-scoped rules**: `.claude/rules/*.md` supports YAML frontmatter `paths: [<globs>]` so a rule loads
   only when Claude works with matching files, instead of unconditionally every session.
2. **`WorktreeCreate`/`WorktreeRemove` hook events**, which sounded like a natural fit for automating the
   manual `bash scripts/sync-local-docs.sh` step that `AGENTS.md`/README currently document for fresh
   worktrees.
3. **Skill frontmatter `disable-model-invocation: true`** (user-invocable only, description dropped from
   Claude's context) and **dynamic context injection** (`` !`command` `` lines whose output is substituted
   into the skill body before Claude ever sees it), which together can turn a file into a slash command that
   inlines that file's content on demand.

## Decision

### (a) Paths-scope `.claude/rules/tasks.md`; `git.md` stays unscoped

Added `paths: ["tasks/**", "scripts/sync-tasks.sh"]` frontmatter to `.claude/rules/tasks.md`. The
task-tracking schema/lifecycle is only relevant when Claude is actually touching `tasks/*` or
`scripts/sync-tasks.sh`; scoping it saves context in every session that isn't doing task-registry work.
`.claude/rules/git.md` is deliberately left **without** `paths` frontmatter (always loaded): commit
conventions apply to every session that might end in a `git commit`, and rules without a matching
in-progress file read to trigger on would otherwise silently never load when actually needed (a commit isn't
a file read). `.codex/rules/{git,tasks}.md` are symlinks to the `.claude/` originals (ADR 0008 (d)), so the
frontmatter travels automatically; Codex's own rule-loading behavior for `paths` is unverified (Codex has no
equivalent documented feature as of this ADR) — worst case Codex ignores the frontmatter block as inert YAML,
which is a safe failure mode either way.

### (b) Worktree auto-sync via `SessionStart`/`SubagentStart`, **not** `WorktreeCreate` — declined as unsafe

This is the one place the pre-verified assumption behind this ADR's implementation task turned out to be
wrong, caught by re-verifying against the live docs before writing the hook:

**`WorktreeCreate` REPLACES Claude Code's own git-worktree-creation behavior** for the `--worktree` CLI flag
and `isolation: "worktree"` (used by the `Agent` tool — actively exercised by this very repo's harness, see
the `worktree-agent-*` branches). Per the hooks reference: the hook itself is responsible for running
`git worktree add` and printing the new path to stdout (or `hookSpecificOutput.worktreePath` for HTTP hooks);
**any non-zero exit code fails worktree creation outright** (not just exit 2, unlike nearly every other hook
event); and a missing path on success also fails creation. A hook that only ran `sync-local-docs.sh` and
exited 0 — as the original implementation plan called for ("exit 0 always, setup failure must not block
worktree creation") — would never actually invoke `git worktree add` and would never print a path, which
would **silently disable `--worktree`/`isolation:"worktree"` project-wide** the moment `.claude/settings.json`
was picked up, since "printed nothing" reads to Claude Code as "creation failed to produce a path." Compounding
this, the exact input field carrying the worktree path was not independently confirmed across repeated
targeted fetches of the docs (one pass surfaced plausible field names `worktree_path`/`isolation_type`, a
stricter follow-up fetch found "no dedicated JSON schema" documented for this event) — so a *correct*
replacement implementation (faithfully re-running `git worktree add` with the right ref/branch) could not be
written safely without live verification against a real payload, which isn't available in this environment.
Given the asymmetric risk — a hook that's merely a no-op miss vs. one that silently breaks a core, actively-used
harness capability for every future session — this ADR **declines** to hook `WorktreeCreate`/`WorktreeRemove`
at all.

Instead, `.claude/hooks/worktree-setup.sh` is wired to **`SessionStart`** (matcher `startup`) and
**`SubagentStart`** (no matcher), both confirmed as purely additive, "Context only" events with no
decision/blocking control — `SessionStart`/`SubagentStart` failures render only as a swallowed "hook error"
notice ("Claude doesn't see it, the session or subagent proceeds" per docs) and can never affect whether a
session, subagent, or worktree comes into existence. `SubagentStart` is included alongside `SessionStart`
specifically because `isolation: "worktree"` agents are the more common worktree-creation path in this
repo's actual usage (background `Agent` calls), and per the docs' decision-control table `SessionStart`,
`Setup`, and `SubagentStart` share the identical safe contract. The wrapper script does not rely on the
hook's `cwd` (confirmed by docs to be the worktree's own directory for `SessionStart`, but this was not
independently re-confirmed for `SubagentStart`): it derives the worktree root from its own on-disk script
path instead (`.claude/hooks/worktree-setup.sh` is always two directories below the worktree root, in every
checkout), then runs `sync-local-docs.sh` there — verified locally against a throwaway two-worktree fixture
(main + child), confirming both the correct-worktree symlink and the main-checkout no-op. The wrapper is
deliberately **not** profile-gated via `lib/profile.sh` — every other hook in `.claude/hooks/` skips itself
outside its assigned `HOOK_PROFILE` tier, but this one is one-time environment setup (symlinking `tasks/`),
not a behavior guardrail; gating it out of `minimal` would leave prototyping worktrees without task tracking,
defeating the point of automating the step.

`AGENTS.md` / README still document the manual `bash scripts/sync-local-docs.sh` step, reworded as: automatic
for Claude Code (this hook), still required for Codex and Cursor, which have no equivalent hook mechanism.

### (c) `contexts/*.md` also exposed as `disable-model-invocation` skills with dynamic injection

Added `.claude/skills/context-{dev,review,research,debug}/SKILL.md`, each `disable-model-invocation: true`
(so Claude never auto-triggers a context switch, but `/context-dev` etc. work) with a single
`` !`cat ${CLAUDE_PROJECT_DIR}/contexts/dev.md` `` body line. `contexts/*.md` remains the single source of
truth; the skill is a thin, generated-feeling pointer, not a fork of the content. `${CLAUDE_PROJECT_DIR}` was
chosen over a bare relative `contexts/dev.md` path specifically because the docs recommend it for "project-
local scripts or files, independent of where the skill is installed" — implying the dynamic-injection
command's actual working directory is not guaranteed to be the project root, which a bare relative path would
have silently assumed. **Caveat**: `${CLAUDE_PROJECT_DIR}` substitution requires Claude Code ≥ v2.1.196; on
older versions the literal string would be passed to `cat` and fail, degrading to a skill that loads with an
error instead of the context body — this repo does not pin a minimum Claude Code version, so this is an
accepted gap rather than a guarded one. `claude --append-system-prompt "$(cat contexts/dev.md)"` remains the
documented path for session-start automation/aliases (unaffected — it doesn't route through skills at all).

### Declined

- **Native Task-system bridge for `tasks.jsonl`**: no confirmed, stable hook/API surface exists for
  intercepting Claude Code's own task/todo UI to mirror it into `tasks/tasks.jsonl`, and the existing
  `sync-tasks.sh` registry (ADR/`​.claude/rules/tasks.md`) already works and is portable across all three
  harnesses (Claude/Codex/Cursor). Revisit if/when such a surface is documented.
- **Output styles**: de-emphasized upstream as of this ADR's research pass; not adopted.
- **Skills-dir consolidation** (`.claude/skills/` vs `.agents/skills/`): already explicitly declined in ADR
  0008 (e) on separate grounds (tool-specific phrasing is a feature, not drift); this ADR does not revisit it.

## Consequences

### Positive

- `.claude/rules/tasks.md` no longer costs context in sessions that never touch `tasks/`.
- Fresh worktrees get `tasks/` symlinked automatically for Claude Code sessions and background
  `isolation:"worktree"` agents, with zero risk to the underlying worktree-creation mechanism itself (the
  chosen hooks structurally cannot block or fail it).
- `contexts/*.md` gained a second, lower-friction access path (`/context-dev` mid-session) without forking
  the content or requiring a session restart, while the automation path (`--append-system-prompt`) is
  untouched.

### Negative / Tradeoffs

- The `WorktreeCreate` hook this ADR's originating task asked for was not implemented; if Claude Code later
  exposes a verified, safe way to layer additive setup onto `WorktreeCreate` (e.g., a documented pre/post
  hook distinct from the replace-default one), the `SessionStart`/`SubagentStart` approach here should be
  revisited — right now it only covers the *start* of a session/subagent in a worktree, not the instant the
  worktree directory is created, so any command run against the worktree before the first
  session/subagent-start hook fires (rare in practice) would not yet see the `tasks/` symlink.
- `${CLAUDE_PROJECT_DIR}` requires Claude Code ≥ v2.1.196; no version guard exists elsewhere in this repo, so
  this ADR doesn't add one either, but it's the first place a hard version floor could bite silently.
- `SubagentStart`'s exact input-field/cwd contract was not independently re-verified beyond the shared
  "Context only" decision-control table row it shares with `SessionStart`/`Setup` — if it later turns out to
  differ materially, `worktree-setup.sh`'s script-path-relative design (not cwd-relative) is the mitigation
  already in place.
- `.claude/rules/tasks.md`'s `paths` frontmatter is unverified for Codex, which reads the same file via
  symlink (ADR 0008 (d)) but has no documented `paths`-equivalent; worst case it's inert YAML Codex ignores.

### Out of scope (future ADR)

- Revisiting `WorktreeCreate` if Claude Code ships a non-replacing worktree-lifecycle hook.
- Task-system native bridge, if a stable surface appears.
- Minimum-Claude-Code-version pinning/guarding (`${CLAUDE_PROJECT_DIR}` and other v2.1.19x+ features).

## References

- ADR 0002: Skills-first architecture と4層分離 (Rules/Skills/Subagents/Hooks layering)
- ADR 0003: Hook profiles, `contexts/` ディレクトリ (origin of `HOOK_PROFILE` and `contexts/*.md`)
- ADR 0006 §6 (live-verification-caveat precedent: documenting an unverifiable payload shape and the
  fail-open/fail-closed choice made around it, mirrored here for `WorktreeCreate`'s payload and
  `SubagentStart`'s contract)
- ADR 0008: 3ハーネス間の protected-path 判定を共有ライブラリへ集約 (e) — skills-dir consolidation declined,
  not revisited here
- `code.claude.com/docs/en/memory` — path-specific rules (`paths` frontmatter)
- `code.claude.com/docs/en/hooks` — `WorktreeCreate`/`WorktreeRemove`/`SessionStart`/`SubagentStart` event
  contracts, exit-code behavior, decision-control tables
- `code.claude.com/docs/en/skills` — `disable-model-invocation`, dynamic context injection (`` !`command` ``),
  `${CLAUDE_PROJECT_DIR}` substitution
