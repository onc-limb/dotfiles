-- ライト / ダークは WezTerm と同じ (~/.config/wezterm/palette.lua が ~/.local/state/wezterm/theme を読む)。
-- vscode.nvim が vim.o.background に追従して Light / Dark テーマになる。WezTerm で LEADER+b を押すと、
-- 開いている nvim も切り替わる (plugin.lua の vscode.nvim の設定)。
-- WezTerm のシェルから nvim / v で開いたときも、作業環境と同じ画面にする (プラグインを読む前に決める)
require("workbench").from_shell()

local palette_ok, palette = pcall(dofile, vim.fn.expand("~/.config/wezterm/palette.lua"))
vim.o.background = palette_ok and type(palette) == "table" and palette.mode or "light"

vim.opt.number = true
vim.opt.cursorline = true -- 現在行をハイライト (VSCode の editor.lineHighlight 相当)
vim.opt.signcolumn = "yes" -- gitsigns/診断でガターが出たり消えたりして揺れるのを防ぐ

-- 基本オプション
vim.opt.clipboard = "unnamedplus" -- y/p を macOS のクリップボードと共有
vim.opt.undofile = true -- ファイルを閉じても undo 履歴を保持
vim.opt.ignorecase = true -- 検索で大文字小文字を無視
vim.opt.smartcase = true -- ただし大文字を含む検索では区別する
vim.opt.scrolloff = 5 -- カーソルの上下に常に確保する行数
vim.opt.splitright = true -- 縦分割は右に開く
vim.opt.splitbelow = true -- 横分割は下に開く
-- コマンド行は普段隠し、: を押したときだけステータス行の位置に出す (画面の一番下まで本文を使う)
vim.opt.cmdheight = 0

-- =========================
-- 外部変更の自動リロード
-- =========================
-- 別プロセス (Claude Code 等) がファイルを書き換えたら自動で読み直す
-- (バッファに未保存の変更がある場合は上書きせず警告が出る)
vim.opt.autoread = true

-- フォーカス復帰・バッファ切替・カーソル停止時に外部変更をチェック
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold" }, {
	callback = function()
		if vim.fn.getcmdwintype() == "" then
			vim.cmd("checktime")
		end
	end,
})

-- フォーカスが当たっていない間も検知できるよう 1 秒間隔でポーリング
local checktime_timer = vim.loop.new_timer()
checktime_timer:start(
	1000,
	1000,
	vim.schedule_wrap(function()
		if vim.fn.mode() == "n" and vim.fn.getcmdwintype() == "" then
			vim.cmd("silent! checktime")
		end
	end)
)

-- 再読込が起きたら通知する
vim.api.nvim_create_autocmd("FileChangedShellPost", {
	callback = function()
		vim.notify("外部で変更されたファイルを再読込しました", vim.log.levels.INFO)
	end,
})

-- 1. Leaderキーをスペースに設定
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- 2. スペースキー本来の動作（右に1文字移動）を無効化
-- これをしないと、Leaderキーを押すたびにカーソルが動いてしまいます
vim.keymap.set({ "n", "v" }, "<Space>", "<Nop>", { silent = true })

-- 行頭・行末を gh / gl に割り当て
-- gh: 行頭（最初の非空白）
-- gl: 行末（最後の非空白）

vim.keymap.set("n", "gh", "^", { desc = "Go to line start" })
vim.keymap.set("n", "gl", "g_", { desc = "Go to line end" })
vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR>")

-- =========================
-- レビュー / 参照用の移動とコピー
-- =========================
-- 直前に開いていたバッファと行き来する (定義へ飛んだ後に戻る、2 ファイルを見比べる用)
vim.keymap.set("n", "<leader><leader>", "<C-^>", { desc = "Alternate buffer" })

-- 現在位置を `path:line` (cwd からの相対パス) でクリップボードにコピー
-- Claude Code / Codex への指示に「この箇所」を貼り付けるため。ビジュアル選択中は `path:start-end`
local function yank_location(with_line)
	local path = vim.fn.expand("%:.")
	local loc = path
	if with_line then
		local mode = vim.fn.mode()
		if mode == "v" or mode == "V" then
			local s, e = vim.fn.line("v"), vim.fn.line(".")
			if s > e then
				s, e = e, s
			end
			loc = string.format("%s:%d-%d", path, s, e)
			vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
		else
			loc = string.format("%s:%d", path, vim.fn.line("."))
		end
	end
	vim.fn.setreg("+", loc)
	vim.notify("Copied: " .. loc)
