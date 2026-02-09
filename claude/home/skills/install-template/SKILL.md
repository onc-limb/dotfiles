---
name: install-template
description: テンプレートをプロジェクトディレクトリにインストールする
---

## 指示

dotfiles のテンプレートからプロジェクト設定（`.claude/` と `CLAUDE.md`）を対象ディレクトリにコピーする。

引数: `$ARGUMENTS`（形式: `<template-name> [target-path]`）

### 手順

1. テンプレートディレクトリのパスを解決する
   - `readlink ~/.claude/skills/install-template/SKILL.md` でシンボリックリンク元を辿る
   - そこから `../../../templates` で `claude/templates/` を得る
   - 解決できない場合はユーザーに dotfiles のパスを聞く

2. `$ARGUMENTS` を解析する
   - 空の場合: テンプレート一覧を `ls` で表示して終了
   - 1つの引数: テンプレート名（ターゲットは現在のディレクトリ）
   - 2つの引数: `<template-name> <target-path>`

3. テンプレートの存在を確認する
   - 存在しない場合: エラーと利用可能なテンプレート一覧を表示

4. ターゲットディレクトリを確認する
   - 存在しない場合: ユーザーに作成するか確認

5. 競合チェック
   - `$TARGET/.claude/` や `$TARGET/CLAUDE.md` が既に存在する場合、ユーザーに上書き確認

6. コピー実行
   - テンプレートに `.claude/` があれば `cp -r` でコピー
   - テンプレートに `CLAUDE.md` があれば `cp` でコピー

7. 結果報告
   - コピーしたファイルの一覧を表示

### 注意事項

- テンプレート側のファイルは読み取り専用（変更しない）
- 既存ファイルの上書きには必ずユーザー確認を取る
