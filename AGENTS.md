# Repository Instructions

## Source of truth
- Code, tests, schemas, ADRs, and CI are truth. Prose docs are not.
- Requirements: `docs/spec.md`
- Architecture decisions: `docs/adr/`

## Workflow
- Do not start implementation before reading:
    - `docs/spec.md`
    - relevant ADRs in `docs/adr/`
- Plan → approval → implement. Never start coding without a plan.

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
- hooks: `.claude/hooks/`
- skills: `.claude/skills/`
- subagents: `.claude/agents/`