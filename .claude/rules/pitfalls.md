# Pitfalls (core)

同じ穴を 2 度踏んだらここに追記する。可能なものはテスト / lint / hook に昇格する。

## 書き方

- 1 項目 1〜2 行: **踏んだ操作** → 見え方 (なぜ気づけないか) → 対処。
- このファイルは常駐するので短く保つ。領域別の穴は `paths` frontmatter 付きの `.claude/rules/pitfalls-<domain>.md` に分ける (対象ファイルを Read したときだけ載る)。手順を伴う塊は skill にする (例: `mutation-testing`)。
- 大きく書き直すときは、旧版を commit の blob で凍結して参照する (`git cat-file blob <commit>:.claude/rules/pitfalls.md`)。項目に番号を振るなら凍結版で固定し、使い回さない。

```markdown
---
paths:
  - "db/**"
  - "migrations/**"
---

# Pitfalls (db)
```

## git・ファイル操作

- `git commit … | tail` / `| head` → lefthook が SIGPIPE で止まり commit が作られない → パイプしない。出力を絞るならファイルにリダイレクトしてから読む。
- 未コミットの作業がある状態で `git checkout -- <path>` / `git restore` → 作業ごと HEAD に戻り復元できない (tracked だけ消えて `git status` はクリーンに見える) → 退避コピーから戻す。worker には撃たせない (`orchestration` skill)。
- commit 済みの変更を `git checkout -- <path>` で戻そうとする → HEAD に入っていれば no-op で、`git status` では分からない → `git checkout <base> -- <path>` を使い、`git diff <base>...HEAD -- <path>` が空になったことを確かめる。
- `git show <rev>:<path>` を在否の確認に使う → パスに `[` `*` `?` を含むと rc=0・0 バイトで返り、新規と全消しの区別がつかない → `git cat-file -e <rev>:<path>` / `git cat-file blob`。
- 追跡を外したファイル (`git rm --cached` + `.gitignore`) → その削除コミットを別のチェックアウトで checkout / merge した瞬間、ディスクからも消える → 外す前に退避し、各チェックアウトで戻す。
- `cat > <path>` / `open(p, 'w')` → 読み込む前に中身が空になる。既存のテストを丸ごと置き換えても緑のまま assertion が減り、`tasks/` 等の git 管理外は戻せない → 先に `git cat-file -e HEAD:<path>`、追記は `>>`、読み書きは 2 文に分けて事前に `cp` で退避。
- 生成スクリプトを鮮度の検査に流用する → git 管理外のファイルを無言で上書きする → 一時ディレクトリに出力して `diff` を取る。

## シェル・環境

- zsh でループ変数に `path` を使う → `PATH` と連動していて以降のコマンドが見つからなくなる → `p` / `f` 等を使う。
- zsh はクォートしない変数を単語分割しない → `for f in $files` が全体で 1 回しか回らず、0 件実行のまま緑になる → 配列にするか bash で実行する。
- zsh で `echo ====` → `=` 展開でエラーになる → クォートする (`echo '===='`)。
- macOS の `/usr/bin/python3` (3.9) → 1 行が 1,023 バイトを超え、1,024 バイト境界が多バイト文字をまたぐと `SyntaxError` (`.py` と stdin が該当、`python3 -c "$(cat …)"` は該当しない) → 先頭に `# -*- coding: utf-8 -*-`、`awk 'length > 1023'` で長い行を探す。
- Bash ツールから `node` / `npx` を呼ぶ → nvm の関数に shadowing されて失敗する → 絶対パスか、パッケージマネージャ経由 (`pnpm exec <bin>` 等) で呼ぶ。
- `pgrep -f <語>` でプロセスの在否を見る → その語を引数に含む別プロセス (brief を渡した agent 等) にも当たる → `ps -Ao pid,comm,args` で comm を見て絞る。

## エージェントの実行

- worker の起動コマンドを同名の関数で包む (`foo() { foo --model x "$@"; }`) → 自分自身を呼び続けて fork bomb になる → 別名にするか `command foo` で本体を呼ぶ。
- `codex exec` をバックグラウンドで起動する → stdin が開いたままだと入力待ちで止まる (CPU 0・セッションファイルが増えない) → `</dev/null` を付ける。
- stop hook や pre-push でテストが走る → 別のセッションが共有資源 (ローカル DB 等) を同時に叩き、無関係な赤を自分の diff のせいだと誤診する → 共有資源を使うテストは台帳で枠を取ってから回す (`orchestration` skill)。docs だけの変更ではテストを skip する。

## 主張の裏取り

- subagent の報告にある `file:line` を計画に転記する → 自分で開いてから。報告は索引として使う。
- レビュアーの「この変異でも緑」「修正済み」 → 自分で撃ってから採否を決める (`mutation-testing` skill)。
- 「無い」「必ず」 → 2 つの方法で確かめる (一覧に無い + 実際に引いても見つからない)。
- 原文を否定する訂正を、再現条件なしで書く → 条件を復元できなければ「未特定」と残す。
