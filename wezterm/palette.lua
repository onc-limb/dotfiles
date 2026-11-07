-- WezTerm と nvim で共有する配色 (配色パターン × ライト / ダーク)
-- nvim からも dofile で読むため、wezterm モジュールには依存しないこと (純粋な Lua だけで書く)。
-- bin/agent-dashboard は WezTerm が書き出す ~/.local/state/wezterm/palette.json を読む (theme.lua)。
--
-- ターミナルらしさを抑え、普通のデスクトップアプリのように見せる:
--   背景は透過させずに塗りつぶし、タブバーや nvim のツリーは本文より一段沈んだ色 (chrome)、
--   カードは一段浮いた色 (card) にする。
--
-- 状態ファイル (~/.local/state/wezterm/):
--   scheme : 配色パターンの id (instrument / aviation / thermal。既定は aviation)
--   theme  : light / dark (既定は dark)
-- LEADER+Shift+b でパターンとモードの 6 通りから選び、LEADER+b でライト / ダークだけを切り替える
-- 返すのは今の配色 (scheme / mode に名前が入る)
local M = {}

local STATE_DIR = (os.getenv("HOME") or "") .. "/.local/state/wezterm"
M.mode_file = STATE_DIR .. "/theme"
M.scheme_file = STATE_DIR .. "/scheme"
M.default_scheme = "aviation"
M.default_mode = "dark"

-- 配色パターン。font は本文のフォント (WezTerm の中で動く nvim・エージェントも同じフォントになる)。
-- 各モードの色:
--   bg 本文 / chrome 沈んだ面 (タブバー・ツリー) / card 浮いた面 (カード) / fg 文字 / muted 補助の文字 /
--   accent 差し色 / accent_fg 差し色の上の文字 / accent_text 文字に使う差し色 (省略時は accent) /
--   border 区切り線 / sel 選択範囲 / ok warn err 状態 /
--   kw str fn num com 構文 (キーワード・文字列・関数・数値・コメント) / blue magenta cyan ANSI の残りの色
M.order = { "instrument", "aviation", "thermal" }

M.schemes = {
	instrument = {
		label = "Instrument  計測器 (グレーの筐体に安全色のオレンジ)",
		-- 本文のフォント (nvim もこのフォントで描かれる)。weight はライト / ダークで変える (下の build を参照)
		font = { family = "SF Mono", light = "Medium", dark = "Regular" },
		light = { bg = "#EEEEEA", chrome = "#DADAD4", card = "#FAFAF7", fg = "#141414", muted = "#6A6A64", accent = "#FF4F00", accent_fg = "#FFFFFF", accent_text = "#D94300", border = "#C7C7C0", sel = "#FFD8C2", ok = "#2D7A3E", warn = "#B87400", err = "#D62A1E", kw = "#0B57D0", str = "#2D7A3E", fn = "#D9480F", num = "#7A3EC8", com = "#8A8A84", blue = "#0B57D0", magenta = "#7A3EC8", cyan = "#0F7C8C" },
		dark = { bg = "#161718", chrome = "#0E0F10", card = "#202123", fg = "#EDEDE8", muted = "#8C8C86", accent = "#FF6A1A", accent_fg = "#111111", border = "#2C2D2F", sel = "#4A2A18", ok = "#5FD38A", warn = "#FFB224", err = "#FF5A4E", kw = "#7AA7FF", str = "#8BD69B", fn = "#FF8A4C", num = "#C9A2FF", com = "#6E6E6A", blue = "#7AA7FF", magenta = "#C9A2FF", cyan = "#5CC8D6" },
	},
	aviation = {
		label = "Aviation    航空計器 (黒い計器盤にマゼンタと緑)",
		font = { family = "JetBrains Mono", light = "Medium", dark = "Regular" },
		light = { bg = "#EEF1F3", chrome = "#DCE2E6", card = "#FBFCFD", fg = "#0F1418", muted = "#5E6B74", accent = "#D6006E", accent_fg = "#FFFFFF", border = "#C5CED4", sel = "#F9CFE3", ok = "#128A55", warn = "#A86A00", err = "#C62828", kw = "#0069A8", str = "#128A55", fn = "#D6006E", num = "#A86A00", com = "#84919A", blue = "#0069A8", magenta = "#D6006E", cyan = "#00838F" },
		dark = { bg = "#0F1418", chrome = "#090D10", card = "#182026", fg = "#E3EAEE", muted = "#7F8E98", accent = "#FF3D9A", accent_fg = "#0F1418", border = "#22303A", sel = "#3A1B2E", ok = "#39D98A", warn = "#FFC247", err = "#FF5252", kw = "#5CC8FF", str = "#39D98A", fn = "#FF7AB8", num = "#FFC247", com = "#5E6E78", blue = "#5CC8FF", magenta = "#FF7AB8", cyan = "#4DD9E8" },
	},
	thermal = {
		label = "Thermal     サーモグラフィ (紫から橙の熱の色)",
		font = { family = "FiraCode Nerd Font Mono", light = "Medium", dark = "Regular" },
		light = { bg = "#F4F2F7", chrome = "#E3DFEA", card = "#FDFCFE", fg = "#17121F", muted = "#6B6478", accent = "#E05A00", accent_fg = "#FFFFFF", border = "#D2CCDB", sel = "#FFE0C2", ok = "#137A5A", warn = "#A87A00", err = "#D11A2A", kw = "#6A35C9", str = "#A87A00", fn = "#E05A00", num = "#C21858", com = "#8A8396", blue = "#3D4FC9", magenta = "#C21858", cyan = "#0F7C8C" },
		dark = { bg = "#110E19", chrome = "#0A0810", card = "#1C1726", fg = "#ECE6F2", muted = "#8C8499", accent = "#FF7A00", accent_fg = "#110E19", border = "#262036", sel = "#3D2414", ok = "#57D9A3", warn = "#FFC800", err = "#FF3B3B", kw = "#B07CFF", str = "#FFC800", fn = "#FF7A00", num = "#FF3B6E", com = "#625A70", blue = "#7C8CFF", magenta = "#FF5BA0", cyan = "#5CD6E0" },
	},
}

