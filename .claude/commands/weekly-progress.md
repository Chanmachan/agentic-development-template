# Weekly Progress (定例向け進捗レポート)

毎週の定例（金曜 9:00 JST）向けに、「先週の定例から今回の定例までの進捗」を
**非エンジニアにも伝わる形**でまとめる。出力は先週のサンプル（画面で見える変化 /
画面では見えない変化 / その他 / まとめ）と同じ構成。

このコマンドは **ローカル限定**（`.gitignore` 済み・remote に共有しない）。

## 境界の考え方（重要）

- 定例は **毎週金曜 9:00（Asia/Tokyo）**。直前まで開発しているため、**日付ではなく時刻で境界を切る**。
- 進捗の判定は **git のコミット／マージ時刻を正**とする（tasks.jsonl の `updated` は日付のみで
  境界判定には使わない。tasks.jsonl は「どのタスク／PR か」の物語付けにだけ使う）。
- 既定の集計ウィンドウ = **[ 先週金曜 9:00, 今週金曜 9:00 )**。
- ウィンドウより後（今週金曜 9:00 〜 now）のコミットは **「次回定例ぶん（繰越・参考）」**として
  末尾に短く出すだけにする（取りこぼし防止）。

## 引数

`$ARGUMENTS` で境界（END = 今回定例の金曜 9:00）を上書きできる。省略時は下の python が自動算出。

- 省略 … 今カレンダー週の金曜 9:00 JST を END、その7日前を START にする。
- `2026-06-26` … その日の 9:00 JST を END にする（例: 当日を明示）。
- `last` … END を1週間前にずらす（先週ぶんを作り直すとき）。

## 手順

1. **集計ウィンドウを確定する**（git タイムスタンプを正とする）。次を実行して START/END を得る:

   ```bash
   python3 - "$ARGUMENTS" <<'PY'
   import sys
   from datetime import datetime, timedelta, timezone
   JST = timezone(timedelta(hours=9))
   arg = (sys.argv[1] if len(sys.argv) > 1 else "").strip()
   now = datetime.now(JST)
   # 今カレンダー週の金曜(weekday=4) 9:00 JST
   this_fri = (now - timedelta(days=(now.weekday() - 4) % 7)).replace(
       hour=9, minute=0, second=0, microsecond=0)
   end = this_fri
   if arg == "last":
       end = this_fri - timedelta(days=7)
   elif arg:
       try:
           d = datetime.fromisoformat(arg)
           end = d.replace(hour=9, minute=0, second=0, microsecond=0, tzinfo=JST) \
               if d.tzinfo is None else d
       except ValueError:
           pass  # 解釈できなければ既定の this_fri を使う
   start = end - timedelta(days=7)
   # git --since/--until 用（ローカルタイム文字列）と、後段の表示用
   print("START=" + start.strftime("%Y-%m-%d %H:%M:%S"))
   print("END=" + end.strftime("%Y-%m-%d %H:%M:%S"))
   print("NOW=" + now.strftime("%Y-%m-%d %H:%M:%S"))
   PY
   ```

2. **ウィンドウ内のコミット／マージを取得する**（時刻つき・全ブランチ）:

   ```bash
   TZ=Asia/Tokyo git log --all --since="<START>" --until="<END>" \
     --pretty=format:"%ad|%an|%h|%s" --date=format:"%Y-%m-%d %H:%M" | sort
   ```

   あわせて **境界以降（次回繰越）**も別途取得して末尾用に控える:

   ```bash
   TZ=Asia/Tokyo git log --all --since="<END>" --pretty=format:"%ad|%h|%s" \
     --date=format:"%Y-%m-%d %H:%M" | sort
   ```

3. **タスク台帳と完了ドキュメントで物語付けする**（PR 番号・ユーザー向け説明の補強）:
   - `bash scripts/sync-tasks.sh list`（または `tasks/tasks.jsonl`）で各 PR の `title` / `status` / `note` を引く。
   - ウィンドウ内にマージされた主要タスクは `tasks/done/<id>.md` の「概要」を読み、
     「ユーザーが何をできるようになったか」を一次情報から拾う（コミットメッセージの推測で埋めない）。

4. **次の構成でレポートを書く**（先週のサンプルと同じ。非エンジニア向けに平易な日本語で）:

   ```markdown
   # 進捗報告（<START の日付> 〜 <END の日付>）

   （冒頭1〜2文: マージ件数 / レビュー中件数 / 今週の最大の成果を一言）

   ## 1. 画面上で見える変化（ユーザーが触れる新機能）
   - 役割（指導員 / 校長 など）ごとに表でまとめる。「何ができるようになったか」を主語に。
   - レビュー中（もうすぐ入る）の PR も小見出しで触れる。

   ## 2. 画面では見えない変化（裏側の重要な仕事）
   - 通知配線・権限/セキュリティ・DB マイグレーション・整合性/並行制御・テスト追加など。
   - 専門用語は噛み砕く（例:「行レベルアクセス制御」=「他校のデータが見えない仕組み」）。

   ## 3. その他（開発を速く・安全にする整備）
   - ツール/コマンド整備・依存更新・CI など。

   ## まとめ（一言で）
   - 今週の到達点を1〜2文で。

   ## 次回定例ぶん（金曜 9:00 以降・参考）
   - 境界後に積み上がっているコミット/PR を箇条書きで（次回レポートへ繰越）。
   ```

5. **出力先**:
   - 既定はチャットにそのまま表示（口頭報告にコピペできる形）。
   - 「ファイルにしたい」と言われたら `research/weekly/<END の日付>.md` に保存する
     （`research/` は既に git-ignore 済み）。

## 注意

- 境界判定は **必ず git の時刻**で行う。tasks.jsonl の日付で「金曜午前のどっち側か」を判定しない。
- 事実（マージ済み・レビュー中）と推測を混ぜない。`done/<id>.md` に書いてある一次情報を優先する。
- dependabot 等の自動 PR は「その他」に1行でまとめ、主役の機能を埋もれさせない。

## 使い方

```
/weekly-progress            # 今週金曜 9:00 を境界に直近1週間
/weekly-progress last       # 先週ぶんを作り直す
/weekly-progress 2026-06-26 # 境界日を明示
```
