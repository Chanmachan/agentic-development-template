#!/usr/bin/env bash
# PreToolUse(Bash) guard: block a small set of git footguns that AGENTS.md
# already forbids in prose but had no machine enforcement for:
#   (a) `git commit --no-verify` / `-n` (skips lefthook), including bundled
#       short-flag clusters like `-qn`
#   (b) direct `git commit` while on `main` (unless ALLOW_MAIN_COMMIT=1 in the
#       hook's env or as a real leading env-assignment prefix on the command —
#       never from text inside a quoted argument)
#   (c) force-push (`--force`/`--force-with-lease`/`-f`, incl. clusters like
#       `-fv`) whose destination refspec resolves to `main`, or issued while
#       `main` is the checked-out branch
#
# Parsing is done in python3 with shlex: the command is tokenized with shell
# quoting semantics (punctuation_chars splits segments on ;/&/|/newline outside
# quotes), git global options (-C/-c/--git-dir/...) are skipped to find the
# real subcommand, and value-taking options (-m, -F, --author, ...) consume
# their argument so message text is never scanned as flags. `git -C <dir>`
# moves the branch check into the directory the commit will actually land in
# (unlike the .claude copy, this variant does not track shell `cd` segments).
# This is still not a full shell interpreter (no expansions/substitutions) —
# deliberately conservative-but-simple.
#
# Fails open (exit 0) on anything unexpected — missing python3, unparseable
# JSON, unbalanced quotes, no git repo, etc. — so a hook bug never blocks
# unrelated development.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/profile.sh"
hook_profile_skip git-guard

input="$(cat)"
command -v python3 >/dev/null 2>&1 || exit 0

rc=0
GIT_GUARD_INPUT="$input" python3 - <<'PY' || rc=$?
import json, os, re, shlex, subprocess, sys

SEP_CHARS = ";&|\n"
GIT_GLOBAL_VALUE_OPTS = {"-C", "-c", "--git-dir", "--work-tree", "--namespace",
                         "--super-prefix", "--config-env"}
COMMIT_VALUE_OPTS = {"-m", "--message", "-F", "--file", "-C", "--reuse-message",
                     "-c", "--reedit-message", "-t", "--template", "--author",
                     "--date", "--fixup", "--squash", "--trailer",
                     "--pathspec-from-file", "--cleanup"}
# Short options whose value may be ATTACHED to the cluster (-mMsg): once one is
# seen mid-cluster the rest of the token is its value, not more flags.
COMMIT_ATTACHED_SHORTS = "mFCctuS"
PUSH_VALUE_OPTS = {"-o", "--push-option", "--repo", "--receive-pack", "--exec"}
PUSH_ATTACHED_SHORTS = "o"

MSG_NO_VERIFY = ("BLOCKED by git-guard: 'git commit --no-verify'/'-n' is "
                 "forbidden (AGENTS.md Quality gates: never skip hooks). Fix "
                 "the underlying lint/typecheck/test failure instead.")
MSG_MAIN_COMMIT = ("BLOCKED by git-guard: direct 'git commit' on main is "
                   "forbidden (AGENTS.md: implementation work goes on a "
                   "feature branch). Prefix the command with "
                   "ALLOW_MAIN_COMMIT=1 to override for an intentional "
                   "docs/chore commit on main.")
MSG_FORCE_PUSH = ("BLOCKED by git-guard: force-push targeting 'main' (or "
                  "issued while on main) is forbidden.")

_branch_cache = {}


def get_branch(d):
    if d not in _branch_cache:
        try:
            r = subprocess.run(["git", "-C", d, "branch", "--show-current"],
                               capture_output=True, text=True, timeout=5)
            _branch_cache[d] = r.stdout.strip() if r.returncode == 0 else ""
        except Exception:
            _branch_cache[d] = ""
    return _branch_cache[d]


def block(msg):
    print(msg, file=sys.stderr)
    sys.exit(2)


def scan_short_cluster(tok, hit_chars, attached_shorts, value_opts):
    """Scan a short-flag cluster like -qn. Returns (hit, consume_next):
    hit — a char from hit_chars appeared as a flag; consume_next — the cluster
    ends in a value-taking short whose value is the NEXT token."""
    hit = False
    consume_next = False
    for k in range(1, len(tok)):
        ch = tok[k]
        if ch in hit_chars:
            hit = True
        if ch in attached_shorts:
            # Rest of the token is this option's value; if there is no rest,
            # the value is the next token (only for options that require one).
            if k == len(tok) - 1 and ("-" + ch) in value_opts:
                consume_next = True
            break
    return hit, consume_next


