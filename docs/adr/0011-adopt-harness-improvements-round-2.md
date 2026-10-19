# ADR 0011: 実案件で育ったハーネス改善の 2 回目の逆流

- Status: Accepted
- Date: 2026-10-19
- Last-validated: 2026-10-19

## Context

ADR 0010 (2026-08-17) の後も、派生先の実プロジェクトでハーネスが育ち続けた。今回は派生先の PM セッション (複数セッション運用の取りまとめ役) と相談しながら、汎用・プロジェクト固有・失敗の 3 つに仕分けた。

派生先で効いた改善の多くは、**モデル名・ツール名・資源名を具体的に書き込んだ実体化版**として育っている。ADR 0010 はこの種のもの (`model-roles.md` / `multi-review.md` の実体化版) を「汎用化すると要点が消える」として見送り、Out of scope に「実案件版の知見を汎用化して取り込むか」を残していた。今回はその宿題に答える。

## Decision

**具体名を抽象化したうえで、運用の骨格を取り込む。** 「どのモデルで回すか」はプロジェクトが決めるが、「何を定常工程にし、何を承認ゲートにし、何を裏取りするか」は汎用である。

取り込んだもの:

- **Plan review フェーズ** (CLAUDE.md Workflow phase 2): 上位モデルの planner レビュー → `/tacit-review` を、定常工程として省略しない。省略可能な書き方だと PM が飛ばし、計画の誤りが実装後に高くついた
- **レーン / PM / worker の体制** (`model-roles.md`、`orchestration` skill、`/focus`): レーンは実装しない、実装主体を報告する、共有資源は台帳 (`tasks/reference/lanes.json` の汎用形 `slots` / `queues`) で PM だけが割り当て、「一報」ではなく「返事を待ってから」使う
- **`mutation-testing` skill**: worker の「直した」もレビュアーの「修正済み」も実測するまで信じない。退避・1 つずつ戻す・実行件数の確認・緑の疑い方
- **`pitfalls.md` の構成と汎用 starter**: core を短く保ち、領域別は `paths` 付き rule に逃がす (派生先では常駐コンテキストが 57k トークンまで膨らみ、分割で 15k に落ちた)
- **registry の `parent` と完遂の判定**: 子スライスの done で自走が止まる事故への対策。`inflight` サブコマンド
- **`suggest-compact` の帯ごと 1 回通知**: 閾値超えのあいだ毎回差し込まれる警告自体が文脈を消費していた
- **commit-msg チェックのスクリプト化**: テスト可能にし、エディタ経由のコメント行で正しいメッセージを拒否していたバグを修正。エージェント trailer を明示的に拒否
- **`git-guard` の PR 本文チェック**: 生成ツール署名・セッション URL を `gh pr` の本文から止める。パターンは 1 箇所の配列
- **CI の docs-only skip**: job レベル `if:` で、判定に疑いがあれば全ジョブを回す側に倒す
- コメント方針と `git checkout` / `restore` / `stash` 禁止の contexts / Cursor rule への反映

取り込まなかったものと理由:

- **Linear 連携** (registry の `linear` フィールド等) — 派生先でも個人ツール扱いで、tracked ファイルに痕跡を残さないことが要件だった。テンプレートの既定にする理由が無い
- **`.codex` を unmaintained 扱いにする変更** — 派生先固有の判断。テンプレートは ADR 0005 の Codex 互換と parity テストを維持する
- **post-lint への自動修正** — 派生先で、自動修正が worker のスコープ外の書き換えに見えて誤診の原因になった
- **派生先の `sync-tasks.sh` での置き換え** — テンプレート版のほうが壊れた行への耐性と Python 3.8 互換で上回る。差分の機能だけを足した
- **commit-msg の prefix 拡張と Merge/Revert 免除の削除** — テンプレートの `git.md` は scope や `!` を許していない。ローカル merge する利用者を止めないよう免除は残す
- **CI 判定の GitHub API 利用** — トークン権限に依存しない素の git に置き換えた。テンプレートではハーネス自体が被テスト対象なので、docs-only の範囲も派生先より狭い
- **領域別の pitfalls 本文、DB / 画面 / deploy 系の skill** — プロジェクト固有

**保護ファイルの扱い**: `suggest-compact.mjs` と `lefthook.yml` は protect-config の保護対象である。実装 worker は案を別パスに書くだけで保護をバイパスせず、orchestrator が diff を確認したうえでユーザの承認を得て Bash で反映した。保護の仕組みは変えていない。

**機密**: ADR 0010 の方針を継続し、派生先の識別子 (クライアント名・プロダクト名・ユーザ名・パス) を成果物に持ち込まない。参照ファイルは事前に grep で検査してから worker に渡した。

## Consequences

### Positive

- 新規プロジェクトが、実運用で効いた工程 (plan review の定常化、レーン規律、mutation による実測) を最初から持てる
- 常駐コンテキストの膨張に対する構成 (core + paths 付き rule + skill) が最初から示される
- `git-guard` / commit-msg / suggest-compact / CI の各ガードの穴と誤検知が、テスト付きで塞がれた

### Negative / Tradeoffs

- `git-guard` の PR 本文チェックはコマンド文字列全体を走査するため、同じコマンド内の別の箇所に署名文字列があると止まる (heredoc 本文を確実に拾うための割り切り)。シェルの完全なパースはしない best effort である
- `orchestration` skill と `/focus` は複数セッション運用を前提にしており、1 セッションで完結する利用者には不要な分量がある (オンデマンドロードなので常駐コストは無い)
- 逆流は今回も手動。ファイル単位の突き合わせと仕分けが毎回必要

### Out of scope (handle in a future ADR)

- 逆流の自動化 (テンプレートを upstream remote として派生先に持たせ、差分を定期的に出す等)
- `git-guard` の既存部分を含む fail-open 契約の徹底 (`set -e` 下で `sed` / `tr` 自体が失敗すると exit 1 になる)

## References

- ADR 0005: Codex 互換
- ADR 0007: CI backstop (docs-only skip の追記)
- ADR 0010: 1 回目の逆流 (本 ADR はその Out of scope に答える)
- `.claude/skills/orchestration/SKILL.md` / `.claude/commands/focus.md` / `.claude/skills/mutation-testing/SKILL.md`
