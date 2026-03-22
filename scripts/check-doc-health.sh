#!/usr/bin/env bash
set -euo pipefail

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
  adr_ts=$(date -d "$validated" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$validated" +%s 2>/dev/null || echo 0)
  diff_days=$(( (TODAY - adr_ts) / 86400 ))
  if [ "$diff_days" -ge "$ERROR_DAYS" ]; then
    echo "ERROR: $adr last-validated $diff_days days ago."
    FAILED=1
  elif [ "$diff_days" -ge "$WARN_DAYS" ]; then
    echo "WARN: $adr last-validated $diff_days days ago."
  fi
done

# 3. AGENTS.md / CLAUDE.md 内の壊れたファイルパス参照チェック
for file in AGENTS.md CLAUDE.md; do
  [ -f "$file" ] || continue
  grep -oP '`[^`]+`' "$file" | tr -d '`' | while read -r path; do
    if [[ "$path" == */* ]] && [ ! -e "$path" ]; then
      echo "WARN: Broken pointer in $file: $path"
    fi
  done
done

exit $FAILED