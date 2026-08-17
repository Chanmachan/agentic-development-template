---
name: repo-audit
description: リポジトリ全体の網羅監査を多エージェントで実施する運用ハーネス。Use when the user asks for a full repository audit (監査/audit).
---

# Repo Audit Skill

カテゴリ別走査 → critical/high のみ反証 → カテゴリ完了ごとに即ファイル書き出し、`progress.md` 台帳 + heartbeat + cron で中断・再開に耐える。別プロジェクトの初回全体監査で確立した運用の移植。

## 運用手順

### 1. 台帳を書く

`tasks/reference/audit/progress.md` に台帳を書く。雛形:

```markdown
# 全体網羅監査 progress

last-heartbeat: <ISO時刻>

## 進捗台帳

- [ ] 01-infra
- [ ] 02-security
- [ ] 03-spec
- [ ] 04-design
- [ ] 05-code-quality
- [ ] 06-tests
- [ ] 07-db
- [ ] 08-dx
- [ ] 09-model-robustness
- [ ] summary.md

---

## 指示全文(この監査のルール。再開セッションはこれに従う)

<ここに本 SKILL.md の「運用手順」「モデル配分」「finding 形式」「severity rubric」「Lessons」を
 貼り付ける。再開セッションが SKILL.md を読み直さなくても progress.md 単体で自己完結するように。>
```

再開セッションが `progress.md` だけ読めば全ルールが分かるよう、指示全文を末尾に貼る (SKILL.md への参照だけでは worktree 間で読めない場合があるため)。

### 2. cron を登録する (30分ごと)

監査開始前に cron を登録する。プロンプト雛形:

> 「`tasks/reference/audit/progress.md` を読む。ファイルが無い、または全カテゴリ完了済みなら、この cron を削除して終了。`progress.md` の `last-heartbeat` が20分以内なら別セッションが稼働中とみなし、何もせず終了。それ以外は `progress.md` 冒頭に書かれたルール (モデル配分・finding 形式含む) に従って未完カテゴリから監査を再開する。全カテゴリ完了したら `summary.md` を書き、この cron を削除する」

### 3. カテゴリごとに走査する

`.claude/skills/repo-audit/assets/audit-category.workflow.js` を Workflow ツールで起動する。args:

```json
{
  "cat": "01",
  "scanners": [
    { "label": "infra-ci", "prompt": "<走査プロンプト。severity rubric を冒頭に注入>", "model": "sonnet", "effort": "medium" }
  ]
}
```

