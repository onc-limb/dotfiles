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
            │   └── sort-notes/
            └── agents/
                └── note-reader/
```

