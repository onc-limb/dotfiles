-- WezTerm や PC を再起動したときに、ワークスペース・worktree タブ・エージェントのセッションを復旧する
--
-- 保存: タブバーの更新 (毎秒) のついでに、構成が変わっていれば ~/.local/state/wezterm/session.json に書く
-- 復元: WezTerm の起動時 (gui-startup) だけ。新しいウィンドウを開いたときには何もしない
--   worktree タブ → メインの nvim を開き直す (開いていたファイルは nvim 側の worktree_session.lua が戻す)
--   エージェント → claude --resume <id> / codex resume <id> で会話を再開する
--                  (見えないワークスペースで再開し、元のタブの状態カードに並べる)
-- 実行中だった処理・スクロール履歴・nvim の中のターミナルは戻らない
local wezterm = require("wezterm")
local statusbar = require("statusbar")
local workspace = require("workspace")

local M = {}

-- WEZTERM_SESSION_FILE は動作確認用 (別プロセスの WezTerm で復旧を試すとき)。
-- 指定したときは、動いている WezTerm のエージェント状態ファイルを消さない
M.test_path = os.getenv("WEZTERM_SESSION_FILE")
M.path = M.test_path or (wezterm.home_dir .. "/.local/state/wezterm/session.json")

local function snapshot()
	local agents = statusbar.read_agents()
	local by_workspace, order = {}, {}
	for _, win in ipairs(wezterm.mux.all_windows()) do
		local name = win:get_workspace()
		-- エージェントを置いておく見えないワークスペースは保存しない (エージェントは所属するタブの分として保存する)
		if name == workspace.STASH then
			goto continue
		end
		if not by_workspace[name] then
			by_workspace[name] = { name = name, tabs = {} }
			table.insert(order, by_workspace[name])
		end
		for _, tab in ipairs(win:tabs()) do
			local entry
			if workspace.is_dashboard(tab) or workspace.tab_name(tab) == workspace.DASHBOARD_TITLE then
				entry = { kind = "dashboard" }
			else
				local main = workspace.find_role_pane(tab, "main")
				-- worktree タブ以外 (素のシェルのタブなど) はディレクトリだけ戻す
				entry = {
					kind = main and "worktree" or "shell",
					cwd = workspace.pane_cwd(main or workspace.home_pane(tab)),
					title = workspace.tab_name(tab),
				}
			end
			entry.agents = {}
			for _, item in ipairs(statusbar.agents_in_tab(tab, agents)) do
				table.insert(entry.agents, {
					tool = item.agent.tool,
					session_id = item.agent.session_id,
					cwd = item.agent.cwd,
				})
			end
			table.insert(by_workspace[name].tabs, entry)
		end
		::continue::
	end
	return { workspaces = order, active_workspace = wezterm.mux.get_active_workspace() }
end

-- 構成が変わったときだけ書く
function M.save()
	if wezterm.GLOBAL.session_restoring then
		return
	end
	local ok, data = pcall(snapshot)
	if not ok or #data.workspaces == 0 then
		return
	end
	local text = wezterm.json_encode(data)
	if text == wezterm.GLOBAL.session_last_saved then
		return
	end
	os.execute("mkdir -p '" .. M.path:match("^(.*)/[^/]+$") .. "'")
	local f = io.open(M.path .. ".tmp", "w")
	if not f then
		return
	end
	f:write(text)
	f:close()
	os.rename(M.path .. ".tmp", M.path)
	wezterm.GLOBAL.session_last_saved = text
end

local function read_session()
	local f = io.open(M.path, "r")
	if not f then
		return nil
	end
	local text = f:read("*a")
	f:close()
	local ok, data = pcall(wezterm.json_parse, text)
	if ok and type(data) == "table" and type(data.workspaces) == "table" and #data.workspaces > 0 then
		return data
	end
	return nil
end

-- 前回の WezTerm のペイン ID で書かれた状態ファイルを消す (ペイン ID は再起動で 0 から振り直される)
local function clear_agent_states()
	local ok, paths = pcall(wezterm.read_dir, statusbar.state_dir)
	if not ok then
		return
	end
	for _, path in ipairs(paths) do
		if path:match("/%d+%.json$") or path:match("/shown%-%d+$") or path:match("/hidden%-%d+$") then
			os.remove(path)
		end
	end
end

local function exists(path)
	return path and wezterm.run_child_process({ "test", "-d", path })
end

-- home: エージェントが所属するペイン (作業環境のメインの nvim など)。
-- エージェントは見えないワークスペースで再開し、タブを開いたときに右の列に積む (workspace.ensure_agent_shown)
local function restore_agents(home, list, cwd)
	for _, a in ipairs(list or {}) do
		if a.tool then
			workspace.spawn_agent(home, a.tool, a.session_id, a.cwd or cwd)
		end
	end
end

local function restore(data)
	for _, ws in ipairs(data.workspaces) do
		-- 1 つ目のタブ (エージェント一覧) でウィンドウを作り、残りのタブを足していく
		local dashboard_tab, dashboard_pane, window = wezterm.mux.spawn_window({
			workspace = ws.name,
			cwd = wezterm.home_dir,
			args = workspace.dashboard_args(),
		})
		dashboard_tab:set_title(workspace.DASHBOARD_TITLE)
		local env_tabs = 0
		for _, entry in ipairs(ws.tabs) do
			if entry.kind == "dashboard" then
				restore_agents(dashboard_pane, entry.agents, wezterm.home_dir)
			elseif exists(entry.cwd) then
				local tab, home
				if entry.kind == "worktree" then
					tab, home = workspace.spawn_worktree_tab(window, entry.cwd)
				else
					tab, home = window:spawn_tab({ cwd = entry.cwd })
				end
				restore_agents(home, entry.agents, entry.cwd)
				if entry.title and entry.title ~= "" then
					tab:set_title(entry.title)
				end
				env_tabs = env_tabs + 1
			end
		end
		-- エージェント一覧タブしか残っていなければ、作業環境のタブを 1 つ開いておく
		if env_tabs == 0 then
			workspace.spawn_worktree_tab(window, wezterm.home_dir)
		end
		-- ワークスペースごとに先頭のエージェント一覧タブを表示しておく
		dashboard_tab:activate()
	end
	if data.active_workspace then
		wezterm.mux.set_active_workspace(data.active_workspace)
	end
end

function M.setup()
	wezterm.on("gui-startup", function(cmd)
		-- `wezterm start -- <command>` のようにコマンド付きで起動されたときは復旧しない
		local data = (not cmd or not cmd.args) and read_session() or nil
		if not M.test_path then
			clear_agent_states()
		end
		if not data then
			if cmd and cmd.args then
				wezterm.mux.spawn_window(cmd)
			else
				-- 初回起動: エージェント一覧タブと、作業環境のタブを 1 つ
				local tab, _, window = wezterm.mux.spawn_window({ cwd = wezterm.home_dir, args = workspace.dashboard_args() })
				tab:set_title(workspace.DASHBOARD_TITLE)
				workspace.spawn_worktree_tab(window, wezterm.home_dir)
			end
			return
		end
		wezterm.GLOBAL.session_restoring = true
		local ok, err = pcall(restore, data)
		wezterm.GLOBAL.session_restoring = false
		if not ok then
			wezterm.log_error("session restore failed: " .. tostring(err))
			if #wezterm.mux.all_windows() == 0 then
				wezterm.mux.spawn_window(cmd or {})
			end
		end
	end)
end

return M
