-- 作業環境 (WezTerm の worktree タブ) の真ん中で、ファイルとターミナルを切り替える (Orca 風)
--
--   ┌ neo-tree ┬ [file.ts] [ Terminal] ┐ ← bufferline のタブ
--   │          │  選んだものを 1 つ表示   │
--
-- - ターミナルは nvim の中のターミナルバッファ。エージェント (Claude Code / Codex) は nvim の外の
--   WezTerm のペインで動かす (wezterm/workspace.lua。nvim の中だと nvim のキーが効かず、監視もしにくい)
-- - WezTerm のキー (Cmd+e / Cmd+j / LEADER t など) は nvim --server <ソケット> --remote-expr で M.rpc を呼ぶ
local M = {}

local last_file_buf = nil

local function info(buf)
	return vim.api.nvim_buf_is_valid(buf) and vim.b[buf].workbench or nil
end

-- 真ん中のウィンドウ: 今のウィンドウがツリーや浮動ウィンドウでなければそれ、違えば最初の普通のウィンドウ
local function center_win()
	local function usable(win)
		if vim.api.nvim_win_get_config(win).relative ~= "" then
			return false
		end
		return vim.bo[vim.api.nvim_win_get_buf(win)].filetype ~= "neo-tree"
	end
	local cur = vim.api.nvim_get_current_win()
	if usable(cur) then
		return cur
	end
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if usable(win) then
			return win
		end
	end
	vim.cmd("botright vnew")
	return vim.api.nvim_get_current_win()
end

-- ターミナルのバッファ (開いた順)
local function list()
	local out = {}
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if info(buf) then
			table.insert(out, buf)
		end
	end
	return out
end

-- 真ん中に buf を出してフォーカスする。ターミナルなら入力できる状態にする
function M.show(buf)
	local win = center_win()
	vim.api.nvim_set_current_win(win)
	vim.api.nvim_win_set_buf(win, buf)
	if info(buf) then
		vim.cmd("startinsert")
	end
end

-- ファイルに戻る (最後に開いていたファイル。なければ空のバッファ)
function M.editor()
	if last_file_buf and vim.api.nvim_buf_is_valid(last_file_buf) then
		M.show(last_file_buf)
	else
		local win = center_win()
		vim.api.nvim_set_current_win(win)
		if info(vim.api.nvim_win_get_buf(win)) then
			vim.cmd("enew")
		end
	end
	vim.cmd("stopinsert")
end

-- 終了したターミナルのバッファを片付け、表示していたウィンドウはファイルに戻す
local function on_exit(buf)
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	for _, win in ipairs(vim.fn.win_findbuf(buf)) do
		vim.api.nvim_win_call(win, function()
			if last_file_buf and vim.api.nvim_buf_is_valid(last_file_buf) then
				vim.api.nvim_win_set_buf(win, last_file_buf)
			else
				vim.cmd("enew")
			end
		end)
	end
	pcall(vim.api.nvim_buf_delete, buf, { force = true })
end

-- ターミナルを開く。opts.cwd: 起動するディレクトリ / opts.background: 表示しない
function M.open(opts)
	opts = type(opts) == "table" and opts or {}
	local buf = vim.api.nvim_create_buf(true, false)
	vim.b[buf].workbench = { kind = "term" }
	local function start()
		vim.fn.jobstart({ vim.o.shell }, {
			term = true,
			cwd = opts.cwd or vim.fn.getcwd(),
			on_exit = function()
				vim.schedule(function()
					on_exit(buf)
				end)
			end,
		})
	end
	if opts.background then
		vim.api.nvim_buf_call(buf, start)
	else
		M.show(buf)
		start()
		vim.cmd("startinsert")
	end
	vim.bo[buf].buflisted = true
	return buf
end

