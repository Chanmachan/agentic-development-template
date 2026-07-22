---
name: plan-mode
description: Use before starting non-trivial implementation work — anything touching multiple files, introducing new abstractions, or with unclear requirements. Guides how to produce a written plan in tasks/<id>-todo.md (per-task file) and get user approval before coding. Trigger when the user asks to "plan", "design", "figure out how to", or when a request is ambiguous enough that jumping to code would be premature.
---

# Plan Mode Skill

## When to use

plan 必須 (いずれか該当したら計画フェーズを挟む):

- (a) テスト以外の変更ファイルが 2 個以上
- (b) 新規ファイル追加
- (c) DB スキーマ・マイグレーション・セキュリティ境界に触れる変更
- (d) 公開 API・共有型のシグネチャ変更
- (e) ユーザ要求が複数解釈できる

全て非該当なら skip 可 (1 ファイル内の typo・明確な 1 行修正・ドキュメント修正)。**迷ったら plan**。

## How to plan

### 1. Inputs を揃える

- `docs/spec.md` の関連セクション
- 関連 ADR
- 既存コードの該当箇所 (調査が広範なら `investigator` / `planner` subagent に委譲)
- ユーザの要求文 (曖昧な部分は質問するか、合理的判断で進めて transparent に伝える)

### 2. tasks/<id>-todo.md に書く

成果物は **`tasks/<id>-todo.md`** (リポジトリ規約: タスクごとに 1 ファイル、`id` は内容が分かる kebab-case slug。特権的な単一 todo.md は廃止)。承認後に `tasks/tasks.jsonl` へ状態行を追記する (スキーマ・ライフサイクルは `.codex/rules/tasks.md`)。以下の構造で書く:

```markdown
# <タスク名>

## Goal
1〜2 文で達成したい状態を書く。

## Approach
- 取るアプローチを 3〜5 個の bullet で
- 採用しなかった選択肢と理由も 1 行で

## Steps
1. <最小の変更単位>
2. <最小の変更単位>
3. ...

## Verification
- 自動で確認できる手段 (テスト、lint、typecheck)
- 手動で確認すべき項目 (UI 変更ならブラウザ確認手順)

## Risks
- 想定される失敗モードと、検知方法
```

### 3. 承認を得る

- todo ファイルをユーザに提示し、**実装に入る前に明示的な OK を得る**
- ユーザが「進めて」と言うまで Edit / Write を実行しない (Plan Mode の本旨)
- 計画への指摘があれば同じ todo ファイルを更新して再承認

### 4. 実装前に feature ブランチを切る

承認後・最初の Edit / Write の前に、`.claude/rules/git.md` / `.codex/rules/git.md` の命名規則に従って feature ブランチを作成する (`feature/...`, `fix/...`, `chore/...` 等)。`main` 上で直接コミットしない。後追いでブランチを切ると履歴が分岐しづらく、PR 単位の差分も汚れる。

### 5. 実装中の計画更新

- 計画と実態が乖離したら、コードを書く前に該当 todo ファイルを更新する
- 「メモリに保存」ではなく todo ファイルを更新するのが原則 (現在の会話のスコープなので)

## Delegating to planner subagent

調査範囲が広い / 設計案を複数比較したい場合は `planner` subagent に委譲する。planner は Read / Grep / Glob / Bash のみを持ち Write / Edit を持たないため、誤って実装に手を出さない保証がある。

## Anti-patterns

- 計画なしで非自明な変更を始める
- todo ファイルに書かず、会話文脈にだけ計画を残す (`/clear` で消える、Plan と Implement の境界が曖昧になり承認の所在も失われる)
- 承認なしに Edit を実行する
- 計画と実装の乖離を放置する
