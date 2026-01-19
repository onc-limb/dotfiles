return {
	{
		"nvim-treesitter/nvim-treesitter",
		branch = "main",
		lazy = false,
		build = ":TSUpdate",
		config = function()
			local configs = require("nvim-treesitter")
			configs.setup({
				ensure_installed = {
					"markdown",
					"markdown_inline",
					"yaml",
					"tsx",
					"typescript",
					"javascript",
					"html",
					"css",
					"json",
				},
				highlight = { enable = true },
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

          local fzf = require('fzf-lua')

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
          vim.keymap.set('n', '<leader>s', fzf.lsp_document_symbols, opts)
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
		opts = {},
	},

	-- 4. 保存時の Prettier 自動整形
	{
		"stevearc/conform.nvim",
		opts = {
			formatters_by_ft = {
				javascript = { "prettier" },
				typescript = { "prettier" },
				javascriptreact = { "prettier" },
				typescriptreact = { "prettier" },
			},
			format_on_save = { timeout_ms = 500, lsp_fallback = true },
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
    dependencies = { "nvim-tree/nvim-web-devicons", { "junegunn/fzf", build = "./install --bin" }, },
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
}

