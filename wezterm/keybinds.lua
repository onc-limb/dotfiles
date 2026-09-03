local wezterm = require("wezterm")
local act = wezterm.action

-- macOS の入力ソース切り替え (im-select)。GUI アプリの wezterm は PATH が通っていないためフルパス指定
local IM_SELECT = wezterm.home_dir .. "/.local/bin/im-select"
local IM_ROMAN = "com.apple.inputmethod.Kotoeri.RomajiTyping.Roman"

-- Claude Code のトランスクリプトモード (Ctrl+O) に入るとき、入力ソースを英数にする。
-- 日本語入力のままだと j / k などのキーが効かないため。Claude Code 以外のペインでは素通しする。
-- Herdr 越しに Claude Code を動かしている場合は前面プロセスが herdr になるので、それも対象にする。
-- Ctrl+O はトグルなので抜けるときも英数になる (日本語で指示を打つときは手動で切り替える)
local function claude_transcript_toggle(window, pane)
	local proc = pane:get_foreground_process_name() or ""
	if proc:find("claude", 1, true) or proc:find("herdr", 1, true) then
		wezterm.run_child_process({ IM_SELECT, IM_ROMAN })
	end
	window:perform_action(act.SendKey({ key = "o", mods = "CTRL" }), pane)
end

-- LEADER+e で開いた nvim ペインをタブごとに記録する (tab_id -> pane_id)。
-- 何度押しても新しいペインを増やさず、既にあればそのペインに戻ってズームし直す
local editor_panes = {}

-- 今いるペインの cwd で nvim をズーム表示する。
-- Claude Code / Codex のセッションを閉じずに .env の編集やディレクトリ確認をするため。
-- 右に分割して即ズーム (全面表示) し、左に neo-tree のディレクトリツリーを出した状態で起動する。
-- nvim を :xa などで終了すると元のペインにフォーカスを戻してからペインが閉じ、元の画面に戻る
local function open_editor_pane(window, pane)
	local tab = window:active_tab()
	local tab_id = tab:tab_id()

	-- このタブに LEADER+e の nvim ペインが残っていればそれを使う
	local existing_id = editor_panes[tab_id]
	if existing_id then
		for _, p in ipairs(tab:panes()) do
			if p:pane_id() == existing_id then
				if pane:pane_id() ~= existing_id then
					p:activate()
				end
				window:perform_action(act.SetPaneZoomState(true), p)
				return
			end
		end
		-- 記録はあるがペインは閉じられている
		editor_panes[tab_id] = nil
	end

	local cwd = pane:get_current_working_dir()
	local origin_pane_id = pane:pane_id()
	local new_pane = pane:split({
		direction = "Right",
		cwd = cwd and cwd.file_path or nil,
		-- ログインシェル経由で起動して PATH (homebrew / mise) を引き継ぐ。
		-- g:start_with_explorer は nvim 側 (plugin.lua の oil 設定) で見て neo-tree を左に開く。
		-- nvim 終了後に元のペインへフォーカスを戻し、シェルが終わってペインが閉じる
		args = {
			"/bin/zsh",
			"-lic",
			string.format(
				"nvim --cmd 'let g:start_with_explorer = 1'; wezterm cli activate-pane --pane-id %d",
				origin_pane_id
			),
		},
	})
	editor_panes[tab_id] = new_pane:pane_id()
	new_pane:activate()
	window:perform_action(act.SetPaneZoomState(true), new_pane)
end

