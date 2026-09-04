-- GitHub PR レビュー: gh pr list → fzf-lua で選択 → git worktree に PR head を展開 →
-- gitsigns の base を merge-base に切り替え + diffview でベースブランチとの差分を開く
--
-- 既存の作業ツリーには一切触れず、PR ごとに別ディレクトリ (worktree) を使う。
-- worktree 内では通常どおり LSP / fzf-lua / neo-tree が使えるので、
-- プロジェクト全体を見ながら、ガターのサインと ]c / [c で PR の変更箇所を辿れる。

local M = {}

-- 進行中のレビュー状態 (同時に 1 件のみ)
--   number     : PR 番号
--   base       : ベースブランチ名 (例: main)
--   worktree   : worktree のパス
--   merge_base : origin/<base> と PR head の merge-base (gitsigns の比較対象)
--   tab        : worktree 用に開いたタブページ
--   diff_tab   : diffview が開いているタブページ
local state = nil

local function notify(msg, level)
	vim.notify("[PR review] " .. msg, level or vim.log.levels.INFO)
end

-- 現在のカレントディレクトリが属する git リポジトリのルート
local function git_root()
	local out = vim.fn.systemlist("git rev-parse --show-toplevel")[1]
	if vim.v.shell_error ~= 0 then
		return nil
	end
	return out
end

-- PR 用 worktree のパス
-- ASSUMPTION: リポジトリの隣に <repo名>-pr-<番号> を作る (例: ~/Documents/foo → ~/Documents/foo-pr-123)。
--             WezTerm のタブ = プロジェクトディレクトリという運用に乗せやすいよう、隠しディレクトリにはしない。
local function worktree_path(root, number)
	return string.format("%s-pr-%d", root, number)
end

-- PR head を保持するローカル ref。ブランチにしないことで、
-- 同名ブランチが既に checkout 済みでも衝突せず、fork からの PR も同じ手順で扱える
local function pr_ref(number)
	return string.format("refs/pr/%d", number)
end

-- vim.system の薄いラッパー。失敗時は通知して on_ok を呼ばない
local function run(cmd, cwd, on_ok)
	vim.system(cmd, { cwd = cwd, text = true }, function(out)
		vim.schedule(function()
			if out.code ~= 0 then
				notify(table.concat(cmd, " ") .. " に失敗しました\n" .. (out.stderr or ""), vim.log.levels.ERROR)
				return
			end
			on_ok(out)
		end)
	end)
end

-- diffview のタブが生きているか
local function diff_tab_valid()
	return state and state.diff_tab and vim.api.nvim_tabpage_is_valid(state.diff_tab)
end

-- worktree 上で diffview を開く (origin/<base>...HEAD = GitHub の PR タブと同じ merge-base 比較)
local function open_diffview()
	vim.cmd(string.format("DiffviewOpen -C%s origin/%s...HEAD", vim.fn.fnameescape(state.worktree), state.base))
	state.diff_tab = vim.api.nvim_get_current_tabpage()
end

-- worktree の準備が整った後: nvim 側のセットアップ
local function enter_review(pr, root, worktree)
	run({ "git", "merge-base", "origin/" .. pr.baseRefName, "HEAD" }, worktree, function(out)
		local merge_base = vim.trim(out.stdout)

		-- 新しいタブページで worktree に tcd (元プロジェクトのタブはそのまま残す)
		vim.cmd("tabnew")
		vim.cmd("tcd " .. vim.fn.fnameescape(worktree))

		-- gitsigns の比較対象を merge-base にする → ガターのサインが「PR での変更」になる
		-- global=true なので元プロジェクトのバッファにも効くが、終了時に reset する
		require("gitsigns").change_base(merge_base, true)

		state = {
			number = pr.number,
			base = pr.baseRefName,
			worktree = worktree,
			merge_base = merge_base,
			tab = vim.api.nvim_get_current_tabpage(),
			root = root,
		}
		open_diffview()
		notify(string.format("#%d %s (base: %s)\nworktree: %s", pr.number, pr.title, pr.baseRefName, worktree))
	end)
end

-- PR head を fetch して worktree を用意する
local function prepare_worktree(pr, root)
	local worktree = worktree_path(root, pr.number)
	local ref = pr_ref(pr.number)

	notify(string.format("#%d を fetch 中...", pr.number))
	-- ベースブランチ (origin/<base> の更新) と PR head を同時に取得
	run({ "git", "fetch", "origin", pr.baseRefName, "+refs/pull/" .. pr.number .. "/head:" .. ref }, root, function()
		if vim.fn.isdirectory(worktree) == 1 then
			-- 既存 worktree を最新の PR head に合わせる (未コミットの変更があれば git が拒否する)
			run({ "git", "checkout", "--detach", ref }, worktree, function()
				enter_review(pr, root, worktree)
			end)
		else
			run({ "git", "worktree", "add", "--detach", worktree, ref }, root, function()
				enter_review(pr, root, worktree)
			end)
		end
	end)
end

-- gh pr list → fzf-lua で選択
local function pick_pr(root)
	run({
		"gh",
		"pr",
		"list",
		"--limit",
		"100",
		"--json",
		"number,title,headRefName,baseRefName,author",
	}, root, function(out)
		local prs = vim.json.decode(out.stdout)
		if #prs == 0 then
			notify("オープンな PR がありません", vim.log.levels.WARN)
			return
		end

		local by_number = {}
		local entries = {}
		for _, pr in ipairs(prs) do
			by_number[pr.number] = pr
			table.insert(
				entries,
				string.format("#%-5d %s  [%s] %s → %s", pr.number, pr.title, pr.author.login, pr.headRefName, pr.baseRefName)
			)
		end

		require("fzf-lua").fzf_exec(entries, {
			prompt = "PR> ",
			actions = {
				["default"] = function(selected)
					local number = tonumber(selected[1]:match("^#(%d+)"))
					local pr = by_number[number]
					if pr then
						prepare_worktree(pr, root)
					end
				end,
			},
		})
	end)
end

-- PR 番号を直接指定してレビューを開始する (:lua require("pr_review").review(123))
function M.review(number)
	if state then
		notify(string.format("#%d のレビュー中です。先に <Leader>gP で終了してください", state.number), vim.log.levels.WARN)
		return
	end
	local root = git_root()
	if not root then
		notify("git リポジトリ内で実行してください", vim.log.levels.WARN)
		return
	end
	run({ "gh", "pr", "view", tostring(number), "--json", "number,title,headRefName,baseRefName" }, root, function(out)
		prepare_worktree(vim.json.decode(out.stdout), root)
	end)
end

-- <Leader>gp: レビュー開始 / レビュー中は diffview の開閉トグル
function M.start_or_toggle()
	if state then
		if diff_tab_valid() then
			vim.api.nvim_set_current_tabpage(state.diff_tab)
			vim.cmd("DiffviewClose")
		else
			vim.api.nvim_set_current_tabpage(state.tab)
			open_diffview()
		end
		return
	end

	local root = git_root()
	if not root then
		notify("git リポジトリ内で実行してください", vim.log.levels.WARN)
		return
	end
	pick_pr(root)
end

-- <Leader>gP: レビュー終了 (diffview を閉じ、gitsigns の base を戻し、タブを閉じる)
-- worktree は確認のうえ削除する (未コミットの変更があれば git が拒否するので残る)
function M.finish()
	if not state then
		notify("進行中のレビューはありません", vim.log.levels.WARN)
		return
	end
	local s = state
	state = nil

	if s.diff_tab and vim.api.nvim_tabpage_is_valid(s.diff_tab) then
		vim.api.nvim_set_current_tabpage(s.diff_tab)
		vim.cmd("DiffviewClose")
	end
	require("gitsigns").reset_base(true)
	if vim.api.nvim_tabpage_is_valid(s.tab) and #vim.api.nvim_list_tabpages() > 1 then
		vim.api.nvim_set_current_tabpage(s.tab)
		vim.cmd("tabclose")
	end

	local choice = vim.fn.confirm(
		string.format("#%d の worktree を削除しますか?\n%s", s.number, s.worktree),
		"&Yes\n&No",
		2
	)
	if choice == 1 then
		run({ "git", "worktree", "remove", s.worktree }, s.root, function()
			vim.fn.system({ "git", "-C", s.root, "update-ref", "-d", pr_ref(s.number) })
			notify("worktree を削除しました: " .. s.worktree)
		end)
	end
end

return M
