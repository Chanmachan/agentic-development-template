# Claude Code 2026 ベスプラ 輸入候補サーベイ

> 作成日: 2026-06-02 / Status: Draft (調査メモ)

## 問い

最近 (〜2026 Q2) 公開された Claude Code ベスプラ記事と公式ドキュメントを横断し、本テンプレートリポに**まだ取り込めていない**実用パターンを洗い出す。各候補について「採用 / 見送り / 要検討」を一次判定し、採用に値するものは後日 ADR / 実装タスクへ昇格させる。

## 現状の棚卸し (= 重複輸入を避けるための前提)

このテンプレが既にカバーしている領域:

- **指示の階層化**: `CLAUDE.md` (短く・普遍) + `AGENTS.md` (リポルール) + `contexts/*.md` (セッション目的別の差分) + `.claude/skills/` (手順詳細) + `.claude/rules/git.md` (リファレンス)
- **subagent**: `planner` / `investigator` / `code-reviewer` / `reviewers/*` (6 視点)
- **skills**: `tdd` / `code-review` / `plan-mode`
- **hooks**: `post-lint` / `stop-check` / `protect-config` / `suggest-compact` + `HOOK_PROFILE` で強度切り替え (ADR 0003)
- **commands**: `/multi-review` (ADR 0004) / `/fix-review` / `/handoff`
- **文書ガバナンス**: `docs/spec.md` 必読、`docs/adr/` で意思決定の足跡、`research/` で棄却履歴

## 候補一覧 (公式 docs + 主要ブログを横断して抽出)

各候補に **重要度 (High / Med / Low)** と **判定 (採用 / 要検討 / 見送り)** を付与。

### A. Spec Interview パターン (`AskUserQuestion` で仕様を聞き出して `SPEC.md` に書き出す)
- **重要度**: High
- **判定**: **採用候補 (ADR 化推奨)**
- **概要**: 公式ベスプラの "Let Claude interview you" — 最小プロンプトから `AskUserQuestion` で技術 / UX / エッジケース / トレードオフを掘り、合意できたら `docs/spec.md` を書く。完了後は別セッションで実装に入る (Specification 汚染を避ける)。
- **本リポとの相性**: 本リポは「コード前に `docs/spec.md`」を中核思想にしている。**現状はその spec を書くフェーズの手順が無い** (CLAUDE.md は "読め" としか言っていない)。Interview パターンは欠けたピースを埋める。
- **取り込み形態案**: `.claude/skills/spec-interview/SKILL.md` (新規)。または `contexts/research.md` から呼ばれる手順として埋め込む。
- **コスト**: Skill 一個 (〜50 行)。

### B. 4 フェーズ Workflow (Explore → Plan → Implement → Commit) の明示
- **重要度**: Med
- **判定**: **要検討 (既存 `plan-mode` と統合)**
- **概要**: 公式が強く推す 4 フェーズ。Plan Mode で読み込み → 計画 → 実装に切り替え → コミット。
- **本リポとの相性**: `plan-mode` skill と `contexts/dev.md` の Workflow セクションでカバー済み。ただし **Explore (Plan Mode で読みだけする)** フェーズは明示されていない。
- **取り込み形態案**: `plan-mode/SKILL.md` の冒頭に "Phase 0: Explore (read-only)" を追記。または `contexts/dev.md` の Workflow に 0 番ステップを足す。
- **コスト**: ファイル数行追記。

### C. 検証 (Verification) 重視の言語化
- **重要度**: High
- **判定**: **採用 (低コスト)**
- **概要**: 公式の最重要メッセージ: "Claude に走らせて読めるチェックを与えよ" (テスト・ビルド終了コード・スクリーンショット差分)。プロンプトに合格条件を含めるテーブル化された例が示されている。
- **本リポとの相性**: `stop-check.sh` で **強制的に** 通すところはやっている。ただし **プロンプトに検証条件を埋め込む** という上流の作法は明文化していない。
- **取り込み形態案**: `contexts/dev.md` の "Verify before stopping" を拡張して「プロンプト時点で合格条件を書く」を追記。`docs/spec.md` テンプレに "Acceptance criteria" 節を入れる案も。
- **コスト**: 数行追記。

