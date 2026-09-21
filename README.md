# dotfiles

各種ツールの設定ファイルを管理するリポジトリ

## 含まれる設定

- `aerospace/` - AeroSpace ウィンドウマネージャー設定
- `borders/` - Borders設定
- `claude/` - Claude Code設定（skills, agents, テンプレート）
- `herdr/` - Herdr（AI エージェント用ターミナルマルチプレクサ）設定
- `karabiner/` - Karabiner-Elements（キーリマップ。Caps→Ctrl、左右 Cmd 単押しで英数/かな、Ctrl 単押しで英数⇄かなトグル、Realforce の Win/Alt 入れ替え）設定
- `nvim/` - Neovim設定
- `starship.toml` - Starshipプロンプト設定
- `wezterm/` - WezTerm設定
- `zed/` - Zed エディタ設定（settings.json / keymap.json）

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
| `herdr/` | `~/.config/herdr` |
| `karabiner/` | `~/.config/karabiner` |
| `starship.toml` | `~/.config/starship.toml` |
| `claude/home/settings.json` | `~/.claude/settings.json` |
| `claude/home/keybindings.json` | `~/.claude/keybindings.json` |
| `claude/home/CLAUDE.md` | `~/.claude/CLAUDE.md` |
| `zed/settings.json` | `~/.config/zed/settings.json` |
| `zed/keymap.json` | `~/.config/zed/keymap.json` |

### 3. Claude テンプレートの配置（任意）

Obsidian vault に Claude Code のスキルとエージェントを配置する:

```bash
cp -r ~/dotfiles/claude/templates/obsidian/{.claude,CLAUDE.md} /path/to/obsidian-vault/
```

コピー後、vault の `CLAUDE.md` を実際のフォルダ構造に合わせて編集してください。

## Zed 設定

`~/.config/zed/` にはプロンプトライブラリの LMDB（`prompts/`）など Zed が書き込む
バイナリ状態が同居するため、ディレクトリごとではなく**ファイル単位**でリンクする。

| ファイル | 役割 |
|---------|------|
| `settings.json` | テーマ・フォント・パネル配置・エージェントサーバーなど全体設定 |
| `keymap.json` | キーバインド（`base_keymap` は VSCode） |

自作テーマ（`themes/*.json`）やスニペット（`snippets/*.json`）を追加した場合は、
`zed/` 配下に置いて `install.sh` にリンクを追記する。
拡張機能の実体やセッション状態は `~/Library/Application Support/Zed/` にあり、
マシンローカルなので管理対象外。

プロジェクト個別の設定はリポジトリ直下の `.zed/settings.json` に置くと
ここのグローバル設定にマージされる（プロジェクト側が優先）。

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

