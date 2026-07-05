# ADR 0008: 3ハーネス間の protected-path 判定を共有ライブラリへ集約

- Status: Accepted
- Date: 2026-07-06
- Last-validated: 2026-07-06

## Context

ADR 0006 の時点で、`.env*`/`tsconfig.json`/lockfile などを保護する PROTECTED_PATTERNS 配列とパス分類ロジック
(`_normalize_path` / `_is_env_secret` / `is_secret_path` / `is_protected_path`) は 3 箇所に存在していた。

- `.cursor/hooks/lib/protected.sh` — 正規化・case-insensitive 一致・`.env.example` 許可リスト・
  相対 `.aws`/`.ssh` パスのカバレッジを含む、最も強化された実装。`.cursor` 内では protect-config /
  protect-read / protect-shell / enforce-model の複数コンシューマが共有していた。
- `.claude/hooks/protect-config.sh` / `.codex/hooks/protect-config.sh` — インライン実装。
  `*.example`/`.env`/PROTECTED_PATTERNS の3段階チェックのみで、`.cursor` 版が持つ正規化や
  case-insensitive 一致、`.aws`/`.ssh` カバレッジを欠いていた。

ADR 0006 §2 と §5 は、この不一致を認識した上で「共有ライブラリ化・`.claude`/`.codex` へのバックポートは
別 PR」と明記して意図的に先送りしていた。本 ADR はその別 PR にあたる。

一方で ADR 0005 §Decision は「`profile.sh` は各ハーネスがコピーを持つ (共有しない)」という判断を、
ADR 0006 §2 が踏襲していた。理由は「各ハーネスを単独で読めることを優先する」という設計方針であり、
これは protected-path 判定の重複とは別の論点である。

## Decision

(a) **`scripts/lib/protected.sh` を分類ロジックの単一の情報源にする。** `.cursor/hooks/lib/protected.sh`
    が持っていた `PROTECTED_PATTERNS` / `_normalize_path` / `_is_env_secret` / `is_secret_path` /
    `is_protected_path` を verbatim で移設した。`.claude/hooks/protect-config.sh` と
    `.codex/hooks/protect-config.sh` はこのライブラリの `is_protected_path` を呼び出すようにアップグレード
    し、正規化・case-insensitive 一致・`.env.example` 許可・相対 `.aws`/`.ssh` カバレッジを獲得した。

(b) **レスポンス整形 (deny の表現方法) はハーネスごとに残す。** `.cursor` は
    `{"permission":"deny", agent_message, user_message}` の JSON を stdout に出す
    (`.cursor/hooks/lib/protected.sh` の `deny()`)。`.claude`/`.codex` は Claude-Code 形式の
    PreToolUse JSON を stdin で受け取り、`exit 2` + stderr メッセージで拒否する。3ハーネスのフック契約が
    異なる以上、この層を無理に共通化するとハーネスごとの契約を扱う条件分岐が共有ライブラリに漏れ出す
    ため、意図的に分離を維持する。

(c) **`post-lint.sh` / `stop-check.sh` / `lib/profile.sh` はハーネスごとのコピーのまま維持する**
    (ADR 0005 §2 の「単独可読性」根拠を維持)。代わりに `tests/harness-parity.test.sh` を追加し、
    意図的に同一であるべきファイルペア (`{.claude,.codex}/hooks/{post-lint.sh,stop-check.sh,
    protect-config.sh,lib/profile.sh}`) が byte-identical であることを CI で強制する。これにより
    「コピーを許容しつつドリフトを機械的に検出する」という、共有ライブラリ化とは別の緩和策を得る。

(d) **`.codex/rules/git.md` / `.codex/rules/tasks.md` を `.claude/rules/` への相対 symlink に置き換える。**
    ADR 0005 の時点でこれらは byte-identical なコピーだった。ルール文書はハーネスごとの契約差分を
    持たない (protected-path 判定のような "ロジック" ではなく "読み物" であり、共有しても単独可読性を
    損なわない) ため、symlink 化してドリフトそのものを構造的に防止する。git はシンボリックリンクを
    そのまま追跡するため、`.codex/` チェックアウトでも `cat .codex/rules/git.md` は解決できる。

(e) **明示的に見送るもの: skills の symlink 化。** `.claude/skills/` と `.agents/skills/` は
    ツールごとの言い回し・スロット (`AskUserQuestion` の有無など) を意図的に持つ。共有すべき標準は
    ファイルそのものではなく `SKILL.md` というフォーマットであり、内容を symlink で強制一致させることは
    「各ツールに最適化された言い回し」という価値を壊す。したがって skills 層の統合は本 ADR のスコープ外
    とし、今後も別 ADR なしに着手しない。

## Consequences

### Positive

- protected-path のルール変更 (新しい secret パターンの追加など) は `scripts/lib/protected.sh` 1箇所の
  編集で 3 ハーネス全てに反映される。
- `.claude`/`.codex` の `protect-config.sh` が `.cursor` 相当の強度 (正規化、case-insensitive、
  `.aws`/`.ssh` カバレッジ) を獲得した。
- `tests/harness-parity.test.sh` が、意図的なコピーファイルのドリフトを CI で機械的に検出する。
  ADR 0005 §2 が容認した「コピーの重複」という trade-off に、初めて自動化された安全網が付いた。
- `.codex/rules/*.md` の symlink 化により、この2ファイルについては構造的にドリフトが発生しなくなる
  (parity テストの対象にする必要すらない)。

### Negative / Tradeoffs

- `scripts/lib/protected.sh` は3ハーネスの共通依存になったため、変更時の影響範囲は広がった
  (`bash scripts/test-cursor-hooks.sh` と `bash tests/protect-config.test.sh` の両方を必ず実行する必要がある)。
- `post-lint.sh` / `stop-check.sh` / `lib/profile.sh` は引き続きコピーのままであり、
  `tests/harness-parity.test.sh` を通さない手動編集(例: 片方だけ直接 push)は依然としてドリフトしうる
  (CI 到達時点で検出されるのみで、ローカル pre-commit では検出しない)。
- symlink は Windows のネイティブ git クライアント設定 (`core.symlinks=false`) 次第でファイルとして
  展開されてしまう場合がある。本テンプレートは POSIX 系シェル (Bash 3.2 互換) を前提にしており、
  このリスクは許容する。

### Out of scope (将来の ADR で扱う)

- `.claude/skills/` と `.agents/skills/` の内容統合 (本 ADR (e) で明示的に見送り)
- `post-lint.sh` / `stop-check.sh` のロジック共通化 (ADR 0005 §2 の単独可読性方針を覆す場合は別 ADR)
- pre-commit 時点で harness-parity を検出する lefthook フックの追加

## References

- ADR 0002: Skills-first architecture と4層分離
- ADR 0005: Codex 互換レイヤーの追加 (§Decision — `profile.sh` 等をハーネスごとにコピーする方針。一部
  本 ADR (c) で維持、(d) で symlink化により部分的に上書き)
- ADR 0006: Cursor Composer を実装担当にする第3ハーネス (`.cursor/`) (§2, §5 — 共有ライブラリ化・
  `.claude`/`.codex` へのバックポートを本 ADR に先送りしていた箇所。本 ADR で実施し、部分的に supersede)
- ADR 0007: エージェント非依存の CI バックストップ (shellcheck 対象に `scripts/lib/*.sh` を追加)
