-- ライト / ダークの切り替え (LEADER+b) と背景
--
-- 背景は、淡い (ダークでは暗い) グラデーションを重ねて下のデスクトップをぼかして透かす。色は palette.lua。
-- モードは ~/.local/state/wezterm/theme に保存し、次の起動でも使う。
-- 切り替えると WezTerm は設定を読み直し、nvim (plugin.lua) とエージェント一覧・状態カード (bin/agent-dashboard)
-- はこのファイルの変化を見て配色を変える
local wezterm = require("wezterm")
local palette = require("palette")

local M = {}

-- palette.background から config.background を組み立てる
local function layers(spec)
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
					colors = { spec.glow_top, "rgba(0,0,0,0)" },
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
					colors = { spec.glow_bottom, "rgba(0,0,0,0)" },
				},
			},
			width = "100%",
			height = "100%",
			opacity = spec.glow_opacity,
		},
	}
end

function M.setup(config)
	config.macos_window_background_blur = palette.blur
	config.background = layers(palette.background)
end

-- LEADER+b: ライトとダークを切り替える。保存して設定を読み直すと、開いているすべてのウィンドウに反映される
function M.toggle()
	return wezterm.action_callback(function()
		local next_mode = palette.mode == "dark" and "light" or "dark"
		os.execute("mkdir -p '" .. palette.mode_file:match("^(.*)/[^/]+$") .. "'")
		local f = io.open(palette.mode_file, "w")
		if not f then
			return
		end
		f:write(next_mode .. "\n")
		f:close()
		wezterm.reload_configuration()
	end)
end

return M
