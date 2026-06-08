# ADR 0004: Multi-perspective PR review via specialized reviewer subagents

- Status: Accepted
- Date: 2026-06-02
- Last-validated: 2026-06-08

## Context

ADR 0002 で skills-first / 4 層分離を採用し、`code-reviewer` という単一の汎用レビュー subagent と `code-review` skill を導入した。運用するなかで以下の課題が見えてきた。

1. **観点の浅さ**: 1 つの subagent が correctness / tests / security / readability / ADR を一度に評価するため、各観点が浅くなる。特に security と performance は専任で見ないと見落としが多い。
2. **観点の越境**: 単一文脈で全観点を見ると、レビュアの「気になる観点」に出力が偏る。バランスが取れない。
3. **並列化されていない**: 大きな PR でも逐次評価のため、レビュー所要時間が線形に伸びる。
4. **外部の独立レビュー機能との棲み分けが不明確**: 利用中ツールに独立レビュー機能がある場合、それをいつ使うべきかが文書化されていない。

Anthropic 公式ドキュメントと late 2025 / 2026 のコミュニティテンプレート (`awesome-claude-code-subagents` 等) では、**専門 reviewer subagent を 5〜7 観点に分け、coordinator が並列起動して集約する** パターンが標準化しつつある。security は独立した文脈で見るのが定石、tests と docs も独立した mental model を要する。

このテンプレートは他リポジトリへ持ち出される前提なので、project-specific な path を reviewer 本文に直書きしない / ADR や spec の有無に応じて adaptive に動作する設計が求められる。

## Decision

### 1. 6 専門 reviewer subagent を導入

`.claude/agents/reviewers/<angle>.md` 配下に 6 ファイルを置く:

| Reviewer | 担当観点 |
|----------|----------|
| `correctness.md` | 仕様一致 / エッジケース / エラーパス / 後方互換性 / 並行性 / idempotency |
| `security.md` | 入力バリデーション / インジェクション / 秘密情報 / authn・authz / 暗号 / 依存脆弱性 |
| `tests.md` | 振る舞い変更のテストカバー / assertion 品質 / mock 適切性 / determinism / 境界値 |
| `performance.md` | N+1 / 計算量 / allocation / sync I/O / caching / batching |
| `readability.md` | 命名 / スコープのドリフト / デッドコード / コメント濫用 / 過剰抽象 / 責務 |
| `docs-adr.md` | ADR 整合 / spec 整合 / `AGENTS.md` ルール違反 / public API docs / WHY コメント |

各 reviewer は frontmatter で `tools: Read, Grep, Glob, Bash` (read-only) に制限。`name` は `review-<angle>` で揃え、subagent 一覧で grouping しやすくする。本文は **Mission / Checklist / Process / Output format / Rules** の 5 セクション固定で、observability と編集容易性を担保する。

各 reviewer の Rules には **「他観点に踏み込まない」** を明示。例えば correctness reviewer は性能の遅さや命名の好みは指摘しない (それぞれ専任 reviewer の責務)。観点の越境を抑え、出力の境界を明確にする。

### 2. `/multi-review` coordinator command

`.claude/commands/multi-review.md` を新設。引数で PR# / URL / 空 (= local HEAD vs main) を受け、Agent tool で 6 reviewer を **1 メッセージ内で並列起動** し、出力を観点別に集約した統合レポートを返す。

オプション:
- `--skip=<angle>[,...]` 指定 reviewer を除外
- `--only=<angle>[,...]` 指定 reviewer のみ実行

集約レポートは:

```
# Multi-Perspective Review: <title>
## Executive Summary
  - マージ可否 / 各観点の Blocking 件数
## By Perspective
  ### Correctness (n) ...  ### Security (n) ...  (他 4 観点同様)
## Consolidated Blocking
  - 全観点の Blocking のみを 1 リストに集約
```

### 3. 既存資産の役割再定義

| 手段 | 役割 |
|------|------|
| `code-review` skill | メイン文脈で短い差分 (~数百行) を inline でレビュー |
| `code-reviewer` subagent | 汎用 1-agent レビュー (1 観点で済む / 並列起動が過剰な場合) |
| `/multi-review` / `multi-review` skill | 6 専門 reviewer 並列。PR レビューの基本形 |
| 外部の独立レビュー機能 | merge 直前の最終ゲート (利用中ツールに存在する場合) |

`code-reviewer` の description を「汎用 / 中間解」と明示する形に更新し、`/multi-review` への誘導を含める。`code-review` skill の SKILL.md と `contexts/review.md` にも 4 手段の使い分け表を入れる。

### 4. 他リポジトリへの export 性

reviewer 本文に project-specific な path / ID を直書きしない。`docs-adr` reviewer のみ ADR と spec を参照するが、frontmatter と本文に **adaptive skip ロジック** を明文化:

- `docs/adr/` が無ければ ADR チェックを skip
- `docs/spec.md` が無ければ spec チェックを skip
- `AGENTS.md` / `CLAUDE.md` / `.claude/rules/` が無ければルール違反チェックを skip

他 repo は `.claude/agents/reviewers/` ディレクトリと `.claude/commands/multi-review.md` をコピーするだけで利用可能。

## Consequences

### Positive

- 観点ごとに独立した文脈で深く評価できる。security / performance の見落としが減る
- 並列実行でレビュー所要時間が短縮 (理論上 6 倍速、実際は I/O 待ちで 2-3 倍)
- 観点別の Blocking 件数が一覧でき、マージ判断がしやすい
- `code-review` skill / `code-reviewer` subagent / multi-review workflow / 外部独立レビューの棲み分けが文書化され、迷わず選べる
- 他リポジトリへディレクトリコピーで持ち出し可能 (export 性)

### Negative / Tradeoffs

- 6 並列起動の token 消費は単一 reviewer の数倍。小さな PR で過剰になりがち → coordinator 側で diff サイズに応じた `--skip` 推奨を docs に明記
- 観点の重複指摘 (correctness と security が同じ入力検証バグを 2 回挙げる等) → coordinator が `path:line` で緩く dedupe する仕様を入れる
- reviewer の `description` が下手だと auto-delegation されず宝の持ち腐れになる → 各 description に "Use when reviewing ... for X concerns only" と書く規約を確立
- 外部独立レビューとの混同リスク → README と SKILL.md の使い分け表で「自前: 速い・カスタム可能、外部独立レビュー: merge 直前の最終確認」を 1 行で示す

### Out of scope (将来の ADR で扱う)

- `claude-code-action` (GitHub Actions) との連携。PR 開く度に自動で `/multi-review` 相当を走らせる仕組み
- `dependencies` / `api-contract` / `a11y` reviewer の追加 (現状 6 観点で安定運用してから検討)
- reviewer 出力を JSON 化して機械的に集約 / dedupe (現状は markdown と coordinator による緩い dedupe)
- reviewer の auto-routing (PR 内容から必要な reviewer を自動選択)

## References

- ADR 0002: Skills-first architecture と 4 層分離
- ADR 0003: Hook profiles, contexts ディレクトリ, bash/Node.js ハイブリッド
- Anthropic Claude Code docs - subagents reference
- awesome-claude-code-subagents (VoltAgent) — multi-agent coordinator pattern
