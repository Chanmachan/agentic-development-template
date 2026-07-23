#!/usr/bin/env bash
# set -euo pipefail は使わない（date コマンドの失敗を手動でハンドリングするため）

FAILED=0
MAX_LINES=50
DEFAULT_WARN_DAYS=14
DEFAULT_ERROR_DAYS=30

WARN_DAYS="${DOC_HEALTH_WARN_DAYS:-$DEFAULT_WARN_DAYS}"
if ! [[ "$WARN_DAYS" =~ ^[0-9]+$ ]]; then
  echo "WARN: DOC_HEALTH_WARN_DAYS='$WARN_DAYS' is not a non-negative integer. Falling back to $DEFAULT_WARN_DAYS." >&2
  WARN_DAYS="$DEFAULT_WARN_DAYS"
fi

ERROR_DAYS="${DOC_HEALTH_ERROR_DAYS:-$DEFAULT_ERROR_DAYS}"
if ! [[ "$ERROR_DAYS" =~ ^[0-9]+$ ]]; then
  echo "WARN: DOC_HEALTH_ERROR_DAYS='$ERROR_DAYS' is not a non-negative integer. Falling back to $DEFAULT_ERROR_DAYS." >&2
  ERROR_DAYS="$DEFAULT_ERROR_DAYS"
fi

TODAY=$(date +%s)

# 1. AGENTS.md / CLAUDE.md の行数チェック
for file in AGENTS.md CLAUDE.md; do
  if [ -f "$file" ]; then
    lines=$(wc -l < "$file")
    if [ "$lines" -gt "$MAX_LINES" ]; then
      echo "ERROR: $file has $lines lines. Keep it under $MAX_LINES."
      FAILED=1
    fi
  fi
done

# 2. ADR の last-validated 日付チェック
# NOTE: staleness は WARN のみで commit をブロックしない (FAILED は立てない)。
#   Last-validated を持つ ADR は一部の ADR に留まり適用が恣意的なうえ、
#   「無関係な作業中に突然 commit がブロックされる」実害が繰り返し発生していたため、
#   ここは注意喚起 (WARN) に留め、実際に更新するかは著者の判断に委ねる。
for adr in docs/adr/*.md; do
  [ -f "$adr" ] || continue
  # 0000 プレフィックスのテンプレートはスキップする（実際の意思決定ではなく雛形のため）
  case "$(basename "$adr")" in 0000-*) continue ;; esac
  validated=$(grep -i "last-validated:" "$adr" | head -1 | sed 's/.*: *//' | tr -d ' ')
  [ -z "$validated" ] && continue

  # macOS (BSD date) と Linux (GNU date) の両方に対応
  adr_ts=""
  adr_ts=$(date -j -f "%Y-%m-%d" "$validated" +%s 2>/dev/null) \
    || adr_ts=$(date -d "$validated" +%s 2>/dev/null) \
    || adr_ts="0"

  diff_days=$(( (TODAY - adr_ts) / 86400 ))
  if [ "$diff_days" -ge "$ERROR_DAYS" ]; then
    echo "WARN: $adr last-validated $diff_days days ago. Consider updating it (non-blocking)."
  elif [ "$diff_days" -ge "$WARN_DAYS" ]; then
    echo "WARN: $adr last-validated $diff_days days ago."
  fi
done

# 3. 壊れたファイルパス参照チェック
# grep -oP は macOS 非対応のため grep -oE を使用
# バッククォート内に書かれた "/" を含む文字列のうち、明らかにファイルパスでない
# パターン (slash command / brace 展開 / shell スニペット / プレースホルダ) はスキップする。
# 対象は AGENTS.md / CLAUDE.md に加え、skills/agents/commands/rules/contexts 配下。
POINTER_FILES=(AGENTS.md CLAUDE.md)
for pattern in \
  ".claude/skills/*/SKILL.md" \
  ".claude/agents/*.md" \
  ".claude/agents/reviewers/*.md" \
  ".claude/commands/*.md" \
  ".claude/rules/*.md" \
  "contexts/*.md"
do
  for f in $pattern; do
    [ -f "$f" ] && POINTER_FILES+=("$f")
  done
done

for file in "${POINTER_FILES[@]}"; do
  [ -f "$file" ] || continue
  grep -oE '`[^`]+`' "$file" | tr -d '`' | while read -r path; do
    # Skip slash commands like /clear, /compact, /fix-review (single segment after /)
    [[ "$path" =~ ^/[A-Za-z][A-Za-z0-9_-]*$ ]] && continue
    # Skip brace expansion patterns like contexts/{dev,review}.md
    [[ "$path" == *"{"* || "$path" == *"}"* ]] && continue
    # Skip glob patterns like tasks/done/*.md (pattern reference, not a literal pointer)
    [[ "$path" == *"*"* ]] && continue
    # Skip shell snippets (whitespace or command substitution inside backticks)
    [[ "$path" == *[[:space:]]* ]] && continue
    [[ "$path" == *'$('* ]] && continue
    # Skip placeholder paths like tasks/<id>-todo.md, docs/pages/<role>/
    [[ "$path" == *"<"* || "$path" == *">"* ]] && continue
    # Skip URIs (e.g. GitHub PR links in command docs)
    [[ "$path" == *"://"* ]] && continue
    # Skip line-number annotations like path/to/file.ext:42
    [[ "$path" =~ :[0-9]+$ ]] && continue
    # Skip ellipsis examples like feature/..., fix/...
    [[ "$path" == *"..."* ]] && continue
    # Skip placeholder path prefixes used in agent/review templates
    [[ "$path" =~ ^path/to/ ]] && continue
    # Skip branch-name examples without a file extension (git.md, plan-mode)
    [[ "$path" =~ ^(feature|fix|update|refactor|chore|docs)/ ]] && [[ "$path" != *.* ]] && continue
    # Skip .git/ — in worktrees .git is a file, so .git/ does not exist
    [[ "$path" == .git/ || "$path" == */.git/ ]] && continue
    # Skip directory references with trailing slash (e.g. __tests__/)
    [[ "$path" == */ ]] && continue

    if [[ "$path" == */* ]] && [ ! -e "$path" ]; then
      echo "WARN: Broken pointer in $file: $path"
    fi
  done
done

exit $FAILED