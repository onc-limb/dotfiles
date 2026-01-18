# dotfiles

各種ツールの設定ファイルを管理するリポジトリ

## 含まれる設定

- `myvim/` - Neovim設定
- `starship.toml` - Starshipプロンプト設定
- `wezterm/` - WezTerm設定

## セットアップ

### 1. リポジトリをクローン

```bash
git clone <repository-url> ~/dotfiles
```

### 2. シンボリックリンクを作成

```bash
# 既存の設定をバックアップ（必要に応じて）
mv ~/.config/myvim ~/.config/myvim.bak
mv ~/.config/starship.toml ~/.config/starship.toml.bak
mv ~/.config/wezterm ~/.config/wezterm.bak

# シンボリックリンクを作成
ln -s ~/dotfiles/myvim ~/.config/myvim
ln -s ~/dotfiles/starship.toml ~/.config/starship.toml
ln -s ~/dotfiles/wezterm ~/.config/wezterm
```

### 確認

```bash
ls -la ~/.config | grep -E "myvim|starship|wezterm"
```

`->` で dotfiles ディレクトリを指していれば成功です。
