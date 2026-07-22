---
description: multi-review → fix-review を「指摘ゼロ(clean)」になるまで自動で繰り返す。人が毎回回さなくて済むようにするレビュー駆動ループ
argument-hint: "[PR番号 | PR URL | 空=現在ブランチ vs main] [--max-rounds N(既定3)] [--base <ref>]"
allowed-tools: Bash, Read, Grep, Glob, Edit, Write, Task
---

# Review Cycle（レビュー収束ループ）

`/multi-review`(6 観点並列レビュー) と `/fix-review`(指摘対応) を**手で交互に打つ手間をなくす**ためのコマンド。
1 回打つと「レビュー → 対応 → 再レビュー」を **clean(対応すべき指摘ゼロ) になるまで自動で回し**、
収束したら結果を 1 つにまとめて報告する。

## いつ使うか
実装(TDD)が一通り終わり、lint/typecheck/test が green になった直後。
ここから「レビュー指摘が出なくなるまで」を自走させたいとき。

## 引数
$ARGUMENTS は任意:
- 数字 (`103`) → PR 番号をレビュー対象に
- URL → 末尾の番号を抽出
- 空 → **現在ブランチ `HEAD` vs `main`** の差分(= そのタスクの全変更)を対象に
- `--base <ref>` → 差分の基準を変える(例: 既レビュー済みなら増分だけ見たい時 `--base <最後にレビューした commit>`)
- `--max-rounds N` → 安全弁。既定 3 周。これを超えても指摘が残るなら**勝手に直し続けず人に返す**

## 手順

1. **対象差分を確定する**
   - PR 番号あり: `gh pr diff <番号>` / 空: `git diff <base>...HEAD`(base 既定 = `main`)
   - 差分が無ければ「レビュー対象なし」で即終了

2. **1 周目のレビュー** — `/multi-review`(または review-* subagent を並列起動)を対象差分に対して実行し、
   観点別の **Blocking / Suggestion / Nit** を集約する。

3. **収束判定**
   - **対応すべき指摘 = Blocking + 「対応する」と判断した Suggestion**。
   - これがゼロ(残りが Nit、または「設計上あえてそうしている=却下済み」だけ)なら → **clean。ループ終了**。
   - ただし clean と宣言できるのは次の3条件が揃ったときだけ: (a) Blocking が 0 (反証 pass 通過後)、かつ (b) 全 reviewer が結果を返した (`failed to evaluate` が無い)、かつ (c) lint/typecheck/test green のログを同レポートに提示できる。1 つでも欠けたら clean を宣言しない。

4. **対応(fix-review)** — 残った指摘を `/fix-review` の方針で実装で潰す。
   - **設計判断で却下する指摘は直さず、却下理由を明記して残す**(例: 過去に確定した authz/status 方針)。
   - 各対応後に **lint / typecheck / test を必ず green に戻す**。ここを緩めて通すのは禁止。

5. **再レビュー** — 修正後の差分でステップ 2 に戻る。`--max-rounds` まで繰り返す。

6. **終了処理**
   - clean で抜けた場合: 何周回して各周で何を直したかを要約して報告。
   - `--max-rounds` 上限で残指摘がある場合: **自動修正を止め**、残っている指摘と「なぜ収束しなかったか」を人に提示して判断を仰ぐ。

## 原則
- **clean の定義を勝手に甘くしない**。Blocking と「対応する Suggestion」がゼロになって初めて clean。
- **却下とは区別する**: 直さない指摘は「直し忘れ」ではなく「設計判断で却下」と理由付きで残す。混同しない。
- **品質ゲートを下げて通さない**(lint/type/test の設定変更・`--no-verify`・テスト緩和は禁止。`AGENTS.md` Quality gates 準拠)。
- **暴走させない**: `--max-rounds` を超えたら必ず人に返す。延々と自己修正し続けない。
- review/fix は別文脈の subagent に委譲してメイン文脈を汚さない(レビューログを長文で貼り込まない)。

## 使い方
```
/review-cycle                 # 現ブランチ vs main を clean まで回す
/review-cycle --base 98fa829  # 98fa829 以降の増分だけを対象に
/review-cycle 103             # PR #103 を対象に
/review-cycle --max-rounds 5  # 上限を 5 周に
```

## 関連
- `/multi-review` — 1 周分の 6 観点レビュー(本コマンドが内部で使う部品)
- `/fix-review` — 指摘 1 件ずつへの対応(本コマンドが内部で使う部品)
