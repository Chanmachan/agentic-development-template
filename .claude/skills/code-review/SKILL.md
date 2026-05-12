---
name: code-review
description: Use when reviewing a pull request, a diff, or a set of staged changes. Provides a structured review checklist (correctness, tests, security, readability, scope). Trigger when the user asks to "review", "look over", "check", or "give feedback on" code changes, or invokes the /review or /fix-review commands.
---

# Code Review Skill

## When to use

- PR レビュー (自分の PR、他人の PR どちらも)
- staged な差分の自己レビュー (commit 前の最終確認)
- `/review` / `/fix-review` コマンド経由

読み取り専用の姿勢を保つ。レビュー中は `Edit` / `Write` を使わない (必要なら指摘として残す)。

### Skill vs subagent

- **この skill (`code-review`)** はメイン文脈で短い差分 (〜数百行) を直接読んでレビューするときに使う。
- 差分が大きくメイン文脈を圧迫しそうなら **`code-reviewer` subagent** に委譲する (Read/Grep/Glob/Bash のみで、差分全文を別文脈で読み込む)。チェックリストは同じ。

## Review checklist

優先度の高い順に確認する。各観点で問題が見つかったら、ファイル名と行番号を引用して指摘する。

### 1. Correctness

- 仕様 (`docs/spec.md`) と一致しているか
- エッジケース: null / 空配列 / 境界値 / 並行性
- エラーパスが握りつぶされていないか
- 既存の呼び出し元との互換性 (破壊的変更が意図的か)

### 2. Tests

- 振る舞いの変更にテストが追加されているか
- テストが「期待する理由で」失敗・成功するように書かれているか
- mock が過剰でないか (実装の詳細に依存していないか)

### 3. Security

- 入力バリデーション (system boundary)
- SQL / command / XSS インジェクション
- 秘密情報のログ出力やコミット
- 認可ロジックの抜け

### 4. Readability / scope

- 命名で意図が伝わるか (コメントで補わないと読めない命名は変える)
- スコープが PR 説明と一致しているか (無関係な変更が混ざっていないか)
- 過剰な抽象化、未使用コード、デッドコメント

### 5. ADR / docs

- 設計判断を伴う変更は ADR が更新 / 追加されているか
- `AGENTS.md` の 50 行制限が破られていないか

## How to deliver feedback

- **Blocking / Suggestion / Nit** の 3 段階でマークする
  - Blocking: マージ前に直す必要がある
  - Suggestion: 直したほうがよいが必須ではない
  - Nit: 好みレベル、無視してよい
- 「なぜそれが問題か」を 1 行添える。指摘だけでなく代替案も提示する
- 良い点も書く (validate された判断は memory に蓄積される)

## Delegate when appropriate

レビュー対象が広範な場合は `code-reviewer` subagent に委譲する。メイン文脈に差分全文を読み込むとコンテキストを大きく消費するため。
