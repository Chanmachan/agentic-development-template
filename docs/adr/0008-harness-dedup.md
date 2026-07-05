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

一方で ADR 0006 §2 は「`profile.sh` は各ハーネスがコピーを持つ (共有しない)」と決定していた。理由は
「各ハーネスを単独で読めることを優先する」という設計方針であり (`.claude`/`.codex` 間の一般的な重複を
許容した ADR 0005 §Decision / Tradeoffs の先例を踏襲する形)、これは protected-path 判定の重複とは
別の論点である。

## Decision

(a) **`scripts/lib/protected.sh` を分類ロジックの単一の情報源にする。** `.cursor/hooks/lib/protected.sh`
    が持っていた `PROTECTED_PATTERNS` / `_normalize_path` / `_is_env_secret` / `is_secret_path` /
    `is_protected_path` を verbatim で移設した。`.claude/hooks/protect-config.sh` と
    `.codex/hooks/protect-config.sh` はこのライブラリの `is_protected_path` を呼び出すようにアップグレード
    し、正規化・case-insensitive 一致・`.env.example` 許可・相対 `.aws`/`.ssh` カバレッジを獲得した。
    副作用として、`.claude`/`.codex` の旧インライン実装が `*.example`/`*.sample`/`*.template` 拡張子を
    無条件に許可していたのに対し、`is_protected_path` は `.env.sample` / `.env.template` を先に
    `_is_env_secret` で判定する (拡張子ベースの許可より優先) ため、この2パターンは **許可 → 拒否へ意図的に
    narrow された**。`.env.example` のみを安全な canonical テンプレート名として扱う方針は `.cursor` の
    ADR 0006 §5 とすでに揃っており、本 ADR で `.claude`/`.codex` もそれに合わせた。

(b) **レスポンス整形 (deny の表現方法) はハーネスごとに残す。** `.cursor` は
    `{"permission":"deny", agent_message, user_message}` の JSON を stdout に出す
    (`.cursor/hooks/lib/protected.sh` の `deny()`)。`.claude`/`.codex` は Claude-Code 形式の
    PreToolUse JSON を stdin で受け取り、`exit 2` + stderr メッセージで拒否する。3ハーネスのフック契約が
    異なる以上、この層を無理に共通化するとハーネスごとの契約を扱う条件分岐が共有ライブラリに漏れ出す
    ため、意図的に分離を維持する。

(c) **`post-lint.sh` / `stop-check.sh` / `lib/profile.sh` はハーネスごとのコピーのまま維持する**
    (ADR 0006 §2 の「単独可読性」根拠を維持)。代わりに `tests/harness-parity.test.sh` を追加し、
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