return {
	keys = {
		{
			key = "Enter",
			mods = "SHIFT",
			action = wezterm.action.SendString("\n"),
		},
		{
			-- workspaceの切り替え
			key = "w",
			mods = "LEADER",
			action = act.ShowLauncherArgs({ flags = "WORKSPACES", title = "Select workspace" }),
		},
		{
			--workspaceの名前変更
			key = "$",
			mods = "LEADER",
			action = act.PromptInputLine({
				description = "(wezterm) Set workspace title:",
				action = wezterm.action_callback(function(win, pane, line)
					if line then
						wezterm.mux.rename_workspace(wezterm.mux.get_active_workspace(), line)
					end
				end),
			}),
		},
		{
			key = "W",
			mods = "LEADER|SHIFT",
			action = act.PromptInputLine({
				description = "(wezterm) Create new workspace:",
				action = wezterm.action_callback(function(window, pane, line)
					if line then
						window:perform_action(
							act.SwitchToWorkspace({
								name = line,
							}),
							pane
						)
					end
				end),
			}),
		},
		-- コマンドパレット表示
		{ key = "p", mods = "SUPER", action = act.ActivateCommandPalette },
		-- Tab移動
		{ key = "Tab", mods = "CTRL", action = act.ActivateTabRelative(1) },
		{ key = "Tab", mods = "SHIFT|CTRL", action = act.ActivateTabRelative(-1) },
		-- Tab入れ替え
		{ key = "{", mods = "LEADER", action = act({ MoveTabRelative = -1 }) },
		-- Tab新規作成
		{ key = "t", mods = "SUPER", action = act({ SpawnTab = "CurrentPaneDomain" }) },
		-- ウィンドウ新規作成 (aerospace で別画面/ワークスペースに wezterm を並べる用)
		-- disable_default_key_bindings = true でデフォルトの Cmd+N が消えているため明示定義
		{ key = "n", mods = "SUPER", action = act.SpawnWindow },
		-- Tabを閉じる
		{ key = "w", mods = "SUPER", action = act({ CloseCurrentTab = { confirm = true } }) },
		{ key = "}", mods = "LEADER", action = act({ MoveTabRelative = 1 }) },

		-- 画面フルスクリーン切り替え
		{ key = "Enter", mods = "ALT", action = act.ToggleFullScreen },

		-- コピーモード
		-- { key = 'X', mods = 'LEADER', action = act.ActivateKeyTable{ name = 'copy_mode', one_shot =false }, },
		{ key = "[", mods = "LEADER", action = act.ActivateCopyMode },

		-- スクロール (コピーモードに入らず直接 / vimium 風)
		{ key = "j", mods = "SHIFT|CTRL", action = act.ScrollByLine(1) },
		{ key = "k", mods = "SHIFT|CTRL", action = act.ScrollByLine(-1) },
		{ key = "d", mods = "SHIFT|CTRL", action = act.ScrollByPage(0.5) },
		{ key = "u", mods = "SHIFT|CTRL", action = act.ScrollByPage(-0.5) },
		{ key = "g", mods = "SHIFT|CTRL", action = act.ScrollToBottom },
		-- コピー
		{ key = "c", mods = "SUPER", action = act.CopyTo("Clipboard") },
		-- 貼り付け
		{ key = "v", mods = "SUPER", action = act.PasteFrom("Clipboard") },

		-- Pane作成 leader + r or d
		{ key = "d", mods = "LEADER", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
		{ key = "r", mods = "LEADER", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
		-- 今いるペインの cwd で nvim をズーム表示 leader + e (詳細は上の open_editor_pane)
		{ key = "e", mods = "LEADER", action = wezterm.action_callback(open_editor_pane) },
		-- Claude Code のトランスクリプトモード切替。入力ソースを英数にしてから Ctrl+O を送る
		{ key = "o", mods = "CTRL", action = wezterm.action_callback(claude_transcript_toggle) },
		-- プロジェクト用のタブを開いて Herdr を起動 leader + A
		-- タブ名 = プロジェクト名 (Herdr の名前付きセッション名) として固定し、
		-- その中の左サイドバーに Claude Code / Codex のセッションを縦に並べる
		{
			key = "A",
			mods = "LEADER|SHIFT",
			action = act.PromptInputLine({
				description = "(herdr) Project / session name:",
				action = wezterm.action_callback(function(window, pane, line)
					if not line or line == "" then
						return
					end
					local cwd = pane:get_current_working_dir()
					local tab, new_pane = window:mux_window():spawn_tab({
						cwd = cwd and cwd.file_path or nil,
						-- ログインシェル経由で起動して PATH (~/.local/bin, homebrew) を引き継ぐ
						args = { "/bin/zsh", "-lic", "exec herdr session attach " .. line },
					})
					tab:set_title(line)
					new_pane:activate()
				end),
			}),
		},
		-- Paneを閉じる leader + x
		{ key = "x", mods = "LEADER", action = act({ CloseCurrentPane = { confirm = true } }) },
		-- Pane移動 leader + hlkj
		{ key = "h", mods = "LEADER", action = act.ActivatePaneDirection("Left") },
		{ key = "l", mods = "LEADER", action = act.ActivatePaneDirection("Right") },
		{ key = "k", mods = "LEADER", action = act.ActivatePaneDirection("Up") },
		{ key = "j", mods = "LEADER", action = act.ActivatePaneDirection("Down") },
		-- Pane選択
		{ key = "[", mods = "CTRL|SHIFT", action = act.PaneSelect },
		-- 選択中のPaneのみ表示
		{ key = "z", mods = "LEADER", action = act.TogglePaneZoomState },

		-- フォントサイズ切替
		{ key = "+", mods = "CTRL", action = act.IncreaseFontSize },
		{ key = "-", mods = "CTRL", action = act.DecreaseFontSize },
		-- フォントサイズのリセット
		{ key = "0", mods = "CTRL", action = act.ResetFontSize },

		-- タブ切替 Cmd + 数字
		{ key = "1", mods = "SUPER", action = act.ActivateTab(0) },
		{ key = "2", mods = "SUPER", action = act.ActivateTab(1) },
		{ key = "3", mods = "SUPER", action = act.ActivateTab(2) },
		{ key = "4", mods = "SUPER", action = act.ActivateTab(3) },
		{ key = "5", mods = "SUPER", action = act.ActivateTab(4) },
		{ key = "6", mods = "SUPER", action = act.ActivateTab(5) },
		{ key = "7", mods = "SUPER", action = act.ActivateTab(6) },
		{ key = "8", mods = "SUPER", action = act.ActivateTab(7) },
		{ key = "9", mods = "SUPER", action = act.ActivateTab(-1) },

		-- QuickSelect: 画面上のパス・URL・ハッシュ等をキーボードだけで選んでコピー
		{ key = "f", mods = "LEADER", action = act.QuickSelect },
		-- スクロールバック検索
		{ key = "/", mods = "LEADER", action = act.Search({ CaseInSensitiveString = "" }) },
		-- コマンドパレット
		{ key = "p", mods = "SHIFT|CTRL", action = act.ActivateCommandPalette },
		-- 設定再読み込み
		{ key = "r", mods = "SHIFT|CTRL", action = act.ReloadConfiguration },
		-- キーテーブル用
		{ key = "s", mods = "LEADER", action = act.ActivateKeyTable({ name = "resize_pane", one_shot = false }) },
		{
			key = "a",
			mods = "LEADER",
			action = act.ActivateKeyTable({ name = "activate_pane", timeout_milliseconds = 2000 }),
		},
	},
	-- キーテーブル
	-- https://wezfurlong.org/wezterm/config/key-tables.html
	key_tables = {
		-- Paneサイズ調整 leader + s
		resize_pane = {
			{ key = "h", action = act.AdjustPaneSize({ "Left", 1 }) },
			{ key = "l", action = act.AdjustPaneSize({ "Right", 1 }) },
			{ key = "k", action = act.AdjustPaneSize({ "Up", 1 }) },
			{ key = "j", action = act.AdjustPaneSize({ "Down", 1 }) },

			-- Cancel the mode by pressing escape
			{ key = "Enter", action = "PopKeyTable" },
		},
		activate_pane = {
			{ key = "h", action = act.ActivatePaneDirection("Left") },
			{ key = "l", action = act.ActivatePaneDirection("Right") },
			{ key = "k", action = act.ActivatePaneDirection("Up") },
			{ key = "j", action = act.ActivatePaneDirection("Down") },
		},
		-- copyモード leader + [
		copy_mode = {
			-- 移動
			{ key = "h", mods = "NONE", action = act.CopyMode("MoveLeft") },
			{ key = "j", mods = "NONE", action = act.CopyMode("MoveDown") },
			{ key = "k", mods = "NONE", action = act.CopyMode("MoveUp") },
			{ key = "l", mods = "NONE", action = act.CopyMode("MoveRight") },
			-- 最初と最後に移動
			{ key = "^", mods = "NONE", action = act.CopyMode("MoveToStartOfLineContent") },
			{ key = "$", mods = "NONE", action = act.CopyMode("MoveToEndOfLineContent") },
			-- 左端に移動
			{ key = "0", mods = "NONE", action = act.CopyMode("MoveToStartOfLine") },
			{ key = "o", mods = "NONE", action = act.CopyMode("MoveToSelectionOtherEnd") },
			{ key = "O", mods = "NONE", action = act.CopyMode("MoveToSelectionOtherEndHoriz") },
			--
			{ key = ";", mods = "NONE", action = act.CopyMode("JumpAgain") },
			-- 単語ごと移動
			{ key = "w", mods = "NONE", action = act.CopyMode("MoveForwardWord") },
			{ key = "b", mods = "NONE", action = act.CopyMode("MoveBackwardWord") },
			{ key = "e", mods = "NONE", action = act.CopyMode("MoveForwardWordEnd") },
			-- ジャンプ機能 t f
			{ key = "t", mods = "NONE", action = act.CopyMode({ JumpForward = { prev_char = true } }) },
			{ key = "f", mods = "NONE", action = act.CopyMode({ JumpForward = { prev_char = false } }) },
			{ key = "T", mods = "NONE", action = act.CopyMode({ JumpBackward = { prev_char = true } }) },
			{ key = "F", mods = "NONE", action = act.CopyMode({ JumpBackward = { prev_char = false } }) },
			-- 一番下へ
			{ key = "G", mods = "NONE", action = act.CopyMode("MoveToScrollbackBottom") },
			-- 一番上へ
			{ key = "g", mods = "NONE", action = act.CopyMode("MoveToScrollbackTop") },
			-- viweport
			{ key = "H", mods = "NONE", action = act.CopyMode("MoveToViewportTop") },
			{ key = "L", mods = "NONE", action = act.CopyMode("MoveToViewportBottom") },
			{ key = "M", mods = "NONE", action = act.CopyMode("MoveToViewportMiddle") },
			-- スクロール
			{ key = "b", mods = "CTRL", action = act.CopyMode("PageUp") },
			{ key = "f", mods = "CTRL", action = act.CopyMode("PageDown") },
			{ key = "d", mods = "CTRL", action = act.CopyMode({ MoveByPage = 0.5 }) },
			{ key = "u", mods = "CTRL", action = act.CopyMode({ MoveByPage = -0.5 }) },
			-- 検索
			{ key = "/", mods = "NONE", action = act.Search({ CaseSensitiveString = "" }) },
			{ key = "n", mods = "NONE", action = act.CopyMode("NextMatch") },
			{ key = "N", mods = "NONE", action = act.CopyMode("PriorMatch") },
			-- 範囲選択モード
			{ key = "v", mods = "NONE", action = act.CopyMode({ SetSelectionMode = "Cell" }) },
			{ key = "v", mods = "CTRL", action = act.CopyMode({ SetSelectionMode = "Block" }) },
			{ key = "V", mods = "NONE", action = act.CopyMode({ SetSelectionMode = "Line" }) },
			-- コピー
			{ key = "y", mods = "NONE", action = act.CopyTo("Clipboard") },

			-- コピーモードを終了
			{
				key = "Enter",
				mods = "NONE",
				action = act.Multiple({ { CopyTo = "ClipboardAndPrimarySelection" }, { CopyMode = "Close" } }),
			},
			{ key = "Escape", mods = "NONE", action = act.CopyMode("Close") },
			{ key = "c", mods = "CTRL", action = act.CopyMode("Close") },
			{ key = "q", mods = "NONE", action = act.CopyMode("Close") },
		},
		-- 検索モード (copy_mode の / や leader + / で入る)
		search_mode = {
			-- Enterで検索を確定して copy_mode に戻る (n / N でマッチ間を移動できる)
			{ key = "Enter", mods = "NONE", action = act.CopyMode("AcceptPattern") },
			{ key = "Escape", mods = "NONE", action = act.CopyMode("Close") },
			{ key = "n", mods = "CTRL", action = act.CopyMode("NextMatch") },
			{ key = "p", mods = "CTRL", action = act.CopyMode("PriorMatch") },
			-- 大文字小文字の区別 / 正規表現のトグル
			{ key = "r", mods = "CTRL", action = act.CopyMode("CycleMatchType") },
			-- 検索文字列をクリア
			{ key = "u", mods = "CTRL", action = act.CopyMode("ClearPattern") },
			{ key = "UpArrow", mods = "NONE", action = act.CopyMode("PriorMatch") },
			{ key = "DownArrow", mods = "NONE", action = act.CopyMode("NextMatch") },
		},
	},
}
