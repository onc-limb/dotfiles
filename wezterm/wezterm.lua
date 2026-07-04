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
config.window_background_opacity = 1.0
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

-- エディタ背景 #FFFFFF、パネル背景 #F8F8F8 (VSCode Light Modern) の淡いグラデーション
config.window_background_gradient = {
	orientation = { Linear = { angle = -45.0 } },
	colors = { "#FFFFFF", "#F8F8F8" },
	interpolation = "Linear",
	blend = "Rgb",
}

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

-- タブの形をカスタマイズ
-- タブの左側の装飾
local SOLID_LEFT_ARROW = wezterm.nerdfonts.ple_left_half_circle_thick
-- タブの右側の装飾
local SOLID_RIGHT_ARROW = wezterm.nerdfonts.ple_right_half_circle_thick

-- 左上ステータス: 現在のワークスペース名
wezterm.on("update-status", function(window, pane)
	local workspace = window:active_workspace()
	window:set_left_status(wezterm.format({
		{ Background = { Color = "#005FB8" } },
		{ Foreground = { Color = "#FFFFFF" } },
		{ Text = "  " .. wezterm.nerdfonts.cod_terminal_bash .. "  " .. workspace .. "  " },
	}))
end)

-- 右下ステータス: キーテーブル / leader 状態 + 時間帯絵文字 + 時刻
wezterm.on("update-right-status", function(window, pane)
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
	window:set_right_status(wezterm.format({
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
