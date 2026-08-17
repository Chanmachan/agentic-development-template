# Context: Development

このセッションは **新機能実装 / バグ修正** を目的とする。AGENTS.md と、利用中ツール固有の指示 (CLAUDE.md / Codex system instructions など) は引き続き有効。本ファイルはその差分。

> **本ファイルの役割**: セッション開始時の "姿勢" を agent に伝える。
> **Skills の役割**: 個々のフェーズ (TDD など) の手順詳細。
> 重複させず、姿勢と手順を分担する。手順は skill 側に置き、ここからは参照だけする。

## Workflow

フェーズ定義の正本は `CLAUDE.md` の "Workflow phases" (このファイルでは再定義しない)。

- **Explore first** (Plan フェーズの前段の姿勢) — 未知のコードに触る前に `plan-mode` skill または `investigator` subagent で読み取り、判断材料を集める。Edit/Write はしない
- **Verify before stopping** — 計画段階で **"何が pass/fail を示すか" を明文化**しておく (失敗するテスト、ビルド終了コード、スクリーンショット差分、ログ出力)。agent 自身が読める形にすることで `stop-check.sh` を待たず自走できる

## Subagent delegation

- 広範な調査が必要なとき → `investigator` (Read/Grep/Glob/Bash のみ、Write/Edit なし)
- 設計案を比較したいとき → `planner` (同上、出力は計画書)
- 自分の diff の自己レビュー → `code-reviewer`

メイン文脈の汚染を避ける。検索結果や調査ログをメインに引きずり込まない。

## Implementation rules

- 仕様外の機能を追加しない (要求のスコープを越えない)
- 過剰な抽象を導入しない。3 回出てきてから共通化する
- バグ修正に周辺リファクタを混ぜない (別 PR にする)
- コメントは "WHY が非自明" なときだけ書く。コードが語ることを再説しない

## Anti-patterns

- 計画なしで複数ファイル変更を始める
- テストなしで振る舞いを変える
- `git commit --no-verify` でフックを迂回する
- lint/typecheck/test の設定を緩めてエラーを消す
