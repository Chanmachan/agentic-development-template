# Model Roles

Orchestrator–Worker 体制の役割分担。実際のモデル割当はセッション/プロジェクト側で決める (reviewer 系 subagent の `model: inherit` 方針と整合)。

## 役割表

| 役割 | 責務 |
|---|---|
| orchestrator (lead/PM) | 計画 (`tasks/<id>-todo.md` の作成・分解) / worker への指示 / 全 diff レビュー / merge 判断 |
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

## エスカレーション基準 (worker → orchestrator に返す)

以下のいずれかに該当したら、自力で押し切らず状況を要約して orchestrator に返す:

- (a) todo/brief に書かれていない設計判断が必要になった
- (b) 同じエラーに 2 回連続で失敗した
- (c) 保護ファイル・スコープ外ファイルに触れる必要が出た
- (d) テストを弱める / lint を緩める以外の解決策が見えない

## orchestrator のレビュー規律

- 実装 diff は必ず自分でファイルを開いて確認する (worker の自己申告を信用しない)。
- Blocking 判断は、指摘内容を実ファイルで裏取りしてから採用する (reviewer 出力を鵜呑みにしない)。
- クリティカルな diff (Blocking が残る、または merge 判断に大きく効く変更) は、上記に加えて可能なら **クロスベンダー反証 1 pass** を挟んでから merge 判断する
  (同一モデル系列内の敵対的レビューは承認に寄るバイアスがあるため。反証側の指摘も鵜呑みにせず orchestrator が裏取りして採否を決める)。
- multi-review に反証 pass が含まれる場合は、その手順に従う。

## 検証の非交渉性

lint/typecheck/test green + 動作確認は体制に関係なく必須。機械ゲート (hooks/CI) を緩める変更は orchestrator でも単独判断しない。
