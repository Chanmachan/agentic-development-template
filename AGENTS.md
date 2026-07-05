# Repository Instructions

## Source of truth
- Code, tests, schemas, ADRs, and CI are truth. Prose docs are not.
- Requirements: `docs/spec.md`
- Architecture decisions: `docs/adr/`

## Workflow
- In a fresh worktree, run `bash scripts/sync-local-docs.sh` first: `tasks/` is git-ignored and does not come with the branch (see README "Worktree setup"). Claude Code runs this automatically on session/subagent start (ADR 0009); Codex and Cursor still need the manual step.
- Do not start implementation before reading:
    - `docs/spec.md`
    - relevant ADRs in `docs/adr/`
- Plan → approval → implement. Never start coding without a plan.
- Implementation work goes on a feature branch (see `.claude/rules/git.md` / `.codex/rules/git.md`), never directly on `main`.
- Track every task per `.claude/rules/tasks.md` / `.codex/rules/tasks.md`: each task has its own per-task todo file (`tasks/{id}-todo.md`) and `tasks/tasks.jsonl` is the status registry. There is no privileged single todo.md.

## Quality gates
- Run lint, typecheck, and tests before finishing.
- Never modify lint/type/test config to make errors disappear.
- Never use `git commit --no-verify`.

## Guardrails
- Do not edit `.env*`, lockfiles, or `.git/`.
- Add or update tests for every behavior change.

## Repo map
- ideas: `idea/`
- research: `research/`
- specs/docs: `docs/`
- tasks: `tasks/`
- Claude hooks/skills/subagents/rules: `.claude/`
- Codex hooks/agents/rules: `.codex/`
- Codex skills: `.agents/skills/`
- Cursor implementer harness: `.cursor/`
- session contexts: `contexts/`
