---
name: context-review
description: Load the code-review session context (read-only stance, Blocking/Suggestion/Nit checklist) mid-session.
disable-model-invocation: true
---

Load `contexts/review.md` as this session's purpose-specific instructions, in addition to CLAUDE.md/AGENTS.md, which stay in effect.

!`cat ${CLAUDE_PROJECT_DIR}/contexts/review.md`
