-- 下のタブバーの右側: エージェントの状態・モデルとコンテキスト・利用制限
--
-- 表示する情報は bin/agent-state が ~/.local/state/agents に書き出したファイルを読むだけ。
--   <ペインID>.json            : ペインで動いているエージェントの状態 / session_id / モデル / コンテキスト
--   quota-<tool>-<profile>.json : Claude / Codex の 5 時間・週次の利用制限 (profile = work / private)
local wezterm = require("wezterm")
local palette = require("palette")

local M = {}

M.state_dir = wezterm.home_dir .. "/.local/state/agents"

local STATE_ICON = { working = "⏳", waiting = "💬", done = "✅", idle = "·" }
M.STATE_ICON = STATE_ICON
local TOOL_LABEL = { claude = "C", codex = "X" }
local CIRCLED = { "①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨" }
-- この秒数より古い利用制限は薄く表示する (しばらくエージェントを使っていない)
local QUOTA_STALE_SEC = 30 * 60

local function read_json(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local text = f:read("*a")
	f:close()
	local ok, data = pcall(wezterm.json_parse, text)
	if ok and type(data) == "table" then
		return data
	end
	return nil
end

-- ペインID -> エージェントの状態
function M.read_agents()
	local agents = {}
	local ok, paths = pcall(wezterm.read_dir, M.state_dir)
	if not ok then
		return agents
	end
	for _, path in ipairs(paths) do
		local id = path:match("/(%d+)%.json$")
		if id then
			local data = read_json(path)
			if data then
				agents[tonumber(id)] = data
			end
		end
	end
	return agents
end

-- タブの中でエージェントが動いているペインを、画面上の並び順 (上→下、左→右) で返す。
-- LEADER+数字でのエージェント選択も同じ並び順を使う
function M.agents_in_tab(tab, agents)
	agents = agents or M.read_agents()
	local list = {}
	for _, info in ipairs(tab:panes_with_info()) do
		local agent = agents[info.pane:pane_id()]
		-- 起動直後で hook がまだ状態を書いていないエージェントも、ペインの user var で拾う
		if not agent then
			local vars = info.pane:get_user_vars()
			if vars.role == "agent" then
				agent = { tool = vars.tool, state = "idle" }
			end
		end
		if agent then
			table.insert(list, { pane = info.pane, info = info, agent = agent })
		end
	end
	table.sort(list, function(a, b)
		if a.info.left ~= b.info.left then
			return a.info.left < b.info.left
		end
		return a.info.top < b.info.top
	end)
	return list
end

-- 今のタブのアカウント (work / private)。エージェントがいればその profile、
-- いなければ bin/agent-auto と同じく「~/work の下か」で決める
local function current_profile(tab, list)
	for _, item in ipairs(list) do
		if item.agent.profile then
			return item.agent.profile
		end
	end
	local cwd = tab:active_pane():get_current_working_dir()
	local path = cwd and cwd.file_path or ""
	if path:find(wezterm.home_dir .. "/work/", 1, true) == 1 then
		return "work"
	end
	return "private"
end

local function pct_color(pct)
	if pct >= 80 then
		return palette.error
	elseif pct >= 60 then
		return palette.warn
	end
	return palette.fg
end

local WEEKDAY = { "日", "月", "火", "水", "木", "金", "土" }

-- リセット時刻: 5 時間枠は "14:30"、週次枠は "水 18:00" (7 日以内なので曜日で一意に決まる)
local function reset_label(key, ts)
	if not ts then
		return nil
	end
	if key == "5h" then
		return os.date("%H:%M", ts)
	end
	return WEEKDAY[tonumber(os.date("%w", ts)) + 1] .. os.date(" %H:%M", ts)
end

-- 利用制限 1 ツール分: 例 "C 5h 32% 14:30 週 18% 水 18:00"
local function quota_cells(tool, profile)
	local data = read_json(string.format("%s/quota-%s-%s.json", M.state_dir, tool, profile))
	if not data or type(data.windows) ~= "table" then
		return {}
	end
	local now = os.time()
	local stale = (now - (data.updated_at or 0)) > QUOTA_STALE_SEC
	local cells = { { Foreground = { Color = palette.muted } }, { Text = TOOL_LABEL[tool] or tool } }
	for _, w in ipairs({ { key = "5h", label = "5h" }, { key = "week", label = "週" } }) do
		local v = data.windows[w.key]
		if v and v.pct then
			local pct = math.floor(v.pct + 0.5)
			local text = pct .. "%"
			-- リセット時刻を過ぎていれば使用量は戻っているはずなので、値の代わりに – を出す
			if v.resets_at and v.resets_at < now then
				text = "–"
			end
			table.insert(cells, { Foreground = { Color = palette.muted } })
			table.insert(cells, { Text = " " .. w.label .. " " })
			table.insert(cells, { Foreground = { Color = stale and palette.muted or pct_color(pct) } })
			table.insert(cells, { Text = text })
			local reset = text ~= "–" and reset_label(w.key, v.resets_at)
			if reset then
				table.insert(cells, { Foreground = { Color = palette.muted } })
				table.insert(cells, { Text = " " .. reset })
			end
		end
	end
	return cells
end

local function append(dst, src)
	for _, c in ipairs(src) do
		table.insert(dst, c)
	end
end

local SEP = { { Foreground = { Color = palette.muted } }, { Text = "  │  " } }

-- 右側のステータス全体を組み立てる
function M.right_status(window, pane)
	local tab = window:active_tab()
	local agents = M.read_agents()
	local list = M.agents_in_tab(tab, agents)
	local cells = {}

	-- LEADER / キーテーブルの状態 (押している最中だけ)
	local key_table = window:active_key_table()
	local mode = key_table and ("TABLE: " .. key_table) or (window:leader_is_active() and "LEADER" or nil)
	if mode then
		append(cells, { { Foreground = { Color = palette.accent } }, { Text = mode .. "  " } })
	end

	-- 今のタブのエージェント: ① claude ⏳  ② codex 💬
	local active_agent = nil
	for i, item in ipairs(list) do
		local is_active = item.pane:pane_id() == pane:pane_id()
		if is_active then
			active_agent = item.agent
		end
		append(cells, {
			{ Foreground = { Color = is_active and palette.accent or palette.fg } },
			{ Attribute = { Intensity = is_active and "Bold" or "Normal" } },
			{ Text = (CIRCLED[i] or tostring(i)) .. " " .. (item.agent.tool or "?") .. " " },
			"ResetAttributes",
			{ Text = (STATE_ICON[item.agent.state] or "·") .. "  " },
		})
	end
	if #list > 0 then
		append(cells, SEP)
	end

	-- 選択中のエージェントのモデルとコンテキスト使用率
	if active_agent and (active_agent.model or active_agent.ctx_pct) then
		append(cells, { { Foreground = { Color = palette.fg } }, { Text = active_agent.model or "?" } })
		if active_agent.ctx_pct then
			append(cells, {
				{ Foreground = { Color = pct_color(active_agent.ctx_pct) } },
				{ Text = " " .. active_agent.ctx_pct .. "%" },
			})
		end
		append(cells, SEP)
	end

	-- 利用制限 (今のタブのアカウント分)
	local profile = current_profile(tab, list)
	local claude = quota_cells("claude", profile)
	local codex = quota_cells("codex", profile)
	append(cells, claude)
	if #claude > 0 and #codex > 0 then
		append(cells, SEP)
	end
	append(cells, codex)

	append(cells, { { Text = " " } })
	return wezterm.format(cells)
end

-- git のリポジトリ名とブランチ名。worktree の中でも、元のリポジトリの名前を返す。
-- タブバーの更新・タブ名の描画のたびに呼ばれるので、ディレクトリごとに数秒キャッシュする
local git_cache = {}
local GIT_TTL_SEC = 5
function M.git_info(path)
	local hit = git_cache[path]
	local now = os.time()
	if hit and now - hit.at < GIT_TTL_SEC then
		return hit.info
	end
	local info = nil
	local ok, out = wezterm.run_child_process({
		"git", "-C", path, "rev-parse", "--path-format=absolute", "--git-common-dir", "--abbrev-ref", "HEAD",
	})
	if ok then
		local common, branch = out:match("^([^\n]+)\n([^\n]+)")
		if common then
			local root = common:gsub("/+$", ""):match("^(.*)/[^/]+$") or common
			info = { repo = root:match("([^/]+)$") or root, branch = branch }
		end
	end
	git_cache[path] = { info = info, at = now }
	return info
end

-- 左側のステータス: ワークスペース名 (ディレクトリとブランチはタブ名に出す)
function M.left_status(window)
	local cells = {
		{ Background = { Color = palette.accent } },
		{ Foreground = { Color = palette.accent_fg } },
		{ Attribute = { Intensity = "Bold" } },
		{ Text = "  ◆ " .. window:active_workspace() .. "  " },
		"ResetAttributes",
	}
	append(cells, { { Foreground = { Color = palette.muted } }, { Text = "  │ " } })
	return wezterm.format(cells)
end

-- on_update: タブバーの更新 (毎秒) のついでに呼ぶ処理 (エージェント一覧タブの補充、セッションの保存)
function M.setup(config, on_update)
	config.tab_bar_at_bottom = true
	config.status_update_interval = 1000
	wezterm.on("update-right-status", function(window, pane)
		if on_update then
			on_update(window, pane)
		end
		window:set_left_status(M.left_status(window))
		window:set_right_status(M.right_status(window, pane))
	end)
end

return M
