return {
	{
		"Mofiqul/vscode.nvim",
		lazy = false,
		priority = 1000,
		config = function()
			require("vscode").setup({
				-- vim.o.background (init.lua で light 指定) に追従して Light テーマになる
				-- 背景は描画せず wezterm の背景 (透過 + 壁紙) をそのまま見せる。
				-- シェル / Claude Code のペインと見た目を揃えるため
				transparent = true,
				italic_comments = true,
			})
			vim.cmd("colorscheme vscode")
		end,
	},
	-- ステータスライン (Git ブランチ・diff・診断を表示)
	{
		"nvim-lualine/lualine.nvim",
		dependencies = { "nvim-tree/nvim-web-devicons" },
		opts = {
			options = {
				theme = "vscode", -- vscode.nvim が提供する lualine テーマ
			},
			-- デフォルトの sections に branch が含まれる (lualine_b = { "branch", "diff", "diagnostics" })
			sections = {
				-- path = 1: ファイル名だけでなく cwd からの相対パスで表示 (同名ファイルの区別のため)
				lualine_c = { { "filename", path = 1 } },
			},
		},
	},
	{
		"nvim-treesitter/nvim-treesitter",
		branch = "main",
		lazy = false,
		build = ":TSInstall markdown markdown_inline yaml tsx typescript javascript html css json elixir heex eex",
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
				ensure_installed = { "vtsls", "tailwindcss", "eslint", "elixirls" },
			})
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

					-- 3.1. 実装へジャンプ (interface / 抽象メソッドから実体へ) -> 'gI'
					vim.keymap.set("n", "gI", fzf.lsp_implementations, opts)

					-- 3.2. 型定義へジャンプ (変数からその型の定義へ) -> 'gy'
					vim.keymap.set("n", "gy", fzf.lsp_typedefs, opts)

					-- 4. エラー内容の確認（フロート表示） -> <Space> + l
					vim.keymap.set("n", "<leader>d", vim.diagnostic.open_float, opts)

					-- 5. リネーム（変数名の変更） -> <Space> + rn
					vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)

					-- 6. コードアクション（自動修正の提案など） -> <Space> + ca
					vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)

					-- ファイル内の関数や変数を検索してジャンプ (<Space> + s)
					vim.keymap.set("n", "<leader>s", fzf.lsp_document_symbols, opts)

					-- プロジェクト全体の関数や型を名前で検索してジャンプ (<Space> + S)
					vim.keymap.set("n", "<leader>S", fzf.lsp_live_workspace_symbols, opts)
				end,
			})

			-- vim.lsp.config を使用 (Neovim 0.11+)
			vim.lsp.config.vtsls = {
				cmd = { "vtsls", "--stdio" },
				filetypes = {
					"javascript",
					"javascriptreact",
					"javascript.jsx",
					"typescript",
					"typescriptreact",
					"typescript.tsx",
				},
				root_markers = { "package.json", "tsconfig.json", "jsconfig.json", ".git" },
				capabilities = capabilities,
			}
			vim.lsp.enable("vtsls")

			-- Elixir 言語サーバ (elixir-ls)
			-- mix.exs のあるプロジェクト内で起動すること。elixir/mix が PATH に必要
			-- (この環境では study/extremis/reference のように mise で elixir が有効なディレクトリ)
			vim.lsp.config.elixirls = {
				cmd = { "elixir-ls" },
				filetypes = { "elixir", "eelixir", "heex", "surface" },
				root_markers = { "mix.exs", ".git" },
				capabilities = capabilities,
			}
			vim.lsp.enable("elixirls")

			vim.lsp.config.tailwindcss = {
				cmd = { "tailwindcss-language-server", "--stdio" },
				filetypes = { "html", "css", "scss", "javascript", "javascriptreact", "typescript", "typescriptreact" },
				root_markers = { "tailwind.config.js", "tailwind.config.ts" },
				capabilities = capabilities,
			}
			vim.lsp.enable("tailwindcss")

			vim.lsp.config.eslint = {
				cmd = { "vscode-eslint-language-server", "--stdio" },
				filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact" },
				root_markers = { ".eslintrc", ".eslintrc.js", ".eslintrc.json", "package.json" },
				capabilities = capabilities,
			}
			vim.lsp.enable("eslint")

			-- ESLint の自動修正を保存時に実行
			vim.api.nvim_create_autocmd("LspAttach", {
				callback = function(args)
					local client = vim.lsp.get_client_by_id(args.data.client_id)
					if client and client.name == "eslint" then
						vim.api.nvim_create_autocmd("BufWritePre", {
							buffer = args.buf,
							command = "EslintFixAll",
						})
					end
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
				-- Elixir は mix format で整形 (cwd に mix.exs が必要)
				elixir = { "mix" },
				eelixir = { "mix" },
				heex = { "mix" },
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
		-- 遅延読み込みだと nvim . などディレクトリ指定の起動時に oil が開かないため、起動時に読み込む (oil 公式の推奨)
		lazy = false,
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
		config = function(_, opts)
			require("oil").setup(opts)
			-- 引数なしで nvim を起動した時もカレントディレクトリの oil 表示から始める。
			-- wezterm の LEADER+e (--cmd 'let g:start_with_explorer = 1') からの起動時は
			-- oil ではなく neo-tree を左に開き、VSCode のようにツリーからファイルを選ぶ
			vim.api.nvim_create_autocmd("VimEnter", {
				callback = function()
					if vim.fn.argc() == 0 and vim.api.nvim_buf_get_name(0) == "" then
						if vim.g.start_with_explorer == 1 then
							vim.cmd("Neotree left")
						else
							require("oil").open()
						end
					end
				end,
			})
		end,
		-- キーマッピング (ここで設定すると、キーを押した時にプラグインが読み込まれます)
		-- <leader>e は neo-tree (左ペインのエクスプローラー) に譲り、oil は - での親ディレクトリ編集に専念
		keys = {
			{
				"-",
				function()
					require("oil").open()
				end,
				desc = "Open parent directory",
			},
		},
	},

	-- 5.5. エクスプローラー (VSCode の左サイドバー相当)
	{
		"nvim-neo-tree/neo-tree.nvim",
		branch = "v3.x",
		dependencies = {
			"nvim-lua/plenary.nvim",
			"nvim-tree/nvim-web-devicons",
			"MunifTanjim/nui.nvim",
		},
		cmd = "Neotree",
		keys = {
			-- <Space> + e: メイン側で押すとツリーにフォーカス (閉じていれば開き、現在ファイルの位置を展開)、
			-- ツリー上で押すとツリーを閉じる。キーボードだけでメインとツリーを往復するため
			{
				"<leader>e",
				function()
					if vim.bo.filetype == "neo-tree" then
						vim.cmd("Neotree close")
						return
					end
					-- 実ファイルを開いているときだけ reveal する。
					-- follow_current_file が有効だと :Neotree focus でも reveal が暗黙に有効になり、
					-- oil:// のような実在しないパスだと「ルートを変更しますか (y/n)」のポップアップが出る。
					-- そのため oil や空バッファでは reveal = false を明示して focus だけにする
					local name = vim.api.nvim_buf_get_name(0)
					local is_real_file = vim.bo.buftype == "" and name ~= "" and vim.fn.filereadable(name) == 1
					require("neo-tree.command").execute({
						action = "focus",
						position = "left",
						reveal = is_real_file,
					})
				end,
				desc = "Explorer (focus / close)",
			},
		},
		opts = {
			close_if_last_window = true, -- ツリーだけ残ったら nvim ごと閉じる
			filesystem = {
				follow_current_file = { enabled = true }, -- 開いているファイルをツリー上で追跡
				use_libuv_file_watcher = true, -- 外部変更 (Claude Code 等) を自動反映
				filtered_items = {
					visible = true, -- ドットファイル等も薄い色で表示 (完全に隠さない)
					hide_dotfiles = false,
					hide_gitignored = true,
				},
				hijack_netrw_behavior = "disabled", -- ディレクトリ指定の起動は oil に任せる
				commands = {
					-- カーソル下のフォルダ (ファイルなら親フォルダ) を右のメインウィンドウの oil で開く。
					-- ツリーで場所を選び、oil でファイルの作成・削除・リネームをテキスト編集する流れ用
					open_in_oil = function(state)
						local node = state.tree:get_node()
						if not node then
							return
						end
						local path = node:get_id()
						if node.type ~= "directory" then
							path = vim.fn.fnamemodify(path, ":h")
						end
						-- ツリー以外の通常ウィンドウ (直前にいたウィンドウを優先) を探して移動する
						local target = vim.fn.win_getid(vim.fn.winnr("#"))
						local function is_main(win)
							return win ~= 0
								and vim.api.nvim_win_is_valid(win)
								and vim.api.nvim_win_get_config(win).relative == ""
								and vim.bo[vim.api.nvim_win_get_buf(win)].filetype ~= "neo-tree"
						end
						if not is_main(target) then
							target = nil
							for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
								if is_main(win) then
									target = win
									break
								end
							end
						end
						if not target then
							return
						end
						vim.api.nvim_set_current_win(target)
						require("oil").open(path)
					end,
				},
				window = {
					mappings = {
						["-"] = "open_in_oil",
					},
				},
			},
			window = { width = 32 },
			default_component_configs = {
				git_status = {
					symbols = {
						-- VSCode のエクスプローラーと同じく 1 文字ステータス
						added = "A",
						modified = "M",
						deleted = "D",
						renamed = "R",
						untracked = "U",
						ignored = "",
						unstaged = "",
						staged = "",
						conflict = "!",
					},
				},
			},
		},
	},

	-- 5.6. バッファをタブ表示 (VSCode のエディタタブ相当)
	{
		"akinsho/bufferline.nvim",
		version = "*",
		dependencies = { "nvim-tree/nvim-web-devicons" },
		event = "VeryLazy",
		keys = {
			{ "<S-l>", "<cmd>BufferLineCycleNext<CR>", desc = "Next buffer tab" },
			{ "<S-h>", "<cmd>BufferLineCyclePrev<CR>", desc = "Prev buffer tab" },
			{ "<leader>bd", "<cmd>bdelete<CR>", desc = "Close buffer" },
			{ "<leader>bo", "<cmd>BufferLineCloseOthers<CR>", desc = "Close other buffers" },
			{ "<leader>bp", "<cmd>BufferLineTogglePin<CR>", desc = "Pin buffer" },
		},
		opts = {
			options = {
				separator_style = "thin",
				show_close_icon = false,
				diagnostics = "nvim_lsp", -- タブ上にエラー/警告数を表示 (VSCode 風)
				-- neo-tree が開いている間はタブバーをその分右にずらす
				offsets = {
					{ filetype = "neo-tree", text = "EXPLORER", text_align = "left", separator = true },
				},
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
			-- プロジェクト全文検索 (VSCode の Cmd+Shift+F 相当)
			{
				"<leader>/",
				function()
					require("fzf-lua").live_grep()
				end,
				desc = "Fzf Live Grep",
			},
			-- 開いているバッファの切り替え
			{
				"<leader>b",
				function()
					require("fzf-lua").buffers()
				end,
				desc = "Fzf Buffers",
			},
			-- 最近開いたファイル
			{
				"<leader>o",
				function()
					require("fzf-lua").oldfiles()
				end,
				desc = "Fzf Recent Files",
			},
			-- 直前の検索を再開
			{
				"<leader>R",
				function()
					require("fzf-lua").resume()
				end,
				desc = "Fzf Resume",
			},
			-- ワークスペース全体の診断一覧 (VSCode の「問題」パネル相当)
			{
				"<leader>x",
				function()
					require("fzf-lua").diagnostics_workspace()
				end,
				desc = "Fzf Workspace Diagnostics",
			},
			-- 現在のファイルだけの診断一覧 (<leader>x のファイル版)
			{
				"<leader>X",
				function()
					require("fzf-lua").diagnostics_document()
				end,
				desc = "Fzf Document Diagnostics",
			},
			-- カーソル下の単語 / 選択範囲をプロジェクト全体から検索
			-- (レビュー中に「この関数はどこで使われている?」を LSP なしでも引ける)
			{
				"<leader>*",
				function()
					require("fzf-lua").grep_cword()
				end,
				desc = "Fzf Grep word under cursor",
			},
			{
				"<leader>*",
				function()
					require("fzf-lua").grep_visual()
				end,
				mode = "v",
				desc = "Fzf Grep selection",
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
				-- ステージ済みハンクのサインを未ステージと別スタイルで表示 (VSCode のガター表示相当)
				signs_staged_enable = true,
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

					-- --- 差分表示 (VSCode のエディタ差分ビュー相当) ---
					map("n", "<Leader>hd", gs.diffthis) -- 作業ツリー vs インデックス (未ステージの差分)
					map("n", "<Leader>hD", function()
						gs.diffthis("HEAD")
					end) -- 作業ツリー vs HEAD (ステージ済みを含む全差分)

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
			-- キーは <Leader>g (git) + 頭文字で統一 (gs = status は fugitive 側で定義済み)
			-- どのキーも再度押すと差分ビューを閉じるトグル式

			-- 差分ビューが開いていれば閉じ、閉じていれば open_fn を実行する
			local function toggle_view(open_fn)
				return function()
					if require("diffview.lib").get_current_view() then
						vim.cmd("DiffviewClose")
					else
						open_fn()
					end
				end
			end

			-- リモートブランチとの比較対象を解決する
			-- upstream が設定されていればそれを、なければ origin/HEAD (リモートの既定ブランチ) を使う
			local function remote_ref()
				local upstream = vim.fn.systemlist("git rev-parse --abbrev-ref @{upstream}")[1]
				if vim.v.shell_error == 0 then
					return upstream
				end
				local head = vim.fn.systemlist("git symbolic-ref --short refs/remotes/origin/HEAD")[1]
				if vim.v.shell_error == 0 then
					return head
				end
				return nil
			end

			local function open_remote_diff()
				local ref = remote_ref()
				if not ref then
					vim.notify(
						"リモートの比較対象が見つかりません (upstream / origin/HEAD 未設定)",
						vim.log.levels.WARN
					)
					return
				end
				vim.cmd("DiffviewOpen " .. ref .. "...HEAD")
			end

			-- g + d = git diff: ローカルの変更一覧 (未ステージ / ステージ済みをパネルで区別表示)
			-- :DiffviewOpen のファイルパネルは VSCode のソース管理パネル相当
			vim.keymap.set(
				"n",
				"<Leader>gd",
				toggle_view(function()
					vim.cmd("DiffviewOpen")
				end),
				{ desc = "Git diff (toggle)" }
			)

			-- g + r = git remote: リモートブランチとの差分 (merge-base 比較 = push で届く内容)
			vim.keymap.set("n", "<Leader>gr", toggle_view(open_remote_diff), { desc = "Git remote diff (toggle)" })

			-- g + R = git Remote (fetch 付き): git fetch で最新化してからリモートとの差分を開く
			vim.keymap.set(
				"n",
				"<Leader>gR",
				toggle_view(function()
					vim.notify("git fetch ...")
					vim.system({ "git", "fetch" }, {}, function(out)
						vim.schedule(function()
							if out.code ~= 0 then
								vim.notify(
									"git fetch に失敗しました: " .. (out.stderr or ""),
									vim.log.levels.ERROR
								)
								return
							end
							open_remote_diff()
						end)
					end)
				end),
				{ desc = "Fetch and git remote diff (toggle)" }
			)

			-- g + h = git history: 現在のファイルの変更履歴
			vim.keymap.set(
				"n",
				"<Leader>gh",
				toggle_view(function()
					vim.cmd("DiffviewFileHistory %")
				end),
				{ desc = "Git file history (toggle)" }
			)
		end,
	},

	-----------------------------------------------------------
	-- 4. render-markdown.nvim: Markdown をバッファ内でリッチ表示
	-----------------------------------------------------------
	{
		"MeanderingProgrammer/render-markdown.nvim",
		dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons" },
		ft = { "markdown" },
		opts = {
			-- ノーマルモードでは装飾表示、インサートモードに入った行は生のマークダウンに戻る
			render_modes = { "n", "c", "t" },
		},
	},

	-----------------------------------------------------------
	-- 4.5. im-select.nvim: ノーマルモードに戻ったら入力ソースを英数にする
	--    (日本語入力のまま Esc して hjkl が効かない問題の対策。要 `brew install im-select`)
	--    英数側は Apple 日本語 IM の英字モード。ABC レイアウトは有効化していないため
	--    起動時の入力ソースの保存と終了時の復元は init.lua の autocmd で行う
	-----------------------------------------------------------
	{
		"keaising/im-select.nvim",
		lazy = false, -- VimEnter で切り替えるため起動時に読み込む
		opts = {
			default_im_select = "com.apple.inputmethod.Kotoeri.RomajiTyping.Roman",
			default_command = "im-select",
			-- 英数に切り替えるタイミング
			set_default_events = { "VimEnter", "FocusGained", "InsertLeave", "CmdlineLeave" },
			-- 直前の入力ソース (日本語など) に戻すタイミング
			set_previous_events = { "InsertEnter" },
			keep_quiet_on_no_binary = false,
			async_switch_im = true,
		},
		config = function(_, opts)
			require("im_select").setup(opts)
		end,
	},

	-----------------------------------------------------------
	-- 5. snacks.nvim (image): 画像ファイル・md 内の画像をターミナルに表示
	--    wezterm の kitty graphics protocol を利用 (要 ImageMagick)
	-----------------------------------------------------------
	{
		"folke/snacks.nvim",
		priority = 1000,
		lazy = false,
		opts = {
			image = { enabled = true },
		},
	},
}
