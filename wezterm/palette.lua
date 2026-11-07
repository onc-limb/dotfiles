-- WezTerm と nvim で共有する配色 (ライト基調 + 背景透過)
-- nvim からも dofile で読むため、wezterm モジュールには依存しないこと。
-- 背景が透けても読めるよう、VSCode Light Modern より文字色を濃くし、ANSI 色も暗めに寄せている
return {
	-- 透過の度合い (WezTerm の window_background_opacity)
	opacity = 0.82,
	blur = 20,

	fg = "#1F1F1F",
	bg = "#FFFFFF",
	-- 補助テキスト (コメント、薄い情報)
	muted = "#6E6E6E",
	-- アクセント (アクティブタブ、カーソル、選択中の要素)
	accent = "#005FB8",
	accent_fg = "#FFFFFF",
	-- 非アクティブのタブなど、背景から少し浮かせたい面
	surface = "#E6E6E6",
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
