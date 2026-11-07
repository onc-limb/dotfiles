local wezterm = require("wezterm")
local config = wezterm.config_builder()

config.automatically_reload_config = true
-- 配色・透過は palette.lua に集約 (nvim からも同じファイルを読む)
local palette = require("palette")

-- Orca のターミナルと同じ SF Mono 14pt / 太さ 500。
-- SF Mono は Terminal.app の中にしか入っていないため、そのフォントフォルダを追加で読む。
-- アイコンは Symbols Nerd Font Mono、日本語はヒラギノで補う
config.font_dirs = { "/System/Applications/Utilities/Terminal.app/Contents/Resources/Fonts" }
config.font_size = 14.0
config.font = wezterm.font_with_fallback({
	{ family = "SF Mono", weight = "Medium" },
	"Symbols Nerd Font Mono",
	"Hiragino Sans",
	"Noto Sans CJK JP",
	"Noto Color Emoji",
})
config.use_ime = true
-- 背景を透かしてぼかす (nvim は背景を描画しないので同じ見た目になる)
config.window_background_opacity = palette.opacity
config.macos_window_background_blur = palette.blur
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

config.colors = {
	foreground = palette.fg,
	background = palette.bg,
	cursor_bg = palette.accent,
	cursor_fg = palette.accent_fg,
	cursor_border = palette.accent,
	selection_fg = palette.fg,
	selection_bg = palette.selection,
	ansi = palette.ansi,
	brights = palette.brights,
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

-- 下のタブバー: 右側にエージェントの状態・モデルとコンテキスト・利用制限・ワークスペース名 (statusbar.lua)
require("statusbar").setup(config)

wezterm.on("format-tab-title", function(tab, tabs, panes, config, hover, max_width)
	local background = palette.surface
	local foreground = palette.fg
	local edge_background = "none"
	if tab.is_active then
		background = palette.accent
		foreground = palette.accent_fg
	end
	local edge_foreground = background
	-- タブ名が明示的に設定されていればそれを優先 (LEADER+n の Herdr プロジェクトタブなど)。
	-- 未設定ならアクティブペインのタイトル (Claude Code のセッション名など)
	local name = tab.tab_title
	if not name or name == "" then
		name = tab.active_pane.title
	end
	local title = "   " .. wezterm.truncate_right(name, max_width - 1) .. "   "
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
