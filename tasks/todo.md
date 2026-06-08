# Codex Settings Migration

## Goal
Claude Code 向けに整備済みの Rules / Skills / Subagents / Hooks / Commands / contexts を、Codex でも同等に使える構成へ移行する。
既存の Claude Code 利用者を壊さず、Codex 側の参照パスとドキュメントを明確にする。

## Approach
- 既に存在する `.agents/skills` と `.codex/hooks` を活かし、足りない Codex 対応だけを追加する。
- Claude 固有パスを AGENTS/README で Codex 対応パスと併記し、共有ルールはツール非依存に寄せる。
- Claude slash commands / reviewer agents は Codex で完全互換ではないため、移植可能な手順書または agent TOML として表現する。
- 採用しない選択肢: `.claude/` を削除する。既存 Claude Code 利用者を壊すため今回は維持する。

## Steps
1. [x] `update/codex-settings-migration` ブランチを作成する。
2. [x] `.codex/` と `.agents/` の現状を Claude 側と比較し、欠けている reviewer agents / commands / rules 相当を追加する。
3. [x] `AGENTS.md`, README, 必要なら `CLAUDE.md` を更新し、Claude/Codex 両対応のパスと起動・運用方法を明記する。
4. [x] フックやドキュメント検査が Codex 側追加ファイルを前提に通るよう、既存テストを確認する。
5. [x] `localpartners` の Codex settings / `.agents/skills` / `contexts/` を参照し、汎用化できる差分を template-repo に反映する。
6. [x] Codex reviewer agents を `.codex/agents/review-*.toml` のフラット配置に揃え、workflow は `.agents/skills` に集約する。

## Verification
- [x] `bash scripts/check-doc-health.sh`
- [x] `bash tests/check-doc-health.test.sh`
- [x] `.codex/hooks.json` parses as JSON
- [x] `.codex/agents/*.toml` has required `name`, `description`, `developer_instructions` keys
- [x] lint / typecheck: 言語別 manifest (`package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`) が無いため対象コマンドなし。

## Risks
- Codex の hooks / agents 仕様が Claude Code と完全一致しない可能性があるため、互換性を断言せず repo-local 設定として扱う。
- `.codex/` と `.agents/` が未追跡なので、既存ユーザー作業を上書きしないよう差分を見てから最小編集する。
