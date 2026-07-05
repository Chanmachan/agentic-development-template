---
name: context-dev
description: Load the dev session context (Plan → TDD → Verify, subagent delegation) mid-session.
disable-model-invocation: true
---

Load `contexts/dev.md` as this session's purpose-specific instructions, in addition to CLAUDE.md/AGENTS.md, which stay in effect.

!`cat ${CLAUDE_PROJECT_DIR}/contexts/dev.md`
