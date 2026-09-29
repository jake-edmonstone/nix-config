vim.filetype.add({
  extension = {
    ll = "llvm",
    td = "tablegen",
  },
})

return {
  -- LSP servers and formatters are installed via nix (modules/neovim.nix
  -- extraPackages), not mason. Disabling mason drops ~15-22 ms from BufReadPre.
  { "mason-org/mason.nvim",           enabled = false },
  { "mason-org/mason-lspconfig.nvim", enabled = false },

  -- Keep clangd's background indexing from monopolizing large Linux
  -- workstations. In particular, /scratch/dev/engine has roughly 39,000
  -- compilation-database entries, so the defaults can consume several cores
  -- and retain a large amount of memory while indexing.
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      opts.servers.clangd.cmd_env = vim.tbl_extend("force", opts.servers.clangd.cmd_env or {}, {
        -- Keep clangd's shared index (standard-library and external headers)
        -- off the small root filesystem. Project files remain indexed in the
        -- ignored /scratch/dev/engine/.cache/clangd directory.
        XDG_CACHE_HOME = "/scratch/dev/.cache",
      })
      if not vim.tbl_contains(opts.servers.clangd.cmd, "--enable-config") then
        table.insert(opts.servers.clangd.cmd, "--enable-config")
      end
      -- LazyVim's bare flag is rejected by newer clangd versions, which
      -- require an explicit boolean value.
      for i, arg in ipairs(opts.servers.clangd.cmd) do
        if arg == "--function-arg-placeholders" then
          opts.servers.clangd.cmd[i] = "--function-arg-placeholders=true"
        end
      end
      if vim.fn.has("linux") == 1 then
        vim.list_extend(opts.servers.clangd.cmd, {
          "-j=3",
          "--background-index-priority=background",
          "--malloc-trim",
        })
      end
    end,
  },

  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      ensure_installed = {
        "cpp",
        "typst",
        "haskell",
        -- Needed by Snacks.image for inline image rendering inside docs
        -- written in these languages (checkhealth flags them when missing).
        -- `norg` omitted: not in nvim-treesitter's registry (maintained by
        -- the neorg team separately) and you don't use .norg files.
        "markdown",
        "markdown_inline",
        "css",
        "html",
        "latex",
        "scss",
        "svelte",
        "vue",
        "yaml",
      },
      -- Use Vim's mature cindent engine for C/C++. Tree-sitter indentation
      -- misplaces the opening brace of an incomplete else block.
      indent = {
        disable = { "c", "cpp" },
      },
    },
  },

  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft = { "markdown" },
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      "nvim-mini/mini.icons",
    },
    opts = {
      code = {
        sign = false,
        width = "block",
        right_pad = 1,
      },
      heading = {
        sign = false,
        icons = {},
      },
      checkbox = {
        enabled = false,
      },
    },
  },

  {
    "gaoDean/autolist.nvim",
    ft = { "markdown" },
    opts = {},
    keys = {
      { "<Tab>", "<cmd>AutolistTab<cr>", mode = "i", ft = "markdown", desc = "Indent list item" },
      { "<S-Tab>", "<cmd>AutolistShiftTab<cr>", mode = "i", ft = "markdown", desc = "Dedent list item" },
      { "<CR>", "<CR><cmd>AutolistNewBullet<cr>", mode = "i", ft = "markdown", desc = "Continue list" },
      { "o", "o<cmd>AutolistNewBullet<cr>", ft = "markdown", desc = "Continue list below" },
      { "O", "O<cmd>AutolistNewBulletBefore<cr>", ft = "markdown", desc = "Continue list above" },
      { "<CR>", "<cmd>AutolistToggleCheckbox<cr><CR>", ft = "markdown", desc = "Toggle checkbox" },
    },
  },

  -- Typst
  {
    "chomosuke/typst-preview.nvim",
    enabled = not vim.g.headless_server,
    opts = {
      open_cmd = "open -b net.imput.helium %s",
      dependencies_bin = {
        websocat = "websocat",
      },
    },
  },
  -- auto-close $$ pairs in typst math mode
  {
    "nvim-mini/mini.pairs",
    opts = function(_, opts)
      opts.skip_next = nil
    end,
    init = function()
      local group = vim.api.nvim_create_augroup("MiniPairsTypst", { clear = true })
      vim.api.nvim_create_autocmd("FileType", {
        group = group,
        pattern = "typst",
        callback = function()
          require("mini.pairs").map_buf(0, "i", "$", {
            action = "closeopen",
            pair = "$$",
            neigh_pattern = "[^\\].",
            register = { cr = true },
          })
        end,
      })
    end,
  },

  -- Haskell
  {
    "mrcjkb/haskell-tools.nvim",
    version = "^6",
    ft = "haskell",
  },

  -- LLVM TableGen / IR
  {
    "antiagainst/vim-tablegen",
    ft = { "tablegen", "llvm" },
  },
}
