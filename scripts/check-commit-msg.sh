#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "usage: check-commit-msg.sh <commit-msg-file>" >&2
  exit 2
fi

msg_file=$1
first_line=$(head -n 1 "$msg_file")

if printf '%s\n' "$first_line" | grep -qE '^(Merge|Revert) '; then
  exit 0
fi

if ! printf '%s\n' "$first_line" | grep -qE '^(feat|fix|update|refactor|style|docs|test|chore|del|perf|ci): .+$'; then
  echo "Commit message must follow .claude/rules/git.md format"
  echo "  Format: prefix: short description (single line, no body/footer)"
  echo "  Allowed prefixes: feat, fix, update, refactor, style, docs, test, chore, del, perf, ci"
  echo "  Merge and Revert commits are also allowed."
  exit 1
fi

comment_char=$(git config core.commentChar 2>/dev/null || true)
if [ -z "$comment_char" ] || [ "$comment_char" = "auto" ]; then
  comment_char="#"
fi
comment_char=${comment_char:0:1}

while IFS= read -r line || [ -n "$line" ]; do
  if [ "${line:0:1}" = "$comment_char" ]; then
    case $line in
      *'>8'*) break ;;
    esac
    continue
  fi
  case $line in
    *[![:space:]]*) ;;
    *) continue ;;
  esac
  if printf '%s\n' "$line" | grep -qiE '^(co-authored-by|claude-session):|claude\.ai/code/session_'; then
    echo "Commit message must not contain agent trailers (Co-Authored-By / Claude-Session / session URL) per .claude/rules/git.md"
    echo "  Offending line: $line"
    exit 1
  fi
  echo "Commit message must be a single line (no body or footer) per .claude/rules/git.md"
  echo "  Found additional non-blank content after the first line."
  exit 1
done < <(tail -n +2 "$msg_file")
