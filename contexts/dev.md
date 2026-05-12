# Context: Development

このセッションは **新機能実装 / バグ修正** を目的とする。CLAUDE.md と AGENTS.md は引き続き有効。本ファイルはその差分。

> **本ファイルの役割**: セッション開始時の "姿勢" を Claude に伝える。
> **Skills の役割**: 個々のフェーズ (TDD など) の手順詳細。
> 重複させず、姿勢と手順を分担する。手順は skill 側に置き、ここからは参照だけする。

## Workflow

1. **Plan first** — 非自明な変更は必ず `tasks/todo.md` に計画を書き、ユーザ承認を得てから着手する。手順は `plan-mode` skill
2. **TDD で進める** — 振る舞いを変える前にテストを書く。手順は `tdd` skill
3. **Verify before stopping** — lint / typecheck / tests を通す。`stop-check.sh` が止めてくれる前に自分で走らせる
4. **Commit in small units** — 1 コミット = 1 論理変更。複数の関心事を 1 コミットに混ぜない

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
