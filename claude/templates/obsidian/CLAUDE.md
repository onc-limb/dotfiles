# Obsidian Vault Context

## Vault 構造

<!-- TODO: 実際のvault構造に合わせて編集してください -->

```
vault/
├── Daily/                  # デイリーノート
│   └── YYYY-MM-DD.md
├── Categories/             # sort-notes による分類先
│   └── <カテゴリ名>.md
└── .obsidian/              # Obsidian設定（変更禁止）
```

## デイリーノート

- 場所: `Daily/`
- 命名規則: `YYYY-MM-DD.md`（例: `2026-02-07.md`）

<!-- TODO: デイリーノートのテンプレート構造を記載してください -->
<!-- 例:
## タスク
- [ ] タスク1

## メモ
- 内容

## 作業ログ
- 09:00-10:00 作業内容
-->

## タグ体系

<!-- TODO: 使用しているタグを記載してください -->
<!-- 例: #project/xxx, #meeting, #idea -->

## ルール

- `.obsidian/` ディレクトリ内のファイルは絶対に変更しないこと
- デイリーノートの元ファイルは `sort-notes` 実行時に変更しないこと
- `Categories/` 配下のファイルへの追記時は日付ヘッダーを付けること
