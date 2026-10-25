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
