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
        "css",
        "latex",
        "scss",
        "svelte",
        "vue",
      },
    },
  },

  -- Cerebras clangd (only on work machines where /cb exists). IIFE returns
  -- the full spec on Cerebras, empty `{}` elsewhere. lazy.nvim treats an
  -- empty table as a no-op and doesn't interact with LazyVim's own
  -- nvim-lspconfig spec. Earlier we tried `cond =` here — it silently broke
  -- LSP attach for ALL filetypes on non-Cerebras hosts.
  (function()
    if vim.fn.isdirectory("/cb") == 1 then
      return {
        "neovim/nvim-lspconfig",
        opts = {
          servers = {
            clangd = {
              cmd = {
                "nice", "-n", "15",
                "prlimit", "--as=4294967296", "--", -- 4GB memory limit
                "cpulimit", "-l", "50", "--",
                vim.fn.expand("~/ws/clangd-18/bin/clangd"),
                "--background-index=false",
                "--compile-commands-dir=" .. vim.fn.getcwd(-1, -1) .. "/build-x86_64/buildroot/build-llvm/",
                "--query-driver=/cb/nightly_builds/builds/master/latest/toolchain/sdk-x86_64/bin/x86_64-linux-g++",
                "--clang-tidy=false",
                "--header-insertion=never",
                "--pch-storage=disk",
                "--malloc-trim",
                "-j=1",
              },
              root_markers = { ".git" },
            },
          },
        },
      }
    end
    return {}
  end)(),

  -- Typst
  {
    "chomosuke/typst-preview.nvim",
    opts = { open_cmd = "open -a 'Orion' %s" },
  },
  -- auto-close $$ pairs in typst math mode
  {
    "nvim-mini/mini.pairs",
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
