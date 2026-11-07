-- worktree ごとに、開いていたファイルとカーソル位置を保存・復元する
--
-- WezTerm の worktree タブで起動したメインの nvim (g:start_with_explorer = 1) だけが対象。
-- :mksession はウィンドウ配置まで保存するが、neo-tree やターミナルのウィンドウが壊れた状態で
-- 戻るため使わず、ファイル一覧だけを JSON で持つ。
-- PC の再起動では VimLeavePre が走らないことがあるので、バッファ切り替えや保存のたびに書き出す。

local M = {}

local dir = vim.fn.stdpath("state") .. "/worktree-sessions"

-- cwd ごとのファイル名 (パスの区切りを % に置き換える。:mksession の慣習と同じ)
local function session_file(cwd)
	return dir .. "/" .. cwd:gsub("/", "%%") .. ".json"
end

-- 復元対象にする通常のファイルバッファか
local function is_file_buffer(buf)
	if not vim.api.nvim_buf_is_valid(buf) or not vim.bo[buf].buflisted or vim.bo[buf].buftype ~= "" then
		return false
	end
	local name = vim.api.nvim_buf_get_name(buf)
	return name ~= "" and vim.fn.filereadable(name) == 1
end

function M.save()
	local cwd = vim.fn.getcwd()
	-- ウィンドウに表示中のファイルはそのウィンドウのカーソル位置を使う
	local shown = {}
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		local buf = vim.api.nvim_win_get_buf(win)
		if is_file_buffer(buf) and not shown[buf] then
			shown[buf] = vim.api.nvim_win_get_cursor(win)
		end
	end
	local files = {}
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if is_file_buffer(buf) then
			-- 表示していないバッファは、最後に離れたときの位置 ('" マーク)
			local pos = shown[buf] or vim.api.nvim_buf_get_mark(buf, '"')
			table.insert(files, { path = vim.api.nvim_buf_get_name(buf), line = pos[1], col = pos[2] })
		end
	end
	-- 開き直すファイル: 今のウィンドウ、ツリーやターミナルにいるなら直前のウィンドウのファイル
	local current = nil
	for _, win in ipairs({ vim.api.nvim_get_current_win(), vim.fn.win_getid(vim.fn.winnr("#")) }) do
		if win ~= 0 and vim.api.nvim_win_is_valid(win) and is_file_buffer(vim.api.nvim_win_get_buf(win)) then
			current = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
			break
		end
	end
	local data = { cwd = cwd, files = files, current = current }
	vim.fn.mkdir(dir, "p")
	vim.fn.writefile({ vim.json.encode(data) }, session_file(cwd))
end

-- 保存済みのファイルを開き直す。何も開けなければ false
function M.restore()
	local path = session_file(vim.fn.getcwd())
	if vim.fn.filereadable(path) == 0 then
		return false
	end
	local ok, data = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
	if not ok or type(data) ~= "table" or type(data.files) ~= "table" then
		return false
	end
	local target = nil
	for _, f in ipairs(data.files) do
		if vim.fn.filereadable(f.path) == 1 then
			vim.cmd("badd " .. vim.fn.fnameescape(f.path))
			if f.path == data.current or not target then
				target = f
			end
		end
	end
	if not target then
		return false
	end
	vim.cmd("edit " .. vim.fn.fnameescape(target.path))
	pcall(vim.api.nvim_win_set_cursor, 0, { target.line > 0 and target.line or 1, target.col or 0 })
	return true
end

function M.setup()
	if vim.g.start_with_explorer ~= 1 then
		return
	end
	local group = vim.api.nvim_create_augroup("worktree_session", { clear = true })
	vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "FocusLost", "VimLeavePre" }, {
		group = group,
		callback = function()
			-- 起動直後 (復元前) の空の状態で上書きしないよう、VimEnter が終わってから保存する
			if vim.v.vim_did_enter == 1 then
				M.save()
			end
		end,
	})
end

return M
