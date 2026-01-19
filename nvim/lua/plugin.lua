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
          "markdown", "markdown_inline", "yaml", 
          "tsx", "typescript", "javascript", "html", "css", "json" 
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
      "yioneko/nvim-vtsls" 
    },
    config = function()
      require("mason").setup()
      require("mason-lspconfig").setup({
        ensure_installed = { "vtsls", "tailwindcss", "eslint" }
      })

      local lspconfig = require("lspconfig")
      lspconfig.vtsls.setup({})
      lspconfig.tailwindcss.setup({})
      lspconfig.eslint.setup({
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
}
