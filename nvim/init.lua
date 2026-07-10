-- ターミナル (wezterm) が白背景 (VSCode Light Modern 風 #FFFFFF) のためライトテーマを使う
-- 暗い背景に戻す場合はここを "dark" にする (vscode.nvim が Dark テーマに追従)
vim.o.background = "light"

vim.api.nvim_set_hl(0, "Normal", { bg = "none" })
vim.api.nvim_set_hl(0, "NormalFloat", { bg = "none" })
vim.api.nvim_set_hl(0, "SignColumn", { bg = "none" })

vim.opt.number = true

-- 基本オプション
vim.opt.clipboard = "unnamedplus" -- y/p を macOS のクリップボードと共有
vim.opt.undofile = true -- ファイルを閉じても undo 履歴を保持
vim.opt.ignorecase = true -- 検索で大文字小文字を無視
vim.opt.smartcase = true -- ただし大文字を含む検索では区別する
vim.opt.scrolloff = 5 -- カーソルの上下に常に確保する行数
vim.opt.splitright = true -- 縦分割は右に開く
vim.opt.splitbelow = true -- 横分割は下に開く

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
-- VSCode Light Modern の Markdown トークンカラーに合わせる (見出しは全レベル #800000)
vim.api.nvim_set_hl(0, "@markup.heading.1.markdown", { fg = "#800000", bold = true })
vim.api.nvim_set_hl(0, "@markup.heading.2.markdown", { fg = "#800000", bold = true })
vim.api.nvim_set_hl(0, "@markup.heading.3.markdown", { fg = "#800000", bold = true })
vim.api.nvim_set_hl(0, "@markup.quote.markdown", { fg = "#0451A5", italic = true })
-- コードブロックの背景 (VSCode の textCodeBlock 相当の淡いグレー)
vim.api.nvim_set_hl(0, "@markup.raw.block.markdown", { bg = "#F3F3F3" })

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
