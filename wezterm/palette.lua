-- WezTerm と nvim で共有する配色 (ライト / ダーク)
-- nvim からも dofile で読むため、wezterm モジュールには依存しないこと。
-- bin/agent-dashboard も読む (M.light = { … } / M.dark = { … } の中の "#RRGGBB" を正規表現で拾う)。
--
-- ターミナルらしさを抑え、普通のデスクトップアプリのように見せる:
--   背景は透過させずに塗りつぶし、タブバーや nvim のツリーは本文より一段沈んだ色 (chrome) にする。
-- 色合いは少しレトロに: ライトは古い紙のクリーム色、ダークは焦げ茶がかった炭色を地にして、
--   ティール・からし色・れんが色・オリーブを差し色にする (どれも彩度を抑えめ)。
--
-- どちらのモードを使うかは ~/.local/state/wezterm/theme (light / dark) に書く。LEADER+b で切り替える (theme.lua)。
-- 返すのは今のモードの配色 (mode にモード名が入る)
local M = {}

M.mode_file = (os.getenv("HOME") or "") .. "/.local/state/wezterm/theme"

M.light = {
	-- 本文の背景 / 文字
	bg = "#F4EFE4",
	fg = "#2F2A23",
	-- タブバー・ツリーなど、本文より一段沈んだ面
	chrome = "#E6DECD",
	-- ペインの区切り線
	border = "#D2C7B1",
	-- 補助テキスト (コメント、薄い情報)
	muted = "#7D7466",
	-- アクセント (アクティブタブ、カーソル、選択中の要素): レトロなティール
	accent = "#2E6E70",
	accent_fg = "#FBF7EE",
	-- 非アクティブのタブなど、背景から少し浮かせたい面
	surface = "#E2D9C6",
	-- タブバー: アクティブなタブの札 / ホバーしたタブ / 非アクティブなタブの文字
	accent_soft = "#F4EFE4",
	hover = "#EDE6D7",
	tab_fg = "#5A5245",
	selection = "#EBD9A4",

	-- 状態表示 (エージェントの状態、利用制限の残量)
	ok = "#557A35",
	warn = "#B0701A",
	error = "#B04330",

	ansi = {
		"#2F2A23", -- black
		"#B04330", -- red (れんが色)
		"#557A35", -- green (オリーブ)
		"#9A7212", -- yellow (からし色)
		"#2F5E88", -- blue
		"#8A4A78", -- magenta
		"#2E6E70", -- cyan (ティール)
		"#6B6255", -- white (明るい背景で読めるよう暗色)
	},
	brights = {
		"#7D7466", -- bright black
		"#C9573F", -- bright red
		"#6A9045", -- bright green
		"#B5861E", -- bright yellow
		"#4275A4", -- bright blue
		"#A35E90", -- bright magenta
		"#3D8A8C", -- bright cyan
		"#8F8676", -- bright white
	},

	-- nvim (vscode.nvim の color_overrides)。構文の色もレトロな差し色に寄せる
	nvim = {
		vscBack = "#F4EFE4",
		vscFront = "#2F2A23",
		vscTabCurrent = "#F4EFE4",
		vscTabOther = "#E6DECD",
		vscTabOutside = "#E6DECD",
		vscLeftDark = "#D9D0BD",
		vscLeftMid = "#E6DECD",
		vscLeftLight = "#ECE5D6",
		vscPopupBack = "#ECE5D6",
		vscPopupFront = "#2F2A23",
		vscPopupHighlightBlue = "#CFE0D9",
		vscPopupHighlightGray = "#DCD3C1",
		vscSplitLight = "#E6DECD",
		vscSplitDark = "#D2C7B1",
		vscSplitThumb = "#D2C7B1",
		vscCursorDarkDark = "#EBE4D4",
		vscCursorDark = "#7D7466",
		vscCursorLight = "#7D7466",
		vscSelection = "#EBD9A4",
		vscLineNumber = "#A69C8A",
		vscContext = "#DCD3C1",
		vscContextCurrent = "#A69C8A",
		vscFoldBackground = "#E9E3D2",
		vscSuggestion = "#A69C8A",
		vscGray = "#7D7466",
		vscViolet = "#6B4F8A",
		vscBlue = "#2F5E88",
		vscDarkBlue = "#2E6E70",
		vscLightBlue = "#3D5F7A",
		vscGreen = "#7D7466",
		vscBlueGreen = "#2E6E70",
		vscLightGreen = "#557A35",
		vscRed = "#B04330",
		vscOrange = "#A1501F",
		vscLightRed = "#B04330",
		vscYellowOrange = "#9A7212",
		vscYellow = "#8A6410",
		vscDarkYellow = "#B5861E",
		vscPink = "#8A4A78",
	},
}

M.dark = {
	bg = "#26221D",
	fg = "#E9E1D1",
	chrome = "#1D1A16",
	border = "#3B352D",
	muted = "#9E9483",
	accent = "#72B5A9",
	accent_fg = "#1B1915",
	surface = "#3A342C",
	accent_soft = "#26221D",
	hover = "#2B2721",
	tab_fg = "#BFB5A3",
	selection = "#4D4433",

	ok = "#A3C173",
	warn = "#E2AA4E",
	error = "#E2735C",

	ansi = {
		"#3A342C", -- black (暗い背景で見えるよう少し明るく)
		"#E2735C", -- red
		"#A3C173", -- green
		"#E2B65C", -- yellow
		"#82A8CF", -- blue
		"#C993BA", -- magenta
		"#72B5A9", -- cyan
		"#D9D0C0", -- white
	},
	brights = {
		"#7F7567", -- bright black
		"#F08A72", -- bright red
		"#B8D68B", -- bright green
		"#F2CA7A", -- bright yellow
		"#9FBFE0", -- bright blue
		"#DDAACD", -- bright magenta
		"#8DCABF", -- bright cyan
		"#F3ECDE", -- bright white
	},

	nvim = {
		vscBack = "#26221D",
		vscFront = "#E9E1D1",
		vscTabCurrent = "#26221D",
		vscTabOther = "#1D1A16",
		vscTabOutside = "#1D1A16",
		vscLeftDark = "#1D1A16",
		vscLeftMid = "#2E2923",
		vscLeftLight = "#5A5247",
		vscPopupBack = "#2E2923",
		vscPopupFront = "#E9E1D1",
		vscPopupHighlightBlue = "#33504B",
		vscPopupHighlightGray = "#3A342C",
		vscSplitLight = "#5A5247",
		vscSplitDark = "#3B352D",
		vscSplitThumb = "#3B352D",
		vscCursorDarkDark = "#2E2923",
		vscCursorDark = "#5A5247",
		vscCursorLight = "#BFB5A3",
		vscSelection = "#4D4433",
		vscLineNumber = "#6B6254",
		vscContext = "#3B352D",
		vscContextCurrent = "#6B6254",
		vscFoldBackground = "#2E2B25",
		vscSuggestion = "#6B6254",
		vscGray = "#9E9483",
		vscViolet = "#A58FC2",
		vscBlue = "#82A8CF",
		vscDarkBlue = "#33504B",
		vscLightBlue = "#B9CBDA",
		vscGreen = "#8E8574",
		vscBlueGreen = "#72B5A9",
		vscLightGreen = "#A3C173",
		vscRed = "#E2735C",
		vscOrange = "#D9956A",
		vscLightRed = "#E2735C",
		vscYellowOrange = "#E2B65C",
		vscYellow = "#E6C98A",
		vscDarkYellow = "#F2CA7A",
		vscPink = "#C993BA",
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
