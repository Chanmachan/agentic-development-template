#!/usr/bin/env bash
# tasks.jsonl グローバル registry の読み書きヘルパ。
#
# registry は分岐元（main チェックアウト）の tasks/tasks.jsonl が単一の正本。
# worktree からでも分岐元の registry を直接 read / upsert する（per-worktree のコピーは作らない）。
# 分岐元は共有 .git（git-common-dir）の親として解決するので、どの worktree からでも同じ registry を指す。
#
# 使い方:
#   bash scripts/sync-tasks.sh list                       # 全行を表示（グローバルビュー）
#   bash scripts/sync-tasks.sh get <id>                   # 1 タスクの行を表示
#   bash scripts/sync-tasks.sh upsert <id> key=value ...  # id をキーに 1 行だけ upsert
#   bash scripts/sync-tasks.sh lint                       # スキーマ/一意性チェック (JSON妥当性・id重複・status enum・done整合・todo存在)
#
# upsert 例:
#   bash scripts/sync-tasks.sh upsert g4c-apply status=in_progress branch=feature/g4c-apply \
#        title="instructor apply POST 配線" todo=tasks/g4c-apply-todo.md
#
# 注意:
#   - id は registry 全体で一意。worktree（別トラック）のタスクは namespace prefix を付ける
#     （例: principal-<slug>）。分岐元自身のトラックは無印で可。
#   - 1 行だけを id で upsert する（ファイル全体を置換しない）+ flock で直列化するので、
#     並列トラック（別 worktree）の同時 upsert でも互いの行を壊さない。
#   - updated は未指定なら今日（YYYY-MM-DD）を自動設定。
#   - 値の解釈: null/空文字 → null、true/false → bool、数値フィールド（pr）のみ整数化、
#     それ以外は文字列（branch=12345 / todo=007 の桁のみ文字列を壊さない）。
#   - 書き込みは temp + os.replace の atomic write。
#   - tasks/ は分岐元 1 本に集中（worktree は tasks/ を分岐元への symlink にする、
#     scripts/sync-local-docs.sh 参照）。todo / done パスは共有 tasks/ 上の相対パスで、
#     done 時は tasks/done/<id>.md を書き registry の done にそのパスを設定する。

set -euo pipefail

