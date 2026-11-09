-- タブ = worktree、ワークスペース = private / work / 案件 の運用を組み立てる
--
-- 各 worktree タブ:
--   左 (main)     : メインの nvim (neo-tree 常駐、ファイルとターミナル)。nvim を抜けても zsh が残る
--   右 (agent)    : そのタブのエージェントを縦に積んだ列 (そのまま操作できる。上からタブバーの ① ② の順、高さは等分)。
--                   Cmd+a / LEADER 数字でエージェントに移る。LEADER z で列ごと見えないワークスペース (STASH) に隠す / 出す
--                   (bin/agent-view)
--   幅            : nvim がファイルを開いていればエージェントの列は右に寄せ (全体の 30%)、ファイルがなければ
--                   nvim をツリーの幅まで縮めて列を広げる (nvim が user var workbench_layout で知らせる)。
--                   Cmd+Shift+a で、ファイルを開いていても列を広げる (ツリーを見ながら指示を出す) / 戻す
-- ワークスペースごとに閉じられないエージェント一覧タブ (dashboard) を 1 つ置く。
--
-- ペインの役割は、ペインの中のシェルが OSC 1337 SetUserVar で書き込む user var で見分ける
--   role = main / agent / dashboard、tool = claude / codex
-- エージェントがどのタブのものかは、状態ファイルの home (所属するペイン) で決める (statusbar.agents_in_tab)
-- (Lua 側のテーブルと違い、設定の自動リロードで消えない)
local wezterm = require("wezterm")
local act = wezterm.action
local statusbar = require("statusbar")

local M = {}

local BIN = wezterm.home_dir .. "/dotfiles/bin"
-- 作業環境の nvim が待ち受けるソケット (<WEZTERM_PANE>.sock)
local SOCKET_DIR = wezterm.home_dir .. "/.local/state/nvim/workbench"
M.DASHBOARD_TITLE = "◆ agents"
-- エージェントを置いておく見えないワークスペース (bin/agent-view と同じ名前)
M.STASH = "_agents"
-- nvim がファイルを開いていないとき (workbench_layout = tree) の nvim の幅: neo-tree (32) と区切り線
local TREE_COLS = 34
-- ファイルを開いているときのエージェントの幅: 全体に対する割合と最小のセル数。nvim にも最低限の幅を残す
local AGENT_RATIO = 0.3
local AGENT_MIN_COLS = 40
local MAIN_MIN_COLS = 60

-- 新しく作ったペイン・タブを知らせるコールバック (session.lua が保存のきっかけに使う)
M.on_change = function() end

local function shell_quote(s)
	return "'" .. tostring(s):gsub("'", [['\'']]) .. "'"
end

local function set_var_cmd(name, value)
	return string.format([[printf '\033]1337;SetUserVar=%s=%%s\a' "$(printf %%s %s | base64)"]], name, shell_quote(value))
end

-- ログインシェル経由で起動して PATH (homebrew / mise / ~/.local/bin) を引き継ぐ。
-- この版の WezTerm (20240203) はコマンド付きで spawn_tab / split すると cwd を無視して
-- 今のペインのディレクトリで起動するため、コマンドの先頭で cd する
function M.zsh(cmd, cwd)
	if cwd then
		cmd = "cd " .. shell_quote(cwd) .. " && " .. cmd
	end
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

function M.pane_cwd(pane)
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
	-- WezTerm から真ん中の切り替えを指示できるよう、ペインごとのソケットで待ち受ける (M.nvim_call)
	local nvim_args = "--cmd 'let g:start_with_explorer = 1'"
	cmd = cmd
		.. string.format(
			'; mkdir -p %s; sock=%s/"$WEZTERM_PANE".sock; rm -f "$sock"; nvim --listen "$sock" %s; exec /bin/zsh -l',
			shell_quote(SOCKET_DIR),
			shell_quote(SOCKET_DIR),
			nvim_args
		)
	local tab, pane = mux_window:spawn_tab({ cwd = path, args = M.zsh(cmd, path) })
	tab:set_title(basename(path))
	M.on_change()
	return tab, pane
