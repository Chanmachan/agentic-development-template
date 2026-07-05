---
name: context-research
description: Load the research session context (compare options, write to research/, promote to ADR) mid-session.
disable-model-invocation: true
---

Load `contexts/research.md` as this session's purpose-specific instructions, in addition to CLAUDE.md/AGENTS.md, which stay in effect.

!`cat ${CLAUDE_PROJECT_DIR}/contexts/research.md`
