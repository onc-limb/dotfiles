vim.api.nvim_set_hl(0, "Normal", { bg = "#0f172a" })
vim.api.nvim_set_hl(0, "NormalFloat", { bg = "none" })
vim.api.nvim_set_hl(0, "SignColumn", { bg = "none" })

vim.opt.number = true

-- 1. Leaderキーをスペースに設定
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- 2. スペースキー本来の動作（右に1文字移動）を無効化
-- これをしないと、Leaderキーを押すたびにカーソルが動いてしまいます
vim.keymap.set({ 'n', 'v' }, '<Space>', '<Nop>', { silent = true })

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
vim.api.nvim_set_hl(0, "@markup.heading.1.markdown", { fg = "#38bdf8", bold = true })
vim.api.nvim_set_hl(0, "@markup.heading.2.markdown", { fg = "#60a5fa", bold = true })
vim.api.nvim_set_hl(0, "@markup.heading.3.markdown", { fg = "#93c5fd" })
vim.api.nvim_set_hl(0, "@markup.quote.markdown", { fg = "#94a3b8" })
-- コードブロックの背景
vim.api.nvim_set_hl(0, "@markup.raw.block.markdown", { bg = "#020617" })

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

