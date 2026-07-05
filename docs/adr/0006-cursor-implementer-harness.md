# ADR 0006: Cursor Composer を実装担当にする第3ハーネス (`.cursor/`)

- Status: Accepted
- Date: 2026-06-25
- Last-validated: 2026-07-06

## Context

ADR 0002 (Skills-first architecture) は Rules / Skills / Subagents / Hooks の4層分離を定め、ADR 0005 は
同じ層を **Codex** にも展開した。結果、ハーネスは Claude Code (`.claude/`) と Codex (`.codex/` + `.agents/`)
の2系統がある。ADR 0003 は Hooks 層の強度を `HOOK_PROFILE` (minimal/standard/strict) で切り替える仕組みを定めた。

ここに **Cursor Composer を「実装担当」として加えたい** という要求が出た。狙いは PM/計画フェーズ
(少量・高難度、フロンティアモデルを慎重に使う) と実装フェーズ (大量・定型) でモデルのコスト/質を
ミスマッチさせないこと。承認済み `tasks/<id>-todo.md` を渡して実装を量産させると割安になる。

これは「3つ目のハーネスを足し、各々が独自のフック層を持つ」という、ADR 0005 が Codex について記録したのと
同クラスの構造判断であり、決定記録なしに established pattern 化するのを避けるため本 ADR を残す。

## Decision

1. **`.cursor/` を git tracked な第3ハーネスとして追加する** (`.claude` / `.codex` と揃える)。採用方針は
   案A = **手動ハンドオフ**: 計画と承認は従来どおり Claude/Codex で行い、実装フェーズだけ Cursor に出す。
   レビュー対応・merge・archive は Claude/Codex に残す。Claude Code での一気通貫も従来どおり維持し、
   タスク単位でどちらに実装させるか選べる。

2. **ハーネス間でフックの `profile.sh` は共有せず、各自コピーを持つ** (ADR 0005 §Decision の慣習を踏襲)。
   3系統で `lib/profile.sh` を重複させるが、各ハーネスを単独で読めるほうを優先する。`.cursor` 内では
   3ガードが `lib/protected.sh` を共有する(consumer が複数あり共有ライブラリ化が正当化される)。
   共有ライブラリ化リファクタは別 PR の論点とする。→ ADR 0008 で実施 (`scripts/lib/protected.sh` に
   分類ロジックを集約。`profile.sh` は方針どおり各ハーネスのコピーを維持)。

3. **`HOOK_PROFILE` の profile 帰属は ADR 0003 を土台に、Cursor 固有の保護フックを足す**。Cursor の
   `standard` は **6 フック** = post-lint, protect-config, **protect-read, protect-shell**, stop-check,
   **enforce-model** (protect-read/protect-shell は protect-config の兄弟ガード、enforce-model はモデル強制)。
   minimal=post-lint のみ。strict 専用フック (ADR 0003 の `suggest-compact`) は Cursor へ未移植のため、
   本ハーネスの `strict` は実質 `standard` と同じ 6 フックになる。

4. **Cursor の実イベントに合わせてアダプタを配線する**。Cursor の hook は6種
   (`beforeShellExecution`/`beforeMCPExecution`/`beforeReadFile`/`beforeSubmitPrompt` が制御可、
   `afterFileEdit`/`stop` は観測のみ)で、Claude のような汎用 `PreToolUse` 一本やファイル編集の事前
   ブロック専用フックは無い。よって `.env*` 保護は三方向で固める:
   `preToolUse`(matcher=`Write`)=protect-config(書込拒否)/ `beforeReadFile`=protect-read(秘密の
   読取拒否=漏洩防止)/ `beforeShellExecution`=protect-shell(`.env`/鍵を触るシェル拒否)。加えて
   `afterFileEdit`=post-lint(format)/ `stop`=stop-check。deny は `{permission:"deny", agent_message,
   user_message}` を返す。stop は `{followup_message}` を返し、ループガードは Claude の `stop_hook_active`
   ではなく Cursor の `loop_count` で行う。matcher は tool 種別で指定する(verb 文字列ではない)。

5. **保護判定は強化し共有 lib(`lib/protected.sh`)に集約する**。`.env*` は gitignore のため lefthook/CI に
   バックストップが無いので、正規化(末尾スラッシュ/空白)・case-insensitive 一致・`.env.*` は `.env.example`
   のみ許可・配列値の全要素検査を加える。書込拒否は config 全般+秘密(`is_protected_path`)、読取/シェル
   拒否は秘密のみ(`is_secret_path`、tsconfig 等の読取は許可)。`.claude` / `.codex` の inline 版への同等
   バックポートは別 PR とする。→ ADR 0008 で実施 (分類ロジックを `scripts/lib/protected.sh` に切り出し、
   `.claude`/`.codex` の `protect-config.sh` をそれ経由の判定にアップグレード)。

6. **モデルを Composer 2.5 に固定し `beforeSubmitPrompt` で強制する**。理由:
   - Cursor Pro の「Auto + Composer」包括プール内であれば Composer を使っても追加費用は無い。Auto は
     世代ごとにサードパーティモデルに振られる可能性があり、その場合は API クレジットを消費する。
   - 実装担当として速度・コストのトレードオフを最適化するには、Composer 2.5 (standard tier) を固定が
     最も合理的(fast tier は 1 トークン当たりのプール消費が大きい)。
   - Cursor のドキュメント (cursor.com/docs/agent/hooks) は `model` フィールドがすべての hook イベントの
     ペイロードに含まれると記載しているが、実際のキー名・値は初回ハンドオフで実機確認するまで未検証
     (`.model` → `.model_id` の順で読み、フィールド自体が無ければ fail-open するのはこのドリフトへの備え)。
   - IDE のモデルピッカーはモード切替のたびに Auto にリセットされるため、設定での固定は不完全。
     フックによるチェックが唯一の強制手段。
   - **ポリシー**: `model` スラグが `CURSOR_REQUIRED_MODEL_PREFIX`(既定 `composer`) から始まらなければ
     deny、始まれば allow。prefix が空文字列の場合はすべて allow(強制無効化)。`model` フィールドが
     ペイロードに存在しない場合は fail-open(allow)し、`hook_debug` でログに記録する。
   - 推奨起動: `cursor-agent --model composer-2.5`(standard tier)。`-fast` は同プールの消費が速い
     ため通常は standard を優先する。

## Consequences

- commit 時の安全網は lefthook pre-commit (`doc-health`。lint/typecheck は言語別に未有効化) と
  commit-msg (コミットメッセージの prefix 規約) で、git レベルのフックはエージェント非依存なので
  Cursor が commit した瞬間にも効く。ただし lefthook を通さない commit は素通りする。加えて ADR 0007 で
  `.github/workflows/ci.yml` (doc-health / `tests/*.test.sh` / shellcheck) が PR・push 単位のバックストップ
  として追加され、lefthook を経由しない変更もカバーするようになった。Cursor 側で新規に作るのは
  「commit を待たない実装中ゲート」だけでよい。
- フックのルーティング/判定は `scripts/test-cursor-hooks.sh` の fixture テストで固定し、Cursor 実機なしで
  回帰を検出する。
- 実機依存の未確定点 (preToolUse の file path フィールド名 / `.cursor/hooks.json` が CLI でも発火するか /
  stop→followup の無限ループ非発生) は初回ハンドオフ時に確認する。詳細は `.cursor/README.md`。
- ハーネスが3系統になり、ワークフロー変更時に更新箇所が増える (ADR 0005 §Negative と同じトレードオフ)。
