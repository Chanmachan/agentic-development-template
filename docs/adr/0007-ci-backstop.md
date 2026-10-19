# ADR 0007: エージェント非依存の CI バックストップ

- Status: Accepted
- Date: 2026-07-06
- Last-validated: 2026-10-19

## Context

`AGENTS.md` は「Code, tests, schemas, ADRs, and CI are truth. Prose docs are not.」と宣言しているが、ADR
0006 が記録した時点ではこの宣言は嘘だった: リポジトリに `.github/workflows/` が存在せず、CI は未整備のまま
だった。安全網は agent 側 (Claude Code の hooks、Codex の hooks、lefthook pre-commit の `doc-health`) のみ
に依存しており、以下の弱点があった。

1. lefthook はローカルの `git commit` 経路でのみ発火する。agent が `--no-verify` を使わない限り機能するが、
   それでも "commit した瞬間" の防御でしかなく、PR 経由でマージされる変更全体 (複数コミットの積み上げ、
   force-push 後の状態など) を通しで検証する仕組みがない。
2. Claude/Codex/Cursor いずれのハーネスも「エージェントが正しく振る舞うこと」に依存しており、エージェントの
   実装ミスやハーネス自体のバグ (hooks.json の配線ミスなど) を捕捉する第三者的なチェックが存在しなかった。
3. `scripts/check-doc-health.sh` や `tests/*.test.sh` はローカルで実行すれば検出できる回帰を持つが、
   「ローカルで実行するのを agent が忘れる/サボる」ケースを防げない。

このテンプレート自体はアプリケーションコードを持たない scaffolding なので、CI が検証すべき対象は
テンプレート自身の testable surface — doc-health ガードレールと `tests/*.test.sh` の bash fixture 群、
および hooks スクリプト群の shellcheck — に限定される。

## Decision

`.github/workflows/ci.yml` を追加し、`pull_request` と `push`(main) をトリガーに 3 ジョブを実行する。

1. **doc-health** — `bash scripts/check-doc-health.sh` を実行し、`AGENTS.md`/`CLAUDE.md` の壊れたポインタと
   ADR の鮮度 (`Last-validated`) を検証する。
2. **tests** — `tests/*.test.sh` を全て実行する。加えて `scripts/test-cursor-hooks.sh` が存在すれば
   (`.cursor/` 実装担当ハーネスが未マージのブランチでは存在しないため、ファイル存在チェックでガードする)
   それも実行する。
3. **shellcheck** — `scripts/*.sh` と `scripts/lib/*.sh`、`.claude/hooks/*.sh` と `.claude/hooks/lib/*.sh`
   (明示した2階層、再帰はしない)、`.codex/hooks/*.sh` と `.codex/hooks/lib/*.sh` (同じく2階層)、
   `.cursor/hooks` が存在する場合は `find` で `.cursor/hooks/**/*.sh` を再帰的に列挙 — に対して
   `--severity=error` で実行する。style/info
   レベルの指摘 (例: `.sh` を source する際の SC1091) は今回スコープ外とし、まずはエラーレベルのみを
   ブロッキングにする warning-level gate として導入する。厳格化 (`--severity=warning` 化や個別 ID の是正)
   は将来の課題。

あわせて `lefthook.yml` に `commit-msg` フックを追加し、`.claude/rules/git.md` が定めるコミットメッセージ
規約 (`prefix: description`、prefix は `feat|fix|update|refactor|style|docs|test|chore|del|perf|ci`、
本文・フッターなしの単一行) を強制する。1行目のプレフィックス検証に加え、2行目以降に空行以外の内容が
あれば reject する (末尾の空行のみは許容)。`Merge ...` / `Revert ...` は例外的に許可し、この場合は複数行の
本文 (git が自動生成するマージ元一覧など) を丸ごと許容する。CI 自体はコミット単位でなく PR 差分単位の
チェックなので、この gate は既存の pre-commit ブロックとは独立した実行単位として追加する (既存の
Conventional Commits validator を本リポジトリの prefix セットに合わせて移植)。この gate が検証しないもの:
`fixup!`/`squash!` プレフィックスは通常のプレフィックス集合に含まれないため reject される — 本ワークフローは
インタラクティブ rebase を前提としていないための意図した挙動であり、バグではない。

