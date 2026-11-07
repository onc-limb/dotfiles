-- 背景のプリセットと切り替え (LEADER+b)
--
-- どのプリセットも、淡いグラデーションを重ねて下のデスクトップをぼかして透かす。
-- 文字の読みやすさを優先し、どの色も明度を高く・彩度を低くしている (配色はライト基調)。
-- 選んだプリセットは ~/.local/state/wezterm/background に保存し、次の起動でも使う。
-- 画像を使うときは ~/.config/wezterm/wallpaper.(jpg|png) を置く (白を重ねて文字を読めるようにする)
local wezterm = require("wezterm")
local palette = require("palette")

local M = {}

M.state_path = wezterm.home_dir .. "/.local/state/wezterm/background"
M.wallpaper_candidates = {
	wezterm.home_dir .. "/.config/wezterm/wallpaper.jpg",
	wezterm.home_dir .. "/.config/wezterm/wallpaper.png",
}

-- base: 左上 → 右下のグラデーション / glow_top・glow_bottom: 右上と左下に差す色
M.presets = {
	{ id = "pastel", label = "Pastel   淡い青 → 桃 (標準)", spec = palette.background },
	{
		id = "aurora",
		label = "Aurora   ミント → 空色 → ラベンダー",
		spec = {
			base = { "#E8FAF3", "#EAF3FF", "#F1ECFF" },
			base_opacity = 0.86,
			glow_top = "#CDF3E6",
			glow_bottom = "#E2D9FF",
			glow_opacity = 0.45,
		},
	},
	{
		id = "sunset",
		label = "Sunset   ピーチ → ローズ → ライラック",
		spec = {
			base = { "#FFF2E8", "#FFEBF1", "#F3EDFF" },
			base_opacity = 0.86,
			glow_top = "#FFDFC6",
			glow_bottom = "#F8D8EA",
			glow_opacity = 0.45,
		},
	},
	{
		id = "sakura",
		label = "Sakura   桜色 → 白 → 藤色",
		spec = {
			base = { "#FFF4F7", "#FFFAFB", "#F5F2FF" },
			base_opacity = 0.88,
			glow_top = "#FCDDE8",
			glow_bottom = "#E6E0FF",
			glow_opacity = 0.4,
		},
	},
	{
		id = "glass",
		label = "Glass    ほぼ透明 (デスクトップを強めに透かす)",
		spec = {
			base = { "#F7F9FC", "#FFFFFF", "#F7F7FB" },
			base_opacity = 0.7,
			glow_top = "#E4EEFF",
			glow_bottom = "#F6E8F2",
			glow_opacity = 0.25,
		},
	},
	{ id = "image", label = "Image    ~/.config/wezterm/wallpaper.jpg|png" },
}

local function wallpaper()
	for _, path in ipairs(M.wallpaper_candidates) do
		local f = io.open(path, "r")
		if f then
			f:close()
			return path
		end
	end
	return nil
end

local function find(id)
	for _, p in ipairs(M.presets) do
		if p.id == id then
			return p
		end
	end
	return M.presets[1]
end

local function gradient_layers(spec)
	return {
		{
			source = {
				Gradient = {
					orientation = { Linear = { angle = -35.0 } },
					colors = spec.base,
					interpolation = "CatmullRom",
					blend = "Oklab",
					-- 細かいノイズでグラデーションの縞 (バンディング) を目立たなくする
					noise = 48,
				},
			},
			width = "100%",
			height = "100%",
			opacity = spec.base_opacity,
		},
		{
			source = {
				Gradient = {
					orientation = { Radial = { cx = 0.85, cy = 0.1, radius = 0.9 } },
					colors = { spec.glow_top, "rgba(255,255,255,0)" },
				},
			},
			width = "100%",
			height = "100%",
			opacity = spec.glow_opacity,
		},
		{
			source = {
				Gradient = {
					orientation = { Radial = { cx = 0.1, cy = 0.95, radius = 0.8 } },
					colors = { spec.glow_bottom, "rgba(255,255,255,0)" },
				},
			},
			width = "100%",
			height = "100%",
			opacity = spec.glow_opacity,
		},
	}
end

-- プリセット ID から config.background を組み立てる
function M.layers(id)
	local preset = find(id)
	if preset.id == "image" then
		local path = wallpaper()
		if not path then
			return gradient_layers(M.presets[1].spec)
		end
		return {
			{ source = { File = path }, width = "Cover", height = "Cover", horizontal_align = "Center", vertical_align = "Middle" },
			-- 白を重ねて、どんな画像でも文字が読めるようにする
			{ source = { Color = "#FFFFFF" }, width = "100%", height = "100%", opacity = 0.78 },
		}
	end
	return gradient_layers(preset.spec)
end

function M.saved()
	local f = io.open(M.state_path, "r")
	if not f then
		return "pastel"
	end
	local id = (f:read("*l") or ""):gsub("%s+", "")
	f:close()
	return id ~= "" and id or "pastel"
end

local function save(id)
	os.execute("mkdir -p '" .. M.state_path:match("^(.*)/[^/]+$") .. "'")
	local f = io.open(M.state_path, "w")
	if f then
		f:write(id .. "\n")
		f:close()
	end
end

function M.setup(config)
	config.macos_window_background_blur = palette.blur
	config.background = M.layers(M.saved())
end

-- LEADER+b: プリセットを選ぶ。開いているすべてのウィンドウにすぐ反映し、次の起動でも使う
function M.pick()
	return wezterm.action_callback(function(window, pane)
		local current = M.saved()
		local choices = {}
		for _, p in ipairs(M.presets) do
			local label = (p.id == current and "● " or "  ") .. p.label
			if p.id == "image" and not wallpaper() then
				label = label .. "  (画像がありません)"
			end
			table.insert(choices, { id = p.id, label = label })
		end
		window:perform_action(
			wezterm.action.InputSelector({
				title = "背景",
				choices = choices,
				action = wezterm.action_callback(function(_, _, id)
					if not id then
						return
					end
					save(id)
					for _, w in ipairs(wezterm.gui.gui_windows()) do
						local overrides = w:get_config_overrides() or {}
						overrides.background = M.layers(id)
						w:set_config_overrides(overrides)
					end
				end),
			}),
			pane
		)
	end)
end

return M
