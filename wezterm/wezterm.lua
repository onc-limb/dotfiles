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

-- タブバーを背景色に合わせつつ、ほんのり暖色グラデーションをかける
config.window_background_gradient = {
	orientation = { Linear = { angle = -45.0 } },
	colors = { "#FAFAFA", "#F4EFE8" },
	interpolation = "Linear",
	blend = "Rgb",
}

-- タブの追加ボタンを非表示
config.show_new_tab_button_in_tab_bar = false

-- Zed One Light 風のカラーパレット
config.colors = {
	foreground = "#383A42",
	background = "#FAFAFA",
	cursor_bg = "#526EFF",
	cursor_fg = "#FAFAFA",
	cursor_border = "#526EFF",
	selection_fg = "#383A42",
	selection_bg = "#D4D7DA",

	ansi = {
		"#1A1A1A", -- black
		"#CA1243", -- red
		"#3E8A3D", -- green
		"#A26B00", -- yellow
		"#0033B3", -- blue
		"#851A82", -- magenta
		"#006B99", -- cyan
		"#383A42", -- white (背景に対して読めるよう暗色化)
	},
	brights = {
		"#4F525E", -- bright black
		"#E45649", -- bright red
		"#50A14F", -- bright green
		"#C18401", -- bright yellow
		"#1851E0", -- bright blue
		"#A626A4", -- bright magenta
		"#0184BC", -- bright cyan
		"#4F525E", -- bright white (背景に対して読めるよう暗色化)
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

-- 右下ステータス: leader 状態 + 時間帯絵文字 + 時刻
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

	local leader = window:leader_is_active() and " LEADER " or ""
	window:set_right_status(wezterm.format({
		{ Foreground = { Color = "#CC7722" } },
		{ Text = leader },
		{ Foreground = { Color = "#4F525E" } },
		{ Text = mood .. "  " .. date .. "  " },
	}))
end)

wezterm.on("format-tab-title", function(tab, tabs, panes, config, hover, max_width)
	local background = "#E5E5E6"
	local foreground = "#383A42"
	local edge_background = "none"
	if tab.is_active then
		background = "#CC7722"
		foreground = "#1a1b26"
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
