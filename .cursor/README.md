# `.cursor/` — Cursor Composer を「実装担当」にするためのハーネス

このディレクトリは Cursor (Composer / Agent mode) に実装を任せるときに、
`.claude` / `.codex` と**同等の実装中ガード**を効かせるための層です。
案A(手動ハンドオフ)を採用しています。決定背景は `docs/adr/0006-cursor-implementer-harness.md`。

> 重要: これを足しても **Claude Code / Codex での一気通貫(計画→実装→commit)はそのまま使えます**。
> `.cursor/` は Cursor だけが読み、`.claude` / `.codex` は一切変更していません。
> 「今回は Claude で全部やる」「今回は実装だけ Cursor に出す」をタスクごとに選べます。

---

## 2つの運用モード

### モードA: Claude / Codex で一気通貫(従来どおり)
これまで通り。計画 → 承認 → 同じエージェントが実装 → commit。何も変わりません。

### モードB: 計画は Claude/Codex、実装は Cursor(分業)
重い実装フェーズを安価で速い Composer に出すモード。

1. **計画(Claude/Codex)**: いつも通り `tasks/<id>-todo.md` に計画を書き、**承認を得る**。
2. **ハンドオフ(人間)**: Cursor を起動し、承認済み `tasks/<id>-todo.md` を渡す。
   - 「実装担当」としての姿勢は `.cursor/rules/cursor-implementer.mdc`(`alwaysApply: true`)が
     **毎セッション自動で注入**するので、手で書く必要はない。`AGENTS.md` も Cursor がネイティブに読む。
     渡すのは「どの todo を実装するか」だけでよい。
   - 推奨は CLI: ターミナルで `cursor-agent --model composer-2.5` を起動し、
     `@tasks/<id>-todo.md を実装して` と指示する(CLI は `AGENTS.md` + `CLAUDE.md` + `.cursor/rules` を読む)。
     **`--model composer-2.5`(standard tier)を明示する**こと。`-fast` は同 Pro プールを速く消費するため
     通常は standard を優先する。GUI のモデルピッカーはモード切替のたびに Auto にリセットされるため、
     `enforce-model` フックが Composer 以外のモデルをブロックする。
   - 起動は **`cursor-agent --model composer-2.5` をターミナルで実行し、プロンプトから todo を渡す**だけでよい。
     `cursor-agent` 呼び出しを shell の alias/起動ファイルに埋めると再帰起動を招く恐れがあるため、
     alias 化はしない。
   - GUI 併用: diff を細かく確認したいときは Cursor.app の Composer/Agent mode
     (GUI は `AGENTS.md` + `.cursor/rules` を読む。`CLAUDE.md` は読まない)。
3. **実装(Cursor)**: Composer が実装 + テスト。下記フックが実装中ゲートとして働く。
4. **commit / push**: ここから先は git/CI レベルの最終防衛線が**エージェント非依存**で効く
   (lefthook pre-commit / commit-msg / pre-push + CI)。
   - 注意: `doc-health`(ADR staleness / 行数上限)は **lefthook pre-commit でしか走らない**ため、
     lefthook を通さない git クライアントでの commit はこの1点を素通りする。lint/type/test は
     プロジェクトの CI 設定次第で二重化できる。
5. **レビュー対応・merge・archive**: 従来どおり Claude/Codex 側で(`/fix-review`、`tasks.jsonl` 更新)。

---

## フックの中身(`.cursor/hooks.json`)

Cursor の hook は6イベント(`beforeShellExecution` / `beforeMCPExecution` / `beforeReadFile` /
`beforeSubmitPrompt` が制御可、`afterFileEdit` は観測のみ、`stop` は編集をブロックはしないが
`followup_message` で続行を誘導できる)。`.claude`/`.codex` のガードを
**正しいイベントに繋ぎ直して** Claude 相当の防御を実現する。Cursor には「編集を事前ブロックする汎用
フック」が無いので、`.env*` 保護は読取・シェル・書込の三方向から固める。

| フック | Cursor イベント(matcher) | 役割 | ブロック |
|---|---|---|---|
| `enforce-model.sh` | `beforeSubmitPrompt` | Composer 以外のモデルへのプロンプト送信を拒否 | `permission: deny` |
| `protect-config.sh` | `preToolUse` (`Write\|Edit\|MultiEdit\|ApplyPatch`) | 保護ファイル(設定/lockfile/`.env*`)への**編集を事前拒否** | `permission: deny` |
| `protect-read.sh` | `beforeReadFile` (`Read\|TabRead`) | **秘密ファイルの読取を拒否**(`.env*`/鍵/credential)→ 漏洩防止 | `permission: deny` |
| `protect-shell.sh` | `beforeShellExecution` | `.env`/鍵を触るシェル(`cat .env` 等の抜け道)を拒否 | `permission: deny` |
| `post-lint.sh` | `afterFileEdit` | 編集後のファイルを format(既定 TS/JS = `biome` + `oxlint`) | 観測のみ |
| `stop-check.sh` | `stop` | 終了時に lint + typecheck + test、失敗なら `followup_message` で続行を促す | followup 注入 |
| `lib/protected.sh` | — | 保護判定の共有ロジック(6フックすべてが source; deny/hook_debug)+ `CURSOR_HOOK_DEBUG` 捕捉 | — |
| `lib/profile.sh` | — | `HOOK_PROFILE`(minimal/standard/strict)ゲート。既定 standard で6フック有効 | — |

