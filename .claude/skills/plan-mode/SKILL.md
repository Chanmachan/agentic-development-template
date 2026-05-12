---
name: plan-mode
description: Use before starting non-trivial implementation work — anything touching multiple files, introducing new abstractions, or with unclear requirements. Guides how to produce a written plan in tasks/todo.md and get user approval before coding. Trigger when the user asks to "plan", "design", "figure out how to", or when a request is ambiguous enough that jumping to code would be premature.
---

# Plan Mode Skill

## When to use

非自明な変更には必ず計画フェーズを挟む。具体的には:

- 複数ファイル / 複数モジュールにまたがる変更
- 新しい抽象 (関数、クラス、ファイル) を導入する
- 仕様が曖昧、または要求が複数解釈できる
- パフォーマンスやセキュリティに影響する変更
- ADR が必要そうな設計判断を含む

スキップしてよい: 1 ファイル内の typo 修正、明確な 1 行バグ修正、ドキュメント修正。

## How to plan

### 1. Inputs を揃える

- `docs/spec.md` の関連セクション
- 関連 ADR
- 既存コードの該当箇所 (調査が広範なら `investigator` / `planner` subagent に委譲)
- ユーザの要求文 (曖昧な部分は質問するか、合理的判断で進めて transparent に伝える)

### 2. tasks/todo.md に書く

成果物は **`tasks/todo.md`** (リポジトリ規約)。以下の構造で書く:

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

- `tasks/todo.md` をユーザに提示し、**実装に入る前に明示的な OK を得る**
- ユーザが「進めて」と言うまで Edit / Write を実行しない (Plan Mode の本旨)
- 計画への指摘があれば `tasks/todo.md` を更新して再承認

### 4. 実装中の計画更新

- 計画と実態が乖離したら、コードを書く前に `tasks/todo.md` を更新する
- 「メモリに保存」ではなく `tasks/todo.md` を更新するのが原則 (現在の会話のスコープなので)

## Delegating to planner subagent

調査範囲が広い / 設計案を複数比較したい場合は `planner` subagent に委譲する。planner は Read / Grep / Glob / Bash のみを持ち Write / Edit を持たないため、誤って実装に手を出さない保証がある。

## Anti-patterns

- 計画なしで非自明な変更を始める
- `tasks/todo.md` に書かず、会話文脈にだけ計画を残す (`/clear` で消える)
- 承認なしに Edit を実行する
- 計画と実装の乖離を放置する