end
vim.keymap.set({ "n", "v" }, "<leader>yl", function()
	yank_location(true)
end, { desc = "Yank path:line" })
vim.keymap.set("n", "<leader>yp", function()
	yank_location(false)
end, { desc = "Yank relative path" })

-- =========================
-- 入力ソース (IME) の保存と復元
-- =========================
-- im-select.nvim (plugin.lua) が VimEnter で英数に切り替えるため、その前に
-- 起動時の入力ソースを控えておき、終了時に戻す。Claude Code のペインでは日本語入力の
-- ままにしておきたいので、nvim を抜けたら日本語に戻るようにする。
-- lazy.nvim より前に定義することで、この VimEnter が im-select.nvim のものより先に走る
local im_select_bin = vim.fn.exepath("im-select")
if im_select_bin ~= "" then
	local im_on_enter = nil
	vim.api.nvim_create_autocmd("VimEnter", {
		callback = function()
			local out = vim.fn.system({ im_select_bin })
			if vim.v.shell_error == 0 then
				im_on_enter = vim.trim(out)
			end
		end,
	})
	vim.api.nvim_create_autocmd("VimLeavePre", {
		callback = function()
			if im_on_enter and im_on_enter ~= "" then
				vim.fn.system({ im_select_bin, im_on_enter })
			end
		end,
	})
end

-- =========================
-- lazy.nvim bootstrap
-- =========================
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
	vim.fn.system({
		"git",
		"clone",
		"--filter=blob:none",
		"https://github.com/folke/lazy.nvim.git",
		lazypath,
	})
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup("plugin")

-- グローバルの折りたたみ設定
vim.opt.foldmethod = "expr"
vim.opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
vim.opt.foldlevel = 99
vim.opt.foldenable = true

-- Markdown専用の設定（2つのautocmdを1つに統合）
vim.api.nvim_create_autocmd("FileType", {
	pattern = "markdown",
	callback = function()
		-- Folding (最新のLua形式に統一)
		vim.opt_local.foldmethod = "expr"
		vim.opt_local.foldexpr = "v:lua.vim.treesitter.foldexpr()"

		-- Layout & Editor
		vim.opt_local.wrap = true
		vim.opt_local.linebreak = true
		vim.opt_local.conceallevel = 2
		vim.opt_local.spell = false
		vim.opt_local.number = true
		vim.opt_local.relativenumber = false
	end,
})

-- Treesitter 用のハイライトグループ (重要)
-- 最新版では markdownH1 ではなく、以下の形式が推奨される場合があります
-- 色は palette.lua から取り、ライト / ダークを切り替えたとき (ColorScheme) にも当て直す。
-- 見出しはれんが色、引用はアクセント色、コードブロックは一段沈んだ背景
local function markdown_highlights()
	local ok, p = pcall(dofile, vim.fn.expand("~/.config/wezterm/palette.lua"))
	if not ok or type(p) ~= "table" then
		return
	end
	for _, level in ipairs({ 1, 2, 3 }) do
		vim.api.nvim_set_hl(0, "@markup.heading." .. level .. ".markdown", { fg = p.error, bold = true })
	end
	vim.api.nvim_set_hl(0, "@markup.quote.markdown", { fg = p.accent, italic = true })
	vim.api.nvim_set_hl(0, "@markup.raw.block.markdown", { bg = p.chrome })
end
markdown_highlights()
vim.api.nvim_create_autocmd("ColorScheme", { callback = markdown_highlights })

-- 見出し移動キーマップを少し改良 (検索履歴を汚さない)
vim.keymap.set("n", "]h", [[<cmd>keepjumps / ^#\+<CR>]], { desc = "Next heading" })
vim.keymap.set("n", "[h", [[<cmd>keepjumps ? ^#\+<CR>]], { desc = "Previous heading" })

-- タブをスペースとして扱う
vim.opt.expandtab = true
-- 画面上のタブ表示幅を4にする
vim.opt.tabstop = 2
-- 自動インデントや「>>」で移動する幅を4にする
vim.opt.shiftwidth = 2
-- キー入力時のタブ幅を4にする
vim.opt.softtabstop = 2
