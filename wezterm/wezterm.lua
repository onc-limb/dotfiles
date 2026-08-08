local wezterm = require("wezterm")
local config = wezterm.config_builder()

config.automatically_reload_config = true
config.font_size = 18.0
config.font = wezterm.font_with_fallback({
	"FiraCode Nerd Font",
	"Hiragino Sans",
	"Noto Sans CJK JP",
	"Noto Color Emoji",
})

config.use_ime = true
-- 通常時は背景を透過してデスクトップ壁紙 (明るめの白・青系) を見せる
-- (nvim 中は user-var-changed で不透過 #FFFFFF に切り替わる。下の nvim 連携を参照)
config.window_background_opacity = 0.50
config.macos_window_background_blur = 20
config.audible_bell = "SystemBeep"
config.scrollback_lines = 10000

-- 非アクティブペインを少し淡くして視線を誘導
config.inactive_pane_hsb = { saturation = 0.85, brightness = 0.92 }

----------------------------------------------------
-- Tab
----------------------------------------------------
-- タイトルバーを非表示
config.window_decorations = "RESIZE"
-- タブバーの表示
config.show_tabs_in_tab_bar = true
-- タブが一つの時は非表示
config.hide_tab_bar_if_only_one_tab = false
-- falseにするとタブバーの透過が効かなくなる
config.use_fancy_tab_bar = false

-- タブの追加ボタンを非表示
config.show_new_tab_button_in_tab_bar = false

-- VSCode Light Modern のカラーパレット
config.colors = {
	foreground = "#3B3B3B",
	background = "#FFFFFF",
	cursor_bg = "#005FB8",
	cursor_fg = "#FFFFFF",
	cursor_border = "#005FB8",
	selection_fg = "#3B3B3B",
	selection_bg = "#ADD6FF",

	ansi = {
		"#000000", -- black
		"#CD3131", -- red
		"#00BC00", -- green
		"#949800", -- yellow
		"#0451A5", -- blue
		"#BC05BC", -- magenta
		"#0598BC", -- cyan
		"#555555", -- white
	},
	brights = {
		"#666666", -- bright black
		"#CD3131", -- bright red
		"#14CE14", -- bright green
		"#B5BA00", -- bright yellow
		"#0451A5", -- bright blue
		"#BC05BC", -- bright magenta
		"#0598BC", -- bright cyan
		"#8C8C8C", -- bright white (VSCode 定義は #A5A5A5 だが白背景で読めるよう暗色化)
	},

	tab_bar = {
		background = "none",
		inactive_tab_edge = "none",
	},
}

----------------------------------------------------
-- nvim 連携: nvim 中だけ VSCode Light Modern の見た目にする
----------------------------------------------------
-- nvim 側 (init.lua) が SetUserVar で IS_NVIM=true/false を送ってくる。
-- ターミナル通常時 (シェル/Claude Code) は透過 + 壁紙のデザイン、
-- nvim 中は VSCode のエディタと同じ不透過 #FFFFFF + 小さめフォントに切り替える。
-- 制約: どちらもウィンドウ単位のため、同じウィンドウの別ペインも一緒に切り替わる
local NVIM_FONT_SIZE = 14.0

wezterm.on("user-var-changed", function(window, pane, name, value)
	if name ~= "IS_NVIM" then
		return
	end
	local overrides = window:get_config_overrides() or {}
	if value == "true" then
		overrides.font_size = NVIM_FONT_SIZE
		overrides.window_background_opacity = 1.0
		overrides.macos_window_background_blur = 0
	else
		overrides.font_size = nil
		overrides.window_background_opacity = nil
		overrides.macos_window_background_blur = nil
	end
	window:set_config_overrides(overrides)
end)

-- タブの形をカスタマイズ
-- タブの左側の装飾
local SOLID_LEFT_ARROW = wezterm.nerdfonts.ple_left_half_circle_thick
-- タブの右側の装飾
local SOLID_RIGHT_ARROW = wezterm.nerdfonts.ple_right_half_circle_thick

-- 右上ステータス: ワークスペース名（黒いタブ風） + キーテーブル / leader 状態 + 時間帯絵文字 + 時刻
wezterm.on("update-right-status", function(window, pane)
	local workspace = window:active_workspace()
	local date = wezterm.strftime("%H:%M")
	local hour = tonumber(wezterm.strftime("%H"))
	local mood = "☕"
	if hour >= 6 and hour < 11 then
		mood = "🌅"
	elseif hour >= 11 and hour < 17 then
		mood = "☀️"
	elseif hour >= 17 and hour < 21 then
		mood = "🌇"
	else
		mood = "🌙"
	end

	-- アクティブなキーテーブル名 > LEADER の優先順で表示
	local mode = ""
	local key_table = window:active_key_table()
	if key_table then
		mode = " TABLE: " .. key_table .. " "
	elseif window:leader_is_active() then
		mode = " LEADER "
	end
	window:set_left_status("")
	window:set_right_status(wezterm.format({
		{ Foreground = { Color = "#000000" } },
		{ Text = SOLID_LEFT_ARROW },
		{ Background = { Color = "#000000" } },
		{ Foreground = { Color = "#FFFFFF" } },
		{ Text = " " .. workspace .. " " },
		"ResetAttributes",
		{ Foreground = { Color = "#000000" } },
		{ Text = SOLID_RIGHT_ARROW .. " " },
		{ Foreground = { Color = "#005FB8" } },
		{ Text = mode },
		{ Foreground = { Color = "#616161" } },
		{ Text = mood .. "  " .. date .. "  " },
	}))
end)

wezterm.on("format-tab-title", function(tab, tabs, panes, config, hover, max_width)
	local background = "#ECECEC"
	local foreground = "#3B3B3B"
	local edge_background = "none"
	if tab.is_active then
		background = "#005FB8"
		foreground = "#FFFFFF"
	end
	local edge_foreground = background
	local title = "   " .. wezterm.truncate_right(tab.active_pane.title, max_width - 1) .. "   "
	return {
		{ Background = { Color = edge_background } },
		{ Foreground = { Color = edge_foreground } },
		{ Text = SOLID_LEFT_ARROW },
		{ Background = { Color = background } },
		{ Foreground = { Color = foreground } },
		{ Text = title },
		{ Background = { Color = edge_background } },
		{ Foreground = { Color = edge_foreground } },
		{ Text = SOLID_RIGHT_ARROW },
	}
end)

----------------------------------------------------
-- keybinds
----------------------------------------------------
config.disable_default_key_bindings = true
config.keys = require("keybinds").keys
config.key_tables = require("keybinds").key_tables
config.leader = { key = "q", mods = "CTRL", timeout_milliseconds = 2000 }

return config
