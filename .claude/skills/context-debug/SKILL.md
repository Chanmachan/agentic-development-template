---
name: context-debug
description: Load the debugging session context (reproduce → hypothesize → verify → fix loop) mid-session.
disable-model-invocation: true
allowed-tools: Bash(cat ${CLAUDE_PROJECT_DIR}/contexts/debug.md)
---

Load `contexts/debug.md` as this session's purpose-specific instructions, in addition to CLAUDE.md/AGENTS.md, which stay in effect.

!`cat ${CLAUDE_PROJECT_DIR}/contexts/debug.md`
