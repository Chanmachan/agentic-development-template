# ADR 0010: 実案件で育ったハーネス改善をテンプレートに逆流させる

- Status: Accepted
- Date: 2026-08-17
- Last-validated: 2026-08-17

## Context

このテンプレートから作られた実プロジェクト (2件) を数か月動かした結果、テンプレートと派生先が**双方向に分岐**していた。

- **テンプレート側が新しい**: `scripts/lib/protected.sh` への分類ロジック集約 (ADR 0008)、`protect-config.sh` の fail-closed 化、`check-doc-health.sh` / `sync-tasks.sh` の修正、`worktree-setup.sh` (ADR 0009)、`context-*` skills、`rules/git.md` の attribution 禁止
- **派生先が新しい**: 実際に手を動かして初めて必要になったもの — `git-guard.sh`、`comments.md`、`repo-audit` skill、`/tacit-review`、`/weekly-progress`、`suggest-compact.mjs` の実トークン数ベース化、各 skill / subagent の文言改善

放置すると差は開く一方で、新規プロジェクトは「実案件で判明した改善」を毎回ゼロから再発見することになる。逆に派生先を無条件にテンプレートへ取り込むと、プロジェクト固有の前提が混入する。

実際、今回の突き合わせで**別クライアントの DB 接続情報・ローカルパス・リポジトリ絶対パスがハーネスファイルに含まれている**ことが判明した。派生先どうしのコピーでこれが伝播していた。

## Decision

**汎用と判断できる改善だけをテンプレートへ取り込む。** 具体的な取り込み内容:

- `git-guard.sh` (Claude / Codex) と `.claude/settings.json` / `.codex/hooks.json` への配線。`main` への直接コミット・`--no-verify`・`main` での force-push をブロックし、`cd` チェーンを解決して**実際に git が走るブランチ**で判定する
- `suggest-compact.mjs` を transcript の**実トークン数** (`message.usage`、sidechain 除外) ベースに変更。従来のファイルサイズ ÷ 2 推定は、巨大な 1 レコードや compact 直後に大きく外れる
- `.claude/rules/comments.md` (コメントを書かず、テスト / todo / PR 本文に逃がす)
- `repo-audit` skill、`/tacit-review`、`/weekly-progress`
- `.cursor/rules/{branch,commit,pull-request}.mdc` (`.claude/rules/git.md` の Cursor 向けミラー)
- 各 subagent / skill / command の文言改善

**取り込まなかったもの**と理由:

- `/update-docs` — 特定プロジェクトの Obsidian vault 構成に依存し、汎用化しても骨が残らない
- 派生先の `verify-guide.md` — ローカル環境の具体値 (ポート・DB 接続情報・seed アカウント) が本体。テンプレートは汎用版を維持する
- 派生先の `model-roles.md` / `multi-review.md` — 具体的なモデル名・プラン・画面IDまで書き込まれた**実体化版**であり、テンプレート側の意図的に抽象化された版とは役割が違う。汎用化すると要点が消える
- 言語依存のフック実装 — テンプレートは language-agnostic を維持する

**分岐の判定は git 履歴で行う。** ファイルサイズや mtime は当てにならない: 派生先の `scripts/*.sh` が小さいのは機能差ではなく no-comments policy でコメントを剥がしたためで、テンプレート側にはその後の実バグ修正が入っていた。

**派生先から持ち込むときは、他プロジェクトの識別子・パス・認証情報が混ざっていないか必ず確認する。**

## Consequences

### Positive

- 新規プロジェクトが実案件由来の改善を最初から得られる
- `git-guard` により `main` 直コミットが構造的に防がれる
- `suggest-compact` の判定が実測ベースになり、誤発火・見逃しが減る
- 逆流の判断基準 (何を持ち込み、何を持ち込まないか) が記録された

### Negative / Tradeoffs

- `suggest-compact.mjs` は 2 ハーネスで**意図的にゲートが異なる** (`.claude` = standard+strict / `.codex` = strict のみ) ため、`tests/harness-parity.test.sh` のバイト一致対象から外した。代わりに `tests/hooks.test.sh` が両方の挙動を検証するが、それ以外の差分は無防備になる
- 旧 `tests/suggest-compact.test.sh` は旧実装 (ファイルサイズ推定) 前提で意味を失ったため削除した
- 逆流は手動作業のまま。次回もファイル単位の突き合わせが必要になる

### Out of scope (handle in a future ADR)

- 逆流の自動化 (テンプレートを upstream remote として派生先に持たせ、定期的に差分を出す等)
- テンプレート側の `model-roles.md` / `multi-review.md` を、実案件版の知見を汎用化して取り込むか

## References

- ADR 0008: harness dedup (`scripts/lib/protected.sh` への集約)
- ADR 0009: 2026 Claude Code features の採用 (`worktree-setup.sh`、path-scoped rules)
- `tests/hooks.test.sh` — `git-guard` と `suggest-compact` のフィクスチャテスト