end

-- エージェントが所属するペイン (home): 作業環境のメインの nvim、エージェント一覧、それ以外は今のペイン
function M.home_pane(tab, pane)
	local home = M.find_role_pane(tab, "main") or M.find_role_pane(tab, "dashboard")
	if home then
		return home
	end
	local first = statusbar.agents_in_tab(tab)[1]
	if first and first.agent.home then
		local ok, p = pcall(wezterm.mux.get_pane, first.agent.home)
		if ok and p then
			return p
		end
	end
	return pane or tab:active_pane()
end

-- エージェントを見えないワークスペースで起動する。session_id があればそのセッションを再開する。
-- home: 所属するペイン / cwd: 起動するディレクトリ (省略時は home の cwd)
function M.spawn_agent(home, tool, session_id, cwd)
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
	cwd = cwd or M.pane_cwd(home)
	local _, pane = wezterm.mux.spawn_window({
		workspace = M.STASH,
		cwd = cwd,
		args = M.zsh(cmd, cwd),
		-- bin/agent-state が状態ファイルの home に書く
		set_environment_variables = { AGENT_HOME = tostring(home:pane_id()) },
	})
	-- hook が状態を書く前から、所属するタブのエージェントとして数える
	os.execute("mkdir -p " .. shell_quote(statusbar.state_dir))
	local f = io.open(string.format("%s/%d.json", statusbar.state_dir, pane:pane_id()), "w")
	if f then
		f:write(wezterm.json_encode({
			tool = tool,
			state = "idle",
			pane = pane:pane_id(),
			home = home:pane_id(),
			session_id = session_id,
			cwd = cwd,
			updated_at = os.time(),
		}))
		f:close()
	end
	M.on_change()
	return pane
end

-- bin/agent-view show / hide を呼ぶ (エージェントをタブの右の列に積む / 見えないワークスペースに戻す)
local function agent_view(cmd, pane_id, ...)
	wezterm.run_child_process({ BIN .. "/agent-view", cmd, tostring(pane_id), ... })
end

-- タブに出ているエージェントを見えないワークスペースに戻す
local function hide_agents(tab)
	local in_tab = {}
	for _, p in ipairs(tab:panes()) do
		in_tab[p:pane_id()] = true
	end
	for _, item in ipairs(statusbar.agents_in_tab(tab)) do
		if in_tab[item.pane:pane_id()] and item.agent.home and item.agent.home ~= item.pane:pane_id() then
			agent_view("hide", item.pane:pane_id())
		end
	end
end

local function state_file(name, home)
	return string.format("%s/%s-%d", statusbar.state_dir, name, home:pane_id())
end

-- 最後に表示したエージェントのペイン ID (bin/agent-view が shown-<home> に書く)
local function last_shown(home)
	local f = io.open(state_file("shown", home), "r")
	if not f then
		return nil
	end
	local id = tonumber(f:read("*l") or "")
	f:close()
	return id
end

-- Cmd+Shift+a でエージェントを広げたタブ (タブ ID -> true)。設定を読み直しても消えないよう GLOBAL に置く
local function wide_tabs()
	wezterm.GLOBAL.agent_wide = wezterm.GLOBAL.agent_wide or {}
	return wezterm.GLOBAL.agent_wide
end

local function is_wide(tab)
	return wide_tabs()[tostring(tab:tab_id())] == true
end

local function cli(...)
	wezterm.run_child_process({ wezterm.executable_dir .. "/wezterm", "cli", ... })
end

-- wezterm cli adjust-pane-size は --pane-id のペインではなく、そのタブのアクティブなペインの境界を動かす。
-- 縦横それぞれ、そのペインに一番近い分割の境界が direction の向きに動く
local function adjust_pane(pane_id, amount, direction)
	cli("adjust-pane-size", "--pane-id", tostring(pane_id), "--amount", tostring(amount), direction)
end

