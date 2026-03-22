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
```

**Required per language — install for your stack before running Claude Code**

| Language | Tools | Install |
|----------|-------|---------|
| TypeScript / JavaScript | `biome`, `oxlint` | `npm install -D @biomejs/biome oxlint` |
| Python | `ruff` | `pip install ruff` |
| Go | `gofumpt`, `golangci-lint` | `brew install gofumpt golangci-lint` |
| Rust | `rustfmt`, `cargo` | `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \| sh` |

> Hooks will exit with an error and tell you what's missing if a required tool is not found.  
> **Do not skip this step** — the PostToolUse hook will fail silently or block Claude Code if tools are absent.

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

**`.claude/hooks/post-lint.sh`** — TS/JS is enabled by default.  
For other languages, uncomment the relevant block and comment out the TS/JS block.

### 4. Fill in `docs/spec.md`

Write the purpose, goals, and constraints of your project.  
Claude Code reads this first before starting any implementation.

```
docs/spec.md  ← fill this in
```

### 5. Create your first ADR

```bash
cp docs/adr/0000-adr-template.md docs/adr/0001-tech-stack.md
# Record your tech stack decisions
```

### 6. Start Claude Code

```bash
cd your-project
claude
```

---

## Repository Structure

```
.
├── AGENTS.md              # Universal agent instructions (keep under 50 lines)
├── CLAUDE.md              # Claude Code-specific instructions
├── lefthook.yml           # Pre-commit hook configuration
│
├── .claude/
│   ├── settings.json      # Claude Code Hook & permission settings
│   └── hooks/
│       ├── protect-config.sh  # Block edits to linter configs (PreToolUse)
│       ├── post-lint.sh       # Auto-lint after every file edit (PostToolUse)
│       │                      # ★ Edit this to match your language
│       └── stop-check.sh      # Block completion until tests pass (Stop)
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
├── tasks/
│   ├── todo.md            # Current tasks and progress
│   └── tasks.jsonl        # Task list for automated development runs
│
├── scripts/
│   └── check-doc-health.sh  # Checks AGENTS.md line count & ADR freshness
│
├── src/                   # Source code (structure per your language/framework)
└── tests/                 # Test code
```

---

## Built-in Guardrails

These run automatically every time Claude Code writes code:

| Trigger | Behavior |
|---------|----------|
| After file edit (PostToolUse) | Runs linter/formatter and feeds violations back to the agent |
| Before config file edit (PreToolUse) | Blocks changes to `eslint.config`, `biome.json`, etc. |
| On completion (Stop) | Blocks the session from ending until lint and tests pass |
| Before commit (Lefthook) | Checks `AGENTS.md` line count and ADR freshness |

---

## Checklist: What to Edit When Starting a New Project

Files you **must** edit:

- [ ] Install language tools (see Prerequisites above)
- [ ] `docs/spec.md` — Write project purpose and goals
- [ ] `docs/adr/000*-*.md` — Record your tech stack decisions
- [ ] `lefthook.yml` — Uncomment the lint command for your language
- [ ] `.claude/hooks/post-lint.sh` — Uncomment the block for your language
- [ ] `tasks/todo.md` — Add your first tasks
- [ ] `AGENTS.md` — Add project-specific rules if needed (keep under 50 lines)

Files you should **not** change (they are the guardrails themselves):

- `.claude/settings.json`
- `.claude/hooks/protect-config.sh`
- `.claude/hooks/stop-check.sh`
- `scripts/check-doc-health.sh`

---

## Development Flow

```
1. Dump all ideas into idea/
2. Research and explore in research/
3. Consolidate into docs/spec.md
4. Record decisions in docs/adr/
5. Break work into tasks/todo.md
6. Run `claude` and start building
```

**Write the spec before writing code.** Claude Code reads `docs/spec.md` and `docs/adr/` before implementing anything.

---

## References

- [Coding Agent Workflow (2026)](https://nyosegawa.github.io/posts/coding-agent-workflow-2026/)
- [Harness Engineering Best Practices](https://nyosegawa.com/posts/harness-engineering-best-practices-2026/)