-- 下のタブバーのタブの見た目 (左端のワークスペースの札は statusbar.lua)
--
--    default   [1] ◆ agents  [2  dotfiles   main ⏳]  [3] app   feat-a 💬
--
-- - タブバーは「fancy」版を使い、本文の等幅フォントではなく UI 用の可変幅フォントで描く
--   (ターミナルではなくアプリのタブ列に見せるため)
-- - タブバーの地は本文より一段沈んだ色 (chrome)。色はタブの色 (palette.tab_accent、紫系統) の一系統だけを使う:
--   アクティブなタブはその色を地にした札 (名前まで)、非アクティブなタブは番号だけを
--   その色の淡い地に同じ色相の濃い文字の札にする
-- - タブの右端の 💬 ⏳ ✅ は、そのタブで一番急ぎのエージェントの状態 (入力待ち > 作業中 > 完了)
local wezterm = require("wezterm")
local palette = require("palette")
local statusbar = require("statusbar")
local workspace = require("workspace")

local M = {}

local BRANCH = wezterm.nerdfonts.dev_git_branch
local STATE_ORDER = { waiting = 1, working = 2, done = 3, idle = 4 }
-- タブの右端に出す、そのタブで一番急ぎのエージェントの状態
local STATE_ICON = { waiting = "💬", working = "⏳", done = "✅" }

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

-- タブ名に出す git の情報を取り直す (git を起動できる update-right-status から毎秒呼ぶ)
function M.refresh_git(window)
	for _, mux_tab in ipairs(window:mux_window():tabs()) do
		local main = workspace.find_role_pane(mux_tab, "main")
		if main then
			statusbar.git_info(workspace.pane_cwd(main), true)
		end
	end
end

local function format_tab(tab, max_width)
	local mux_tab = wezterm.mux.get_tab(tab.tab_id)
	local name, branch = tab_name(tab, mux_tab)
	local state = mux_tab and tab_state(mux_tab)

	-- 番号・名前・ブランチ・状態の ● を max_width に収める (余白で 4 文字)
	local room = max_width - 4 - #tostring(tab.tab_index + 1) - (state and 2 or 0)
	if branch then
		local branch_room = math.max(6, math.floor(room * 0.45))
		branch = wezterm.truncate_right(branch, branch_room)
		room = room - wezterm.column_width(branch) - 4
	end
	name = wezterm.truncate_right(name, math.max(4, room))

	-- アクティブなタブは名前までタブの色の札、非アクティブなタブは番号だけを淡いタブの色の札にする
	local color = tab.is_active and palette.tab_accent or palette.tint(palette.tab_accent)
	local ink = tab.is_active and palette.tab_accent_fg or palette.ink(palette.tab_accent)
	local cells = {
		{ Background = { Color = color } },
		{ Foreground = { Color = ink } },
		{ Attribute = { Intensity = "Bold" } },
		{ Text = " " .. (tab.tab_index + 1) .. " " },
	}
	if tab.is_active then
		table.insert(cells, { Text = " " .. name })
		if branch then
			table.insert(cells, "ResetAttributes")
			table.insert(cells, { Background = { Color = color } })
			table.insert(cells, { Foreground = { Color = ink } })
			table.insert(cells, { Text = "   " .. BRANCH .. " " .. branch })
		end
		table.insert(cells, { Text = " " .. (state and STATE_ICON[state] and (STATE_ICON[state] .. " ") or "") })
		table.insert(cells, "ResetAttributes")
		return cells
	end
	table.insert(cells, "ResetAttributes")
	table.insert(cells, { Foreground = { Color = palette.tab_fg } })
	table.insert(cells, { Text = "  " .. name })
	if branch then
		table.insert(cells, { Foreground = { Color = palette.muted } })
		table.insert(cells, { Text = "   " .. BRANCH .. " " .. branch })
	end
	if state and STATE_ICON[state] then
		table.insert(cells, { Text = "  " .. STATE_ICON[state] })
	end
	table.insert(cells, { Text = "  " })
	return cells
end

function M.setup(config)
	config.use_fancy_tab_bar = true
	config.show_new_tab_button_in_tab_bar = false
	-- タブの × は出さない (Cmd+w / LEADER X で閉じる)。この設定は 20240203 より後の版 (nightly) にしかなく、
	-- 古い版で書くと設定ごと読み込めなくなるので、版を見てから設定する
	if wezterm.version > "20240203-999999" then
		config.show_close_tab_button_in_tabs = false
	end
	-- タブ名 (リポジトリ名  ブランチ) が切れないよう、既定の 16 文字より広くする
	config.tab_max_width = 44
	-- タブバーの文字: UI 用の可変幅フォント (日本語はヒラギノ、アイコンは Nerd Font で補う)
	config.window_frame = {
		font = wezterm.font_with_fallback({
			{ family = "Helvetica Neue", weight = "Medium" },
			"Hiragino Sans",
			"Symbols Nerd Font Mono",
		}),
		font_size = 13.0,
		active_titlebar_bg = palette.chrome,
		inactive_titlebar_bg = palette.chrome,
	}
	config.colors = config.colors or {}
	config.colors.tab_bar = {
		background = palette.chrome,
		inactive_tab_edge = palette.chrome,
		active_tab = { bg_color = palette.bg, fg_color = palette.fg },
		inactive_tab = { bg_color = palette.chrome, fg_color = palette.tab_fg },
		inactive_tab_hover = { bg_color = palette.hover, fg_color = palette.fg },
	}
	wezterm.on("format-tab-title", function(tab, _, _, _, _, max_width)
		return format_tab(tab, max_width)
	end)
end

return M
