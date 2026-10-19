# 既存プロジェクトにハーネスを重ねる

このテンプレートを `Use this template` で始めるのではなく、**すでにあるリポジトリ**に AI 開発ハーネスを持ち込むときの手順。チームのリポジトリに共有として入れる場合と、自分だけが使う個人オーバーレイとして重ねる場合の両方を扱う。

末尾に、別の環境の AI エージェントにそのまま渡せるプロンプトがある。

## 2 つのモード

| モード | 何をするか | 向いているもの |
|---|---|---|
| **共有** | ハーネスを commit し、PR でチームに入れる | チームで合意できる規約・ガード (commit-msg、CI、レビュー手順) |
| **個人オーバーレイ** | tracked ファイルに痕跡を残さずに重ねる。既存の `CLAUDE.md` / `.claude/settings.json` / `lefthook.yml` / CI は書き換えない | 自分の進め方 (計画・台帳・PM 運用・個人の hook / skill)、チームに押しつけたくないもの |

部品ごとにどちらかを決める。混在するのが普通で、迷ったら個人オーバーレイにする (後から共有に格上げするほうが、共有から外すより安全)。

## 部品ごとの置き場所

| 部品 | 共有 | 個人オーバーレイ |
|---|---|---|
| 常駐の指示 | `CLAUDE.md` / `AGENTS.md` | `CLAUDE.local.md` (自分で ignore する)。全プロジェクト共通なら `~/.claude/CLAUDE.md` |
| rules | `.claude/rules/*.md` | `.claude/rules/<接頭辞>-*.md` を exclude。全プロジェクト共通なら `~/.claude/rules/` |
| hooks | `.claude/settings.json` | `.claude/settings.local.json`。hook はスコープをまたいでマージされ、チームの hook と並んで走る。スクリプトはリポジトリの外に置き、絶対パスで参照する |
| skills / commands | `.claude/skills/` / `.claude/commands/` | リポジトリ内に置いて exclude するか、`~/.claude/skills/` (全プロジェクトで有効) |
| subagents | `.claude/agents/` | `~/.claude/agents/` |
| 計画・台帳 (`tasks/`) | — | `tasks/` を exclude。worktree へは symlink (`scripts/sync-local-docs.sh` の方式) |
| 個人の補助スクリプト | `scripts/` | リポジトリの外に置くか、分岐元にだけ置いて `"$(git rev-parse --git-common-dir)/../scripts/<name>.sh"` で呼ぶ |
| git hooks | `lefthook.yml` | `lefthook-local.yml` (lefthook が `lefthook.yml` に重ねて読む)。これも ignore する |
| CI | `.github/workflows/` | 持たない。個人のゲートはローカルの hook で回す |

個人オーバーレイの ignore は、原則 `.git/info/exclude` に書く。リポジトリの `.gitignore` を編集すると、それ自体が tracked の痕跡になる。`.git/info/exclude` は分岐元とすべての worktree で共有される。

## 手順

1. **棚卸し (読むだけ)** — 既存の AI 設定 (`CLAUDE.md` / `AGENTS.md` / `.claude/` / `.cursor/` / `.codex/`)、git hooks、CI、`.gitignore`、言語・パッケージマネージャ・lint / typecheck / test のコマンド、ブランチとコミットの規約。
2. **計画** — 上の表をこのプロジェクト用に埋め、部品ごとに共有か個人かを決めて `tasks/<id>-todo.md` に書く。テンプレートから何を持ち込み、何を持ち込まないかもここで決める。承認を得るまでファイルを変更しない。
3. **持ち込む** — 必要な部品だけを持ち込む。言語依存の部分 (`post-lint.sh` / `stop-check.sh` のコマンド、`lefthook.yml` の lint・typecheck) は、このプロジェクトのツールチェーンに合わせる。既存の規約 (コミットの prefix、ブランチ名) とぶつかる部分は既存側に合わせる。
4. **個人分を除外する** — `.git/info/exclude` に追記し、`git check-ignore -v <path>` で効いていることを、`git status --porcelain` が空であることを確かめる。
5. **worktree に対応する** — 未追跡のファイルは新しい worktree に現れない。`tasks/` のような共有したい個人ディレクトリは symlink する。gitignored のファイルをコピーしたいなら `.worktreeinclude` (`.gitignore` と同じ書式) を使い、`.worktreeinclude` 自体も exclude する。
6. **検証** — hook はテンプレートの `tests/` を流用できる範囲でテストする。新しいセッションを起動し、`/context` で rules・skills が載っていることを確かめる。最後に `git status --porcelain` が空であること、PR 本文やコミットに個人ハーネスの言及が無いことを確かめる。

