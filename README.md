# dotfiles

各種ツールの設定ファイルを管理するリポジトリ

## 含まれる設定

- `aerospace/` - AeroSpace ウィンドウマネージャー設定
- `borders/` - Borders設定
- `claude/` - Claude Code設定（skills, agents, テンプレート）
- `nvim/` - Neovim設定
- `starship.toml` - Starshipプロンプト設定
- `wezterm/` - WezTerm設定

## セットアップ

### 1. リポジトリをクローン

```bash
git clone <repository-url> ~/dotfiles
```

### 2. インストールスクリプトを実行

```bash
cd ~/dotfiles
./install.sh
```

以下のシンボリックリンクが作成されます:

| ソース | リンク先 |
|-------|---------|
| `aerospace/` | `~/.config/aerospace` |
| `borders/` | `~/.config/borders` |
| `nvim/` | `~/.config/nvim` |
| `wezterm/` | `~/.config/wezterm` |
| `starship.toml` | `~/.config/starship.toml` |
| `claude/home/settings.json` | `~/.claude/settings.json` |
| `claude/home/CLAUDE.md` | `~/.claude/CLAUDE.md` |

### 3. Claude テンプレートの配置（任意）

Obsidian vault に Claude Code のスキルとエージェントを配置する:

```bash
cp -r ~/dotfiles/claude/templates/obsidian/{.claude,CLAUDE.md} /path/to/obsidian-vault/
```

コピー後、vault の `CLAUDE.md` を実際のフォルダ構造に合わせて編集してください。

## Claude Code 設定

### ディレクトリ構成

```
claude/
├── home/                        # → ~/.claude/ に個別シンボリックリンク
│   ├── settings.json
│   └── CLAUDE.md
└── templates/
    └── obsidian/                 # Obsidian vault 用テンプレート
        ├── CLAUDE.md
        └── .claude/
            ├── settings.json
            ├── skills/           # スラッシュコマンド
            │   ├── daily-report/
            │   ├── monthly-report/
            │   ├── refine-daily/
            │   ├── sort-notes/
            │   └── weekly-summary/
            └── agents/
                └── note-reader/
```

### Skills 一覧

| コマンド | 説明 |
|---------|------|
| `/daily-report [日付]` | デイリーノートから日報を作成 |
| `/monthly-report [YYYY-MM]` | 月次作業報告書を作成 |
| `/refine-daily [日付]` | デイリーノートの不足情報を対話形式で補完 |
| `/sort-notes [日付/期間]` | ノート内容を分類別ファイルに振り分け |
| `/weekly-summary [日付]` | 週次サマリーを作成 |

### Agents 一覧

| エージェント | 説明 |
|-------------|------|
| `note-reader` | 大量のデイリーノートを読み取り要約する（monthly-report から自動呼び出し） |

### Skill を SubAgent に切り替える判断基準

以下の兆候が見られたら、そのskillの処理をsubagentに委譲することを検討する:

1. **コンテキスト不足**: 実行中に「前の情報を覚えていない」「先ほどの内容を再度教えてください」といった応答が出始めたら、コンテキストウィンドウが溢れている
2. **大量ファイル読み取り**: 10ファイル以上を一度に読む必要がある処理（例: 月次報告書で30日分のノートを読む）
3. **処理時間の長さ**: 一つのskill実行が長時間に及び、途中で途切れる
4. **独立した前処理**: メインの対話に不要な中間データを大量に生成する処理（例: 全ノートスキャン→分類→結果のみ必要）

SubAgentにすべき処理の特徴:
- 読み取り中心（Read, Glob, Grep）で対話が不要
- 結果を要約して返せば十分（中間データは不要）
- メインの対話コンテキストを汚したくない

SubAgentにすべきでない処理の特徴:
- ユーザーとの対話が必要（refine-dailyのような補完作業）
- 少数ファイルの処理で済む
- メインコンテキストの情報が必要
