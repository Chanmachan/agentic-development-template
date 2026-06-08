# Git Rules

## Branch Naming

Format: `prefix/issue_<number>/short-description` (omit issue part if no issue)

- English, lowercase, use hyphens `-` or underscores `_` as word separators

| prefix | use case |
|--------|----------|
| feature | new feature |
| fix | bug fix |
| update | improve or change existing feature |
| refactor | refactoring |
| chore | config, dependencies, etc. |
| docs | documentation changes |

Examples (with issue):
- `feature/issue_234/custom-notification-timing`
- `fix/issue_12/milestone-sort-layout`

Examples (without issue):
- `feature/custom-notification-timing`
- `chore/add-cursor-rules`

## Commit Messages

Format: `prefix: short description` (single line only, no body or footer)

- English only
- Title line only — no body, no footer

| prefix | use case |
|--------|----------|
| feat | new feature |
| fix | bug fix |
| update | improve or change existing feature |
| refactor | code improvement without behavior change |
| style | formatting, no logic change |
| docs | documentation only |
| test | add or fix tests |
| chore | build config, dependencies, etc. |
| del | delete files or features |
| perf | performance improvement |
| ci | CI/CD config changes |

Examples:
- `feat: add custom notification timing setting`
- `fix: correct notification schedule time offset`
- `refactor: replace NotificationTiming enum with class`

## Co-author

Do not add `Co-Authored-By` to commit messages.

## Pull Request Template

When creating a PR, follow this format:

\```
## 概要
（この PR で何をしたか、1〜2 文で）

## 変更内容
- 変更点1
- 変更点2

## 変更理由
- なぜこの変更が必要か

## 動作確認方法
1. 手順1
2. 手順2

## 備考（任意）
- 補足事項があれば
  \```