(f) **ガードの自己防衛 (self-protection) を PROTECTED_PATTERNS に追加する。** `scripts/lib/protected.sh`
    の `PROTECTED_PATTERNS` に `lib/protected.sh` / `protect-config.sh` / `stop-check.sh` を追加した。
    3つとも部分文字列一致なので、それぞれ 3 ハーネス全てのコピー (`.claude`/`.codex`/`.cursor` の
    `protect-config.sh`・`stop-check.sh`、および `scripts/lib/protected.sh` 本体と `.cursor` の
    thin wrapper `lib/protected.sh`) を横断してカバーする。動機: このガード自身への1回の編集で write
    保護全体を無効化できてしまう "kill-switch" を、ガード自身に塞がせる。トレードオフとして、ハーネスの
    メンテナンス編集 (バグ修正など) がこれらのファイルに対して必要な場合は `HOOK_PROFILE=minimal` で
    この保護を一時的に迂回するか、ユーザー承認を経由する必要がある — これは意図された摩擦であり、
    「設定を緩めて誤りを隠す」のではなく「意図的な変更であることを人間に確認させる」ためのものである。

    **(f-1) 3-angle レビュー (ADR 0009) を受けて、周辺を hook パーミター全体へ拡張した。** (f) で保護した
    3ファイルは「ブロック可能なガード本体」に限られており、残りの hook スクリプト群 (`worktree-setup.sh` /
    `post-lint.sh` / `.cursor` の `protect-read.sh` / `protect-shell.sh` / `enforce-model.sh`)、共有の
    profile ゲーティングライブラリ (`lib/profile.sh`、3ハーネス分)、そして **どのスクリプトが実際に
    実行されるかを決める hook-WIRING ファイル自体** (`.claude/settings.json`、`.cursor/hooks.json`、
    `.codex/hooks.json`) は未保護のままだった。これらへの単独の編集も (f) と同じ persistence/neutering
    経路になる — 例えば `.claude/settings.json` から `PreToolUse` エントリを削除すれば、
    `protect-config.sh` 自体には一切触れずに write 保護全体を無効化できる。よってこれらすべてを
    `PROTECTED_PATTERNS` に追加し、ガードの防衛範囲を「ガード本体」から「hook パーミター全体」へ広げた。
    `.claude/settings.json` は意図的にバレの `"settings.json"` ではなく完全な相対パスを使う —
    バレの部分文字列だと、このテンプレートを使う下流プロジェクトが持ちうる無関係な `settings.json`
    (例: `.vscode/settings.json`) まで誤って保護対象にしてしまう。新規パターンがリポジトリ内の他の
    正当なファイルパスと衝突しないことは追加時に `find` で確認済み (該当テストは
    `tests/protect-config.test.sh` に "deny guard perimeter" / "allow ... outside .claude/" として追加)。

    **メンテナンス経路**: (f) の摩擦をそのまま踏襲する — `HOOK_PROFILE=minimal` で一時的に迂回するか、
    ライブセッション内では Bash 経由の明示的な編集 (Edit ツールの拒否を確認した上で、python3/heredoc 等で
    直接書き換える) が許容される。いずれも「設定を緩めて誤りを隠す」のではなく、「意図的な変更である
    ことを人間 (または明示的に指示されたエージェント) に確認させる」ための speed bump であり、
    セッション内 hook-integrity の担保はあくまで即時のシグナルに過ぎない。恒久的な安全網は git 履歴
    (変更が diff として必ず残る) と CI (`tests/protect-config.test.sh` / `scripts/test-cursor-hooks.sh` /
    `tests/harness-parity.test.sh`) であり、この PROTECTED_PATTERNS は「セッション内で誤って/意図せず
    ガードを壊す」ことへの一次防御に過ぎないと位置づける。

(g) **共有ライブラリのロード失敗は fail-closed にする。** `.claude`/`.codex` の `protect-config.sh` は
    `scripts/lib/protected.sh` の `source` が失敗する (ファイル欠落など) か `is_protected_path` が
    関数として定義されなかった場合、stderr にエラーを出して `exit 2` (block) する。`exit 1` は Claude
    Code では non-blocking 扱いになるため、意図的に `exit 2` を選んだ。`.cursor` の3ブロック可能ガード
    (protect-config/read/shell) は、共有の thin wrapper (`lib/protected.sh`) 内でこの失敗を検知し、
    `deny()` 自体が未定義な時点でも動作するよう deny JSON を直接組み立てて出力する。理由: 分類ロジックが
    読み込めない状態で「わからないので許可する」を選ぶと、このガード群の存在意義 (write/read/shell の
    secret 漏洩防止) が壊れる。なお bash (特に macOS 同梱の 3.2) は `source` の対象ファイルが無いとき、
    `if !`/`||` の中にあっても `set -e` 下で即座にスクリプトを終了させることがあるため、実装では
    `set +e` / `set -e` で `source` 呼び出しを挟んで戻り値を明示的に捕捉している。

## Consequences

### Positive

- protected-path のルール変更 (新しい secret パターンの追加など) は `scripts/lib/protected.sh` 1箇所の
  編集で 3 ハーネス全てに反映される。
