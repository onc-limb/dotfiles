-- 下のタブバーのタブの見た目 (左端のワークスペースの札は statusbar.lua)
--
--  ( ◆ default )   1 ◆ agents   ( 2 dotfiles   main ● )   3 dotfiles   feat-a ●
--
-- - ワークスペースは濃いアクセント色の丸い札
-- - アクティブなタブは淡いアクセント色の丸い札。非アクティブなタブは背景なしで文字だけ (ホバーで薄く浮かせる)
-- - タブの右端の ● は、そのタブで一番急ぎのエージェントの状態 (入力待ち > 作業中 > 完了)
local wezterm = require("wezterm")
local palette = require("palette")
local statusbar = require("statusbar")
local workspace = require("workspace")

local M = {}

local LEFT = wezterm.nerdfonts.ple_left_half_circle_thick
local RIGHT = wezterm.nerdfonts.ple_right_half_circle_thick
local BRANCH = wezterm.nerdfonts.dev_git_branch
local STATE_ORDER = { waiting = 1, working = 2, done = 3, idle = 4 }
local STATE_COLOR = { waiting = palette.warn, working = palette.accent, done = palette.ok }

-- エージェントの状態ファイルは、タブを描くたびではなく 1 秒に 1 回だけ読む
local agents_cache = { at = -1, agents = {} }
local function agents()
	local now = os.time()
	if agents_cache.at ~= now then
		agents_cache = { at = now, agents = statusbar.read_agents() }
	end
	return agents_cache.agents
end

local function tab_state(mux_tab)
	local best = nil
	for _, item in ipairs(statusbar.agents_in_tab(mux_tab, agents())) do
		local st = item.agent.state
		if STATE_ORDER[st] and (not best or STATE_ORDER[st] < STATE_ORDER[best]) then
			best = st
		end
	end
	return best
end

-- タブの名前: 作業環境のタブ (メインの nvim がある) は リポジトリ名 と ブランチ。
-- worktree でも元のリポジトリ名を出すので、同じリポジトリの worktree はブランチで見分けられる。
-- git の外ならディレクトリ名 (LEADER+n / Cmd+t で付けたタブ名)。
-- それ以外 (エージェント一覧・素のシェル) は、タブ名が付いていればそれ、なければアクティブペインのタイトル
local function tab_name(tab, mux_tab)
	local main = mux_tab and workspace.find_role_pane(mux_tab, "main")
	local git = main and statusbar.git_info(workspace.pane_cwd(main))
	if git then
		return git.repo, git.branch
	end
	local name = tab.tab_title
	if not name or name == "" then
		name = tab.active_pane.title
	end
	return name, nil
end

local function format_tab(tab, hover, max_width)
	local mux_tab = wezterm.mux.get_tab(tab.tab_id)
	local name, branch = tab_name(tab, mux_tab)
	local state = mux_tab and tab_state(mux_tab)

	local bg = "none"
	if tab.is_active then
		bg = palette.accent_soft
	elseif hover then
		bg = palette.hover
	end
	local edge = bg == "none" and " " or nil

	-- 番号・名前・ブランチ・状態の ● を max_width に収める (両端の丸と余白で 6 文字)
	local room = max_width - 6 - #tostring(tab.tab_index + 1) - (state and 2 or 0)
	if branch then
		local branch_room = math.max(6, math.floor(room * 0.45))
		branch = wezterm.truncate_right(branch, branch_room)
		room = room - wezterm.column_width(branch) - 4
	end
	name = wezterm.truncate_right(name, math.max(4, room))

	local cells = {
		{ Background = { Color = "none" } },
		{ Foreground = { Color = bg == "none" and palette.fg or bg } },
		{ Text = edge or LEFT },
		{ Background = { Color = bg } },
		{ Foreground = { Color = tab.is_active and palette.accent or palette.muted } },
		{ Attribute = { Intensity = "Bold" } },
		{ Text = " " .. (tab.tab_index + 1) .. "  " },
		{ Foreground = { Color = tab.is_active and palette.fg or palette.tab_fg } },
		{ Attribute = { Intensity = tab.is_active and "Bold" or "Normal" } },
		{ Text = name },
		"ResetAttributes",
		{ Background = { Color = bg } },
	}
	if branch then
		table.insert(cells, { Foreground = { Color = tab.is_active and palette.accent or palette.muted } })
		table.insert(cells, { Text = "  " .. BRANCH .. " " .. branch })
	end
	if state and STATE_COLOR[state] then
		table.insert(cells, { Foreground = { Color = STATE_COLOR[state] } })
		table.insert(cells, { Text = " ●" })
	end
	table.insert(cells, { Text = " " })
	table.insert(cells, { Background = { Color = "none" } })
	table.insert(cells, { Foreground = { Color = bg == "none" and palette.fg or bg } })
	table.insert(cells, { Text = edge or RIGHT })
	return cells
end

function M.setup(config)
	config.use_fancy_tab_bar = false
	config.show_new_tab_button_in_tab_bar = false
	-- タブ名 (リポジトリ名  ブランチ) が切れないよう、既定の 16 文字より広くする
	config.tab_max_width = 44
	config.colors = config.colors or {}
	config.colors.tab_bar = { background = "none", inactive_tab_edge = "none" }
	wezterm.on("format-tab-title", function(tab, _, _, _, hover, max_width)
		return format_tab(tab, hover, max_width)
	end)
end

return M
