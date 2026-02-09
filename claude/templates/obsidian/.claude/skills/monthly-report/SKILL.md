---
name: monthly-report
description: 月次作業報告書を作成する
context: fork
agent: note-reader
---

## 指示

指定された月の日報を集約し、月次作業報告書を作成してください。

対象月: $ARGUMENTS（例: 2026-02。未指定の場合は今月を使用）

### 手順

1. `daily-report/` 配下から対象月の日報（`daily-report/YYYY-MM-*.md`）を全て読み取る
2. 日報が不足している場合は `daily/` のデイリーノートの `## work` セクションにフォールバックする
3. 内容を週単位でグルーピングする
4. `template.md` のフォーマットに沿って月次報告書を `monthly-report/YYYY-MM.md` に出力する

### 注意事項

- 全ての日報に目を通し、重要な作業・成果を漏れなく拾うこと
- 週ごとのまとまりで整理すると読みやすい
- 定量的な情報（件数、時間等）があれば含める
