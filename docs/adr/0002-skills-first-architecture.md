# ADR 0002: Skills-first architecture と4層分離

- Status: Accepted
- Date: 2026-05-11
- Last-validated: 2026-05-12

## Context

このテンプレートは ADR 0001 で基本構成 (AGENTS.md / CLAUDE.md / Claude hooks / Lefthook / ADR) を採用したが、運用を重ねるなかで以下の課題が見えてきた。

1. **CLAUDE.md / AGENTS.md にワークフロー知識を集約しすぎている**。TDD・コードレビュー・PR 作成などのワークフローは常時参照する必要がないにもかかわらず、毎セッション冒頭でロードされ、コンテキストウィンドウを消費している。
2. **Subagents が活用されていない**。調査・レビュー・計画立案などのタスクをメインの会話文脈で実行しているため、文脈が早期に汚染される。
3. **Plan → Implement → Verify → Commit のフェーズ分けが暗黙的**。`AGENTS.md` に「Plan → approval → implement」と1行あるのみで、各フェーズで何を成果物として作るかが明確でない。
4. **コンテキスト管理の指針がない**。`/clear`、`/compact`、サブエージェント切り出しの使い分けがルール化されていない。

Anthropic 公式のベスプラ (Claude Code docs, "Best practices") は次を強調している。

- **コンテキストウィンドウは最も重要なリソース**であり、埋まるほど性能が劣化する
- **CLAUDE.md は短く保つ** — 「これを削ったら Claude がミスを犯すか?」を各行に問い、答えが No なら削る
- 常時必要ない知識は **Skills (`.claude/skills/`)** に切り出し、オンデマンドでロードする
- 調査・分析タスクは **Subagents** に委譲してメイン文脈を保護する
- **Explore → Plan → Implement → Commit** の4フェーズを意識する
- 検証手段 (テスト、スクリーンショット、期待出力) を必ず与える

ECC (everything-claude-code) リポジトリでは、これを **4層分離アーキテクチャ** として具体化している。

- Rules: 常時ロードの制約 (何をすべきか)
- Skills: オンデマンドロードのワークフロー (どうやるか)
- Subagents: 制約付きツールアクセスを持つ実行コンテキスト
- Hooks: ツール使用イベントに反応する確定的な自動化

## Decision

公式ベスプラと ECC の4層分離を採用し、以下の構造に再編する。

### 1. 4層の役割分担

| 層 | 配置 | ロードタイミング | 用途 |
|----|------|------------------|------|
| Rules | `AGENTS.md` / `CLAUDE.md` / `.claude/rules/` | 常時 | 不変の制約、原則、リポジトリの地図 |
| Skills | `.claude/skills/<name>/SKILL.md` | オンデマンド | 手順、ワークフロー、How-to |
| Subagents | `.claude/agents/<name>.md` | 委譲時 | 制約付きツールアクセスでの専門タスク |
| Hooks | `.claude/hooks/*.sh` | ツール使用イベント時 | 確定的に動かしたい自動化・ガードレール |

判断基準: **「毎セッションで必要か?」が Yes なら Rules、No なら Skills。「人間が指示する必要があるか?」が Yes なら Skills/Subagents、No (毎回自動で動くべき) なら Hooks。**

### 2. Skills ディレクトリの新設

`.claude/skills/` を作成し、以下のスキルを初期実装する。

- `tdd/SKILL.md` — TDD ワークフロー (Explore → 失敗するテスト → 実装 → リファクタ)
- `code-review/SKILL.md` — レビュー観点と進め方
- `plan-mode/SKILL.md` — Plan Mode を使った設計フェーズの進め方

各 SKILL.md は YAML フロントマター (name, description) を持ち、Claude Code が `description` を見て自動ロードを判断する。

### 3. Subagents ディレクトリの新設

`.claude/agents/` を作成し、以下を初期実装する。

- `planner.md` — 計画立案専用。ツールは Read / Grep / Glob / Bash のみ (Write / Edit を持たない)。
- `code-reviewer.md` — レビュー専用。読み取り系ツールのみ。
- `investigator.md` — コードベース調査専用。メイン文脈を汚さずに探索する。

各 Subagent は YAML フロントマター (name, description, tools, model) を持ち、`description` に "Use PROACTIVELY when ..." と書くことで自動委譲を誘導する。

### 4. CLAUDE.md / AGENTS.md のスリム化

- 現状の `CLAUDE.md` から「Editing rules」「Planning」セクションのうち、ワークフロー知識に該当する部分を Skills に移す
- `AGENTS.md` は引き続き 50 行制限を守る (`scripts/check-doc-health.sh` で強制)
- `CLAUDE.md` には次のみを残す:
  - Plan → Implement → Verify → Commit の4フェーズフロー
  - コンテキスト管理ルール (`/clear` / `/compact` / Subagent 切り出しの使い分け)
  - Skills と Subagents が存在することの明示

### 5. 4フェーズワークフローの明文化

`CLAUDE.md` に以下を記載する。

```
1. Plan — 非自明な変更は planner subagent または Plan Mode で計画。tasks/todo.md に成果物を残す
2. Implement — tdd skill に従い、失敗するテスト → 実装 → リファクタ
3. Verify — lint / typecheck / test を通す (stop-check.sh で強制)
4. Commit — git rule に従う (review コマンドで PR 対応)
```

### 6. コンテキスト管理ルール

`CLAUDE.md` に次の指針を入れる。

- 調査タスクは investigator subagent に委譲する (メイン文脈を保護)
- セッションが長くなったら `/compact` でなく `/clear` を優先 (要約より破棄のほうが文脈クリーンに保てる)
- 大規模リファクタはコンテキスト消費 20% 未満の段階で着手する

## Consequences

### Positive

- CLAUDE.md / AGENTS.md のロードコストが下がる (常時必要な指示だけになる)
- ワークフロー知識が `.claude/skills/` に集約され、追加・改廃が容易
- Subagent によりメイン文脈の劣化が遅くなり、長時間セッションでも品質が維持される
- 公式ベスプラに沿った構造になるため、Claude Code のアップデートに追従しやすい
- ECC の `~/.claude/skills/` (グローバル) と project-scoped `.claude/skills/` (プロジェクト固有) のレイヤリングが将来導入しやすい

### Negative / Tradeoffs

- ファイル数が増える (現状 3 ファイル → Skills と Subagents 含めて 10 ファイル前後)
- Skills の `description` が下手だと自動ロードされず宝の持ち腐れになる → description を「いつ使うか」が明確になる形式で書くルールを skills 自体に含める
- 新規プロジェクトでテンプレを使う際の初期理解コストが上がる → README に4層の役割を図解する

### Out of scope (将来の ADR で扱う)

- 継続学習 (Instinct) パイプライン
- セキュリティスキャナ (AgentShield 相当)
- 言語別ルールファイルの分離 (`rules/typescript.md` 等)
- スタック別 CLAUDE.md テンプレート集

## References

- Anthropic Claude Code docs - Best practices
- ADR 0001: Template baseline for agentic development
- everything-claude-code (affaan-m/everything-claude-code) の skills-first 設計
