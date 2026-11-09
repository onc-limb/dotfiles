# dotfiles

## WezTerm (`wezterm/`)

設計は `docs/wezterm-workspace-design.md`。設定を変えるときは次を守る（破ると WezTerm が CPU 100% で固まる）。

- WezTerm の Lua はメインスレッドで動く。イベントごとに何度も呼ばれるフック（`format-tab-title`・`format-window-title` など）は使わない。
  タブ名などの表示は `update-right-status`（毎秒）からまとめて作る（タブ名は `tabs.refresh` が `set_title` で書き込む）
- 元のタブ名は `workspace.tab_name(tab)` で読む。`tab:get_title()` は表示用の名前（リポジトリ名・ブランチ・状態）を返す
- 毎秒のハンドラで外部コマンド（`wezterm.run_child_process`）を毎回起動しない。結果をキャッシュする（例: `statusbar.git_info`）
- 変更後は `wezterm --config-file wezterm/wezterm.lua show-keys >/dev/null` で設定が読めることを確かめる。
  動いている WezTerm は自動で読み直すので、`~/.local/share/wezterm/wezterm-gui-log-<pid>.txt` にエラーが出ていないかも見る