-- Ctrl+/ / Cmd+j: ターミナルとファイルを行き来する (ターミナルがなければ作る)
function M.toggle_terminal()
	local cur = info(vim.api.nvim_win_get_buf(center_win()))
	if cur then
		return M.editor()
	end
	local terms = list()
	if #terms > 0 then
		M.show(terms[#terms])
	else
		M.open()
	end
end

-- 真ん中のタブを左右に移動する (bufferline の並び順)
function M.cycle(step)
	vim.api.nvim_set_current_win(center_win())
	vim.cmd("stopinsert")
	vim.cmd(step > 0 and "BufferLineCycleNext" or "BufferLineCyclePrev")
end

-- 真ん中に出ているもの (ファイル・ターミナル) を閉じる
function M.close()
	local win = center_win()
	local buf = vim.api.nvim_win_get_buf(win)
	if info(buf) then
		pcall(vim.fn.jobstop, vim.b[buf].terminal_job_id)
		on_exit(buf)
	else
		-- :bdelete だとウィンドウごと閉じてツリーだけが残り、nvim が終了してしまう
		Snacks.bufdelete(buf)
	end
end

-- WezTerm から呼ぶ入口。--remote-expr の応答を待たせないよう、処理は後回しにしてすぐ返す
function M.rpc(name, ...)
	local args = { ... }
	vim.schedule(function()
		M[name](unpack(args))
	end)
	return ""
end

----------------------------------------------------
-- bufferline の表示
----------------------------------------------------

-- bufferline の name_formatter から呼ぶ。ターミナルのバッファ以外は nil (通常の表示)
function M.buf_label(bufnr)
	return info(bufnr) and " Terminal" or nil
end

----------------------------------------------------
-- 起動
----------------------------------------------------

-- 作業環境の nvim の起動時 (VimEnter) に呼ぶ。restored = 前回のファイルを開き直せたか。
-- ターミナルを 1 つ用意する (ファイルがなければそれを表示する)
function M.start(restored)
	M.open({ background = restored })
	if restored then
		vim.cmd("stopinsert")
	end
	-- 起動直後の空のバッファ ([No Name]) がタブに残らないよう消す
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if
			vim.bo[buf].buflisted
			and not info(buf)
			and vim.api.nvim_buf_get_name(buf) == ""
			and not vim.bo[buf].modified
			and #vim.fn.win_findbuf(buf) == 0
		then
			pcall(vim.api.nvim_buf_delete, buf, {})
		end
	end
end

-- WezTerm のシェルから nvim / v (nvim .) で開いたときも、作業環境と同じ画面 (ツリー + 真ん中) にする。
-- init.lua の先頭 (プラグインを読む前) で呼ぶ。対象は WezTerm の中で、引数なしかディレクトリ 1 つで起動したときだけ
-- (ファイルを指定した起動や、git commit・Claude から呼ばれるエディタ、nvim の中の nvim はそのまま)。
-- 作業環境のタブ (wezterm/workspace.lua) と同じく、
--   - ペインの role を main にして、WezTerm にメインの nvim として扱わせる (タブ名・Cmd+e・エージェントの所属先)
--   - <WEZTERM_PANE>.sock で待ち受けて、WezTerm のキーで真ん中を切り替えられるようにする
-- 終了したら role を戻す
local SOCKET_DIR = vim.fn.expand("~/.local/state/nvim/workbench")

local function set_role(value)
	-- OSC 1337 SetUserVar を端末に送る (WezTerm の user var)
	pcall(vim.fn.chansend, vim.v.stderr, "\27]1337;SetUserVar=role=" .. vim.base64.encode(value) .. "\7")
end

function M.from_shell()
	if vim.g.start_with_explorer == 1 or not vim.env.WEZTERM_PANE or vim.env.NVIM then
		return
	end
	for _, a in ipairs(vim.v.argv) do
		-- 通常の起動でも設定は --embed の子プロセスで読まれるので、--embed は除外しない
		if a == "--headless" or a == "-es" or a == "-Es" then
			return
		end
	end
	local argc = vim.fn.argc()
	if argc == 1 and vim.fn.isdirectory(vim.fn.argv(0)) == 1 then
		-- nvim . / nvim <dir>: そのディレクトリで作業環境を開く (ディレクトリ自体は開かない)
		vim.cmd.cd(vim.fn.fnameescape(vim.fn.argv(0)))
		vim.cmd("silent! %argdelete")
		-- それでも oil がディレクトリのバッファを開くので、VimEnter で片付ける (plugin.lua)
		vim.g.workbench_from_dir = 1
	elseif argc ~= 0 then
		return
	end
	vim.g.start_with_explorer = 1
	local sock = SOCKET_DIR .. "/" .. vim.env.WEZTERM_PANE .. ".sock"
	if vim.v.servername ~= sock then
		vim.fn.mkdir(SOCKET_DIR, "p")
		os.remove(sock)
		pcall(vim.fn.serverstart, sock)
	end
	set_role("main")
	vim.api.nvim_create_autocmd("VimLeavePre", {
		callback = function()
			set_role("")
		end,
	})
end

function M.setup()
	local group = vim.api.nvim_create_augroup("workbench", { clear = true })
	vim.api.nvim_create_autocmd("BufEnter", {
		group = group,
		callback = function(ev)
			local buf = ev.buf
			if info(buf) then
				vim.cmd("startinsert")
			elseif vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_name(buf) ~= "" then
				last_file_buf = buf
			end
		end,
	})
end

return M
