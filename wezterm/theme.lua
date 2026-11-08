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

-- starship のプロンプト用: dotfiles の starship.toml (雛形) の palette を wezterm に差し替え、
-- 今の配色から作った palettes.wezterm を足したものを書き出す (内容が変わったときだけ)。
-- 札の地はタブバーと同じく、色を背景に寄せた淡い色 (tint)、文字は同じ色相の濃い色 (ink)
M.starship_template = wezterm.home_dir .. "/.config/starship.toml"
M.starship_path = STATE_DIR .. "/starship.toml"

local function write_starship()
	local f = io.open(M.starship_template, "r")
	if not f then
		return false
	end
	local template = f:read("*a")
	f:close()
	local p = palette
	local colors = {
		{ "path_bg", p.tint(p.ansi[5]) },
		{ "path_ink", p.ink(p.ansi[5]) },
		{ "path_dim", p.muted },
		{ "branch_bg", p.tint(p.ansi[6]) },
		{ "branch_ink", p.ink(p.ansi[6]) },
		{ "chip_bg", p.surface },
		{ "chip_ink", p.tab_fg },
		{ "dim_ink", p.muted },
		{ "ok_ink", p.ink(p.ok) },
		{ "warn_bg", p.tint(p.warn) },
		{ "warn_ink", p.ink(p.warn) },
		{ "err_bg", p.tint(p.error) },
		{ "err_ink", p.ink(p.error) },
		{ "info_bg", p.tint(p.ansi[7]) },
		{ "info_ink", p.ink(p.ansi[7]) },
		{ "accent", p.accent_text },
		{ "err", p.error },
		{ "vim", p.ok },
	}
	local lines = { "", "# wezterm/theme.lua が今の配色 (" .. p.scheme .. " / " .. p.mode .. ") から書き出した色", "[palettes.wezterm]" }
	for _, kv in ipairs(colors) do
		table.insert(lines, string.format('%s = "%s"', kv[1], kv[2]))
	end
	local text = template:gsub('palette = "fallback"', 'palette = "wezterm"', 1) .. table.concat(lines, "\n") .. "\n"
	f = io.open(M.starship_path, "r")
	if f then
		local old = f:read("*a")
		f:close()
		if old == text then
			return true
		end
	end
	os.execute("mkdir -p '" .. STATE_DIR .. "'")
	f = io.open(M.starship_path, "w")
	if not f then
		return false
	end
	f:write(text)
	f:close()
	return true
end

function M.setup(config)
	-- 雛形を書き換えたときも設定を読み直し、書き出し直す
	wezterm.add_to_config_reload_watch_list(M.starship_template)
	if write_starship() then
		config.set_environment_variables = config.set_environment_variables or {}
		config.set_environment_variables.STARSHIP_CONFIG = M.starship_path
	end
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