- `.claude`/`.codex` の `protect-config.sh` が `.cursor` 相当の強度 (正規化、case-insensitive、
  `.aws`/`.ssh` カバレッジ) を獲得した。
- `tests/harness-parity.test.sh` が、意図的なコピーファイルのドリフトを CI で機械的に検出する。
  ADR 0006 §2 が容認した「コピーの重複」という trade-off に、初めて自動化された安全網が付いた。
- `.codex/rules/*.md` の symlink 化により、この2ファイルについては構造的にドリフトが発生しなくなる
  (parity テストの対象にする必要すらない)。
- ガードの自己防衛 (f) により、このガード自身への単独の編集で write 保護全体を無効化する経路が塞がれた。
- fail-closed 化 (g) により、共有ライブラリの欠落・破損時に「わからないので許可する」という
  最も危険な失敗モードが排除された。

### Negative / Tradeoffs

- `scripts/lib/protected.sh` は3ハーネスの共通依存になったため、変更時の影響範囲は広がった
  (`bash scripts/test-cursor-hooks.sh` と `bash tests/protect-config.test.sh` の両方を必ず実行する必要がある)。
- `post-lint.sh` / `stop-check.sh` / `lib/profile.sh` は引き続きコピーのままであり、
  `tests/harness-parity.test.sh` を通さない手動編集(例: 片方だけ直接 push)は依然としてドリフトしうる
  (CI 到達時点で検出されるのみで、ローカル pre-commit では検出しない)。
- symlink は Windows のネイティブ git クライアント設定 (`core.symlinks=false`) 次第でファイルとして
  展開されてしまう場合がある。本テンプレートは POSIX 系シェル (Bash 3.2 互換) を前提にしており、
  このリスクは許容する。
- ガードの自己防衛 (f) は正当なハーネスメンテナンス編集にも摩擦をかける。`protect-config.sh` /
  `stop-check.sh` / `lib/protected.sh` を直す必要があるときは `HOOK_PROFILE=minimal` で一時的に
  迂回するか、ユーザー承認を経由する必要がある。これは意図された trade-off である (§Decision (f))。
- `.env.sample` / `.env.template` の許可 → 拒否narrowing ((a) 参照) は、これらのサフィックスを
  安全なテンプレートとして使っていた既存の `.claude`/`.codex` ワークフローがあれば破壊的変更になる。
  `.env.example` への rename が回避策。

### Out of scope (将来の ADR で扱う)

- `.claude/skills/` と `.agents/skills/` の内容統合 (本 ADR (e) で明示的に見送り)
- `post-lint.sh` / `stop-check.sh` のロジック共通化 (ADR 0006 §2 の単独可読性方針を覆す場合は別 ADR)
- pre-commit 時点で harness-parity を検出する lefthook フックの追加

## References

- ADR 0002: Skills-first architecture と4層分離
- ADR 0005: Codex 互換レイヤーの追加 (§Decision / Tradeoffs — Codex 用ディレクトリ構成の追加と、
  `.claude`/`.codex` 間の一般的な重複を許容する方針。`profile.sh` 等を「ハーネスごとにコピーし単独
  可読性を優先する」という具体的判断は ADR 0006 §2 で行われた)
- ADR 0006: Cursor Composer を実装担当にする第3ハーネス (`.cursor/`) (§2 — `profile.sh` 等の
  コピー方針と単独可読性の根拠。§5 — 共有ライブラリ化・`.claude`/`.codex` へのバックポートを本 ADR に
  先送りしていた箇所。本 ADR で実施し、部分的に supersede)
- ADR 0007: エージェント非依存の CI バックストップ (shellcheck 対象に `scripts/lib/*.sh` を追加)
- ADR 0009: 2026 Claude Code 新機能の採用 (§Decision (b) — `worktree-setup.sh` / `.claude/settings.json`
  の追加により、本 ADR (f-1) で保護対象を hook パーミター全体へ拡張する動機になった)
