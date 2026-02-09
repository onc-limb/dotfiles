# obsidian テンプレート

Obsidian vault 用の Claude Code スキルとエージェント。

`/install-template obsidian` でプロジェクトに配置できる。

## Skills 一覧

| コマンド | 説明 |
|---------|------|
| `/daily-report [日付]` | デイリーノートから日報を作成 |
| `/monthly-report [YYYY-MM]` | 月次作業報告書を作成 |
| `/refine-daily [日付]` | デイリーノートの不足情報を対話形式で補完 |
| `/sort-notes [日付/期間]` | ノート内容を分類別ファイルに振り分け |

## Agents 一覧

| エージェント | 説明 |
|-------------|------|
| `note-reader` | 大量のデイリーノートを読み取り要約する（monthly-report から自動呼び出し） |
