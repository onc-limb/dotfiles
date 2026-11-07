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
-- 背景は透過させずに塗りつぶす (デスクトップアプリ風)。ライト / ダークは LEADER+b で切り替える (theme.lua)
require("theme").setup(config)
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
	split = palette.border,
}
-- 下のタブバー: 左端にワークスペース名、右側にエージェントの状態・モデルとコンテキスト・利用制限 (statusbar.lua)
-- 更新のついでに、ワークスペースにエージェント一覧タブ・エージェントの状態カードがなければ作り、
-- タブを閉じて取り残されたエージェントを止め (workspace.lua)、
-- 構成が変わっていれば復旧用に保存する (session.lua)
local workspace = require("workspace")
local session = require("session")
session.setup()
require("statusbar").setup(config, function(window)
	if wezterm.GLOBAL.session_restoring then
		return
	end
	workspace.ensure_dashboard(window)
	workspace.ensure_sidebars(window)
	workspace.cleanup_agents()
	session.save()
end)

-- タブの見た目 (アクティブなタブは淡いアクセント色の丸い札、名前は リポジトリ名 と ブランチ) は tabs.lua
require("tabs").setup(config)

----------------------------------------------------
-- keybinds
----------------------------------------------------
config.disable_default_key_bindings = true
config.keys = require("keybinds").keys
config.key_tables = require("keybinds").key_tables
config.leader = { key = "q", mods = "CTRL", timeout_milliseconds = 2000 }

return config
