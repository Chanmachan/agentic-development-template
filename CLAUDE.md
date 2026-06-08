# Claude Code Instructions

See: @AGENTS.md

## Workflow phases

1. **Plan** — 非自明な変更は `planner` subagent または Plan Mode (`plan-mode` skill) で計画し、成果物を `tasks/todo.md` または task-specific な todo ファイルに残す。
2. **Implement** — `tdd` skill に従い、失敗するテスト → 最小実装 → リファクタの順で進める。
3. **Verify** — lint / typecheck / test を通す (`stop-check.sh` が強制)。
4. **Commit** — `.claude/rules/git.md` に従う。PR レビュー対応は `/fix-review` コマンドを使う。
5. **Archive** — 完了 / 凍結したタスクは `tasks/todo.md` から `tasks/done/{slug}.md` に移し、todo には in-flight の作業だけを残す。

## Task tracking

- セッション開始時は `tasks/todo.md` と `tasks/done/` 内の最新タスクノートを読み、現在状態と直近の経緯を把握する。
- `tasks/done/{slug}.md` は self-contained に保つ (概要 / ブランチ / コミット / PR / 検証結果)。

## Context management

- 調査タスクは `investigator` subagent に委譲する (メイン文脈の汚染を防ぐ)。
- セッションが長くなったら `/compact` より `/clear` を優先する (要約より破棄のほうが文脈をクリーンに保てる)。
- 大規模リファクタはコンテキスト消費 20% 未満の段階で着手する。

## Skills and subagents

- `.claude/skills/` — `spec-interview`, `plan-mode`, `tdd`, `code-review` (オンデマンドロード)
- `.claude/agents/` — `planner`, `code-reviewer`, `investigator` (委譲時にロード)

## Hook profiles and contexts

- フック強度は `HOOK_PROFILE` (`minimal`/`standard`/`strict`) で切り替える。詳細は README とADR 0003。
- セッション目的別のシステムプロンプトは `contexts/{dev,review,research,debug}.md`。`claude --append-system-prompt "$(cat contexts/dev.md)"` で注入。

## Editing rules

- Fix code errors from hooks before proceeding.
- If the same mistake recurs, encode it as a test or hook.