-- 右の列のエージェントの高さを等分する。列は agent-view が一番下のエージェントを分割して積むので、
-- 上から順にそのエージェントをアクティブにして下の境界を動かし (動かすたびに高さを読み直す)、最後にフォーカスを戻す
local function equalize_column(tab, ids)
	local active = tab:active_pane()
	for i = 1, #ids - 1 do
		local heights = {}
		for _, info in ipairs(tab:panes_with_info()) do
			heights[info.pane:pane_id()] = info.height
		end
		local rest = 0
		for j = i, #ids do
			rest = rest + (heights[ids[j]] or 0)
		end
		local delta = math.floor(rest / (#ids - i + 1)) - (heights[ids[i]] or 0)
		if delta ~= 0 then
			cli("activate-pane", "--pane-id", tostring(ids[i]))
			adjust_pane(ids[i], math.abs(delta), delta > 0 and "Down" or "Up")
		end
	end
	if active and tab:active_pane():pane_id() ~= active:pane_id() then
		cli("activate-pane", "--pane-id", tostring(active:pane_id()))
	end
end

-- nvim とエージェントの列の幅を、nvim が知らせる workbench_layout と Cmd+Shift+a の切り替えに合わせ、列の高さを等分する。
-- 合わせたあとに手で大きさを変えても戻さないよう、(layout, Cmd+Shift+a の切り替え, 列のエージェント, 全体の大きさ)
-- が変わったときだけ合わせる
local applied = {}
function M.apply_layout(tab)
	local infos = tab:panes_with_info()
	local main, column = nil, {}
	for _, info in ipairs(infos) do
		local role = role_of(info.pane)
		if role == "main" then
			main = info
		elseif role == "agent" then
			table.insert(column, info)
		end
	end
	-- nvim と、その右に縦に積んだエージェントだけのタブ
	if not main or #column == 0 or #infos ~= #column + 1 then
		return
	end
	table.sort(column, function(a, b)
		return a.top < b.top
	end)
	local left, width = column[1].left, column[1].width
	if left <= main.left or column[1].top ~= main.top then
		return
	end
	local ids, height = {}, #column - 1
	for _, info in ipairs(column) do
		if info.left ~= left or info.width ~= width then
			return
		end
		table.insert(ids, info.pane:pane_id())
		height = height + info.height
	end
	-- 高さをそろえるときにペインをアクティブにするので、見ているタブだけ合わせる (ほかのタブは開いたときに合わせる)
	local window = tab:window()
	local current = window and window:active_tab()
	if not (current and current:tab_id() == tab:tab_id()) then
		return
	end
	local total = main.width + width + 1
	local layout = main.pane:get_user_vars().workbench_layout or ""
	local wide = is_wide(tab)
	local key = string.format("%s:%s:%s:%d:%d", layout, tostring(wide), table.concat(ids, ","), total, height)
	if applied[tab:tab_id()] == key then
		return
	end
	applied[tab:tab_id()] = key
	local target
	if layout == "tree" or wide then
		target = TREE_COLS
	else
		target = math.max(MAIN_MIN_COLS, total - 1 - math.max(AGENT_MIN_COLS, math.floor(total * AGENT_RATIO)))
	end
	-- 狭いウィンドウでもエージェントに 20 セルは残す
	target = math.max(1, math.min(target, total - 1 - 20))
	local delta = main.width - target
	-- 左右の境界は nvim と列のあいだにしかないので、どのペインがアクティブでも同じ境界が動く
	if delta ~= 0 then
		adjust_pane(main.pane:pane_id(), math.abs(delta), delta > 0 and "Left" or "Right")
	end
	equalize_column(tab, ids)
end

-- 作業環境のタブのエージェントが右の列にそろっていなければ、残りを列に積み (フォーカスは移さない)、
-- 大きさを合わせる (update-status から毎秒呼ばれる。復旧したタブ・エージェント一覧から起動したエージェント用)。
-- LEADER z で隠したタブには出さない
function M.ensure_agent_shown(window)
	local tab = window:active_tab()
	local main = tab and M.find_role_pane(tab, "main")
	if not main then
		return
	end
	local in_tab = {}
	for _, p in ipairs(tab:panes()) do
		in_tab[p:pane_id()] = true
	end
	local missing = nil
	for _, item in ipairs(statusbar.agents_in_tab(tab)) do
		if item.agent.home == main:pane_id() and not in_tab[item.pane:pane_id()] then
			missing = missing or item
		end
	end
	if not missing then
		M.apply_layout(tab)
		return
	end
	local hidden = io.open(state_file("hidden", main), "r")
	if hidden then
		hidden:close()
		return
	end
	agent_view("show", missing.pane:pane_id(), "--no-focus")
end

-- 所属するペインが無くなった (タブを閉じた) エージェントを止め、終了したエージェントの状態ファイルを消す。
-- update-status から毎秒呼ばれる
function M.cleanup_agents()
	for id, agent in pairs(statusbar.read_agents()) do
		local ok_home, home = pcall(wezterm.mux.get_pane, agent.home or -1)
		local ok, pane = pcall(wezterm.mux.get_pane, id)
		if not (ok and pane) then
			os.remove(string.format("%s/%d.json", statusbar.state_dir, id))
		elseif agent.home and not (ok_home and home) then
			local window = pane:window()
			if window and window:get_workspace() == M.STASH then
				wezterm.run_child_process({ wezterm.executable_dir .. "/wezterm", "cli", "kill-pane", "--pane-id", tostring(id) })
			end
		end
	end
end

-- エージェント一覧タブで動かすコマンド (session.lua がウィンドウを作るときにも使う)
function M.dashboard_args()
	return M.zsh(set_var_cmd("role", "dashboard") .. "; exec " .. BIN .. "/agent-dashboard", wezterm.home_dir)
end

-- エージェント一覧タブを作る
function M.spawn_dashboard(mux_window)
	local tab, pane = mux_window:spawn_tab({ cwd = wezterm.home_dir, args = M.dashboard_args() })
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
		local root = main_repo_root(M.pane_cwd(pane))
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
							if main and M.pane_cwd(main):gsub("/+$", "") == dest then
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

-- Cmd+t: 今のペインのディレクトリで作業環境のタブ (nvim + ツリー) を開く。
-- エージェント一覧タブからはホームで開く
function M.new_env_tab()
	return wezterm.action_callback(function(window, pane)
		local cwd = role_of(pane) == "dashboard" and wezterm.home_dir or M.pane_cwd(pane)
		M.spawn_worktree_tab(window:mux_window(), cwd)
	end)
end

----------------------------------------------------
-- 作業環境の nvim (真ん中のファイル・ターミナル・エージェント) を操作する
----------------------------------------------------

local NVIM = nil
local function nvim_bin()
	if not NVIM then
		NVIM = "nvim"
		for _, p in ipairs({ "/opt/homebrew/bin/nvim", "/usr/local/bin/nvim" }) do
			if wezterm.run_child_process({ "test", "-x", p }) then
				NVIM = p
				break
			end
		end
	end
	return NVIM
end

-- メインの nvim の workbench.rpc(name, ...) を呼ぶ。引数は数値か文字列
function M.nvim_call(main_pane, name, ...)
	local args = { string.format("'%s'", name) }
	for _, v in ipairs({ ... }) do
		table.insert(args, type(v) == "number" and tostring(v) or string.format("'%s'", v))
	end
	local sock = string.format("%s/%d.sock", SOCKET_DIR, main_pane:pane_id())
	local ok = wezterm.run_child_process({
		nvim_bin(),
		"--server",
		sock,
		"--remote-expr",
		"v:lua.require'workbench'.rpc(" .. table.concat(args, ", ") .. ")",
	})
	return ok
end

-- 作業環境のタブなら、メインの nvim のペインに移ってから name を呼ぶ (右のエージェントはそのまま)。
-- 作業環境でなければ false
local function in_workbench(window, pane, name, ...)
	local tab = window:active_tab()
	local main = M.find_role_pane(tab, "main")
	if not main then
		return false
	end
	main:activate()
	M.nvim_call(main, name, ...)
	return true
end

-- LEADER+c / LEADER+x: エージェントを起動して右の列の一番下に積み、フォーカスを移す
function M.launch_agent(tool)
	return wezterm.action_callback(function(window, pane)
		local tab = window:active_tab()
		local home = M.home_pane(tab, pane)
		local agent = M.spawn_agent(home, tool)
		agent_view("show", agent:pane_id())
	end)
end

-- LEADER+t: 真ん中に新しいターミナルを開く
function M.new_terminal()
	return wezterm.action_callback(function(window, pane)
		in_workbench(window, pane, "open")
	end)
end

-- Cmd+j: 真ん中のターミナルとファイルを行き来する
function M.toggle_terminal()
	return wezterm.action_callback(function(window, pane)
		in_workbench(window, pane, "toggle_terminal")
	end)
end

-- Cmd+[ / Cmd+]: 真ん中のタブを左右に移動する
function M.cycle_center(step)
	return wezterm.action_callback(function(window, pane)
		in_workbench(window, pane, "cycle", step)
	end)
end

-- Cmd+e: ファイル (メインの nvim の編集画面) へ。右のエージェントはそのまま
function M.focus_main()
	return wezterm.action_callback(function(window, pane)
		in_workbench(window, pane, "editor")
	end)
end

-- タブに出ているエージェントの番号 (出ていなければ nil)
local function shown_index(tab, agents)
	local in_tab = {}
	for _, p in ipairs(tab:panes()) do
		in_tab[p:pane_id()] = true
	end
	for i, item in ipairs(agents) do
		if in_tab[item.pane:pane_id()] then
			return i
		end
	end
	return nil
end

-- Cmd+a: 右の列の次のエージェントへ (nvim からは一番上へ)。隠していれば列を出す
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
		agent_view("show", agents[next_index].pane:pane_id())
	end)
end

-- LEADER+数字: n 番目のエージェントへ (タブバーの ① ② と同じ番号)。隠していれば列を出す
function M.focus_agent(n)
	return wezterm.action_callback(function(window)
		local item = statusbar.agents_in_tab(window:active_tab())[n]
		if item then
			agent_view("show", item.pane:pane_id())
		end
	end)
end

-- Cmd+Shift+a: ファイルを開いていても、ツリーだけ残してエージェントの列を広げる / 戻す (タブごと)。
-- 列を隠していれば出す
function M.toggle_agent_wide()
	return wezterm.action_callback(function(window, pane)
		local tab = window:active_tab()
		if not M.find_role_pane(tab, "main") then
			return
		end
		local id = tostring(tab:tab_id())
		local tabs = wide_tabs()
		tabs[id] = not tabs[id] or nil
		wezterm.GLOBAL.agent_wide = tabs
		local agents = statusbar.agents_in_tab(tab)
		if #agents > 0 and not shown_index(tab, agents) then
			local target, last = agents[1], last_shown(M.home_pane(tab, pane))
			for _, item in ipairs(agents) do
				if item.pane:pane_id() == last then
					target = item
				end
			end
			agent_view("show", target.pane:pane_id(), "--no-focus")
		end
		M.apply_layout(tab)
	end)
end

-- LEADER+z: 右のエージェントの列を隠す / 出して最後に見たエージェントに移る (隠している間は自動で出さない)。
-- エージェントのいないタブでは、ふつうのペインの拡大・縮小
function M.toggle_agent()
	return wezterm.action_callback(function(window, pane)
		local tab = window:active_tab()
		local agents = statusbar.agents_in_tab(tab)
		if #agents == 0 then
			window:perform_action(act.TogglePaneZoomState, pane)
			return
		end
		if shown_index(tab, agents) then
			hide_agents(tab)
			return
		end
		local target, last = agents[1], last_shown(M.home_pane(tab, pane))
		for _, item in ipairs(agents) do
			if item.pane:pane_id() == last then
				target = item
			end
		end
		agent_view("show", target.pane:pane_id())
	end)
end

local function find_dashboard_tab(mux_window)
	for _, t in ipairs(mux_window:tabs()) do
		if t:get_title() == M.DASHBOARD_TITLE or M.is_dashboard(t) then
			return t
		end
	end
	return nil
end

-- LEADER+w: ワークスペースを選ぶ。作業環境 (タブ) の数とエージェントの状態を添えて並べ、
-- 入ったらエージェント一覧タブ (作業環境 → エージェントの一覧) を表示する
function M.pick_workspace()
	return wezterm.action_callback(function(window, pane)
		local agents = statusbar.read_agents()
		local summary, order = {}, {}
		for _, w in ipairs(wezterm.mux.all_windows()) do
			local name = w:get_workspace()
			if name == M.STASH then
				goto continue
			end
			if not summary[name] then
				summary[name] = { envs = 0, states = {} }
				table.insert(order, name)
			end
			for _, t in ipairs(w:tabs()) do
				if not (t:get_title() == M.DASHBOARD_TITLE or M.is_dashboard(t)) then
					summary[name].envs = summary[name].envs + 1
				end
				for _, item in ipairs(statusbar.agents_in_tab(t, agents)) do
					table.insert(summary[name].states, statusbar.STATE_ICON[item.agent.state] or "·")
				end
			end
			::continue::
		end
		local current = window:active_workspace()
		local choices = {}
		for _, name in ipairs(order) do
			local s = summary[name]
			table.insert(choices, {
				id = name,
				label = string.format(
					"%s%s   作業環境 %d   %s",
					name == current and "● " or "  ",
					name,
					s.envs,
					#s.states > 0 and table.concat(s.states, " ") or ""
				),
			})
		end
		window:perform_action(
			act.InputSelector({
				title = "workspace",
				fuzzy = true,
				choices = choices,
				action = wezterm.action_callback(function(win, p, id)
					if not id then
						return
					end
					-- 切り替える前に、行き先のエージェント一覧タブをアクティブにしておく
					for _, w in ipairs(wezterm.mux.all_windows()) do
						if w:get_workspace() == id then
							local t = find_dashboard_tab(w)
							if t then
								t:activate()
							end
						end
					end
					win:perform_action(act.SwitchToWorkspace({ name = id }), p)
				end),
			}),
			pane
		)
	end)
end

-- Cmd+0: エージェント一覧タブへ
function M.focus_dashboard()
	return wezterm.action_callback(function(window)
		local t = find_dashboard_tab(window:mux_window())
		if t then
			t:activate()
		end
	end)
end

-- Cmd+w: タブを閉じる。エージェント一覧タブは閉じない。
-- エージェントは見えないワークスペースにいてタブを閉じても止まらないので、確認してから一緒に止める
function M.close_tab()
	return wezterm.action_callback(function(window, pane)
		local tab = window:active_tab()
		if M.is_dashboard(tab) then
			window:toast_notification("agents", "エージェント一覧タブは閉じられません", nil, 2000)
			return
		end
		local agents = statusbar.agents_in_tab(tab)
		if #agents == 0 then
			window:perform_action(act.CloseCurrentTab({ confirm = true }), pane)
			return
		end
		window:perform_action(
			act.InputSelector({
				title = string.format("タブを閉じて、エージェント %d 個も止めますか?", #agents),
				choices = { { id = "no", label = "閉じない" }, { id = "yes", label = "閉じて止める" } },
				action = wezterm.action_callback(function(win, p, id)
					if id ~= "yes" then
						return
					end
					for _, item in ipairs(agents) do
						wezterm.run_child_process({
							wezterm.executable_dir .. "/wezterm", "cli", "kill-pane", "--pane-id", tostring(item.pane:pane_id()),
						})
					end
					win:perform_action(act.CloseCurrentTab({ confirm = false }), p)
				end),
			}),
			pane
		)
	end)
end

-- LEADER+X: ペインを閉じる。エージェント一覧のペインは閉じない。作業環境の nvim では真ん中のもの (ファイル・ターミナル) を閉じる
function M.close_pane()
	return wezterm.action_callback(function(window, pane)
		if role_of(pane) == "dashboard" then
			window:toast_notification("agents", "エージェント一覧は閉じられません", nil, 2000)
			return
		end
		if role_of(pane) == "main" then
			M.nvim_call(pane, "close")
			return
		end
		window:perform_action(act.CloseCurrentPane({ confirm = true }), pane)
	end)
end

return M
