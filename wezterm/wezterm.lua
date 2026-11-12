local wezterm = require("wezterm")
local config = wezterm.config_builder()

config.automatically_reload_config = true
-- 配色とフォントは palette.lua に集約 (nvim からも同じファイルを読む)
local palette = require("palette")

-- 本文のフォントは配色パターンごとに決める (palette.lua の font。nvim・エージェントもこのフォントで描かれる)。
-- ダークでは一段細いウェイトにする。SF Mono は Terminal.app の中にしか入っていないため、そのフォントフォルダを追加で読む。
-- アイコンは Symbols Nerd Font Mono、日本語はヒラギノで補う
config.font_dirs = { "/System/Applications/Utilities/Terminal.app/Contents/Resources/Fonts" }
config.font_size = 14.0
config.font = wezterm.font_with_fallback({
	{ family = palette.font.family, weight = palette.font.weight },
	"Symbols Nerd Font Mono",
	"Hiragino Sans",
	"Noto Sans CJK JP",
	"Noto Color Emoji",
})
-- 文字の輪郭: ヒンティング (輪郭を画素の格子に合わせる処理) を弱め、縦方向だけにする。
-- 既定の強いヒンティングは、暗い背景の明るい文字で段差 (ガタガタ) が目立つ
config.freetype_load_target = "Light"
-- さらにヒンティングを切り、macOS のアプリと同じく輪郭をそのままなめらかに描く
-- (タブバーの UI フォントが滑らかに見えるのと同じ描き方)
config.freetype_load_flags = "NO_HINTING"
config.use_ime = true
-- 背景は透過させずに塗りつぶす (デスクトップアプリ風)。配色は LEADER+Shift+b、ライト / ダークは LEADER+b (theme.lua)
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
	-- カーソルと、日本語入力の変換中の文字の下地 (同じ色で描かれる)。
	-- 差し色そのままだと濃すぎて文字が読みにくいので、本文の背景に寄せて薄める
	cursor_bg = palette.cursor,
	cursor_fg = palette.fg,
	cursor_border = palette.cursor,
	compose_cursor = palette.cursor,
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
	require("tabs").refresh(window)
	workspace.ensure_dashboard(window)
	workspace.ensure_agent_shown(window)
	workspace.cleanup_agents()
	session.save()
end)

-- 作業環境の nvim がファイルを開いた / 閉じたら (user var workbench_layout)、すぐに右のエージェントの幅を合わせる
wezterm.on("user-var-changed", function(_, pane, name)
	if name == "workbench_layout" then
		local tab = pane:tab()
		if tab then
			workspace.sync_agents(tab)
			workspace.apply_layout(tab)
		end
	end
end)

-- タブの見た目 (紫系統の一系統: アクティブなタブはその色の札、名前は リポジトリ名 と ブランチ) は tabs.lua
require("tabs").setup(config)

----------------------------------------------------
-- keybinds
----------------------------------------------------
config.disable_default_key_bindings = true
config.keys = require("keybinds").keys
config.key_tables = require("keybinds").key_tables
config.mouse_bindings = require("keybinds").mouse_bindings
config.leader = { key = "q", mods = "CTRL", timeout_milliseconds = 2000 }

return config
