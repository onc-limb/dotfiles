-- WezTerm と nvim で共有する配色 (ライト基調 + 背景透過)
-- nvim からも dofile で読むため、wezterm モジュールには依存しないこと。
-- 背景が透けても読めるよう、VSCode Light Modern より文字色を濃くし、ANSI 色も暗めに寄せている
return {
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
