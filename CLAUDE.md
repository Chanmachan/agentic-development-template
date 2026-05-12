# Claude Code Instructions

See: @AGENTS.md

## Workflow phases

1. **Plan** — 非自明な変更は `planner` subagent または Plan Mode (`plan-mode` skill) で計画し、成果物を `tasks/todo.md` に残す。
2. **Implement** — `tdd` skill に従い、失敗するテスト → 最小実装 → リファクタの順で進める。
3. **Verify** — lint / typecheck / test を通す (`stop-check.sh` が強制)。
4. **Commit** — `.claude/rules/git.md` に従う。PR レビュー対応は `/fix-review` コマンドを使う。

## Context management

- 調査タスクは `investigator` subagent に委譲する (メイン文脈の汚染を防ぐ)。
- セッションが長くなったら `/compact` より `/clear` を優先する (要約より破棄のほうが文脈をクリーンに保てる)。
- 大規模リファクタはコンテキスト消費 20% 未満の段階で着手する。

## Skills and subagents

- `.claude/skills/` — `tdd`, `code-review`, `plan-mode` (オンデマンドロード)
- `.claude/agents/` — `planner`, `code-reviewer`, `investigator` (委譲時にロード)

## Editing rules

- Fix code errors from hooks before proceeding.
- If the same mistake recurs, encode it as a test or hook.
