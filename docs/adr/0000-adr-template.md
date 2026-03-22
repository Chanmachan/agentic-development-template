# ADR 0001: Template baseline for agentic development

- Status: Accepted
- Date: 2026-03-22

## Context
This repository is intended to be used as a reusable starting point for AI-assisted software projects.

## Decision
We adopt:
- AGENTS.md for shared agent instructions
- CLAUDE.md for Claude-specific operational instructions
- Claude hooks in `.claude/settings.json`
- Lefthook for local pre-commit enforcement
- ADRs for architecture decisions
- tests/lint/typecheck as executable source of truth

## Consequences
- prose guidance stays short
- repeated mistakes must become hooks, tests, or rules
- planning documents should exist before large implementation work