----------------------------------------------------
-- 色の計算
----------------------------------------------------

local function rgb(hex)
	return tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16)
end

-- a と b を t (0..1) の割合で混ぜる
local function mix(a, b, t)
	local r1, g1, b1 = rgb(a)
	local r2, g2, b2 = rgb(b)
	local function ch(x, y)
		return math.floor(x + (y - x) * t + 0.5)
	end
	return string.format("#%02X%02X%02X", ch(r1, r2), ch(g1, g2), ch(b1, b2))
end
M.mix = mix

-- パターンの色から、WezTerm / nvim / 一覧タブが使う色をすべて組み立てる
function M.build(c, mode)
	local dark = mode == "dark"
	local p = {
		mode = mode,
		bg = c.bg,
		fg = c.fg,
		chrome = c.chrome,
		card = c.card,
		border = c.border,
		muted = c.muted,
		accent = c.accent,
		accent_fg = c.accent_fg,
		accent_text = c.accent_text or c.accent,
		-- カーソル・変換中の文字の下地: 差し色を背景に寄せて薄めた色
		cursor = mix(c.accent, c.bg, dark and 0.45 or 0.6),
		selection = c.sel,
		ok = c.ok,
		warn = c.warn,
		error = c.err,
		-- メーターの空き・キーの札など、背景から少し浮かせたい面
		surface = mix(c.card, c.fg, 0.12),
		-- タブバー: アクティブなタブの札は本文と同じ色 / ホバー / 非アクティブなタブの文字
		accent_soft = c.bg,
		hover = mix(c.chrome, c.fg, 0.07),
		tab_fg = mix(c.fg, c.chrome, 0.3),
	}
	-- ANSI 色。明るい版は、ダークでは白に、ライトでは黒に少し寄せる
	local toward = dark and "#FFFFFF" or "#000000"
	local base = {
		dark and mix(c.bg, c.fg, 0.18) or c.fg,
		c.err,
		c.ok,
		c.warn,
		c.blue,
		c.magenta,
		c.cyan,
		dark and mix(c.fg, c.bg, 0.12) or mix(c.fg, c.bg, 0.45),
	}
	p.ansi, p.brights = {}, {}
	for i, col in ipairs(base) do
		p.ansi[i] = col
		p.brights[i] = mix(col, toward, dark and 0.22 or 0.12)
	end
	p.brights[1] = c.muted
	p.brights[8] = dark and mix(c.fg, "#FFFFFF", 0.5) or mix(c.fg, c.bg, 0.3)

	-- nvim (vscode.nvim の color_overrides)
	p.nvim = {
		vscBack = c.bg,
		vscFront = c.fg,
		vscTabCurrent = c.bg,
		vscTabOther = c.chrome,
		vscTabOutside = c.chrome,
		vscLeftDark = c.chrome,
		vscLeftMid = mix(c.chrome, c.fg, 0.06),
		vscLeftLight = mix(c.chrome, c.fg, 0.3),
		vscPopupBack = c.card,
		vscPopupFront = c.fg,
		vscPopupHighlightBlue = c.sel,
		vscPopupHighlightGray = mix(c.card, c.fg, 0.1),
		vscSplitLight = c.border,
		vscSplitDark = c.border,
		vscSplitThumb = c.border,
		vscCursorDarkDark = mix(c.bg, c.fg, 0.05),
		vscCursorDark = c.muted,
		vscCursorLight = c.muted,
		vscSelection = c.sel,
		vscLineNumber = mix(c.muted, c.bg, 0.25),
		vscContext = c.border,
		vscContextCurrent = c.muted,
		vscFoldBackground = mix(c.bg, c.fg, 0.05),
		vscSuggestion = c.muted,
		vscGray = c.muted,
		vscViolet = c.magenta,
		vscBlue = c.kw,
		vscPink = c.kw,
		vscAccentBlue = c.accent_text or c.accent,
		vscMediumBlue = c.accent_text or c.accent,
		vscDarkBlue = c.sel,
		vscDisabledBlue = c.muted,
		vscLightBlue = mix(c.fg, c.cyan, 0.35),
		vscBlueGreen = c.cyan,
		vscGreen = c.com,
		vscLightGreen = c.num,
		vscRed = c.err,
		vscLightRed = c.err,
		vscOrange = c.str,
		vscYellowOrange = c.str,
		vscYellow = c.fn,
		vscDarkYellow = c.warn,
	}
	return p
end

----------------------------------------------------
-- 今の配色
----------------------------------------------------

local function read_line(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local line = (f:read("*l") or ""):gsub("%s+", "")
	f:close()
	return line
end

function M.current_mode()
	local mode = read_line(M.mode_file)
	if mode == "light" or mode == "dark" then
		return mode
	end
	return M.default_mode
end

function M.current_scheme()
	local id = read_line(M.scheme_file)
	return M.schemes[id or ""] and id or M.default_scheme
end

local scheme, mode = M.current_scheme(), M.current_mode()
local palette = M.build(M.schemes[scheme][mode], mode)
palette.scheme = scheme
-- 暗い背景の明るい文字は太って滲んで見えやすいので、ダークでは一段細いウェイトにする
palette.font = { family = M.schemes[scheme].font.family, weight = M.schemes[scheme].font[mode] }
palette.mode_file = M.mode_file
palette.scheme_file = M.scheme_file
palette.schemes = M.schemes
palette.order = M.order
return palette