`.github/dependabot.yml` (github-actions エコシステムのみ、週次) と `.github/pull_request_template.md`
(`.claude/rules/git.md` の PR テンプレートと同一構造) も本 ADR のスコープで追加する。

## Consequences

### Positive

- `AGENTS.md` の "CI are truth" が PR レベルで実際に成立するようになる。agent のハーネス実装に依存しない
  第三者チェックが手に入る。
- lefthook はローカルの高速フィードバック経路として引き続き有効 (commit 時点で即座に doc-health /
  commit-msg を検証)。CI は "lefthook を経由しない commit・force-push・複数コミットの積み上げ" もまとめて
  検証する、独立したセーフティネットとして機能する。
- shellcheck を warning-level gate として先に入れることで、後から `--severity=warning` に締めるときの
  差分が小さくなる。

### Negative / Tradeoffs

- shellcheck は `--severity=error` に限定しているため、quoting 忘れなど warning レベルの実質的なバグを
  今は検出しない。個別スクリプトの手動レビューに依存し続ける部分が残る。
- `.github/workflows/ci.yml` は `.cursor/` ディレクトリの有無をファイル存在チェックで吸収しているため、
  ADR 0006 のブランチがマージされるまでは Cursor 関連の shellcheck/fixture テストは実行されない
  (マージ後は自動的に対象に入る)。
- CI はこのテンプレート自身の testable surface のみを見ており、利用者がアプリケーションコードを追加した
  後の lint/typecheck/build/test ジョブは含まれていない。README の "Checklist" に従って利用者が追加する
  前提。

### Out of scope (将来の ADR で扱う)

- shellcheck の `--severity=warning` 以上への引き上げ
- 言語スタック選定後の lint/typecheck/build/test ジョブ追加
- CI 上での `HOOK_PROFILE=strict` 相当の追加チェック (テレメトリ、フック実行回数の計測など)

## Addendum: docs-only change では tests / shellcheck をスキップする

`changes` ジョブが `scripts/ci-detect-code-changes.sh` で変更パスを判定し、`tests` と `shellcheck` を job レベルの
`if:` で制御する。`doc-health` は常に実行する。

- docs-only の定義はスクリプト冒頭の `is_docs_only` 1 箇所: `docs/`・`idea/`・`research/` 配下と、リポジトリ直下の
  `*.md`。ハーネス自体 (`.claude/` `.codex/` `.cursor/` `.agents/` `contexts/` `scripts/` `tests/`) がこのテンプレートの
  被テスト対象なので code 扱い。利用者はプロジェクトに合わせて書き換える。
- 判定は API を使わない素の git (`git diff --name-only --no-renames`)。rename は旧パス・新パスの両方が報告される
  ため、code から docs への移動で削除が隠れない。
- fail-safe は常に全ジョブ実行 (`code=true`) の方向: 未知のイベント、before SHA の欠落・全ゼロ、到達不能な SHA、
  git 失敗、空の変更リストはすべて `::warning::` を出して `code=true` にする。
- required check との関係: job レベル `if:` でスキップされたジョブは success 扱いで required check を塞がない。
  `on.<event>.paths` フィルタはワークフロー自体が起動せず required check が pending のまま残るため使わない。

## References

- ADR 0002: Skills-first architecture と4層分離
- ADR 0003: Hook profiles, contexts ディレクトリ, bash/Node.js ハイブリッド
- ADR 0006: Cursor Composer を実装担当にする第3ハーネス (`.cursor/`)
- `.claude/rules/git.md` — commit message / PR template の source of truth