## 落とし穴

- **追跡を外したファイル** (`git rm --cached` してから ignore) は、その削除コミットを別のチェックアウトで checkout / merge した瞬間にディスクからも消える。外す前に退避しておく。
- **除外した個人ファイルと同じパスに、チームが後からファイルを追加する**と、pull / merge が「untracked working tree file would be overwritten」で止まる。個人ファイルには衝突しにくい接頭辞を付ける。
- **名前の衝突**: `~/.claude/skills/` の個人 skill は同名のチームの skill を上書きする。逆に `~/.claude/agents/` の個人 subagent は、同名のチームの subagent に負ける。
- **`CLAUDE.local.md` と `AGENTS.md`**: `CLAUDE.md` が無く `AGENTS.md` だけのリポジトリで `CLAUDE.local.md` を足すと、`AGENTS.md` が読まれなくなる。その場合は `CLAUDE.local.md` の先頭で `@AGENTS.md` を import する。
- **`settings.local.json` の ignore**: Claude Code が初めて書き込むときは、利用者の global な git excludes に追加される。手で作った場合は自分で ignore する。
- **worktree の `${CLAUDE_PROJECT_DIR}`** は、worktree ではなくセッションを始めた分岐元を指す。hook のスクリプトを `${CLAUDE_PROJECT_DIR}` 相対で参照すると、worktree のブランチで hook を書き換えても、動くのは分岐元のスクリプトのまま。
- **機密**: クライアント案件の名前・パス・接続情報を、テンプレートや `~/.claude/` の全プロジェクト共通の設定に持ち出さない。

## 派生先の改善をテンプレートへ戻す

派生先で育ったハーネスの改善は、テンプレートへ戻すと次のプロジェクトが最初から使える。手順は ADR 0010 / ADR 0011 に記録している:

- 分岐の向き (どちらが新しいか) は git 履歴で判定する。ファイルサイズや mtime は当てにならない
- 汎用・プロジェクト固有・失敗だったもの、に仕分ける。派生先で運用している人 (PM セッション等) に聞くのが早い
- モデル名・ツール名・資源名は抽象化して骨格だけを持ち込む
- 持ち込む前に、派生先の識別子 (クライアント名・プロダクト名・人名・パス) を grep で検査する。commit・PR 本文・ブランチ名・task id も対象

## AI エージェントに渡すプロンプト

`<PROJECT_PATH>` と `<TEMPLATE_PATH>` を埋めて、対象プロジェクトで起動したセッションに渡す。

````text
既存プロジェクト <PROJECT_PATH> に AI 開発ハーネスを整えてほしい。参照するテンプレートは <TEMPLATE_PATH> にある。

進め方:
1. まず <TEMPLATE_PATH>/docs/adopt-existing-project.md を読み、その手順に従う。テンプレートの AGENTS.md / CLAUDE.md / .claude/rules/ / docs/adr/0010・0011 にも目を通す。
2. 対象プロジェクトを棚卸しする。読むだけで、まだ何も変更しない: 既存の AI 設定 (CLAUDE.md, AGENTS.md, .claude/, .cursor/, .codex/)、git hooks、CI、.gitignore、言語・パッケージマネージャ・lint/typecheck/test のコマンド、ブランチ・コミットの規約。
3. ガイドの「部品ごとの置き場所」の表をこのプロジェクト用に埋めた計画を書いて見せる。部品ごとに「共有 (commit して PR で入れる)」か「個人オーバーレイ (tracked ファイルに痕跡を残さない)」かを提案し、迷うものは質問する。既定は個人オーバーレイ。
4. 私が承認するまで、ファイルを変更しない。
5. 承認後に実装する。共有の部品は feature ブランチと PR で入れる。個人の部品は .git/info/exclude で除外し、git status --porcelain に何も出ないことを確かめる。
6. 最後に、検証の結果を報告する: git status、hook の動作確認、新しいセッションで rules / skills が載るかどうか。

守ること:
- 共有と合意した部品以外の tracked ファイル (CLAUDE.md, .claude/settings.json, lefthook.yml, CI など) は書き換えない。
- このプロジェクトの名前・パス・認証情報を、テンプレートや ~/.claude/ の全プロジェクト共通の設定に持ち出さない。
- テンプレートの言語依存の部分は、このプロジェクトのツールチェーンに合わせる。既存の規約とぶつかる部分は既存側に合わせる。
- コミットと PR はこのプロジェクトの規約に従う (無ければテンプレートの .claude/rules/git.md)。ツールの署名や Co-Authored-By は付けない。
````
