return {
	{
		"scottmckendry/cyberdream.nvim",
		lazy = false,
		priority = 1000,
		config = function()
			require("cyberdream").setup({
				transparent = true, -- ★背景透過を有効化
				italic_comments = true,
				hide_fillchars = true,
				borderless_telescope = true, -- TelescopeなどのUIも枠なしでスッキリ
			})
			vim.cmd("colorscheme cyberdream")
		end,
	},
	{
		"nvim-treesitter/nvim-treesitter",
		branch = "main",
		lazy = false,
		build = ":TSInstall markdown markdown_inline yaml tsx typescript javascript html css json",
		config = function()
			vim.api.nvim_create_autocmd("FileType", {
				callback = function()
					pcall(vim.treesitter.start)
				end,
			})
		end,
	},

	{
		"neovim/nvim-lspconfig",
		dependencies = {
			"williamboman/mason.nvim",
			"williamboman/mason-lspconfig.nvim",
			"yioneko/nvim-vtsls",
			"hrsh7th/cmp-nvim-lsp",
		},
		config = function()
			require("mason").setup()
			require("mason-lspconfig").setup({
				ensure_installed = { "vtsls", "tailwindcss", "eslint" },
			})
			local lspconfig = require("lspconfig")
			local capabilities = require("cmp_nvim_lsp").default_capabilities()

			vim.api.nvim_create_autocmd("LspAttach", {
				callback = function(args)
					-- よく使う操作をキーに割り当て
					local opts = { buffer = args.buf }

					local fzf = require("fzf-lua")

					-- 1. ホバー（型情報・ドキュメント閲覧） -> 'K' (Shift + k)
					vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)

					-- 2. 定義へジャンプ -> 'gd' (Go Definition)
					vim.keymap.set("n", "gd", fzf.lsp_definitions, opts)

					-- 3. 参照を一覧表示 -> 'gr' (Go References)
					-- (Telescopeを入れているなら Telescope lsp_references の方が見やすいです)
					vim.keymap.set("n", "gr", fzf.lsp_references, opts)

					-- 4. エラー内容の確認（フロート表示） -> <Space> + l
					vim.keymap.set("n", "<leader>d", vim.diagnostic.open_float, opts)

					-- 5. リネーム（変数名の変更） -> <Space> + rn
					vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)

					-- 6. コードアクション（自動修正の提案など） -> <Space> + ca
					vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)

					-- ファイル内の関数や変数を検索してジャンプ (<Space> + s)
					vim.keymap.set("n", "<leader>s", fzf.lsp_document_symbols, opts)
				end,
			})

			lspconfig.vtsls.setup({ capabilities = capabilities })
			lspconfig.tailwindcss.setup({ capabilities = capabilities })
			lspconfig.eslint.setup({
				capabilities = capabilities,
				on_attach = function(client, bufnr)
					vim.api.nvim_create_autocmd("BufWritePre", {
						buffer = bufnr,
						command = "EslintFixAll",
					})
				end,
			})
		end,
	},

	-- 3. JSX/TSXの閉じタグ自動挿入
	{
		"windwp/nvim-ts-autotag",
		dependencies = { "nvim-treesitter/nvim-treesitter" },
		event = { "BufReadPre", "BufNewFile" },
		config = function()
			require("nvim-ts-autotag").setup({
				opts = {
					enable_close = true, -- <div> と入力すると </div> を自動挿入
					enable_rename = true, -- 開始タグを編集すると閉じタグも同時に変更
					enable_close_on_slash = true, -- </ と入力すると自動で閉じタグを補完
				},
			})
		end,
	},

	-- 括弧の自動補完
	{
		"windwp/nvim-autopairs",
		event = "InsertEnter",
		opts = {},
	},

	-- 4. 保存時の自動整形
	{
		"stevearc/conform.nvim",
		opts = {
			formatters_by_ft = {
				lua = { "stylua" },
				javascript = { "prettier" },
				typescript = { "prettier" },
				javascriptreact = { "prettier" },
				typescriptreact = { "prettier" },
				json = { "prettier" },
				html = { "prettier" },
				css = { "prettier" },
				markdown = { "prettier" },
				yaml = { "prettier" },
			},
			format_on_save = { timeout_ms = 500, lsp_format = "fallback" },
		},
	},

	-- フォーマッターの自動インストール
	{
		"WhoIsSethDaniel/mason-tool-installer.nvim",
		dependencies = { "williamboman/mason.nvim" },
		opts = {
			ensure_installed = {
				"prettier",
				"stylua",
			},
		},
	},

	-- 5. ファイルマネージャー
	{
		"stevearc/oil.nvim",
		dependencies = { "nvim-tree/nvim-web-devicons" },
		opts = {
			view_options = {
				show_hidden = true, -- ドットファイルを表示
			},
			float = {
				padding = 2,
				max_width = 60,
				max_height = 30,
			},
		},
		-- キーマッピング (ここで設定すると、キーを押した時にプラグインが読み込まれます)
		keys = {
			-- <Space> + e でプロジェクトルートをフロート表示
			{
				"<leader>e",
				function()
					require("oil").toggle_float(".")
				end,
				desc = "Open project root (Oil Float)",
			},
			{
				"-",
				function()
					require("oil").open()
				end,
				desc = "Open parent directory",
			},
		},
	},

	-- 6. Fuzzy Finder
	{
		"ibhagwan/fzf-lua",
		dependencies = { "nvim-tree/nvim-web-devicons", { "junegunn/fzf", build = "./install --bin" } },
		config = function()
			require("fzf-lua").setup({
				-- 必要であればここに詳細設定を書きますが、
				-- デフォルトでも十分に美しいUIで動作します
				winopts = {
					preview = {
						layout = "vertical", -- プレビューを下に表示（好みで horizontal に変更可）
					},
				},
			})
		end,
		keys = {
			{
				"<leader>f",
				function()
					require("fzf-lua").files()
				end,
				desc = "Fzf Files",
			},
		},
	},
	-- 6. 自動補完 (nvim-cmp)
	{
		"hrsh7th/nvim-cmp",
		event = "InsertEnter", -- 入力モードに入ったら読み込む
		dependencies = {
			"hrsh7th/cmp-nvim-lsp", -- LSPの補完ソース
			"hrsh7th/cmp-buffer", -- バッファ内の単語補完
			"hrsh7th/cmp-path", -- パス補完
			"L3MON4D3/LuaSnip", -- スニペットエンジン (必須)
		},
		config = function()
			local cmp = require("cmp")
			local luasnip = require("luasnip")

			cmp.setup({
				snippet = {
					expand = function(args)
						luasnip.lsp_expand(args.body)
					end,
				},
				mapping = cmp.mapping.preset.insert({
					["<C-n>"] = cmp.mapping.select_next_item(), -- 次の候補
					["<C-p>"] = cmp.mapping.select_prev_item(), -- 前の候補
					["<C-d>"] = cmp.mapping.scroll_docs(-4),
					["<C-f>"] = cmp.mapping.scroll_docs(4),
					["<C-Space>"] = cmp.mapping.complete(), -- 手動で補完表示
					["<CR>"] = cmp.mapping.confirm({ select = true }), -- Enterで確定
				}),
				sources = {
					{ name = "nvim_lsp" }, -- LSPからの候補を出す
					{ name = "luasnip" },
					{ name = "buffer" },
					{ name = "path" },
				},
			})
		end,
	},

	-----------------------------------------------------------
	-- 1. vim-fugitive: Gitコマンドのラッパー
	-----------------------------------------------------------
	{
		"tpope/vim-fugitive",
		config = function()
			-- よく使う操作のキーマッピング例
			-- <Leader> (スペースキーなど) + gs で Gitステータス画面を開く
			vim.keymap.set("n", "<Leader>gs", vim.cmd.Git)
		end,
	},

	-----------------------------------------------------------
	-- 2. gitsigns.nvim: エディタ端のサイン表示とハンク操作
	-----------------------------------------------------------
	{
		"lewis6991/gitsigns.nvim",
		config = function()
			require("gitsigns").setup({
				-- ここでキーマッピングを設定します
				on_attach = function(bufnr)
					local gs = package.loaded.gitsigns

					local function map(mode, l, r, opts)
						opts = opts or {}
						opts.buffer = bufnr
						vim.keymap.set(mode, l, r, opts)
					end

					-- --- ナビゲーション（変更箇所へのジャンプ） ---
					map("n", "]c", function()
						if vim.wo.diff then
							return "]c"
						end
						vim.schedule(function()
							gs.next_hunk()
						end)
						return "<Ignore>"
					end, { expr = true })

					map("n", "[c", function()
						if vim.wo.diff then
							return "[c"
						end
						vim.schedule(function()
							gs.prev_hunk()
						end)
						return "<Ignore>"
					end, { expr = true })

					-- --- ハンク操作（変更箇所の操作） ---
					map("n", "<Leader>hs", gs.stage_hunk) -- 変更をステージ (Add)
					map("n", "<Leader>hr", gs.reset_hunk) -- 変更を元に戻す
					map("v", "<Leader>hs", function()
						gs.stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
					end) -- 選択範囲をステージ
					map("v", "<Leader>hr", function()
						gs.reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
					end) -- 選択範囲をリセット
					map("n", "<Leader>hS", gs.stage_buffer) -- バッファ全体をステージ
					map("n", "<Leader>hu", gs.undo_stage_hunk) -- ステージを取り消し
					map("n", "<Leader>hR", gs.reset_buffer) -- バッファ全体をリセット

					-- --- プレビュー ---
					map("n", "<Leader>hp", gs.preview_hunk) -- 変更内容を浮動ウィンドウで表示

					-- --- Blame（誰が書いたか表示） ---
					map("n", "<Leader>hb", function()
						gs.blame_line({ full = true })
					end) -- 行のBlameを表示
					map("n", "<Leader>tb", gs.toggle_current_line_blame) -- 行末にBlame情報を常時表示するスイッチ
				end,
			})
		end,
	},

	-----------------------------------------------------------
	-- 3. diffview.nvim: 強力な差分ビューア
	-----------------------------------------------------------
	{
		"sindrets/diffview.nvim",
		config = function()
			-- 特に設定しなくても使えますが、キーバインドがあると便利です
			vim.keymap.set("n", "<Leader>do", ":DiffviewOpen<CR>") -- 差分ビューを開く
			vim.keymap.set("n", "<Leader>dc", ":DiffviewClose<CR>") -- 差分ビューを閉じる
			vim.keymap.set("n", "<Leader>dh", ":DiffviewFileHistory %<CR>") -- 現在のファイルの履歴を見る
		end,
	},
}