DST="$(git rev-parse --show-toplevel)"
COMMON_DIR="$(git rev-parse --git-common-dir)"
case "$COMMON_DIR" in
  /*) ;;                          # 既に絶対パス
  *) COMMON_DIR="$DST/$COMMON_DIR" ;;
esac
SRC="$(cd "$COMMON_DIR/.." && pwd)"
REGISTRY="$SRC/tasks/tasks.jsonl"

CMD="${1:-}"
shift || true

case "$CMD" in
  list)
    [ -f "$REGISTRY" ] && cat "$REGISTRY" || true
    ;;

  get)
    id="${1:-}"
    [ -n "$id" ] || { echo "usage: sync-tasks.sh get <id>" >&2; exit 2; }
    [ -f "$REGISTRY" ] || exit 0
    python3 - "$REGISTRY" "$id" <<'PY'
import sys, json
reg, tid = sys.argv[1], sys.argv[2]
for line in open(reg, encoding="utf-8"):
    if not line.strip():
        continue
    try:
        o = json.loads(line)
    except json.JSONDecodeError:
        continue  # 壊れた行は read 系では黙ってスキップ
    if o.get("id") == tid:
        print(line.rstrip())
        break
PY
    ;;

  upsert)
    id="${1:?usage: sync-tasks.sh upsert <id> key=value ...}"
    shift
    mkdir -p "$(dirname "$REGISTRY")"
    python3 - "$REGISTRY" "$id" "$@" <<'PY'
import sys, json, os, datetime, fcntl
reg, tid = sys.argv[1], sys.argv[2]
pairs = sys.argv[3:]

# 値の解釈: null/空文字 → null、true/false → bool。整数化は数値フィールド (pr) のみ
# (branch=12345 / todo=007 のような桁のみ文字列を誤って数値化・先頭ゼロ脱落させないため)。
NUMERIC_KEYS = {"pr"}

def coerce(k, v):
    if v in ("", "null"):
        return None
    if v == "true":
        return True
    if v == "false":
        return False
    if k in NUMERIC_KEYS:
        try:
            return int(v)
        except ValueError:
            return v
    return v

fields = {"id": tid}
for p in pairs:
    if "=" not in p:
        continue
    k, v = p.split("=", 1)
    if not k:
        continue
    fields[k] = coerce(k, v)
fields.setdefault("updated", datetime.date.today().isoformat())

SCHEMA = ["id", "title", "status", "branch", "pr", "todo", "done", "updated", "note"]

# SCHEMA 順にフィールドを並べ、スキーマ外のキーは後ろに付ける。
# dict-union (a | b) は Python 3.9+ 限定のため {**a, **b} で広い環境に対応。
def ordered(o):
    head = {k: o.get(k) for k in SCHEMA}
    tail = {k: v for k, v in o.items() if k not in SCHEMA}
    return {**head, **tail}

# 並列トラック (別 worktree) の同時 upsert によるロスト更新を防ぐため、read-modify-write
# 全体を排他ロックで直列化する。ロックは専用 .lock ファイル (registry は os.replace で
# inode が差し替わるためロック対象にしない)。
lock_path = reg + ".lock"
with open(lock_path, "w") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    rows, found = [], False
    if os.path.exists(reg):
        for line in open(reg, encoding="utf-8"):
            if not line.strip():
                continue
            try:
                o = json.loads(line)
            except json.JSONDecodeError:
                # 壊れた 1 行で全 upsert が止まるのを防ぐ。行はそのまま残す
                # (手で直せるよう破棄しない) が、警告だけ出す。
                sys.stderr.write("warning: skipping malformed registry line: " + line.rstrip() + "\n")
                rows.append(("__raw__", line.rstrip("\n")))
                continue
            if o.get("id") == tid:
                o.update(fields)
                o = ordered(o)
                found = True
            rows.append(o)
    if not found:
        base = {k: None for k in SCHEMA}
        base.update(fields)
        rows.append(ordered(base))
    tmp = reg + "." + str(os.getpid()) + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        for o in rows:
            if isinstance(o, tuple) and o[0] == "__raw__":
                f.write(o[1] + "\n")  # 壊れた行は原文のまま保持
            else:
                f.write(json.dumps(o, ensure_ascii=False) + "\n")
    os.replace(tmp, reg)

upserted = next(o for o in rows if isinstance(o, dict) and o.get("id") == tid)
print("upsert " + tid + ": " + json.dumps(upserted, ensure_ascii=False))
PY
    ;;

  lint)
    if [ ! -f "$REGISTRY" ]; then
      echo "OK: 0 tasks"
      exit 0
    fi
    python3 - "$REGISTRY" "$SRC" <<'PY'
import sys, json, os

reg, src = sys.argv[1], sys.argv[2]
VALID_STATUS = {"planned", "in_progress", "review", "blocked", "done"}

errors = []
seen_ids = {}
count = 0

with open(reg, encoding="utf-8") as f:
    for lineno, line in enumerate(f, 1):
        if not line.strip():
            continue
        count += 1
        try:
            obj = json.loads(line)
        except json.JSONDecodeError as e:
            errors.append(f"line {lineno}: invalid JSON ({e})")
            continue

        if not isinstance(obj, dict):
            errors.append(
                f"line {lineno}: invalid row (expected JSON object, got {type(obj).__name__})"
            )
            continue

        tid = obj.get("id")
        if not tid:
            errors.append(f"line {lineno}: missing id")
        elif not isinstance(tid, str):
            errors.append(
                f"line {lineno}: invalid row (id must be str, got {type(tid).__name__})"
            )
        elif tid in seen_ids:
            errors.append(f"line {lineno}: duplicate id '{tid}' (first seen at line {seen_ids[tid]})")
        else:
            seen_ids[tid] = lineno

        status = obj.get("status")
        status_ok = False
        if "status" not in obj:
            errors.append(f"line {lineno}: missing status")
        elif status is None:
            errors.append(f"line {lineno}: status is null")
        elif not isinstance(status, str):
            errors.append(
                f"line {lineno}: invalid row (status must be str, got {type(status).__name__})"
            )
        elif status not in VALID_STATUS:
            errors.append(
                f"line {lineno}: invalid status '{status}' (must be one of {sorted(VALID_STATUS)})"
            )
        else:
            status_ok = True

        if status_ok and status == "done":
            done = obj.get("done")
            if not isinstance(done, str) or not done:
                if isinstance(done, str) and not done:
                    errors.append(f"line {lineno}: status=done but done field is null/missing")
                elif done is None or "done" not in obj:
                    errors.append(f"line {lineno}: status=done but done field is null/missing")
                else:
                    errors.append(
                        f"line {lineno}: invalid row (done must be str, got {type(done).__name__})"
                    )

        if status_ok and status != "done":
            todo = obj.get("todo")
            if not todo:
                errors.append(f"line {lineno}: missing or empty todo")
            elif not isinstance(todo, str):
                errors.append(
                    f"line {lineno}: invalid row (todo must be str, got {type(todo).__name__})"
                )
            else:
                todo_path = todo if os.path.isabs(todo) else os.path.join(src, todo)
                if not os.path.isfile(todo_path):
                    errors.append(f"line {lineno}: todo is not a file: {todo}")

if errors:
    for e in errors:
        print("FAIL: " + e)
    sys.exit(1)

print(f"OK: {count} tasks")
PY
    ;;

  *)
    echo "usage: sync-tasks.sh {list | get <id> | upsert <id> key=value ... | lint}" >&2
    exit 2
    ;;
esac
