-- WezTerm と nvim で共有する配色 (ライト / ダーク + 背景透過)
-- nvim からも dofile で読むため、wezterm モジュールには依存しないこと。
-- bin/agent-dashboard も読む (M.light = { … } / M.dark = { … } の中の "#RRGGBB" を正規表現で拾う)。
--
-- どちらのモードを使うかは ~/.local/state/wezterm/theme (light / dark) に書く。LEADER+b で切り替える (theme.lua)。
-- 返すのは今のモードの配色 (mode にモード名が入る)
local M = {}

M.mode_file = (os.getenv("HOME") or "") .. "/.local/state/wezterm/theme"

-- ライト: 背景が透けても読めるよう、VSCode Light Modern より文字色を濃くし、ANSI 色も暗めに寄せている
M.light = {
	-- 背景のぼかし (WezTerm の macos_window_background_blur)
	blur = 30,

	-- 背景: 淡いパステルのグラデーションを重ね、その下にデスクトップをぼかして透かす。
	-- 文字の読みやすさを優先し、どの色も明度を高く・彩度を低くしている。
	-- opacity を下げるほど透ける (下げすぎると暗い壁紙で文字が読みにくくなる)
	background = {
		-- ベース: 左上の淡い青 → 右下の淡い桃
		base = { "#EEF4FF", "#F5F0FF", "#FFF3EE" },
		base_opacity = 0.86,
		-- 右上と左下にうっすら色を差して、平板に見えないようにする
		glow_top = "#DCEBFF",
		glow_bottom = "#FBE6F1",
		glow_opacity = 0.35,
	},

	fg = "#1F1F1F",
	bg = "#FFFFFF",
	-- 補助テキスト (コメント、薄い情報)
	muted = "#6E6E6E",
	-- アクセント (アクティブタブ、カーソル、選択中の要素)
	accent = "#005FB8",
	accent_fg = "#FFFFFF",
	-- 非アクティブのタブなど、背景から少し浮かせたい面
	surface = "#E6E6E6",
	-- タブバー: アクティブなタブの札 / ホバーしたタブ / 非アクティブなタブの文字
	accent_soft = "#D9E7FA",
	hover = "#ECEEF3",
	tab_fg = "#4A4A4A",
	selection = "#ADD6FF",

	-- 状態表示 (エージェントの状態、利用制限の残量)
	ok = "#0B7A0B",
	warn = "#9A6700",
	error = "#B3261E",

	ansi = {
		"#000000", -- black
		"#B3261E", -- red
		"#0B7A0B", -- green
		"#8A6D00", -- yellow
		"#0451A5", -- blue
		"#A0179E", -- magenta
		"#0A7A99", -- cyan
		"#4A4A4A", -- white (白背景で読めるよう暗色)
	},
	brights = {
		"#5C5C5C", -- bright black
		"#D0312D", -- bright red
		"#14A014", -- bright green
		"#A68600", -- bright yellow
		"#1A6FD1", -- bright blue
		"#BC05BC", -- bright magenta
		"#0598BC", -- bright cyan
		"#767676", -- bright white
	},
}

-- ダーク: 紺〜すみれ色の暗いグラデーション。ANSI 色は VSCode Dark Modern に近い明るめの色
M.dark = {
	blur = 30,

	background = {
		-- ベース: 左上の紺 → 右下の暗いすみれ色
		base = { "#121826", "#161628", "#1E1624" },
		base_opacity = 0.88,
		glow_top = "#1C3356",
		glow_bottom = "#3A1C3C",
		glow_opacity = 0.35,
	},

	fg = "#E4E4E4",
	bg = "#1E1E1E",
	muted = "#9A9DA6",
	accent = "#4C9BF0",
	accent_fg = "#0E1620",
	surface = "#3A3D45",
	accent_soft = "#22344E",
	hover = "#2C2F37",
	tab_fg = "#B8BCC6",
	selection = "#264F78",

	ok = "#5BC46A",
	warn = "#E2B341",
	error = "#F0605A",

	ansi = {
		"#3C3C3C", -- black (暗い背景で見えるよう少し明るく)
		"#F14C4C", -- red
		"#23D18B", -- green
		"#E5C07B", -- yellow
		"#3B8EEA", -- blue
		"#D670D6", -- magenta
		"#29B8DB", -- cyan
		"#CCCCCC", -- white
	},
	brights = {
		"#7A7A7A", -- bright black
		"#FF6B6B", -- bright red
		"#4BE0A0", -- bright green
		"#F5D78E", -- bright yellow
		"#6CB0FF", -- bright blue
		"#E591E5", -- bright magenta
		"#5FD0EC", -- bright cyan
		"#F2F2F2", -- bright white
	},
}

-- 今のモード (ファイルがなければライト)
function M.current_mode()
	local f = io.open(M.mode_file, "r")
	if not f then
		return "light"
	end
	local mode = (f:read("*l") or ""):gsub("%s+", "")
	f:close()
	return mode == "dark" and "dark" or "light"
end

local mode = M.current_mode()
local palette = M[mode]
palette.mode = mode
palette.mode_file = M.mode_file
return palette