### D. CLAUDE.local.md (個人スコープのプロジェクトメモ)
- **重要度**: Low-Med
- **判定**: **採用 (低コスト・無害)**
- **概要**: 公式が紹介する "team-shared `CLAUDE.md`" と "personal `CLAUDE.local.md`" の分離。後者は `.gitignore` 行き。
- **本リポとの相性**: 本リポは team 共有版だけある。個人メモを書ける場所が無いので、各自が `CLAUDE.md` に手を入れたくなる誘惑が残る。
- **取り込み形態案**: `.gitignore` に `CLAUDE.local.md` を 1 行追加 + README の "Files to edit" に短く言及。
- **コスト**: 2 行。

### E. Auto Mode / Sandbox / Allowlist の運用ドキュメント
- **重要度**: Med
- **判定**: **要検討 (README に節を足す程度)**
- **概要**: 承認疲れを避けるため、`claude --permission-mode auto` (分類器が危険操作だけブロック) と `/sandbox` (OS レベル隔離) と `permissions` allowlist の使い分け。
- **本リポとの相性**: `.claude/settings.json` で permissions は管理されているが、Auto mode / Sandbox の使い分けガイドは無い。`HOOK_PROFILE` と直交する軸なので、README に並列に書ける。
- **取り込み形態案**: README "Permission strategy" 節を追加 (Hook Profiles の隣)。
- **コスト**: README 20〜30 行。

### F. "2 回失敗したら `/clear`" の明示ルール
- **重要度**: Med
- **判定**: **採用 (contexts への追記で済む)**
- **概要**: 公式 anti-patterns で繰り返し言及: 同じ修正を 2 回しても直らないときは context が汚染されているサイン、`/clear` して prompt を書き直す。
- **本リポとの相性**: `contexts/debug.md` あたりに馴染む。現状 anti-patterns 節はあるが、この閾値ルールは入っていない。
- **取り込み形態案**: `contexts/dev.md` と `contexts/debug.md` の Anti-patterns 節に 1 行追加。
- **コスト**: 各 1 行。

### G. Fan-out スクリプト (`claude -p` 並列実行) のテンプレ
- **重要度**: Low-Med
- **判定**: **見送り → idea/ に置く**
- **概要**: 大規模 migration で `for file in $(...); do claude -p "..."; done`。`--allowedTools` で絞る。
- **本リポとの相性**: テンプレリポ自体が migration を抱えるわけではないので、雛形をリポに置く意味は薄い。Idea / 個人 dotfiles 行き。
- **取り込み形態案**: 必要時に `scripts/fan-out.sh.example` を追加してドキュメントから参照、程度。
- **コスト**: なし (見送り)。

### H. Statusline の HOOK_PROFILE / context% 表示
- **重要度**: Low-Med
- **判定**: **要検討**
- **概要**: 公式が推す custom statusline で「使ったトークン量を常時可視化」。`HOOK_PROFILE` の現在値も同様に出せる。
- **本リポとの相性**: 本テンプレは `HOOK_PROFILE` をセッションごとに切り替える前提だが、**現在値が見えない**。間違ったプロファイルで作業する事故が起きうる。
- **取り込み形態案**: `.claude/statusline.sh` を追加し、README に "オプトインで有効化" として書く。
- **コスト**: シェルスクリプト 1 本 (20 行程度)。

### I. MCP セットアップガイド (`gh` CLI 等の推奨)
- **重要度**: Med
- **判定**: **採用 (README の Prerequisites に小節を足す)**
- **概要**: `gh` を入れるだけで GitHub 操作が context 効率化、`claude mcp add` で外部システム接続。
- **本リポとの相性**: `gh` 前提のコマンド (`/fix-review` 等) が既にあるが、README の Prerequisites には書いていない。
- **取り込み形態案**: Prerequisites 表に `gh` を追加。MCP は「必要に応じて」と短く言及。
- **コスト**: README 数行。

### J. Adversarial Review (軽量版) — 単発の verification subagent
- **重要度**: Low
- **判定**: **見送り (既存 `/multi-review` と重複)**
- **概要**: 公式の bundled `/code-review` skill のような「diff だけ別 context で見直す」軽量ループ。
- **本リポとの相性**: 既に `code-reviewer` subagent と `code-review` skill と `/multi-review` の三段構えがある。これ以上増やすと選択肢過多になる。
- **取り込み形態案**: なし。
- **コスト**: なし (見送り)。

### K. Plugins の存在を README に言及
- **重要度**: Low
- **判定**: **要検討**
- **概要**: `/plugin` で community plugin をインストール。typed language の code-intelligence plugin は強力。
- **本リポとの相性**: テンプレが言語非依存なので、「言語を決めたら code-intelligence plugin の導入を検討」を README に 1 行入れる程度なら無害。
- **取り込み形態案**: README "Per language" 節に追記。
- **コスト**: 1 行。

