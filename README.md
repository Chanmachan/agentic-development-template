# Agentic Development Template

A template repository for AI-assisted development with [Claude Code](https://code.claude.com) / Codex.  
Harness Engineering best practices — Hooks, Linter, ADR, and guardrails — are built in from day one.

> ⚠️ Update this README as your project evolves.

---

## Prerequisites

Install the following tools before starting:

**Required (all projects)**

```bash
# Lefthook — pre-commit hook runner
brew install lefthook

# jq — JSON processor used in hooks
brew install jq

# gh — GitHub CLI (used by /fix-review and /multi-review for PR operations)
brew install gh && gh auth login
```

**Required per language — install for your stack before running Claude Code or Codex**

| Language | Tools | Install |
|----------|-------|---------|
| TypeScript / JavaScript | `biome`, `oxlint` | `npm install -D @biomejs/biome oxlint` |
| Python | `ruff` | `pip install ruff` |
| Go | `gofumpt`, `golangci-lint` | `brew install gofumpt golangci-lint` |
| Rust | `rustfmt`, `cargo` | `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \| sh` |

> Hooks will exit with an error and tell you what's missing if a required tool is not found.  
> **Do not skip this step** — the PostToolUse hook can block Claude Code or Codex if tools are absent.

---

## Getting Started

### 1. Copy this repository

```bash
# Click "Use this template" on GitHub, or:
git clone https://github.com/Chanmachan/template-repo.git your-project
cd your-project
```

### 2. Install Lefthook

```bash
lefthook install
```

### 3. Configure hooks for your language

**`lefthook.yml`** — uncomment the lint command for your language:

| Language | Line to uncomment |
|----------|-------------------|
| TypeScript / JavaScript | `lint-ts` |
| Python | `lint-py` |
| Go | `lint-go` |

**`.claude/hooks/post-lint.sh` / `.codex/hooks/post-lint.sh`** — TS/JS is enabled by default.  
For other languages, uncomment the relevant block and comment out the TS/JS block.

### 4. Fill in `docs/spec.md`

Write the purpose, goals, and constraints of your project.  
Claude Code and Codex read this first before starting any implementation.

```
docs/spec.md  ← fill this in
```

### 5. Create your first ADR

```bash
cp docs/adr/0000-adr-template.md docs/adr/0001-tech-stack.md
# Record your tech stack decisions
```

### 6. Start an agent session

```bash
cd your-project
claude   # Claude Code
codex    # Codex
```

---

## Repository Structure

```
.
├── AGENTS.md              # Universal agent instructions (keep under 50 lines)
├── CLAUDE.md              # Claude Code-specific instructions
├── CLAUDE.local.md        # (optional, gitignored) personal project notes
├── lefthook.yml           # Pre-commit hook configuration
│
├── .claude/
│   ├── settings.json      # Claude Code Hook & permission settings
│   ├── agents/            # Subagents (planner, code-reviewer, investigator)
│   │   └── reviewers/     # Per-perspective review subagents (correctness, security, tests, performance, readability, docs-adr)
│   ├── skills/            # On-demand skills (spec-interview, plan-mode, tdd, code-review)
│   ├── commands/          # Slash commands (/fix-review, /handoff, /multi-review)
│   └── hooks/
│       ├── lib/profile.sh     # HOOK_PROFILE gating (sourced by other hooks)
│       ├── protect-config.sh  # Block edits to linter configs (PreToolUse)
│       ├── post-lint.sh       # Auto-lint after every file edit (PostToolUse)
│       │                      # ★ Edit this to match your language
│       ├── stop-check.sh      # Block completion until tests pass (Stop)
│       └── suggest-compact.mjs # Suggest /clear when context fills (strict only)
│
├── .codex/
│   ├── hooks.json         # Codex hook settings
│   ├── agents/            # Codex subagent TOML files
│   │                      # Includes review-*.toml perspective reviewers
│   ├── rules/             # Codex-local reusable rules
│   └── hooks/             # Codex hook scripts mirroring .claude/hooks
│
├── .agents/
│   └── skills/            # Codex skills (spec-interview, plan-mode, tdd, code-review, fix-review, handoff, multi-review)
│
├── contexts/              # Session-purpose system prompts (dev/review/research/debug)
│
├── docs/
│   ├── spec.md            # ★ Project specification (edit this first)
│   ├── architecture.md    # System architecture notes
│   └── adr/               # Architecture Decision Records
│       └── 0000-adr-template.md
│
├── idea/                  # Raw ideas and brainstorming (keep it messy)
├── research/              # Research notes (no design decisions here)
│
├── tasks/                 # (gitignored) Local task tracking — convention: .claude/rules/tasks.md
│   ├── tasks.jsonl        # Status registry (one line per task)
│   ├── <id>-todo.md       # Per-task plan/checklist
│   └── done/<id>.md       # Archived task records (once merged)
│
├── scripts/
│   ├── check-doc-health.sh  # Checks AGENTS.md line count & ADR freshness
│   ├── sync-tasks.sh        # Read/upsert the tasks.jsonl registry (locked, atomic)
│   └── sync-local-docs.sh   # Worktree setup: symlink tasks/ + copy gitignored docs
│
├── src/                   # Source code (structure per your language/framework)
└── tests/                 # Test code
```

---

## Built-in Guardrails

These run automatically when the configured agent writes code:

| Trigger | Behavior |
|---------|----------|
| After file edit (PostToolUse) | Runs linter/formatter and feeds violations back to the agent |
| Before config file edit (PreToolUse) | Blocks changes to configs, secrets, lockfiles, and version pins. `*.example` / `*.sample` / `*.template` are allowlisted |
| On completion (Stop) | Blocks the session from ending until lint, typecheck (if configured), and tests pass. Auto-detects pnpm via `pnpm-lock.yaml` or `packageManager` field |
| Before any tool use (PreToolUse, strict only) | `suggest-compact` nudges `/clear` when context approaches the limit |
| Before commit (Lefthook) | Checks `AGENTS.md` line count and ADR freshness |

---

## Hook Profiles

Hooks are gated by `HOOK_PROFILE` (default `standard`). Set it per session to dial guardrail strength up or down without disabling hooks entirely. See ADR 0003 for rationale.

| Profile | Active hooks | Use when |
|---------|--------------|----------|
| `minimal` | post-lint | Prototyping, demos, external repos |
| `standard` (default) | post-lint, protect-config, stop-check | Day-to-day development |
| `strict` | all of standard + suggest-compact (+ future hooks) | Pre-release, hardening branches |

```bash
HOOK_PROFILE=minimal claude     # loosen Claude Code
HOOK_PROFILE=strict claude      # tighten Claude Code
HOOK_PROFILE=minimal codex      # loosen Codex
HOOK_PROFILE=strict codex       # tighten Codex
```

`suggest-compact.mjs` uses transcript byte size / 4 as a rough token estimate. Override the threshold via `SUGGEST_COMPACT_THRESHOLD` (default `140000`).

---

## Session Contexts

`contexts/*.md` are purpose-specific system prompts. For Claude Code they complement `CLAUDE.md`; for Codex they complement `AGENTS.md` and project skills. Inject one at session start when your tool supports an appended system prompt:

```bash
claude --append-system-prompt "$(cat contexts/dev.md)"
```

Suggested shell aliases:

```bash
alias cc-dev='claude --append-system-prompt "$(cat contexts/dev.md)"'
alias cc-review='HOOK_PROFILE=strict claude --append-system-prompt "$(cat contexts/review.md)"'
alias cc-research='claude --append-system-prompt "$(cat contexts/research.md)"'
alias cc-debug='claude --append-system-prompt "$(cat contexts/debug.md)"'
```

| Context | Focus |
|---------|-------|
| `dev.md` | Plan → TDD → Verify, subagent delegation rules |
| `review.md` | Read-only stance, Blocking/Suggestion/Nit categorization |
| `research.md` | Comparing options, writing to `research/`, promoting to ADR |
| `debug.md` | Reproduce → hypothesize → verify → fix loop |

---

## Code Review

Five mechanisms with different cost/depth trade-offs. Pick by context, not habit.

| Mechanism | Where | When to use |
|-----------|-------|-------------|
| `code-review` skill | Main conversation | Short diffs (~few hundred lines), inline self-review before commit |
| `code-reviewer` subagent | Isolated read-only context | Single-perspective review of a large diff that would pollute the main context |
| `multi-review` workflow | 6 isolated contexts in parallel | Full PR review. 6 specialists (correctness / security / tests / performance / readability / docs-adr) evaluate independently and a coordinator merges findings |
| `review-cycle` command | Main conversation, orchestrates subagents | Run review→fix→re-review automatically until no actionable findings remain (max 3 rounds) |
| External independent review | Tool-dependent | Pre-merge final gate when independent verification is needed |

`multi-review` is the default for PR review. Each reviewer lives in `.claude/agents/reviewers/<angle>.md` for Claude Code and `.codex/agents/review-<angle>.toml` for Codex, with read-only intent and a fixed-shape body (Mission / Checklist / Process / Output / Rules). The `docs-adr` reviewer is adaptive: it auto-skips ADR/spec/rule checks when those files are absent, so the reviewer setup is portable to other repositories.

```bash
/multi-review                # local HEAD vs main
/multi-review 123            # PR #123
/multi-review 123 --skip=performance,docs-adr
/multi-review 123 --only=security,correctness
```

See ADR 0004 for the design rationale.

---

## Task Tracking

`tasks/` is **git-ignored local working state** (like `tmp/` and `log/`), not shipped to teammates — share via the PR body. The convention itself lives in committed docs, so it travels with every clone:

- `.claude/rules/tasks.md` / `.codex/rules/tasks.md` — canonical schema and lifecycle.
- Each task gets its own `tasks/<id>-todo.md` plan file; `tasks/tasks.jsonl` is the status registry (one line per task, upserted by `id`). There is no privileged single `todo.md`.

Update a registry line safely (locked, atomic write) with the helper:

```bash
bash scripts/sync-tasks.sh list                          # show all tasks
bash scripts/sync-tasks.sh get <id>                      # show one task
bash scripts/sync-tasks.sh upsert <id> status=in_progress branch=feature/x pr=12
```

### Worktree setup

`tasks/` is **single-sourced in the main checkout (分岐元)**. Because it is git-ignored, a fresh `git worktree` starts without it. Run this once in a new worktree:

```bash
bash scripts/sync-local-docs.sh            # symlink tasks/ to the main checkout (+ copy any gitignored docs)
bash scripts/sync-local-docs.sh --dry-run  # preview without changing anything
```

It auto-detects the main checkout via `git rev-parse --git-common-dir`, no-ops when run from the main checkout itself, and symlinks the worktree's `tasks/` to the shared one. So every worktree reads/writes one `tasks/tasks.jsonl` registry, todo files, and `tasks/done/` — all worktrees' work is visible in one place, and nothing is lost when a worktree is deleted (no copy-back step). Use `bash scripts/sync-tasks.sh upsert <id> ...` to update the shared registry safely, and give non-main-track task ids a namespace prefix (e.g. `principal-<slug>`) so the shared registry has no id collisions. If your project also git-ignores some docs (spec, business notes), list them in the `PATHS` array of `sync-local-docs.sh` to have them copied in too.

---

## Checklist: What to Edit When Starting a New Project

Files you **must** edit:

- [ ] Install language tools (see Prerequisites above)
- [ ] `docs/spec.md` — Write project purpose and goals
- [ ] `docs/adr/000*-*.md` — Record your tech stack decisions
- [ ] `lefthook.yml` — Uncomment the lint command for your language
- [ ] `.claude/hooks/post-lint.sh` / `.codex/hooks/post-lint.sh` — Uncomment the block for your language
- [ ] `tasks/<id>-todo.md` + `tasks/tasks.jsonl` — Add your first task (see `.claude/rules/tasks.md`)
- [ ] `AGENTS.md` — Add project-specific rules if needed (keep under 50 lines)

Files you should **not** change (they are the guardrails themselves):

- `.claude/settings.json`
- `.codex/hooks.json`
- `.claude/hooks/protect-config.sh` / `.codex/hooks/protect-config.sh`
- `.claude/hooks/stop-check.sh` / `.codex/hooks/stop-check.sh`
- `scripts/check-doc-health.sh`

---

## Development Flow

```
1. Dump all ideas into idea/
2. Research and explore in research/
3. Consolidate into docs/spec.md  ← use the `spec-interview` skill to drive this interactively
4. Record decisions in docs/adr/
5. Break work into `tasks/<id>-todo.md` + a `tasks/tasks.jsonl` line  ← use the `plan-mode` skill
6. Run `claude` or `codex` and start building (TDD via the `tdd` skill)
```

**Write the spec before writing code.** Claude Code and Codex read `docs/spec.md` and `docs/adr/` before implementing anything.

The `spec-interview` skill uses `AskUserQuestion` to walk you through purpose / scope / acceptance criteria / constraints / trade-offs, then writes the result to `docs/spec.md`. Run it in its own session, then `/clear` and start a fresh session for implementation — this keeps specification bias from leaking into implementation decisions.

---

## References

- [Coding Agent Workflow (2026)](https://nyosegawa.github.io/posts/coding-agent-workflow-2026/)
- [Harness Engineering Best Practices](https://nyosegawa.com/posts/harness-engineering-best-practices-2026/)