設計の要点:
- **モデル固定は `beforeSubmitPrompt`**。Cursor Pro の「Auto + Composer」プールは Composer を使っても
  追加費用が無い。Auto がサードパーティへ振れると API クレジットを消費する。`enforce-model.sh` が
  スラグの prefix を確認し、`composer` 以外なら deny する。`CURSOR_REQUIRED_MODEL_PREFIX` を空にすると
  強制を無効化できる。モデルフィールドがペイロードに無い場合は fail-open(セッションを壊さない)。
- **秘密保護は読取(`beforeReadFile`)が要**。`.env*` は gitignore で commit/CI に網が無く、しかも
  読まれた時点で内容がコンテキストに漏れる。Cursor は読取を事前拒否できるので Claude より綺麗に塞げる。
- **書込の事前ブロックは `preToolUse`(matcher=`Write|Edit|MultiEdit|ApplyPatch`)**。matcher は tool 種別
  (`Write`/`Read`/`Shell`/`MCP:*`)で指定する点に注意(verb 文字列ではない)。`Edit`/`MultiEdit`/
  `ApplyPatch` は将来 Cursor が編集系 tool を細分化した場合への speculative な備えで、実在しない tool
  名を足しても無害(マッチしないだけ)。実際の tool 種別の taxonomy は初回ハンドオフで確認する。
- **stop-check は full**(lint+type+test)で `.claude`/`.codex` とパリティ。`loop_count` で無限ループを防止
  (既定上限 2、`CURSOR_STOP_LOOP_LIMIT` で調整可)。
- `strict` は ADR 0003 では `suggest-compact` 等も含むが Cursor へ未移植なので、本ハーネスでは
  `strict` ≒ `standard`(6フック)。`minimal` は post-lint のみ。

### 環境変数オーバーライド

| 変数 | 既定値 | 説明 |
|---|---|---|
| `HOOK_PROFILE` | `standard` | `minimal` / `standard` / `strict` でフックの有効範囲を切り替える |
| `CURSOR_STOP_LOOP_LIMIT` | `2` | stop-check が nudge する最大回数 |
| `CURSOR_REQUIRED_MODEL_PREFIX` | `composer` | enforce-model が要求するスラグ prefix。空文字列でモデル強制を無効化 |
| `CURSOR_HOOK_DEBUG` | (未設定) | 書き込み可能パスを設定すると各フックが raw stdin をログに追記する |

---

## 検証(fixture)

フックのルーティング/判定ロジックは fixture テストで固定してある(Cursor 実機不要):

```
bash scripts/test-cursor-hooks.sh
```

保護ファイルの書込拒否・秘密ファイルの読取拒否・`.env` を触るシェル拒否・`.ts` の format 呼び出し・
stop の followup とループガードを検証する。

---

## 実機で発火を確認する(merge 前の end-to-end チェック)

fixture はシェルロジックを固定するだけで、**Cursor が実際にフックを呼ぶか**は実機でしか分からない。
各フックは `CURSOR_HOOK_DEBUG` を立てたときだけ生の stdin を `=== <event> ===` 付きでログに吐く
(未設定なら no-op)。

```bash
export CURSOR_HOOK_DEBUG=/tmp/cursor-hooks.log
rm -f "$CURSOR_HOOK_DEBUG"
cursor-agent --model composer-2.5 "適当なソースに無害なコメントを1行足して。そのあと .env を読んで、.env に書き込んでみて。"
grep '^=== ' /tmp/cursor-hooks.log   # どのイベントが発火したか
cat /tmp/cursor-hooks.log            # 各イベントの生 JSON(キー名確認)
unset CURSOR_HOOK_DEBUG
```

確認したいこと:
- `=== beforeSubmitPrompt ===` が出て **`model` フィールドの実キー名**を確認する。`enforce-model.sh`
  は `.model` → `.model_id` の順で読む。ログの JSON に両方ともなければフィールド名を直す必要がある。
  また deny の応答フィールドが `beforeSubmitPrompt` で実際に `permission:"deny"` を解釈するかも確認する
  (他の制御可能イベントと同じ shape を採用しているが、実機未確認)。
- `=== beforeReadFile ===` が出て **`.env` の読取が拒否**されるか(漏洩防止の要)。
- `=== preToolUse ===` が出て **`.env`/設定の書込が拒否**されるか。出る JSON の path キー名が
  `protect-config.sh` の防御読み(`tool_input.file_path` / `file_path` / `path` …)で拾えているか。
  拾えていなければログの実キーに合わせて読みを1行直す。
- `=== beforeShellExecution ===` で `cat .env` 等が拒否されるか。
- `=== afterFileEdit ===` が編集後に出て format が走るか / `=== stop ===` が終了時に出て、
  失敗時 followup が回り `loop_count` で無限ループしないか。
- `preToolUse` の matcher (`Write|Edit|MultiEdit|ApplyPatch`) が実際の書込/編集系 tool 種別を
  網羅しているか確認する。`Edit`/`MultiEdit`/`ApplyPatch` は speculative な備えなので、実機の
  tool 名がこの4つ以外(あるいは一部のみ)なら matcher をログの実名に合わせて直す。

> 既知の注意: `preToolUse` の matcher は tool 種別(`Write` 等)で指定する。verb 文字列
> (`"edit|write|..."`)で書くと発火しないため、発火しないときはまず matcher を疑う。
