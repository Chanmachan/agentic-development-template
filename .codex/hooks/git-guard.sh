#!/usr/bin/env bash
# PreToolUse(Bash) guard: block a small set of git footguns that AGENTS.md
# already forbids in prose (AUD-9-08) but had no machine enforcement for:
#   (a) `git commit --no-verify` / `git commit -n` (skips lefthook)
#   (b) direct `git commit` while on `main` (unless ALLOW_MAIN_COMMIT=1,
#       either in the hook's env or as an env-assignment prefix on the command)
#   (c) `git push --force`/`-f` that targets `main` (word match) or is issued
#       while `main` is checked out
#
# Detection is segment-based: the command string is split on newlines and
# `;`/`&`/`|`, and rules only apply to segments whose command position is
# `git ...` (optionally after VAR=val prefixes). Quoted substrings are stripped
# before flag detection so a commit message containing " -n " or a mention of
# `git commit -n` inside e.g. `echo '...'` does not false-positive. This is
# not a full shell parser — it is deliberately conservative-but-simple.
#
# Segments whose command position is `cd` move the directory the branch is read
# from, so `cd <worktree> && git commit ...` is judged against the branch that
# will actually receive the commit rather than the hook's own cwd.
#
# Also blocks `gh pr …` bodies that carry a PR_BODY_FORBIDDEN pattern
# (see .claude/rules/git.md); scans the raw command string and body-file paths.
#
# Fails open (exit 0) on anything unexpected — missing jq, unparseable JSON,
# no git repo, etc. — so a hook bug never blocks unrelated development.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/profile.sh"
hook_profile_skip git-guard

input="$(cat)"

command_str="$(jq -r '.tool_input.command // empty' <<< "$input" 2>/dev/null)" || exit 0
[ -z "$command_str" ] && exit 0
command_str="${command_str//"\\"$'\n'/ }"

segments="$(printf '%s\n' "$command_str" | tr ';&|' '\n')"

PR_BODY_FORBIDDEN=(
  'Generated with [Claude Code]'
  'Generated with Claude Code'
  'Generated with Cursor'
  'claude.ai/code/session_'
)
gh_pr_trigger=0
gh_pr_dir="."
gh_pr_block_msg="BLOCKED by git-guard: PR body contains an agent tool signature / session URL (.claude/rules/git.md). Remove the footer; if you only need to mention it, paraphrase."

pr_body_has_signature() {
  local pat
  for pat in "${PR_BODY_FORBIDDEN[@]}"; do
    printf '%s' "$1" | grep -Fiq -- "$pat" && return 0
  done
  return 1
}

gh_command_position_norm() {
  local s="$1"
  while :; do
    s="$(printf '%s' "$s" | sed -E 's/^[[:space:]]+//; s/^([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*//')"
    case "$s" in
      env\ *)
        s="${s#env}"
        s="${s#"${s%%[![:space:]]*}"}"
        ;;
      command\ *)
        s="${s#command}"
        s="${s#"${s%%[![:space:]]*}"}"
        ;;
      exec\ *)
        s="${s#exec}"
        s="${s#"${s%%[![:space:]]*}"}"
        ;;
      nohup\ *)
        s="${s#nohup}"
        s="${s#"${s%%[![:space:]]*}"}"
        ;;
      time\ *)
        s="${s#time}"
        s="${s#"${s%%[![:space:]]*}"}"
        ;;
      !\ *)
        s="${s#!}"
        s="${s#"${s%%[![:space:]]*}"}"
        ;;
      \(* )
        s="${s#(}"
        s="${s#"${s%%[![:space:]]*}"}"
        ;;
      {* )
        s="${s#\{}"
        s="${s#"${s%%[![:space:]]*}"}"
        ;;
      /*)
        first="${s%% *}"
        rest=""
        if [ "$first" != "$s" ]; then
          rest="${s#"$first"}"
          rest="${rest#"${rest%%[![:space:]]*}"}"
        fi
        if [ "${first##*/}" = "gh" ]; then
          if [ -n "$rest" ]; then
            s="gh $rest"
          else
            s="gh"
          fi
        elif [[ "${first##*/}" =~ ^(env|command|exec|nohup|time)$ && -n "$rest" ]]; then
          s="${first##*/} $rest"
        else
          break
        fi
        ;;
      *)
        break
        ;;
    esac
  done
  printf '%s' "$s"
}

