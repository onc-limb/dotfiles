-- タブ = worktree、ワークスペース = private / work / 案件 の運用を組み立てる
--
-- 各 worktree タブ:
--   左 (main)   : メインの nvim (neo-tree 常駐、ターミナルも nvim の中)。nvim を抜けても zsh が残る
--   右 (agent)  : Claude Code / Codex。複数なら右側に縦に並べる
-- ワークスペースごとに閉じられないエージェント一覧タブ (dashboard) を 1 つ置く。
--
-- ペインの役割は、ペインの中のシェルが OSC 1337 SetUserVar で書き込む user var で見分ける
--   role = main / agent / dashboard、tool = claude / codex
-- (Lua 側のテーブルと違い、設定の自動リロードで消えない)
local wezterm = require("wezterm")
local act = wezterm.action
local statusbar = require("statusbar")

local M = {}

local BIN = wezterm.home_dir .. "/dotfiles/bin"
M.DASHBOARD_TITLE = "◆ agents"

-- 新しく作ったペイン・タブを知らせるコールバック (session.lua が保存のきっかけに使う)
M.on_change = function() end

local function shell_quote(s)
	return "'" .. tostring(s):gsub("'", [['\'']]) .. "'"
end

local function set_var_cmd(name, value)
	return string.format([[printf '\033]1337;SetUserVar=%s=%%s\a' "$(printf %%s %s | base64)"]], name, shell_quote(value))
end

-- ログインシェル経由で起動して PATH (homebrew / mise / ~/.local/bin) を引き継ぐ
local function zsh(cmd)
	return { "/bin/zsh", "-lic", cmd }
end

local function role_of(pane)
	return pane:get_user_vars().role
end

function M.find_role_pane(tab, role)
	for _, p in ipairs(tab:panes()) do
		if role_of(p) == role then
			return p
		end
	end
	return nil
end

function M.is_dashboard(tab)
	return M.find_role_pane(tab, "dashboard") ~= nil
end

local function git(cwd, ...)
	local ok, out, err = wezterm.run_child_process({ "git", "-C", cwd, ... })
	return ok and out or nil, err
end

local function trim(s)
	return (s or ""):gsub("%s+$", "")
end

local function basename(path)
	return (path:gsub("/+$", ""):match("([^/]+)$")) or path
end

local function dirname(path)
	return (path:gsub("/+$", ""):match("^(.*)/[^/]+$")) or path
end

-- メインのチェックアウトのルート (worktree の中から呼ばれても、元のリポジトリを返す)
local function main_repo_root(cwd)
	local common = trim(git(cwd, "rev-parse", "--path-format=absolute", "--git-common-dir"))
	if common == "" then
		return nil
	end
	return dirname(common)
end

-- リポジトリの隣に <repo>-<branch> (branch の / は - に置き換える)
local function worktree_path(root, branch)
	return string.format("%s/%s-%s", dirname(root), basename(root), (branch:gsub("/", "-")))
end

local function pane_cwd(pane)
	local cwd = pane:get_current_working_dir()
	return cwd and cwd.file_path or wezterm.home_dir
end

----------------------------------------------------
-- タブとペインを作る
----------------------------------------------------

-- worktree のタブを開く。opts.init = true なら初期化スクリプトを実行してから nvim を起動する。
-- 初期化スクリプトは worktree の .worktree-init、無ければメインのチェックアウトの .worktree-init
function M.spawn_worktree_tab(mux_window, path, opts)
	opts = opts or {}
	local cmd = set_var_cmd("role", "main")
	if opts.init then
		local root = main_repo_root(path) or path
		cmd = cmd
			.. string.format(
				"; for f in ./.worktree-init %s/.worktree-init; do if [ -f \"$f\" ]; then echo \"==> $f\"; sh \"$f\"; break; fi; done",
				shell_quote(root)
			)
	end
	cmd = cmd .. "; nvim --cmd 'let g:start_with_explorer = 1'; exec /bin/zsh -l"
	local tab, pane = mux_window:spawn_tab({ cwd = path, args = zsh(cmd) })
	tab:set_title(basename(path))
	M.on_change()
	return tab, pane
