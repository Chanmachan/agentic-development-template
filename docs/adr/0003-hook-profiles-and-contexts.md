# ADR 0003: Hook profiles, contexts ディレクトリ, bash/Node.js ハイブリッド

- Status: Accepted
- Date: 2026-05-11
- Last-validated: 2026-05-11

## Context

ADR 0002 で 4層分離 (Rules / Skills / Subagents / Hooks) を採用したが、Hooks 層と運用面で以下の課題が残っている。

1. **フックの強度がオール・オア・ナッシング**。現状は `protect-config.sh` / `post-lint.sh` / `stop-check.sh` がすべて常時オンで、開発フェーズ (試作・本実装・本番直前) ごとの強度調整ができない。試作中に `stop-check.sh` がテスト未整備で常にブロックすると体験が悪く、フックを丸ごと disable する誘惑が生まれる。
2. **セッションの目的別にシステムプロンプトを切り替える手段がない**。新機能実装、コードレビュー、調査、デバッグでは Claude に与えたい指示が異なるが、現状は `CLAUDE.md` 1本ですべてを賄っている。
3. **フックの実装言語が bash 一択で、jq への依存が強い**。短いフックは bash で十分だが、コンテキスト使用率の計算や JSONL の追記など複雑なロジックを書く際に bash + jq だと保守性が落ちる。一方で、すべてを Node.js に移行する (ECC のような) のはオーバーキル。
4. **将来追加したいフック (`suggest-compact` 等) は bash で書きにくい**。コンテキスト使用率を Claude Code の入力から取得し閾値判定する処理は、Node.js のほうが自然に書ける。

ECC では `ECC_HOOK_PROFILE=minimal|standard|strict` 環境変数で フック群を3段階制御している。また `contexts/dev.md` などをセッション開始時に `--system-prompt` で注入する運用が紹介されている。

## Decision

### 1. フックプロファイルの導入

環境変数 `HOOK_PROFILE` (デフォルト `standard`) で3段階制御する。

| Profile | 含まれるフック | 想定用途 |
|---------|----------------|----------|
| `minimal` | post-lint のみ | プロトタイピング、デモ、外部リポジトリ |
| `standard` (default) | minimal + protect-config + stop-check | 通常開発 |
| `strict` | standard + suggest-compact + commit-quality | 本番直前、リリース前ブランチ |

各フック内で先頭に下記を入れ、自分が現在の profile に含まれるか判定する:

```bash
PROFILE="${HOOK_PROFILE:-standard}"
case "$PROFILE" in
  minimal) [[ "$HOOK_NAME" == "post-lint" ]] || exit 0 ;;
  standard) [[ "$HOOK_NAME" =~ ^(post-lint|protect-config|stop-check)$ ]] || exit 0 ;;
  strict) ;; # 全フック実行
esac
```

将来 `.claude/hooks/lib/profile.sh` (bash 用) と `.claude/hooks/lib/profile.mjs` (Node.js 用) として共通ライブラリ化する。

**未知の profile への扱い**: タイポや非対応値 (`HOOK_PROFILE=bogus` など) は WARN を stderr に出した上で `standard` 相当として動作させる (fail-soft)。理由は (a) テンプレートが利用者に対して厳しすぎないこと、(b) 値の typo で開発が止まる事故を避けること。ECC など本番運用前提のシステムでは reject する選択肢もあるが、本リポジトリはテンプレートのため fail-soft を採用する。

### 2. contexts/ ディレクトリの新設

リポジトリルートに `contexts/` を作り、セッション目的別のシステムプロンプトを置く。

- `contexts/dev.md` — 新機能実装・バグ修正向け (Plan → TDD → Verify を強調)
- `contexts/review.md` — コードレビュー向け (読み取り専用の姿勢、観点リスト)
- `contexts/research.md` — 調査・技術選定向け (research/ に書き出し、ADR に昇格させる流れ)
- `contexts/debug.md` — デバッグ向け (仮説 → 検証 → 修正の繰り返し、最小再現の重視)

起動時に `claude --append-system-prompt "$(cat contexts/dev.md)"` のように使う。README にエイリアス例を載せる。

`CLAUDE.md` は引き続き全セッション共通の最小知識を担い、contexts/ はセッション目的特化の差分を担う。

### 3. フック実装言語のハイブリッド方針

- **短い・I/O 単純なフック** → bash (例: `protect-config.sh`, `post-lint.sh`, `stop-check.sh`)
- **複雑なロジックを持つフック** → Node.js (例: `suggest-compact.mjs`, 将来の `observe.mjs`)

判断基準:

- bash で 50 行を超える、または jq が 3 箇所以上必要になったら Node.js を検討
- Node.js 側は外部依存を持たない (Node 標準のみ) ことを原則とする
- どちらも `set -euo pipefail` 相当のエラーハンドリングを必ず入れる

### 4. suggest-compact フックの追加 (strict のみ)

Node.js 実装で、ツール使用イベントの累積トークン数を概算し、閾値 (デフォルト 70% = 約 140k tokens) を超えたら additionalContext で `/clear` か Subagent 切り出しを推奨するメッセージを返す。

実装ファイル: `.claude/hooks/suggest-compact.mjs`

入力は `stdin` から JSON で受け取り、`hookSpecificOutput.additionalContext` を返す Claude Code の標準スキーマに従う。

### 5. settings.json の更新

`.claude/settings.json` に suggest-compact を `PreToolUse` (全マッチャー) として追加する。ただしフック自体が `HOOK_PROFILE` で自己無効化するため、settings.json は profile を意識しなくてよい。

## Consequences

### Positive

- フックを丸ごと無効化せず、プロジェクトフェーズに応じて強度調整できる
- セッション目的別の contexts/ により、CLAUDE.md を肥大化させずに状況特化の指示を出せる
- フック言語のハイブリッド化で、短いものは bash の簡潔さを保ち、複雑なものは Node.js の保守性を得られる
- ECC のような完全 Node.js 移行のコストを払わずに、必要な部分だけ近代化できる

### Negative / Tradeoffs

- HOOK_PROFILE の存在を開発者が知っていないと「なぜフックが動かない / 動きすぎる」となる → README とエラーメッセージで明示
- bash と Node.js が混在すると、フック共通ロジック (例: 入力 JSON のパース) を 2 言語でメンテすることになる → 共通ライブラリは最小化し、各フックで直接書く方針にする
- contexts/ は手動で `--append-system-prompt` する運用なので、忘れがち → README にシェルエイリアスのサンプルを載せる

### Out of scope (将来の ADR で扱う)

- 全フックの Node.js 完全移行 (現状はハイブリッド維持)
- contexts の自動切り替え (git ブランチ名やコマンドエイリアスから推測する仕組み)
- フック実行のテレメトリ (どのフックが何回ブロックしたかの計測)

## References

- ADR 0002: Skills-first architecture と4層分離
- everything-claude-code の hook profile / contexts 設計
- Anthropic Claude Code docs - hooks reference
