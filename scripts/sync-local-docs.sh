#!/usr/bin/env bash
# 新しい worktree の初期セットアップ:
#   (1) tasks/ を分岐元（main チェックアウト）への symlink にする、
#   (2) (任意) git-ignore 済みのローカル限定 docs を分岐元からコピー同期する。
#
# 背景: `tasks/` は git 管理外（.gitignore の "Task tracking" 参照）なので、
# `git worktree add` で新しい worktree を切っても付いてこない。tasks/ は分岐元 1 本を
# 正とし（todo / tasks.jsonl / done を全 worktree で共有し、どの worktree の作業も
# 1 か所で把握できる）、symlink なので相対パス tasks/... がそのまま分岐元を指す。
#
# プロジェクトによっては spec / 事業系 docs なども .gitignore してローカル限定にする
# 場合がある。その場合は下の PATHS 配列に列挙すると、worktree へコピー同期される。
# テンプレート初期状態では tasks/ 以外に git-ignore された docs は無いため PATHS は空。
#
# 使い方:
#   bash scripts/sync-local-docs.sh            # 同期実行
#   bash scripts/sync-local-docs.sh --dry-run  # 何をするか表示のみ
#
# 注意:
#   - tasks/ はコピーせず分岐元への symlink を張る（分岐元 1 本が canonical）。
#   - docs は分岐元が canonical。worktree 側の同名ファイルは上書きされる。
#   - 追加・上書きのみ（mirror ではない）。分岐元で削除されたファイルは worktree 側に残る。
#   - 同期後、ignore されていないファイルが無いか git status で安全確認する（末尾の警告）。

set -euo pipefail

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

# 現在の worktree のルート
DST="$(git rev-parse --show-toplevel)"

# 分岐元（main チェックアウト）= 共有 .git ディレクトリの親
COMMON_DIR="$(git rev-parse --git-common-dir)"
case "$COMMON_DIR" in
  /*) ;;                          # 既に絶対パス
  *) COMMON_DIR="$DST/$COMMON_DIR" ;;
esac
SRC="$(cd "$COMMON_DIR/.." && pwd)"

if [ "$SRC" = "$DST" ]; then
  echo "ここは分岐元（main チェックアウト）です。同期は不要なので終了します。"
  exit 0
fi

echo "分岐元: $SRC"
echo "同期先: $DST"
echo ""

# コピー同期対象（git-ignore 済みのローカル限定 docs / scratch）。
# 末尾にスラッシュなし。ファイル・ディレクトリどちらも可。
# このリポを使うプロジェクトで spec / 事業系 docs などを .gitignore した場合に列挙する。
# 例:
#   "docs/spec.local.md"
#   "docs/client"
#   "idea"
#   "research"
PATHS=(
)

copied=0
for p in "${PATHS[@]}"; do
  if [ ! -e "$SRC/$p" ]; then
    continue  # 分岐元に無いものはスキップ
  fi
  echo "  + $p"
  if [ "$DRY_RUN" -eq 0 ]; then
    mkdir -p "$DST/$(dirname "$p")"
    if [ -d "$SRC/$p" ]; then
      cp -R "$SRC/$p/." "$DST/$p/"
    else
      cp "$SRC/$p" "$DST/$p"
    fi
  fi
  copied=$((copied + 1))
done

[ ${#PATHS[@]} -gt 0 ] && echo ""

# tasks/ を分岐元への symlink にする（分岐元 1 本を正とする集中運用）。
echo "tasks/ symlink:"
[ "$DRY_RUN" -eq 0 ] && mkdir -p "$SRC/tasks"
if [ -L "$DST/tasks" ]; then
  current="$(readlink "$DST/tasks")"
  if [ "$current" = "$SRC/tasks" ]; then
    echo "  = 既に分岐元を指しています ($DST/tasks → $SRC/tasks)"
  else
    echo "  ~ 貼り直し ($current → $SRC/tasks)"
    [ "$DRY_RUN" -eq 0 ] && ln -sfn "$SRC/tasks" "$DST/tasks"
  fi
elif [ ! -e "$DST/tasks" ]; then
  echo "  + tasks → $SRC/tasks"
  [ "$DRY_RUN" -eq 0 ] && ln -s "$SRC/tasks" "$DST/tasks"
else
  echo "  ⚠️  $DST/tasks が実ディレクトリ/ファイルです。中身を分岐元 tasks/ へ移してから"
  echo "      削除し、本スクリプトを再実行してください（symlink 化されず集中運用から外れます）。"
fi

echo ""
if [ "$DRY_RUN" -eq 1 ]; then
  echo "[dry-run] 上記 $copied 項目のコピーと tasks symlink を実行します（実行はしていません）。"
  exit 0
fi

echo "$copied 項目を同期し、tasks/ symlink を設定しました。"

# 安全確認: コピー同期したパス配下に git-ignore されていないファイルが無いか検出する。
# このスクリプトは「ignore 済み docs だけを持ち込む」前提なので、ここで何か出たら
# .gitignore の列挙漏れの可能性が高い。git status は ignore 済みを隠すため、
# ここに現れる = 追跡対象になりうる / 追跡中ファイルを書き換えた、のいずれか。
if [ ${#PATHS[@]} -gt 0 ]; then
  leaked="$(git -C "$DST" status --porcelain --untracked-files=all -- "${PATHS[@]}" 2>/dev/null || true)"
  if [ -n "$leaked" ]; then
    echo ""
    echo "⚠️  警告: 同期したファイルの一部が git-ignore されていません（コミット禁止）:"
    echo "$leaked" | sed 's/^/    /'
    echo "  → .gitignore に追記するか、これらをコミットしないこと。"
  fi
fi