def commit_rule(args, branch, allow_main):
    j = 0
    while j < len(args):
        a = args[j]
        if a == "--":
            break
        if a == "--no-verify" or a.startswith("--no-verify="):
            block(MSG_NO_VERIFY)
        if a in COMMIT_VALUE_OPTS:
            j += 2
            continue
        if a.startswith("--"):
            j += 1
            continue
        if a.startswith("-") and len(a) > 1:
            hit, consume_next = scan_short_cluster(
                a, "n", COMMIT_ATTACHED_SHORTS, COMMIT_VALUE_OPTS)
            if hit:
                block(MSG_NO_VERIFY)
            j += 2 if consume_next else 1
            continue
        j += 1
    if branch == "main" and not allow_main:
        block(MSG_MAIN_COMMIT)


def push_rule(args, branch):
    force = False
    positionals = []
    j = 0
    while j < len(args):
        a = args[j]
        if a == "--":
            positionals.extend(args[j + 1:])
            break
        if a == "--force" or a.startswith("--force-with-lease"):
            force = True
            j += 1
            continue
        if a in PUSH_VALUE_OPTS:
            j += 2
            continue
        if a.startswith("--"):
            j += 1
            continue
        if a.startswith("-") and len(a) > 1:
            hit, consume_next = scan_short_cluster(
                a, "f", PUSH_ATTACHED_SHORTS, PUSH_VALUE_OPTS)
            if hit:
                force = True
            j += 2 if consume_next else 1
            continue
        positionals.append(a)
        j += 1
    if not force:
        return
    # positionals = [remote, refspec...]; the push target is each refspec's
    # DESTINATION (after ':', else the refspec itself) — a substring scan
    # would false-block e.g. feature/main-refactor.
    targets_main = False
    for r in positionals[1:]:
        dst = r.lstrip("+")
        if ":" in dst:
            dst = dst.split(":")[-1]
        if dst in ("main", "refs/heads/main"):
            targets_main = True
    if targets_main or branch == "main":
        block(MSG_FORCE_PUSH)


def main():
    raw = os.environ.get("GIT_GUARD_INPUT", "")
    try:
        cmd = json.loads(raw).get("tool_input", {}).get("command", "")
    except Exception:
        return
    if not cmd or not isinstance(cmd, str):
        return
    try:
        lex = shlex.shlex(cmd, posix=True, punctuation_chars=SEP_CHARS)
        lex.whitespace = " \t\r"
        lex.whitespace_split = True
        tokens = list(lex)
    except ValueError:
        return  # unbalanced quotes etc. — fail open

    segments = []
    cur = []
    for t in tokens:
        if t and all(c in SEP_CHARS for c in t):
            if cur:
                segments.append(cur)
            cur = []
        else:
            cur.append(t)
    if cur:
        segments.append(cur)

    env_allow = os.environ.get("ALLOW_MAIN_COMMIT") == "1"
    curdir = "."  # hook cwd; this variant does not track shell `cd` segments

    for toks in segments:
        allow_main = env_allow
        while toks and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", toks[0]):
            if toks[0] == "ALLOW_MAIN_COMMIT=1":
                allow_main = True
            toks = toks[1:]
        if not toks:
            continue

        if toks[0] != "git":
            continue

        # Skip git GLOBAL options to find the real subcommand; -C moves the
        # repo the same way a shell cd does, so track it for the branch check.
        git_dir = None
        subcmd = None
        i = 1
        while i < len(toks):
            t = toks[i]
            if not t.startswith("-"):
                subcmd = t
                i += 1
                break
            if t == "-C":
                if i + 1 < len(toks):
                    git_dir = toks[i + 1]
                i += 2
                continue
            if t.startswith("-C") and len(t) > 2 and not t.startswith("--"):
                git_dir = t[2:]
                i += 1
                continue
            if t in GIT_GLOBAL_VALUE_OPTS:
                i += 2
                continue
            if t.startswith("-c") and len(t) > 2 and not t.startswith("--"):
                i += 1
                continue
            i += 1  # boolean global (-p, --bare, ...) or --opt=value form
        if subcmd is None:
            continue

        branch_dir = curdir
        if git_dir:
            branch_dir = git_dir if os.path.isabs(git_dir) \
                else os.path.join(curdir, git_dir)
        branch = get_branch(branch_dir)
        args = toks[i:]

        if subcmd == "commit":
            commit_rule(args, branch, allow_main)
        elif subcmd == "push":
            push_rule(args, branch)


try:
    main()
except SystemExit:
    raise
except Exception:
    pass  # fail open
PY

if [ "$rc" -eq 2 ]; then
  exit 2
fi
exit 0
