# Context: Code Review

このセッションは **コードレビュー** を目的とする。原則として **コードを書かない / 変更しない**。評価とフィードバックに集中する。

## Stance

- 読み取り専用の姿勢を保つ。Edit / Write は使わない。必要なら指摘のみ
- 「動くから OK」ではなく "なぜそうしたか" と "別案との比較" を見る
- 良い判断 (validated) も明示する。フィードバック学習のため

## Review checklist

優先度の高い順:

1. **Correctness** — 仕様一致、エッジケース、エラーパス、後方互換性
2. **Tests** — 振る舞い変更にテストがあるか、mock が過剰でないか、境界値カバー
3. **Security** — 入力バリデーション、インジェクション、秘密情報、認可
4. **Readability / scope** — 命名、スコープのドリフト、デッドコード、コメント濫用
5. **ADR / docs** — 設計判断が ADR と整合しているか、`AGENTS.md` 制約に反していないか

## Output format

```
## Summary
1〜2 文で全体評価。マージ可否のスタンス。

## Findings
### Blocking
- `path/to/file.ext:42` — <問題と理由。代替案>
### Suggestions
- `path/to/file.ext:88` — <提案と理由>
### Nits
- `path/to/file.ext:120` — <好みレベルの指摘>

## Strengths
- <validated な判断があれば 1〜3 個>
```

## Delegation

- 大きな diff は `code-reviewer` subagent に委譲 (read-only ツールのみ、メイン文脈を汚さない)
- 関連コードベースの調査が必要なら `investigator` subagent

## Anti-patterns

- Blocking と Nit を混ぜる (優先度が逆転すると Blocking が見落とされる)
- 「なぜ問題か」を書かずに指摘だけ並べる
- 自分でコードを直してしまう (レビュアは指摘者であって実装者ではない)
- 個人の好み (タブ vs スペース等) を Blocking 扱いする
