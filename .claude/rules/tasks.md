---
paths:
  - "tasks/**"
  - "scripts/sync-tasks.sh"
---

# Task Tracking Rules

`tasks/` is git-ignored local working state. Sharing with reviewers/teammates is via the PR body, not these files. This doc is the canonical spec; `AGENTS.md` / `CLAUDE.md` only point here.

## Layout

- **`tasks/tasks.jsonl` — status registry.** One JSON object per line, one per task. The single, global index of "what tasks exist and their state" — canonical in the **main checkout** (see Worktrees). Read it at session start to see in-flight work, then open the relevant `tasks/<id>-todo.md` + recent `tasks/done/*.md` for detail.
- **`tasks/<id>-todo.md` — per-task detail.** Each task has its own file holding the plan/checklist (use `- [ ]` checkboxes). There is no privileged single `todo.md`.
- **`tasks/done/<id>.md` — archive.** Self-contained record once MERGED (概要 / branch / commits / PR / 検証結果 が単体で読める).
- **`tasks/reference/` — permanent reference material.** Briefs, conventions, check scripts: not a task, not listed in the registry.
- **`tasks/backlog.md` — out-of-scope gaps.** Running checklist of items noticed but not in the current task scope.

## backlog.md

When you spot an out-of-scope gap or leftover, don't silently drop it: log it as a one-line `- [ ]` checklist item with source (file:line or PR comment) in `tasks/backlog.md`. Read-only agents (review subagents) do not write backlog entries — they report gaps to the orchestrator/implementer, who records them. Fix it now only if it belongs in the current change. `tasks/` is git-ignored, so anything a reviewer/teammate must see also goes in the PR body.

## tasks.jsonl line schema

State registry: **upsert by `id`** — append one line when a task is first created, then update that same line in place on every later change; never add a second line for the same `id`. `done` tasks stay in the file (full ledger). From a worktree, do this via `scripts/sync-tasks.sh upsert` (see Worktrees), which serializes writes with a lock.

Placeholder note: `<id>` here and `{id}` in `AGENTS.md` / `CLAUDE.md` are the same token (the brace form dodges the doc-health pointer check, which only scans those two files). The `id`-equals-filename invariant below applies to new tasks; pre-existing `tasks/done/*.md` slugs predate this convention.

| field | meaning |
|-------|---------|
| `id` | kebab-case slug, unique. Identical to `tasks/<id>-todo.md` / `tasks/done/<id>.md` filenames. |
| `title` | short human label. |
| `status` | `planned` → `in_progress` → `review` → `done`, plus `blocked` when stuck. |
| `branch` | feature branch name, or `null` while still planning on `main`. |
| `parent` | parent task `id`; `null` for standalone tasks. Used for completion judgement (see 完遂の判定). |
| `pr` | PR number, or `null`. |
| `todo` | path to `tasks/<id>-todo.md`. |
| `done` | path to `tasks/done/<id>.md` once MERGED, else `null`. |
| `updated` | `YYYY-MM-DD` of the last change to this line. |
| `note` | optional one-liner (e.g. blocker reason); `null` if unused. |

Example line:

```json
{"id":"g4c-apply","title":"instructor apply POST 配線","status":"in_progress","branch":"feature/g4c-apply","parent":null,"pr":null,"todo":"tasks/g4c-apply-todo.md","done":null,"updated":"2026-06-15","note":null}
```

## Lifecycle

1. **Plan approved** → create `tasks/<id>-todo.md` + append a `planned` (or `in_progress`) line to `tasks/tasks.jsonl`.
2. **Branch cut** → set `status:"in_progress"` + `branch`.
3. **PR opened** → set `status:"review"` + `pr`.
4. **Blocked** → set `status:"blocked"` + a `note` explaining the blocker.
5. **MERGED** → set `status:"done"` + the `done` path, and move the detail into a self-contained `tasks/done/<id>.md`. The `done` line stays in the registry as the ledger.

Bump `updated` on every transition above.

## 完遂の判定

子 slice が `done` になっても、終わったのはその slice だけ。自律ループ (`/loop` 等) は停止判断を次の順で行う:

1. 子の status を確認する。
2. 親 (`parent`) の status を確認する。親が未完 (≠ `done`) なら、親の todo (`tasks/<parent>-todo.md`) から次の slice を選ぶ。

`bash scripts/sync-tasks.sh lint` は `parent` が実在する id を指し、自分自身でないことを検査する。

## Worktrees

`tasks/` is **single-sourced in the main checkout (分岐元)**. A worktree does not keep its own copy: `bash scripts/sync-local-docs.sh` (run first in a fresh worktree) symlinks the worktree's `tasks/` to the main checkout's. So normal relative paths (`tasks/<id>-todo.md`, `tasks/tasks.jsonl`, `tasks/done/<id>.md`) transparently read/write the one shared `tasks/`, and every worktree's work is visible in one registry. Nothing is lost when a worktree is deleted (no copy-back step). Claude Code runs this automatically via the `SessionStart`/`SubagentStart` hook (ADR 0009 (b)); Codex and Cursor have no equivalent hook mechanism, so the manual step above still applies to them.

- **Concurrent writes**: since several worktrees may touch the same `tasks/tasks.jsonl`, update a line via `bash scripts/sync-tasks.sh upsert <id> status=... branch=... pr=...`. It upserts a single line by `id` (never rewrites the whole file) and serializes writes with a file lock, so parallel tracks don't lose each other's lines. `list` / `get <id>` / `inflight` (status≠done の行のみ) read it. (The helper also resolves the main checkout via `git-common-dir`, so it works even before the symlink is set up.)
- **`id` is globally unique.** Prefix non-main-track task ids with the track name (e.g. `principal-<slug>`) so the shared registry has no collisions; the main checkout's own track may stay unprefixed.
- **Setup detail**: `scripts/sync-local-docs.sh` skips the symlink (warns) if the worktree already has a real `tasks/` directory — move its contents into the main checkout's `tasks/` and delete the dir first. `.gitignore` uses `/tasks` (no trailing slash) so the symlink itself stays ignored.

## Session start

Read `tasks/tasks.jsonl` first to see in-flight work (`status` ≠ `done`) — in a worktree the symlinked `tasks/` already points at the canonical file (or use `bash scripts/sync-tasks.sh list`) — then open the relevant `tasks/<id>-todo.md` and recent `tasks/done/*.md` for context.

registry が育ったら全体を開かず、in-flight 行だけ読む (`bash scripts/sync-tasks.sh inflight`、または同等の jq one-liner)。トップレベル行 (`parent` が null) を見失わないこと。
