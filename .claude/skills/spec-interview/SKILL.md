---
name: spec-interview
description: Use when starting a new project, feature, or component whose specification doesn't yet exist. Drives an interview-style flow using AskUserQuestion to surface purpose, scope, success criteria, constraints, edge cases, and trade-offs, then writes the result to docs/spec.md (or docs/specs/<feature>.md). Trigger when the user asks to "write a spec", "define requirements", "start a new project", or when docs/spec.md is empty and implementation is being discussed.
---

# Spec Interview Skill

## When to use

`docs/spec.md` または対象機能の仕様が**まだ存在しない** ときに使う。具体的には:

- 新しいプロジェクトを開始するとき (`docs/spec.md` が空または雛形のみ)
- 既存プロジェクトに大きな機能を追加するとき (機能単位の spec が必要)
- ユーザの最初の要求が曖昧で、複数解釈できるとき

skip してよい: 既に spec がある修正、明確な 1 行バグ修正、リネーム、承認済み `tasks/todo.md` がある作業。

## Principle

仕様は実装より先に確定させ、**実装は別セッションで行う**。spec 作成中に固まった「こう作るつもり」というバイアスが実装フェーズの判断を歪めるのを避けるため (公式が "specification bias" として警告)。

## How to interview

### 1. Ask, don't assume

`AskUserQuestion` ツールで以下の観点を順に掘る。一度に 1〜3 問ずつ、ユーザが答えやすい単位に分ける。

- **Purpose**: 何を解決したいのか / なぜ今なのか
- **Users & scenarios**: 誰が使うか / 主要ユースケース 3 個まで
- **Scope boundaries**: 含めるもの / **明示的に含めないもの (out of scope)**
- **Acceptance criteria**: 何が満たされたら "完成" と言えるか — **測定可能な形** で
- **Constraints**: 技術 / 時間 / 依存 / 既存 ADR との整合
- **Edge cases**: ユーザが想定してなさそうな境界条件を 1〜2 個ぶつけて反応を見る
- **Trade-offs**: 明示的に二択を作る (シンプル vs 拡張性、速度 vs 一貫性 等)

明らかな質問はしない。掘るべきは「ユーザがまだ考えていなさそうな所」。

### 2. Write to docs/spec.md

合意ができたら以下の構造で `docs/spec.md` を書く (機能単位なら `docs/specs/<feature>.md`):

```markdown
# <Project / Feature> Spec

## 目的
- なぜ作るか (1〜2 文)

## ユーザとシナリオ
- 想定ユーザ
- 主要ユースケース (3 個まで)

## スコープ
### In scope
- ...
### Out of scope (今回やらない)
- ...

## Acceptance criteria
- 自動で検証可能な条件 (失敗するテスト / メトリクス / ビルド成功)
- 手動で確認すべき条件 (UI / 体感)

## 制約
- 技術的制約
- 既存資産・ADR との整合
- 時間 / リソース制約

## 主要なトレードオフ
- 選択肢と採用理由 (棄却理由も含む)

## Open questions
- 未解決 (棚上げ可)
```

### 3. Hand off to a fresh session

Spec を書き終えたら、**同じセッションでそのまま実装に入らない**。

- ユーザに `/clear` を提案する
- 新セッションでは `contexts/dev.md` を append-system-prompt して、`docs/spec.md` を起点に `plan-mode` skill で計画フェーズに入るよう案内する
- 大きな設計判断が spec から派生したら `docs/adr/` へ昇格させる

## Delegation

- 既存コードへの影響を spec に含めたい → `investigator` subagent で読み取り、結果を spec の "制約" 節に反映
- 複数の実装案を比較したい → spec 確定後の Plan フェーズで `planner` に委譲する (Interview 中に実装案を議論しない)

## Anti-patterns

- Interview を飛ばして「たぶんこういう仕様」と書き始める
- Acceptance criteria を「いい感じに動くこと」のような測定不能な形で書く
- Spec を書いた同じセッションでそのまま実装に突入する (バイアス混入)
- すべての open question を埋めようとする (棚上げできるものは Open questions に残す)
- Interview 中に実装方針を決め込む (spec と plan を混ぜない)