- 走査は sonnet。機械的な列挙 (対応表・一覧作成) だけは haiku の enumerator agent に分離してよい (Lessons #1 に従い、fan-out に流す前に必ずスポットチェックする)。
- workflow は Scan → Verify の2フェーズ: Verify では severity が critical/high の finding だけを sonnet で反証する (medium 以下は `verified:false` のまま載せてよい)。

### 4. markdown 化する

`.claude/skills/repo-audit/assets/render_audit.py` で workflow の出力 JSON を markdown に変換する。

```
python3 .claude/skills/repo-audit/assets/render_audit.py <workflow-output.json> <cat番号> <タイトル> <出力.md>
```

出力先は `tasks/reference/audit/<cat番号>-<タイトル>.md` (例: `01-infra.md`)。

### 5. カテゴリ完了ごとに台帳を更新する

`progress.md` の該当行を `- [x]` にし、件数サマリ (severity 別内訳) を追記、`last-heartbeat` を更新する。**全部終わってからまとめて書くのは禁止** — カテゴリの調査が終わるたびに即書き出す。

### 6. 全完了で summary.md を書き cron を削除する

全カテゴリ完了したら `tasks/reference/audit/summary.md` に横断サマリを書く: カテゴリ別件数の表、上位10件の優先順位案 (PM が todo を切る順の推奨)。書いたら cron を削除する。

## モデル配分 (トークン節約のため厳守)

| 役割 | モデル | 備考 |
|------|--------|------|
| 走査エージェント | sonnet | 各カテゴリの本体調査 |
| 機械的な列挙 (対応表・一覧作成) | haiku | enumerator agent。判断させず表だけ作らせる |
| 反証チェック | sonnet | 対象は severity が critical/high の finding のみ。medium 以下は `verified:false` のまま可 |
| 統合・優先順位付け | メインの PM 本人 | 委譲しない。統合用エージェントは立てない |

観点9 (モデル頑健性) のみ例外: エージェントに委譲せず、メインのモデル自身が調査・執筆する (ハーネス自体の穴を見つける観点なので、モデルの推論力の差がそのまま結果の質に出る)。

## finding 形式

- `id`: `AUD-<カテゴリ番号>-<連番>`
- `severity`: critical / high / medium / low / suggestion
- `verified`: true / false (critical/high は反証チェック通過が true の条件、medium 以下は false のままでよい)
- `file:line`: 根拠の場所。複数根拠はカンマ区切り
- 1行要約
- 根拠 (該当コードで実際に確認した内容)
- 修正方針の素案
- 工数感: S / M / L
- 依存: 他 finding / 前提への依存。無ければ「なし」

## severity rubric (全走査プロンプト冒頭に統一注入する)

- **critical**: 認可穴・データ破壊・本番停止級
- **high**: 本番バグ・仕様違反・明確な弱点
- **medium**: 品質・保守性の実害
- **low**: 軽微
- **suggestion**: 改善提案、または健全性確認 (問題なしの根拠を残す)

rubric が scanner 間で不統一だと severity がぶれ、メインループの優先順位付けが成立しない。反証エージェントには棄却・severity 降格の権限を明示し、finding を JSON のまま渡す。

## Lessons (2026-07-07 の初回監査で確立した非自明な運用知。必ず従う)

1. **haiku の機械列挙は fan-out の入力にする前に 2-3 行を実ファイルでスポットチェックする。** 初回監査では principal 6 画面が「未実装」と誤判定された (page.tsx が 5-28 行でも client Loader パターンで実装済みだった)。鵜呑みにすれば実装済み画面が監査対象から欠落する。
2. **走査が `findings: []` を返したら「完了」ではなく「疑わしい空」として扱う。** 問題ゼロでも、何をどう確認して健全と判断したかを suggestion として最低 N 件返す形式で再走査する。空返答をカバレッジ済みと誤認すると監査に穴が空く。
3. **Workflow の `args` は文字列化されて届くことがある。** スクリプト側の `typeof args === 'string' ? JSON.parse(args) : args` ガードを外さない (外すと初手 `args.scanners.map is not a function` で即死する)。
4. **反証エージェントには棄却・severity 降格の権限を明示し、finding を JSON のまま渡す。** 権限が曖昧だと反証が形骸化し、severity インフレや偽陽性の混入を防げない。

## 観点カタログ (9観点)

1. インフラ/CI: CI 設定、デプロイ構成、migration 運用の弱点 (git init 前は該当分をスキップ)
2. セキュリティ: 認証/認可の網羅性 (API 全エンドポイント×全ロール)、strong parameters、secret 混入、モバイル側のトークン管理
3. spec 準拠: 仕様ドキュメント・GitHub issue の受け入れ条件と実装の乖離
4. 画面デザイン準拠: 実装済み画面をデザイン参照 (Stitch 等) と突合せ、表示項目/ボタン/配色の差分を列挙
5. コード品質: 重複、過剰/不足な抽象、dead code、型の穴 (dynamic/any/as)、エラーハンドリングの欠落
6. テスト: 振る舞い変更にテストが無い箇所、実質走っていないテスト、flaky 要因 (flutter test / rspec / Cypress)
7. DB/データ層: Rails schema と migration のドリフト、インデックス欠落、N+1、既知の落とし穴の再発箇所
8. DX/開発効率: hooks/skills/scripts の摩擦、3アプリ間の品質ゲートの穴、doc-health 対象外のドキュメント腐り
9. モデル頑健性 (エージェントに委譲せず、メインのモデル自身が調査・執筆する): CLAUDE.md/AGENTS.md/rules の暗黙判断、skills/agents の決定性、hooks/scripts/CI の機械ゲート不足、この監査自体の運用知の書き残し

## assets/ の説明

- **`audit-category.workflow.js`**: 1カテゴリ分の走査ハーネス。Scan フェーズで `args.scanners` を sonnet エージェントに並列 fan-out (null 返却時は同じプロンプトで1回だけリトライ)、Verify フェーズで severity が critical/high の finding だけを sonnet で反証する。`args` は文字列で届く場合があるため `typeof args === 'string' ? JSON.parse(args) : args` でガードしている (編集不要、参照のみ)。
- **`render_audit.py`**: workflow の出力 JSON を所定の markdown 形式に変換する。usage: `python3 render_audit.py <workflow-output.json> <cat番号> <タイトル> <出力.md>`。severity 順にソートし、反証で棄却された finding は末尾に別枠でまとめる (編集不要、参照のみ)。
