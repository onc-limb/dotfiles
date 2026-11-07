-- 配色の選択 (LEADER+Shift+b、パターン × ライト / ダークの 6 通り)、ライト / ダークの切り替え (LEADER+b)、ウィンドウの見た目
--
-- 背景は透過させずに palette.bg で塗りつぶし、タブバーは一段沈んだ palette.chrome にして、
-- ターミナルではなく普通のデスクトップアプリのように見せる。
-- 選んだパターンとモードは ~/.local/state/wezterm/scheme / theme に保存し、次の起動でも使う。
-- 切り替えると WezTerm は設定を読み直し、nvim (plugin.lua) はこれらのファイルの変化を見て配色を変える。
-- エージェント一覧・状態カード (bin/agent-dashboard) 用に、今の配色を palette.json に書き出す
local wezterm = require("wezterm")
local palette = require("palette")

local M = {}

local STATE_DIR = wezterm.home_dir .. "/.local/state/wezterm"
M.json_path = STATE_DIR .. "/palette.json"

-- 文字列の色だけを JSON に書く (内容が変わったときだけ)
local function write_json()
	local flat = { scheme = palette.scheme, mode = palette.mode }
	for k, v in pairs(palette) do
		if type(v) == "string" and v:match("^#%x%x%x%x%x%x$") then
			flat[k] = v
		end
	end
	local text = wezterm.json_encode(flat)
	local f = io.open(M.json_path, "r")
	if f then
		local old = f:read("*a")
		f:close()
		if old == text then
			return
		end
	end
	os.execute("mkdir -p '" .. STATE_DIR .. "'")
	f = io.open(M.json_path, "w")
	if f then
		f:write(text)
		f:close()
	end
end

function M.setup(config)
	config.window_background_opacity = 1.0
	config.macos_window_background_blur = 0
	-- 文字が窓の縁に張り付かないよう、アプリらしく余白を取り、行間も少し広げる。
	-- 下はタブバーと接するので余白を付けない (nvim のステータス行がタブバーの真上に来る)
	config.window_padding = { left = 14, right = 14, top = 12, bottom = 0 }
	config.line_height = 1.1
	-- ブロックではなく縦線のカーソル (テキストエディタのように)
	config.default_cursor_style = "SteadyBar"
	write_json()
	-- 以前の背景プリセットがウィンドウに残した背景の上書きを消す (残っていると塗りつぶしの色より優先される)
	wezterm.on("window-config-reloaded", function(window)
		local overrides = window:get_config_overrides()
		if overrides and overrides.background then
			overrides.background = nil
			window:set_config_overrides(overrides)
		end
	end)
end

local function write(path, value)
	os.execute("mkdir -p '" .. STATE_DIR .. "'")
	local f = io.open(path, "w")
	if not f then
		return false
	end
	f:write(value .. "\n")
	f:close()
	return true
end

-- 書いてから設定を読み直す (開いているすべてのウィンドウに反映される)
local function save(path, value)
	if write(path, value) then
		wezterm.reload_configuration()
	end
end

-- LEADER+b: ライトとダークを切り替える。保存して設定を読み直すと、開いているすべてのウィンドウに反映される
function M.toggle()
	return wezterm.action_callback(function()
		save(palette.mode_file, palette.mode == "dark" and "light" or "dark")
	end)
end

-- LEADER+Shift+b: 配色パターンとライト / ダークの組み合わせ (3 × 2 = 6 通り) から選ぶ
function M.pick()
	return wezterm.action_callback(function(window, pane)
		local choices = {}
		for _, id in ipairs(palette.order) do
			for _, mode in ipairs({ "light", "dark" }) do
				local current = id == palette.scheme and mode == palette.mode
				table.insert(choices, {
					id = id .. ":" .. mode,
					label = string.format(
						"%s%s  %s",
						current and "● " or "  ",
						palette.schemes[id].label,
						mode == "dark" and "ダーク" or "ライト"
					),
				})
			end
		end
		window:perform_action(
			wezterm.action.InputSelector({
				title = "配色",
				fuzzy = true,
				choices = choices,
				action = wezterm.action_callback(function(_, _, choice)
					if not choice then
						return
					end
					local id, mode = choice:match("^(.-):(.*)$")
					write(palette.scheme_file, id)
					save(palette.mode_file, mode)
				end),
			}),
			pane
		)
	end)
end

return M
