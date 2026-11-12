-- 下のタブバーのタブの見た目 (左端のワークスペースの札は statusbar.lua)
--
--    default   0: ◆ agents   1: dotfiles   main ⏳   2: app   feat-a 💬
--
-- - タブバーは「fancy」版を使い、本文の等幅フォントではなく UI 用の可変幅フォントで描く
--   (ターミナルではなくアプリのタブ列に見せるため)
-- - タブバーの地は本文より一段沈んだ色 (chrome)。アクティブなタブだけタブの色 (palette.tab_accent、紫系統) の札にする
-- - タブの右端の 💬 ⏳ 👀 ✅ は、そのタブで一番急ぎのエージェントの状態 (入力待ち > 作業中 > 監視中 > 完了)
-- - タブ名は format-tab-title では作らず、update-right-status (毎秒) から set_title で書き込む (M.refresh)。
--   format-tab-title はペインのタイトルが変わるたびに全タブ分呼ばれ、そのたびに設定全体を Lua に変換するため、
--   エージェントが多いと WezTerm のメインスレッドが埋まって固まる
local wezterm = require("wezterm")
local palette = require("palette")
local statusbar = require("statusbar")
local workspace = require("workspace")

local M = {}

local BRANCH = wezterm.nerdfonts.dev_git_branch
local STATE_ORDER = { waiting = 1, working = 2, watching = 3, done = 4, idle = 5 }
-- タブの右端に出す、そのタブで一番急ぎのエージェントの状態
local STATE_ICON = { waiting = "💬", working = "⏳", watching = "👀", done = "✅" }

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

-- タブバーに出す名前: 作業環境のタブ (メインの nvim がある) は リポジトリ名 と ブランチ。
-- worktree でも元のリポジトリ名を出すので、同じリポジトリの worktree はブランチで見分けられる。
-- git の外ならディレクトリ名 (LEADER+n / Cmd+t で付けたタブ名)。
-- それ以外 (エージェント一覧・素のシェル) は、タブ名が付いていればそれ、なければアクティブペインのタイトル。
-- 番号 (「1: 」) は WezTerm が付ける (0 から。エージェント一覧タブが 0)
local TITLE_WIDTH = 40
local function tab_title(mux_tab, name)
	if name == workspace.DASHBOARD_TITLE or workspace.is_dashboard(mux_tab) then
		return name
	end
	local main = workspace.find_role_pane(mux_tab, "main")
	local git = main and statusbar.git_info(workspace.pane_cwd(main), true)
	local state = tab_state(mux_tab)
	local icon = state and STATE_ICON[state]
	-- 名前もブランチも状態もなければ空のままにして、WezTerm にアクティブペインのタイトルを出させる
	if not git and not icon then
		return name
	end
	local label, branch = name, nil
	if git then
		label, branch = git.repo, git.branch
	elseif label == "" then
		local pane = mux_tab:active_pane()
		label = pane and pane:get_title() or ""
	end

	-- 名前・ブランチ・状態を TITLE_WIDTH に収める
	local room = TITLE_WIDTH - (icon and 3 or 0)
	if branch then
		local branch_room = math.max(6, math.floor(room * 0.45))
		branch = wezterm.truncate_right(branch, branch_room)
		room = room - wezterm.column_width(branch) - 5
	end
	local title = wezterm.truncate_right(label, math.max(4, room))
	if branch then
		title = title .. "   " .. BRANCH .. " " .. branch
	end
	if icon then
		title = title .. "  " .. icon
	end
	return title
end

-- ウィンドウのタブ名を書き直す (git を起動できる update-right-status から毎秒呼ぶ)。
-- 変わったタブにだけ set_title する
function M.refresh(window)
	for _, mux_tab in ipairs(window:mux_window():tabs()) do
		local name = workspace.tab_name(mux_tab)
		workspace.show_tab_title(mux_tab, name, tab_title(mux_tab, name))
	end
end

function M.setup(config)
	config.use_fancy_tab_bar = true
	-- タブの番号を 0 から振る。エージェント一覧タブ (常に先頭) が 0 = Cmd+0、作業環境が 1, 2, … = Cmd+1, Cmd+2, …
	config.tab_and_split_indices_are_zero_based = true
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
		active_tab = { bg_color = palette.tab_accent, fg_color = palette.tab_accent_fg, intensity = "Bold" },
		inactive_tab = { bg_color = palette.chrome, fg_color = palette.tab_fg },
		inactive_tab_hover = { bg_color = palette.hover, fg_color = palette.fg },
	}
end

return M
