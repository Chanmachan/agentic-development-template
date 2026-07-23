---
name: land-task
description: Use after the user approves merge, to perform the mechanical landing of a task — verify CI green, pin head SHA, preflight archive, squash-merge with --match-head-commit, archive todo to done/, mark tasks.jsonl done, and prune. Merge approval stays a human gate; never run before it.
---

# Land Task（タスク着地）

ユーザーが **merge を承認した後**の定型作業（merge と後片付け、台帳更新、todo の archive）を 1 つにまとめる。
毎回手で叩いていた手順を機械化して、完了処理のミスと手間を減らす。

## 前提（重要）
- **merge 承認は人間ゲート**。このスキルは「ユーザーが merge OK と言った後」にのみ実行する。
  スキル自身が承認の代わりにはならない。承認がまだなら実行しない。
- 動作確認・レビューが終わっていること(`review-cycle` が clean、`verify-guide` の手元確認 OK)。

## 引数
- `<task-id>`(必須) — `tasks/tasks.jsonl` の `id`。todo/done ファイル名と同一。
- `[PR番号]`(任意) — 省略時は tasks.jsonl の当該行の `pr` から解決する。

## 手順

1. **対象タスクを解決** — `bash scripts/sync-tasks.sh get <task-id>` で行を引き、`pr` / `branch` / `todo` を取得。
   **registry に行が無ければ中止**する。PR 番号が引数にあればそれを優先。

2. **マージ可否を確認し、検証済み head を固定**（安全弁）
   - `gh pr view <pr> --json state,mergeStateStatus,mergeable,headRefName,baseRefName,headRefOid` と
     `gh pr checks <pr>` で **CI が全 green** かつ未マージであることを確認。
   - 応答の `headRefOid` を **検証済み head SHA** として保持する(以降の merge で使う)。
   - `headRefName` が task の `branch` と一致し、`baseRefName` が `main` であることを確認する
     (打ち間違いで無関係な green PR を merge して別タスクをアーカイブする事故を防ぐ)。
   - green でない / head・base 不一致 / すでに closed 等なら **merge せず停止**して状況を報告する。

3. **archive preflight**（merge 前・不可逆操作の前）
   - `tasks/<task-id>-todo.md` が**存在する**ことを確認する。無ければ **merge せず停止**。
   - `tasks/done/<task-id>.md` が**存在しない**ことを確認する(パス衝突防止)。あれば **merge せず停止**。

4. **squash merge**（検証済み head を固定）
   - `gh pr merge <pr> --squash --delete-branch --match-head-commit <headRefOid>`
   - 検証後に force-push され head が変わっていた場合は merge が拒否される(未検証コミットの merge を防ぐ)。
   - ⚠ **worktree 落とし穴**: main が別 worktree に checkout されていると `--delete-branch` の
     **local 後始末だけ**が失敗するが、**merge 自体と remote ブランチ削除はサーバ側で成功**する。
     `gh pr view <pr> --json state,mergedAt,mergeCommit` で `state=MERGED` を確認すれば OK。
     エラー文だけ見て失敗と早合点しない。

5. **todo を done/ へ archive（self-contained に）**
   - `tasks/<task-id>-todo.md` の内容を `tasks/done/<task-id>.md` へ移す。
   - 先頭に**完了サマリ**(MERGED 日付 / PR / merge commit / 概要 / 主要コミット / 検証結果)を付け、
     単体で経緯が読める形にする(`CLAUDE.md` Archive フェーズ準拠)。元 todo は削除。
   - 書込に失敗したら **台帳は done にしない**。状況を報告して手動復旧を促す。

6. **台帳(tasks.jsonl)を done に更新**（archive 成功後のみ）
   - `bash scripts/sync-tasks.sh upsert <task-id> status=done pr=<resolved-pr> todo=null done=tasks/done/<task-id>.md updated=<今日の日付> note="MERGED <日付> PR#<pr> squash (<merge commit 短縮>)"`
   - `branch` は保持する(pre-branch planning のときだけ `null`)。`todo` は step 5 で archive 済みなので `null`。
   - `updated` は今日の日付(`YYYY-MM-DD`)。

7. **ローカル同期**
   - `git fetch --prune origin` で削除済み remote ブランチを掃除し、`origin/main` を最新化。

8. **報告** — merge commit / done パス / 台帳更新内容を 1 つにまとめて返す。

## 原則
- **merge 承認が無ければ走らせない**(人間ゲートを飛ばさない)。
- **CI green を確認してから merge**(UNSTABLE のまま merge しない)。
- **検証時点の head SHA を `--match-head-commit` で固定**して merge する(force-push による未検証コミット merge を防ぐ)。
- **archive preflight を merge 前に行い、台帳 done 化は archive 成功後のみ**(status=done なのに done パスが無い状態を防ぐ)。
- worktree の local 後始末失敗を「merge 失敗」と誤認しない(state=MERGED を真実とする)。
- `git commit`/merge 出力を `tail`/`head` パイプに通さない(SIGPIPE 無言失敗に注意)。
- archive 後の `tasks/done/<id>.md` は **single-sourced な main checkout** の `tasks/` に書かれる(worktree は symlink)。

## 使い方
```
land-task <task-id>        # tasks.jsonl から PR を解決して着地
land-task <task-id> 42    # PR 番号を明示
```

## 関連
- `review-cycle` — 着地の前にレビューを clean まで収束させる
- `verify-guide` — 着地の前に手元動作確認の runbook を出す
- `handoff` — 着地後、次タスクへの引き継ぎプロンプトを生成 → clear
