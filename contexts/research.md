# Context: Research

このセッションは **調査 / 技術選定** を目的とする。コードを書く前に "選択肢の比較" と "判断材料の整理" を済ませる。

## Output destination

- 一次成果物は `research/<topic>.md` に書く
- 設計判断に昇格しそうなものは `docs/adr/NNNN-<title>.md` に ADR として書く (Status: Proposed → 議論 → Accepted/Rejected)
- 結論が出ない調査も `research/` に残す。"検討して棄却した" 履歴も価値

## How to research

1. **問いを固める** — 何を決めるための調査か。判断のために必要な情報は何か
2. **選択肢を 2〜4 個** — A 案 / B 案 / 採用しなかった案を並列に評価
3. **判断基準を明示** — コスト・複雑度・将来の拡張性・既存資産との整合
4. **事実と推測を分ける** — 「ドキュメントに書いてある」「動かしてみた結果」と「たぶんこう動く」を混ぜない
5. **未解決を残す** — Open questions セクションで明示。すぐに埋めなくていい

## Delegation

- 既存コードへの影響を探る → `investigator` subagent
- 比較表 + 推奨を作りたい → `planner` subagent (Write/Edit なしで計画書を返す)

## Output format (research/<topic>.md)

```markdown
# <Topic>

## 問い
- 何を決めるための調査か (1〜2 文)

## 選択肢
### A: <名前>
- 要約 / Pros / Cons / コスト

### B: <名前>
- 要約 / Pros / Cons / コスト

## 判断基準と比較表
| 観点 | A | B |
|------|---|---|

## 推奨と理由
- 1〜2 段落

## Open questions
- <未解決>
```

## Anti-patterns

- 一次資料に当たらず推測で結論を出す
- 単一案だけ調べて "これが正解" と書く (比較なしの推奨は弱い)
- 調査メモを `tasks/` や conversation に残して `/clear` で消す
- ADR 化すべき判断を research/ に埋もれさせる (後から探せなくなる)
