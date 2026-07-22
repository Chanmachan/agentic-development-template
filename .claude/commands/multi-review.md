# Multi-Perspective PR Review

6 つの専門 reviewer subagent (correctness / security / tests / performance / readability / docs-adr) を並列起動し、観点別に独立評価した結果を 1 つの統合レポートにまとめる。

## 目的

単一 reviewer に全観点を任せると見落としやバイアスが出やすい。**観点ごとに独立した文脈** で評価することで、(a) 各 reviewer が境界外に踏み込まず深く見れる、(b) 並列実行で時間短縮、(c) 観点別の Blocking 件数が一覧できマージ判断しやすい。

レビュー手段の棲み分け:
- **このコマンド** = ローカル / 即時 / カスタマイズ可能 (反復レビュー、CI 連携、PR 提出前の最終確認向け)
- **`code-reviewer` subagent** = 1 つの別文脈で大きめの diff を汎用レビューしたい場合

## 引数

$ARGUMENTS は任意:
- 数字のみ (`123`) → PR 番号として扱う
- URL (`https://github.com/owner/repo/pull/123`) → 末尾の番号を抽出
- 空 → ローカル `HEAD` vs `main` の diff を対象に
- `--skip=<angle>[,<angle>...]` → 指定 reviewer をスキップ (例: `--skip=performance,docs-adr`)
- `--only=<angle>[,<angle>...]` → 指定 reviewer のみ実行

## 手順

1. **対象の確定**
   - PR 番号が解決できた場合: `gh pr view <番号>` で title / description / base branch を取得、`gh pr diff <番号>` で差分を取得
   - 空 (= ローカル): `git branch --show-current` / `git log main..HEAD --oneline` / `git diff main...HEAD` で差分把握
   - 差分が極端に大きい (>2000 行) 場合は警告し、ファイル単位での絞り込みを提案 (`gh pr diff -- <path>`)
2. **適用する reviewer の決定**
   - デフォルト: `review-correctness`, `review-security`, `review-tests`, `review-performance`, `review-readability`, `review-docs-adr` の 6 つ
   - `--skip` / `--only` を反映
   - **docs-adr reviewer の adaptive skip**: `docs/adr/` も `docs/spec.md` も `AGENTS.md` / `CLAUDE.md` / `.claude/rules/` も無いリポジトリでは `review-docs-adr` を自動 skip (reviewer 側でも adaptive 動作するが、起動コストを節約)
3. **並列起動**
   - Agent tool を **1 メッセージ内で複数 tool_use** として並列発行 (subagent_type=`review-<angle>`)
   - 各 reviewer の prompt には次を渡す:
     - レビュー対象の特定情報 (PR 番号 or branch + base)
     - PR 説明 (あれば)
     - 「あなたは <angle> 観点のみを見ること。他観点には踏み込まないこと」の念押し
   - reviewer 出力は描画コストが高いので **report で総合表示する前に個別ログを長く貼らない**
4. **集約**
   - 各 reviewer の出力から Blocking / Suggestion / Nit / Strengths を抽出
   - `path:line` 単位で **緩く dedupe** (同じ箇所が複数観点から指摘されたら、最も厳しい観点を主とし他観点を括弧で添える)
   - **反証 pass**: 各 Blocking は、統合レポートに載せる前に該当ファイルを実際に開いて指摘が成立するか再確認する。成立しない・誇張と判明したものは Suggestion に降格するか棄却し、その旨を記録する
   - 全観点の Blocking のみを末尾に集約リスト化
5. **統合レポートを出力** (下記フォーマット)

## 出力フォーマット

```markdown
# Multi-Perspective Review: <PR title or branch name>

## Executive Summary
- マージ可否: <Approve / Request changes / Needs discussion>
- Blocking 件数: correctness <n> / security <n> / tests <n> / performance <n> / readability <n> / docs-adr <n>
- 1〜2 文で総評 (どの観点が最も懸念か)

## By Perspective

### Correctness (<n> findings)
<correctness reviewer の Findings 本文をそのまま貼る (Summary は executive に統合済みなので省略可)>

### Security (<n> findings)
...

### Tests (<n> findings)
...

### Performance (<n> findings)
...

### Readability (<n> findings)
...

### Docs / ADR (<n> findings)
<adaptive skip があれば "skipped: <理由>" と明記>

## Consolidated Blocking (全観点)
- `path:line` [observed by: correctness, security] — 問題と修正方針

## Strengths (validated な判断)
- (各 reviewer の Strengths を 1〜5 個に集約)
```

## 原則

- **観点別文脈の独立性を保つ**: reviewer 出力を編集して別観点の指摘を混ぜない
- **Blocking と Nit を混ぜない**: Executive Summary では Blocking 件数のみを目立たせる
- **マージ可否のスタンスを明示**: 「Approve / Request changes / Needs discussion」のいずれかを最初に書く
- **失敗フォールバック**: ある reviewer がエラーで結果を返さなかった場合、その観点は "failed to evaluate" と Summary に明記して他は通常通り出力

## 使い方

```
/multi-review                  # ローカル HEAD vs main をレビュー
/multi-review 123              # PR #123 をレビュー
/multi-review https://github.com/owner/repo/pull/123
/multi-review 123 --skip=performance,docs-adr
/multi-review 123 --only=security,correctness
```

## 関連ツールとの使い分け

| 手段 | 使いどき |
|------|----------|
| `code-review` skill | inline 小差分 (~数百行) を main 文脈で直接見る |
| `/multi-review` (このコマンド) | フル PR を 6 観点で並列レビュー、ローカル、無料 |
| `code-reviewer` subagent | 1 観点に絞らず汎用に長文 diff を別文脈で見たい場合 |
