# Claude Code Instructions

See: @AGENTS.md

## Workflow phases

1. **Plan** — 非自明な変更は `planner` subagent または Plan Mode (`plan-mode` skill) で計画し、成果物を `tasks/{id}-todo.md` に残し、`tasks/tasks.jsonl` に状態行を追記する (`planned`/`in_progress`)。
2. **Implement** — `tdd` skill に従い、失敗するテスト → 最小実装 → リファクタの順で進める。
3. **Verify** — lint / typecheck / test を通す (`stop-check.sh` が強制)。
4. **Commit** — `.claude/rules/git.md` に従う。PR レビュー対応は `/fix-review` コマンドを使う。指摘ゼロまで自動で回したいときは `/review-cycle` を使う。
5. **Archive** — MERGED したら `tasks/tasks.jsonl` の当該行を `status:"done"` + `done` パスに更新し、`tasks/{id}-todo.md` の内容を `tasks/done/{id}.md` に移す。`id` は内容が一目で分かる slug。

## Task tracking

> 正本のスキーマ・ライフサイクルは `.claude/rules/tasks.md`。以下は Claude 固有の運用補足。

- セッション開始時はまず `tasks/tasks.jsonl` で in-flight (status≠done) を把握し、関連する `tasks/{id}-todo.md` と `tasks/done/` の最新ノートを読んで直近の経緯を掴む。
- タスクごとに `tasks/{id}-todo.md` を持つ。特権的な単一 todo.md は廃止。
- 状態が動いたら (ブランチ作成 / PR open / blocked / merged) registry の当該行を**id キーで upsert** する (`id` ごとに 1 行、重複追記しない)。worktree からは `bash scripts/sync-tasks.sh upsert <id> ...` で更新する。
- `tasks/done/{id}.md` は self-contained に保つ (概要 / ブランチ / コミット / PR / 検証結果)。done 行は台帳として jsonl に残す。
- `tasks/` は git 管理外。分岐元 1 本を正とし (全 worktree で共有)、共有は PR 本文経由で行う。

## Context management

- 調査タスクは `investigator` subagent に委譲する (メイン文脈の汚染を防ぐ)。
- セッションが長くなったら `/compact` より `/clear` を優先する (要約より破棄のほうが文脈をクリーンに保てる)。
- 大規模リファクタはコンテキスト消費 20% 未満の段階で着手する。

## Skills and subagents

- `.claude/skills/` — `spec-interview`, `plan-mode`, `tdd`, `code-review`, `context-{dev,review,research,debug}` (オンデマンドロード)
- `.claude/agents/` — `planner`, `code-reviewer`, `investigator`, `enumerator` (委譲時にロード)
- `.claude/rules/` 索引: `git` / `tasks` / `pitfalls` / `model-roles`。path frontmatter の無い rule (`git` / `pitfalls` / `model-roles`) はセッション開始時に一読。`tasks` は ADR 0009 の path-scoping に従い、該当パス (`tasks/**`, `scripts/sync-tasks.sh`) を触るときだけロードされる。

## Hook profiles and contexts

- フック強度は `HOOK_PROFILE` (`minimal`/`standard`/`strict`) で切り替える。詳細は README とADR 0003。
- セッション目的別のシステムプロンプトは `contexts/{dev,review,research,debug}.md`。起動時は `claude --append-system-prompt "$(cat contexts/dev.md)"`、セッション途中は `/context-dev` 等の skill で注入。

## Editing rules

- Fix code errors from hooks before proceeding.
- If the same mistake recurs, encode it as a test or hook.