segment_triggers_gh_pr_body_check() {
  local seg="$1"
  local gh_s
  gh_s="$(gh_command_position_norm "$seg")"
  case "$gh_s" in
    gh|gh\ *) ;;
    *) return 1 ;;
  esac
  local -a t
  local i=1
  read -ra t <<< "$gh_s"
  while :; do
    case "${t[i]:-}" in
      -R|--repo) i=$((i + 2)) ;;
      -R?*|--repo=*) i=$((i + 1)) ;;
      *) break ;;
    esac
  done
  [ "${t[i]:-}" = "pr" ] || return 1
  case "${t[i+1]:-}" in
    create|edit|comment|review|merge) return 0 ;;
  esac
  return 1
}

strip_quotes_path() {
  local p="$1"
  p="${p#"${p%%[![:space:]]*}"}"
  p="${p%"${p##*[![:space:]]}"}"
  case "$p" in
    \"*\") p="${p#\"}"; p="${p%\"}" ;;
    \'*\') p="${p#\'}"; p="${p%\'}" ;;
  esac
  printf '%s' "$p"
}

read_body_file_at_branch_dir() {
  local raw="$1"
  local p content
  p="$(strip_quotes_path "$raw")"
  case "$p" in
    ''|'-'|'$'*|'~'*) return 1 ;;
  esac
  if [[ "$p" != /* ]]; then
    p="$gh_pr_dir/$p"
  fi
  [ -r "$p" ] || return 1
  content="$(cat "$p")"
  printf '%s' "$content"
}

collect_body_file_paths() {
  local -a words
  local w next_bf=0 next_f=0
  read -ra words <<< "${command_str//$'\n'/ }"
  for w in "${words[@]}"; do
    case "$w" in
      --body-file) next_bf=1 ;;
      --body-file=*)
        printf '%s\n' "${w#--body-file=}"
        ;;
      -F) next_f=1 ;;
      -F=*)
        printf '%s\n' "${w#-F=}"
        ;;
      -F[^=]*)
        if [ "$w" != "-F-" ]; then
          local attached="${w#-F}"
          [ -n "$attached" ] && printf '%s\n' "$attached"
        fi
        ;;
      *)
        if [ "$next_bf" -eq 1 ]; then
          printf '%s\n' "$w"
          next_bf=0
        elif [ "$next_f" -eq 1 ]; then
          printf '%s\n' "$w"
          next_f=0
        fi
        ;;
    esac
  done
}

check_gh_pr_body_signatures() {
  if pr_body_has_signature "$command_str"; then
    echo "$gh_pr_block_msg" >&2
    exit 2
  fi

  local path content sub p
  while IFS= read -r path; do
    [ -z "$path" ] && continue
    content="$(read_body_file_at_branch_dir "$path")" || continue
    if pr_body_has_signature "$content"; then
      echo "$gh_pr_block_msg" >&2
      exit 2
    fi
  done < <(collect_body_file_paths)

  while IFS= read -r sub; do
    [ -z "$sub" ] && continue
    p=""
    case "$sub" in
      '$(cat '*)
        p="${sub#\$(cat }"
        p="${p%)}"
        ;;
      *)
        sub_redir_prefix='$(< '
        if [ "${sub#"$sub_redir_prefix"}" != "$sub" ]; then
          p="${sub#"$sub_redir_prefix"}"
          p="${p%)}"
        fi
        ;;
    esac
    [ -z "$p" ] && continue
    content="$(read_body_file_at_branch_dir "$p")" || continue
    if pr_body_has_signature "$content"; then
      echo "$gh_pr_block_msg" >&2
      exit 2
    fi
  done < <(printf '%s' "$command_str" | grep -oE '\$\(cat[[:space:]]+[^)]+\)|\$\(<[[:space:]]+[^)]+\)' || true)
}

# Virtual cwd for the segments that follow, so the branch is read where the git
# command will ACTUALLY run. Commands here often take the form
# `cd <worktree> && git commit ...`; the hook's own cwd stays the checkout it was
# launched from, so reading the branch there misreads a nested-worktree commit as
# a commit on main and false-blocks it. Only `cd` in *command position* moves
# this, so a path mentioned inside a commit message never does.
# Unresolvable targets (bare `cd`, `~/...`, a dir that does not exist) leave it
# alone, which fails closed.
branch_dir="."
branch="$(git -C "$branch_dir" branch --show-current 2>/dev/null || true)"

while IFS= read -r seg; do
  [ -z "$seg" ] && continue

  # ALLOW_MAIN_COMMIT=1 may arrive as an env-assignment prefix on the command
  # itself rather than in this hook's environment — honor both.
  allow_main="${ALLOW_MAIN_COMMIT:-}"
  if printf '%s' "$seg" | grep -Eq '(^|[[:space:]])ALLOW_MAIN_COMMIT=1([[:space:]]|$)'; then
    allow_main=1
  fi

  # Trim leading whitespace and leading VAR=value assignments, then require
  # `git` in command position — quoted mentions inside other commands pass.
  s="$(printf '%s' "$seg" | sed -E 's/^[[:space:]]+//; s/^([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*//')"

  # `cd` in command position retargets the branch lookup for later segments.
  case "$s" in
    cd|cd\ *)
      target="${s#cd}"
      target="${target#"${target%%[![:space:]]*}"}"
      target="${target%"${target##*[![:space:]]}"}"
      case "$target" in
        \"*\") target="${target#\"}"; target="${target%\"}" ;;
        \'*\') target="${target#\'}"; target="${target%\'}" ;;
      esac
      case "$target" in
        '')  candidate="" ;;
        /*)  candidate="$target" ;;
        *)   candidate="$branch_dir/$target" ;;
      esac
      if [ -n "$candidate" ] && [ -d "$candidate" ]; then
        branch_dir="$candidate"
        branch="$(git -C "$branch_dir" branch --show-current 2>/dev/null || true)"
      fi
      continue
      ;;
  esac

  if segment_triggers_gh_pr_body_check "$seg"; then
    if [ "$gh_pr_trigger" -eq 0 ]; then
      gh_pr_dir="$branch_dir"
    fi
    gh_pr_trigger=1
  fi

  case "$s" in
    git\ *|git) ;;
    *) continue ;;
  esac

  # Strip single/double-quoted substrings before flag/word detection so
  # commit-message text never triggers the flag rules.
  s_noq="$(printf '%s' "$s" | sed -E "s/\"[^\"]*\"//g; s/'[^']*'//g")"

  if printf '%s' "$s_noq" | grep -Eq '^git[[:space:]]+commit([[:space:]]|$)'; then
    # (a) --no-verify / bare -n flag
    if printf '%s' "$s_noq" | grep -Eq -- '(--no-verify([[:space:]]|$|=)|[[:space:]]-n([[:space:]]|$))'; then
      echo "BLOCKED by git-guard: 'git commit --no-verify'/'-n' is forbidden (AGENTS.md Quality gates: never skip hooks). Fix the underlying lint/typecheck/test failure instead." >&2
      exit 2
    fi
    # (b) direct commit on main
    if [ "$branch" = "main" ] && [ "$allow_main" != "1" ]; then
      echo "BLOCKED by git-guard: direct 'git commit' on main is forbidden (AGENTS.md: implementation work goes on a feature branch). Prefix the command with ALLOW_MAIN_COMMIT=1 to override for an intentional docs/chore commit on main." >&2
      exit 2
    fi
  fi

  # (c) force-push targeting main (word match, so 'domain' etc. don't count),
  # or any force-push issued while main is the checked-out branch.
  if printf '%s' "$s_noq" | grep -Eq '^git[[:space:]]+push([[:space:]]|$)' \
    && printf '%s' "$s_noq" | grep -Eq -- '(--force([[:space:]]|$|-)|[[:space:]]-f([[:space:]]|$))'; then
    if printf '%s' "$s_noq" | grep -Eq '(^|[^[:alnum:]_])main([^[:alnum:]_]|$)' || [ "$branch" = "main" ]; then
      echo "BLOCKED by git-guard: force-push targeting 'main' (or issued while on main) is forbidden. Push to your feature branch instead; if main history must be rewritten, stop and ask the user." >&2
      exit 2
    fi
  fi
done <<< "$segments"

if [ "$gh_pr_trigger" -eq 1 ]; then
  check_gh_pr_body_signatures
fi

exit 0