end

-- エージェントのペインを右側に足す。session_id があればそのセッションを再開する
function M.spawn_agent(tab, tool, session_id)
	local agents = statusbar.agents_in_tab(tab)
	local base, direction, size
	if #agents > 0 then
		-- 2 つ目以降は一番下のエージェントの下に縦に積む
		base, direction, size = agents[#agents].pane, "Bottom", 0.5
	else
		base = M.find_role_pane(tab, "main") or M.find_role_pane(tab, "dashboard") or tab:active_pane()
		-- エージェント一覧タブではメタエージェントを一覧の下に置く
		direction = role_of(base) == "dashboard" and "Bottom" or "Right"
		size = direction == "Right" and 0.4 or 0.6
	end
	local launcher = tool == "codex" and "codex-auto" or "claude-auto"
	local resume = ""
	if session_id and session_id ~= "" then
		resume = tool == "codex" and (" resume " .. shell_quote(session_id)) or (" --resume " .. shell_quote(session_id))
	end
	local cmd = string.format(
		"%s; %s; exec %s/%s%s",
		set_var_cmd("role", "agent"),
		set_var_cmd("tool", tool),
		BIN,
		launcher,
		resume
	)
	local pane = base:split({ direction = direction, size = size, cwd = pane_cwd(base), args = zsh(cmd) })
	M.on_change()
	return pane
end

-- エージェント一覧タブを作り、タブの先頭に置く
function M.spawn_dashboard(mux_window)
	local cmd = set_var_cmd("role", "dashboard") .. "; exec " .. BIN .. "/agent-dashboard"
	local tab, pane = mux_window:spawn_tab({ cwd = wezterm.home_dir, args = zsh(cmd) })
	tab:set_title(M.DASHBOARD_TITLE)
	return tab, pane
end

-- ワークスペースにエージェント一覧タブがなければ作る (update-status から毎秒呼ばれる)。
-- 作ったタブは先頭に移し、元のタブにフォーカスを戻す
function M.ensure_dashboard(window)
	local workspace = window:active_workspace()
	for _, w in ipairs(wezterm.mux.all_windows()) do
		if w:get_workspace() == workspace then
			for _, t in ipairs(w:tabs()) do
				-- 作った直後は user var がまだ届いていないので、タイトルでも判定する
				if t:get_title() == M.DASHBOARD_TITLE or M.is_dashboard(t) then
					return
				end
			end
		end
	end
	local previous = window:active_tab()
	local _, pane = M.spawn_dashboard(window:mux_window())
	window:perform_action(act.MoveTab(0), pane)
	if previous then
		previous:activate()
	end
end

----------------------------------------------------
-- キー操作
----------------------------------------------------

-- LEADER+n: 今のリポジトリの worktree を開く / 作る
function M.pick_worktree()
	return wezterm.action_callback(function(window, pane)
		local root = main_repo_root(pane_cwd(pane))
		if not root then
			window:toast_notification("worktree", "git リポジトリの中で実行してください", nil, 3000)
			return
		end
		local choices = { { id = "new", label = "＋ 新しいブランチで作る" } }
		local opened = {}
		local out = git(root, "worktree", "list", "--porcelain") or ""
		local path = nil
		for line in out:gmatch("[^\n]+") do
			local p = line:match("^worktree (.+)$")
			if p then
				path = p
			end
			local branch = line:match("^branch refs/heads/(.+)$")
			if branch and path then
				opened[branch] = true
				table.insert(choices, { id = "open:" .. path, label = branch .. "  (" .. basename(path) .. ")" })
			end
		end
		-- worktree になっていないローカルブランチ
		for branch in (git(root, "for-each-ref", "--format=%(refname:short)", "refs/heads") or ""):gmatch("[^\n]+") do
			if not opened[branch] then
				table.insert(choices, { id = "branch:" .. branch, label = branch .. "  (worktree を作る)" })
			end
		end

		local function create(branch, new_branch)
			local dest = worktree_path(root, branch)
			local args = new_branch and { "worktree", "add", "-b", branch, dest } or { "worktree", "add", dest, branch }
			local ok, err = git(root, table.unpack(args))
			if not ok then
				window:toast_notification("worktree", "作成に失敗しました: " .. trim(err), nil, 5000)
				return
			end
			M.spawn_worktree_tab(window:mux_window(), dest, { init = true })
		end

		window:perform_action(
			act.InputSelector({
				title = "worktree (" .. basename(root) .. ")",
				fuzzy = true,
				choices = choices,
				action = wezterm.action_callback(function(win, _, id)
					if not id then
						return
					end
					if id == "new" then
						win:perform_action(
							act.PromptInputLine({
								description = "新しいブランチ名:",
								action = wezterm.action_callback(function(w, _, line)
									if line and line ~= "" then
										create(line, true)
									end
								end),
							}),
							pane
						)
					elseif id:find("^branch:") then
						create(id:sub(8), false)
					else
						local dest = id:sub(6)
						-- 既に開いているタブがあればそこへ移動する
						for _, t in ipairs(win:mux_window():tabs()) do
							local main = M.find_role_pane(t, "main")
							if main and pane_cwd(main):gsub("/+$", "") == dest then
								t:activate()
								return
							end
						end
						M.spawn_worktree_tab(win:mux_window(), dest)
					end
				end),
			}),
			pane
		)
	end)
end

function M.launch_agent(tool)
	return wezterm.action_callback(function(window)
		local pane = M.spawn_agent(window:active_tab(), tool)
		pane:activate()
	end)
end

-- Cmd+e: メインの nvim へ
function M.focus_main()
	return wezterm.action_callback(function(window, pane)
		local target = M.find_role_pane(window:active_tab(), "main")
		if target then
			window:perform_action(act.SetPaneZoomState(false), pane)
			target:activate()
		end
	end)
end

-- Cmd+a: エージェントのペインへ。押すたびに次のエージェントへ
function M.cycle_agent()
	return wezterm.action_callback(function(window, pane)
		local agents = statusbar.agents_in_tab(window:active_tab())
		if #agents == 0 then
			return
		end
		local next_index = 1
		for i, item in ipairs(agents) do
			if item.pane:pane_id() == pane:pane_id() then
				next_index = i % #agents + 1
			end
		end
		window:perform_action(act.SetPaneZoomState(false), pane)
		agents[next_index].pane:activate()
	end)
end

-- LEADER+数字: n 番目のエージェントへ (タブバーの ① ② と同じ番号)
function M.focus_agent(n)
	return wezterm.action_callback(function(window, pane)
		local item = statusbar.agents_in_tab(window:active_tab())[n]
		if item then
			window:perform_action(act.SetPaneZoomState(false), pane)
			item.pane:activate()
		end
	end)
end

-- Cmd+0: エージェント一覧タブへ
function M.focus_dashboard()
	return wezterm.action_callback(function(window)
		for _, t in ipairs(window:mux_window():tabs()) do
			if t:get_title() == M.DASHBOARD_TITLE or M.is_dashboard(t) then
				t:activate()
				return
			end
		end
	end)
end

-- Cmd+w: タブを閉じる。エージェント一覧タブは閉じない
function M.close_tab()
	return wezterm.action_callback(function(window, pane)
		if M.is_dashboard(window:active_tab()) then
			window:toast_notification("agents", "エージェント一覧タブは閉じられません", nil, 2000)
			return
		end
		window:perform_action(act.CloseCurrentTab({ confirm = true }), pane)
	end)
end

-- LEADER+X: ペインを閉じる。エージェント一覧のペインは閉じない
function M.close_pane()
	return wezterm.action_callback(function(window, pane)
		if role_of(pane) == "dashboard" then
			window:toast_notification("agents", "エージェント一覧は閉じられません", nil, 2000)
			return
		end
		window:perform_action(act.CloseCurrentPane({ confirm = true }), pane)
	end)
end

return M