### L. Compaction のカスタム指示 (`/compact <instructions>`)
- **重要度**: Low
- **判定**: **見送り (CLAUDE.md の `/clear` 推奨方針と衝突)**
- **概要**: `/compact` 時に "API 変更を残せ" 等の指示を渡せる、CLAUDE.md にも書ける。
- **本リポとの相性**: CLAUDE.md が `/compact` より `/clear` を推奨している (要約より破棄)。ここで compaction 指示を増やすと方針が割れる。
- **取り込み形態案**: なし (現行方針を維持)。
- **コスト**: なし (見送り)。

## 判断基準と優先度マトリクス

| 候補 | 重要度 | 実装コスト | 既存資産との整合 | 判定 |
|------|--------|-----------|------------------|------|
| A: Spec Interview skill | High | 中 (Skill 1 本) | 高 (`docs/spec.md` 中核思想と整合) | **採用候補 → ADR** |
| C: Verification 言語化 | High | 低 | 高 | **採用** |
| D: CLAUDE.local.md | Med | 極低 | 高 | **採用** |
| I: `gh` を Prereq に | Med | 極低 | 高 (`/fix-review` が前提に) | **採用** |
| B: Explore フェーズ明示 | Med | 低 | 中 (plan-mode と統合要) | **要検討** |
| E: Auto Mode 運用 doc | Med | 中 (README 節) | 中 (HOOK_PROFILE と直交) | **要検討** |
| F: 2 回失敗で `/clear` | Med | 極低 | 高 | **採用** |
| H: Statusline 可視化 | Low-Med | 低 | 中 (HOOK_PROFILE 事故防止) | **要検討** |
| K: Plugins 言及 | Low | 極低 | 中 | **要検討** |
| G: Fan-out テンプレ | Low-Med | 低 | 低 (リポの目的と乖離) | **見送り** |
| J: 軽量 Adversarial review | Low | 中 | 低 (重複) | **見送り** |
| L: Compaction 指示 | Low | 低 | 低 (方針衝突) | **見送り** |

## 推奨と理由

**まず最優先で着手すべきは A (Spec Interview skill)**。
本テンプレは「コード前に `docs/spec.md`」を中核思想として据えているのに、その spec を**書くため**の手順が存在しない。ユーザは結局自力で書くか、あるいは spec なしで実装に入ってしまう。公式 docs が紹介する `AskUserQuestion` ベースの interview は、テンプレの思想と完全に噛み合う。これは ADR 0005 として「spec の書き方 / spec interview skill の導入」を起票する価値がある。

**次の波で C / D / F / I を一括で取り込む**。いずれも README / contexts / .gitignore への追記レベルで、相互独立。1 PR にまとめて入れられる。

**B / E / H / K は ADR にする前に試運用が必要**。とくに E (Auto Mode) は実際にいくつかのセッションで運用してみないと、`HOOK_PROFILE` との掛け合わせがどう効くか判断しづらい。

**G / J / L は明確に見送り**。テンプレの目的やすでにある資産と衝突する。

## Open questions

- A の Spec Interview skill は **どの語彙** で書くか? (`AskUserQuestion` は Claude Code 固有 → Codex でも動くか要確認)
- H の statusline 可視化は **どの粒度** が適切か? (`HOOK_PROFILE` だけ? それともコンテキスト % まで?)
- E の Auto Mode と `stop-check.sh` (Stop hook) の挙動干渉は未検証 (non-interactive モードで 8 回ブロックで強制終了する仕様がある)。
- 公式が推す `/goal` 条件は本テンプレで `stop-check.sh` と機能的に重複する可能性がある — どちらをどう使い分けるかは別調査。

## 一次資料

- [Best practices for Claude Code (公式)](https://code.claude.com/docs/en/best-practices)
- [Designing CLAUDE.md correctly: The 2026 architecture (obviousworks)](https://www.obviousworks.ch/en/designing-claude-md-right-the-2026-architecture-that-finally-makes-claude-code-work/)
- [Claude Code Advanced Best Practices: 11 Techniques (smartscope)](https://smartscope.blog/en/generative-ai/claude/claude-code-best-practices-advanced-2026/)
- [My Claude Code Setup (okhlopkov)](https://okhlopkov.com/claude-code-setup-mcp-hooks-skills-2026/)
- [Writing a good CLAUDE.md (HumanLayer)](https://www.humanlayer.dev/blog/writing-a-good-claude-md)
