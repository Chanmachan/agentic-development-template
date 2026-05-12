#!/usr/bin/env bash
# set -euo pipefail は使わない（date コマンドの失敗を手動でハンドリングするため）

FAILED=0
MAX_LINES=50
WARN_DAYS=3
ERROR_DAYS=5
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
for adr in docs/adr/*.md; do
  [ -f "$adr" ] || continue
  validated=$(grep -i "last-validated:" "$adr" | head -1 | sed 's/.*: *//' | tr -d ' ')
  [ -z "$validated" ] && continue

  # macOS (BSD date) と Linux (GNU date) の両方に対応
  adr_ts=""
  adr_ts=$(date -j -f "%Y-%m-%d" "$validated" +%s 2>/dev/null) \
    || adr_ts=$(date -d "$validated" +%s 2>/dev/null) \
    || adr_ts="0"

  diff_days=$(( (TODAY - adr_ts) / 86400 ))
  if [ "$diff_days" -ge "$ERROR_DAYS" ]; then
    echo "ERROR: $adr last-validated $diff_days days ago. Update or remove it."
    FAILED=1
  elif [ "$diff_days" -ge "$WARN_DAYS" ]; then
    echo "WARN: $adr last-validated $diff_days days ago."
  fi
done

# 3. AGENTS.md / CLAUDE.md 内の壊れたファイルパス参照チェック
# grep -oP は macOS 非対応のため grep -oE を使用
# バッククォート内に書かれた "/" を含む文字列のうち、明らかにファイルパスでない
# パターン (slash command / brace 展開 / shell スニペット) はスキップする。
for file in AGENTS.md CLAUDE.md; do
  [ -f "$file" ] || continue
  grep -oE '`[^`]+`' "$file" | tr -d '`' | while read -r path; do
    # Skip slash commands like /clear, /compact, /fix-review (single segment after /)
    [[ "$path" =~ ^/[A-Za-z][A-Za-z0-9_-]*$ ]] && continue
    # Skip brace expansion patterns like contexts/{dev,review}.md
    [[ "$path" == *"{"* || "$path" == *"}"* ]] && continue
    # Skip shell snippets (whitespace or command substitution inside backticks)
    [[ "$path" == *[[:space:]]* ]] && continue
    [[ "$path" == *'$('* ]] && continue

    if [[ "$path" == */* ]] && [ ! -e "$path" ]; then
      echo "WARN: Broken pointer in $file: $path"
    fi
  done
done

exit $FAILED