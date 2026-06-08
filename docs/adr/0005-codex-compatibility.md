# ADR 0005: Codex 互換レイヤーの追加

- Status: Accepted
- Date: 2026-06-08
- Last-validated: 2026-06-08

## Context

このテンプレートは、すでに Claude Code 向けの構成を持っている。

- 共通ルール: `AGENTS.md`
- Claude Code 固有の実行時指示: `CLAUDE.md`
- Claude Code 向けの skills / agents / commands / hooks / rules: `.claude/`
- セッション目的別プロンプト: `contexts/`

一方で、このリポジトリは Codex でも使う。運用知識が `.claude/` にだけ置かれていると、Codex セッションでは計画、TDD、レビュー agent、hook profile、git rule などの重要なワークフローを参照できない。

## Decision

Claude Code のサポートを維持したまま、Codex 互換レイヤーを追加する。

- Codex project skills は `.agents/skills/` に置く。
- Codex hooks は `.codex/hooks/` に置き、`.codex/hooks.json` で配線する。
- Codex agents は `.codex/agents/*.toml` に置く。専門 review agents は `.codex/agents/review-*.toml` として同じ階層に置く。
- Codex command 相当の workflow は `.agents/skills/` に置く (`fix-review`, `handoff`, `multi-review`)。
- Codex-local reusable rules は `.codex/rules/` に置く。
- `AGENTS.md` は、すべての agent が常時読むリポジトリ共通ルールの source of truth として維持する。
- `CLAUDE.md` は Claude Code 固有の指示として維持し、Codex が安全に動くための必須ファイルにはしない。

`.claude/` は削除しない。Claude Code 利用者は既存の挙動を維持し、Codex 利用者は同等の repo-local settings を使えるようにする。

## Consequences

### Positive

- Codex でも Claude Code と同じ計画、TDD、レビュー、hook、git rule のワークフローを使える。
- Claude Code 互換性を壊さずに済む。
- ツール固有ファイルが分離されるため、将来の syntax change は該当レイヤーだけで扱いやすい。

### Negative / Tradeoffs

- `.claude/` と `.codex/` の間で一部内容が重複する。今後ワークフローを変更するときは両レイヤーを更新する必要がある。
- Codex workflow skills は Claude slash commands を写した手順書だが、正確な呼び出し方法は利用する Codex surface に依存する。
- hook schema はツールごとに独立して変わる可能性がある。`.codex/hooks.json` は Codex 固有の配線点として扱う。

## References

- ADR 0001: Template baseline for agentic development
- ADR 0002: Skills-first architecture と4層分離
- ADR 0003: Hook profiles, contexts ディレクトリ, bash/Node.js ハイブリッド
- ADR 0004: Multi-perspective PR review via specialized reviewer subagents
