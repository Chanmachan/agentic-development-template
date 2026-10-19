# Model Roles

Orchestrator–Worker 体制の役割分担。実際のモデル割当はセッション/プロジェクト側で決める (reviewer 系 subagent の `model: inherit` 方針と整合)。

## 役割表

| 役割 | 責務 |
|---|---|
| orchestrator (lead/PM) | 計画 (`tasks/<id>-todo.md` の作成・分解) / worker への指示 / 全 diff レビュー / merge 判断 |
| レーン (PM 配下のセッション) | PM から 1 タスクを受け持つ **orchestrator の分身** (worker ではない)。計画・brief・diff 確認・ゲート・PR・報告。**実装コードは書かない** |
| 計画レビュアー | 着手前の plan review (CLAUDE.md Workflow phase 2)。判断の当否・事実誤認・抜けを出す。orchestrator より上位か別系統のモデル |
| 実装 worker | todo の worker brief 単位の実装。`tdd` 準拠。スコープ外に手を出さない |
| 反証レビュアー (cross-vendor) | **クリティカルな diff に限り**、multi-review 後にクロスベンダーの反証 1 pass を追加。brief を書いた orchestrator 自身が correctness も見る「設計レベルの自己確証」バイアスのヘッジ |
| 列挙役 | `enumerator` agent。対応表・一覧の機械列挙のみ (判断しない) |

## モデル割当の例 (参考)

プロジェクト/セッションで上書き可。subagent frontmatter の `model: inherit` は親セッションに委ねる (reviewer 系は b4ee030 方針)。

| 役割 | 例 |
|---|---|
| orchestrator | 上位推論モデル (計画・レビュー統合) |
| 実装 worker | IDE 実装モデル (例: Cursor Composer) |
| 反証レビュアー | 別ベンダーのレビュー用モデル |
| 列挙役 | haiku (`enumerator` agent — 役割に内在する pin) |

## subagent のモデル既定 (例)

- review 観点別: correctness / security は深い推論向け、tests / performance / readability / docs-adr はチェックリスト駆動向け
- `code-reviewer` (単観点 quick) / `investigator` = inherit / `enumerator` = haiku / `planner` = inherit
- 統合・レビュー統合・優先順位付け = orchestrator 自身が直接行う (subagent に委譲しない)

## レーンの実装規律

PM から依頼を受けたセッション (レーン) は、依頼文に書かれていなくても次に従う。

- 実装 (本体コード・テストコード) は worker brief で実装 worker に渡す。レーン自身は実装しない
- 直接書いてよいもの: `tasks/` / spec / ADR / PR 本文 / brief、および worker の diff への 1〜2 行の手直し (報告に書く)
- worker が使えないとき (limit・障害) は別の実装 worker (subagent 等) に brief を渡す。自分で書くことへの fallback はしない
- 報告には「実装した主体」を書く。PM はこれで規律を確認する
- worker の「直した」もレビュアーの「修正済み」も、mutation を撃って実測するまで信じない (`mutation-testing` skill)

## エスカレーション基準 (worker → orchestrator に返す)

以下のいずれかに該当したら、自力で押し切らず状況を要約して orchestrator に返す:

- (a) todo/brief に書かれていない設計判断が必要になった
- (b) 同じエラーに 2 回連続で失敗した
- (c) 保護ファイル・スコープ外ファイルに触れる必要が出た
- (d) テストを弱める / lint を緩める以外の解決策が見えない

## 承認ゲート

- 着手前の 2 段レビュー (計画レビュアー → `/tacit-review`) は定常工程。スライスごとに起動の可否を聞き直さない
- 利用枠を圧迫する高コストなレビュー (上位モデルの反証 pass 等) は、起動前に提案してユーザの承認を待つ。黙って回すのも、必要そうなのに黙って省くのも駄目
- 通常の品質ゲート (主レビュー / lint / typecheck / test / CI) は自動で回す。高コストレビューを省いたことを理由に緩めない

## orchestrator のレビュー規律

- 実装 diff は必ず自分でファイルを開いて確認する (worker の自己申告を信用しない)。
- Blocking 判断は、指摘内容を実ファイルで裏取りしてから採用する (reviewer 出力を鵜呑みにしない)。
- クリティカルな diff (Blocking が残る、または merge 判断に大きく効く変更) は、上記に加えて可能なら **クロスベンダー反証 1 pass** を挟んでから merge 判断する
  (同一モデル系列内の敵対的レビューは承認に寄るバイアスがあるため。反証側の指摘も鵜呑みにせず orchestrator が裏取りして採否を決める)。
- multi-review に反証 pass が含まれる場合は、その手順に従う。

## 検証の非交渉性

lint/typecheck/test green + 動作確認は体制に関係なく必須。機械ゲート (hooks/CI) を緩める変更は orchestrator でも単独判断しない。

worker brief の書き方・報告フォーマット・共有資源の台帳・レビュー経路の fallback は `orchestration` skill。
