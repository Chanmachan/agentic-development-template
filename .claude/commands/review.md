# PR Review Response

指定したPRのレビューコメントを確認し、修正対応する。

## 引数
$ARGUMENTS にはPR番号、URLのいずれかを指定できる。

例:
- `123`
- `https://github.com/owner/repo/pull/123`

## 手順

1. $ARGUMENTS からPR番号を抽出する（URLの場合は末尾の数字を取得）
2. `gh pr view <番号> --comments` でPRの情報とコメントを取得する
3. `gh pr diff <番号>` で差分を確認する
4. レビューコメントの内容を整理して一覧表示する
5. 各コメントに対して修正が必要かどうか判断し、必要なものから順に対応する
6. 修正後は `git add` して `git commit` する（コミットメッセージはcommitルールに従う）
7. 全対応が完了したら修正内容のサマリーを表示する

## 使い方

/review 123
/review https://github.com/owner/repo/pull/123