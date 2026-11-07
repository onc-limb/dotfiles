-- ライト / ダークの切り替え (LEADER+b) と、ウィンドウの見た目
--
-- 背景は透過させずに palette.bg で塗りつぶし、タブバーは一段沈んだ palette.chrome にして、
-- ターミナルではなく普通のデスクトップアプリのように見せる。
-- モードは ~/.local/state/wezterm/theme に保存し、次の起動でも使う。
-- 切り替えると WezTerm は設定を読み直し、nvim (plugin.lua) とエージェント一覧・状態カード (bin/agent-dashboard)
-- はこのファイルの変化を見て配色を変える
local wezterm = require("wezterm")
local palette = require("palette")

local M = {}

function M.setup(config)
	config.window_background_opacity = 1.0
	config.macos_window_background_blur = 0
	-- 文字が窓の縁に張り付かないよう、アプリらしく余白を取る
	config.window_padding = { left = 12, right = 12, top = 10, bottom = 6 }
	-- 以前の背景プリセット (LEADER+b) がウィンドウに残した背景の上書きを消す (残っていると塗りつぶしの色より優先される)
	wezterm.on("window-config-reloaded", function(window)
		local overrides = window:get_config_overrides()
		if overrides and overrides.background then
			overrides.background = nil
			window:set_config_overrides(overrides)
		end
	end)
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
		-- 以前の背景プリセットがウィンドウごとの上書き (set_config_overrides) を残していると、
		-- 読み直した設定より優先されてしまうので消す
		for _, w in ipairs(wezterm.gui.gui_windows()) do
			w:set_config_overrides({})
		end
		wezterm.reload_configuration()
	end)
end

return M
