---
name: tdd
description: Use when implementing a new feature, fixing a bug, or making any behavior change that should be covered by tests. Guides the Explore → failing test → minimal implementation → refactor cycle. Trigger when the user asks to "implement", "add", "fix", or "change" code that has observable behavior.
---

# TDD Skill

## When to use

- 観察可能な振る舞いを変える変更すべて (新機能、バグ修正、リファクタの一部)
- テストが存在する領域、または新しく追加すべき領域

スキップしてよい場面: ドキュメントのみの変更、`.claude/` 内のルール/skill/agent 編集、設定ファイルのみ、テストが書けない UI 試作の最初のスケッチ。

## 4 step loop

### 1. Explore

実装に入る前に、必ず以下を確認する:

- `docs/spec.md` の関連セクション
- 関連する ADR (`docs/adr/`)
- 既存のテスト (`tests/`) と、似た振る舞いがどうテストされているか
- 変更対象のコードと呼び出し元

調査が広範になりそうな場合は `investigator` subagent に委譲する (メイン文脈を保護)。

### 2. Failing test

- 期待する振る舞いを表す**最小**のテストを 1 つ書く
- テストを実行し、**期待した理由で失敗する**ことを確認する (コンパイルエラーや import 漏れではなく)
- この段階で実装を書かない

テスト名は「何を保証するか」を述べる: `returns_404_when_user_not_found` のように。

### 3. Minimal implementation

- テストを通す**最小の実装**を書く
- このフェーズではリファクタしない (YAGNI)
- テストが green になることを確認する

### 4. Refactor

- 重複の除去、命名の改善、抽象化の整理
- **テストは触らない**。テストが green のまま実装だけを整える
- リファクタ後、もう一度テストを走らせて green を確認

## Rules

- テストなしで実装を始めない。例外は `AGENTS.md` の "Add or update tests for every behavior change" を破るときだけで、その場合は理由をユーザに伝える
- lint / typecheck / test は **commit 前に必ず通す**。`stop-check.sh` が強制する
- 同じバグを 2 度踏んだら、`feedback memory` に書くか、専用のテストを追加する

## Verification

完了報告の前に必ず:

1. 該当テストが green
2. 周辺テストも green (回帰なし)
3. lint / typecheck がクリーン

UI 変更を含む場合は、ブラウザ等で実際に触って確認。自動テストでは振る舞いの正しさは保証されない。
