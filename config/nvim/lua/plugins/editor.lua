return {
  { "folke/persistence.nvim", enabled = false },

  {
    "nvim-mini/mini.ai",
    opts = {
      mappings = {
        around_next = "", -- free an for builtin treesitter node selection
        inside_next = "", -- free in for builtin treesitter node selection
      },
    },
  },

  {
    "folke/noice.nvim",
    opts = { presets = { lsp_doc_border = true } },
  },

  {
    "folke/snacks.nvim",
    opts = {
      explorer = { enabled = false },
      -- Inline image rendering (PDF / LaTeX / Mermaid / raster) via Kitty
      -- graphics. `needs_setup = true` in Snacks.image, so this opt-in is
      -- required. Render deps (magick / gs / tectonic / mmdc) are Darwin-only
      -- in modules/neovim.nix — SSH'd nvim on Linux hosts falls back to
      -- PNG-only until you install them there too.
      image = { enabled = true },
      styles = {
        win = { border = "rounded" },
        news = { border = "rounded" },
        lazygit = { border = "rounded" },
      },
      picker = {
        win = { preview = { wo = { wrap = true } } },
        sources = {
          files = { hidden = true },
          explorer = { layout = { layout = { position = "right" } } },
        },
        layout = { preset = "default" },
        hidden = true,
      },
    },
  },

  {
    "pwntester/octo.nvim",
    opts = { use_local_fs = true },
  },

  {
    "max397574/better-escape.nvim",
    event = "InsertEnter",
    opts = {
      timeout = vim.o.timeoutlen,
      default_mappings = false,
      mappings = {
        i = {
          j = { k = "<Esc>" },
          k = { j = "<Esc>" },
        },
      },
    },
  },

  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      opts.options.component_separators = { left = "", right = "" } -- pipe separator character: │
      opts.options.section_separators = ""
      opts.sections.lualine_c = {
        { "diagnostics" },
        { "filetype", icon_only = true, separator = "", padding = { left = 1, right = 0 } },
        { LazyVim.lualine.pretty_path({ modified_sign = " ●", modified_hl = "LualineModified" }) },
      }
      table.insert(opts.sections.lualine_x, { "lsp_status" })
      opts.sections.lualine_z = {}
    end,
  },

  {
    "nvim-mini/mini.diff",
    event = "LazyFile",
    opts = {
      mappings = {
        apply = "",
        reset = "",
        textobject = "",
        goto_first = "",
        goto_prev = "",
        goto_next = "",
        goto_last = "",
      },
      view = {
        style = "sign",
        -- Keep mini.diff active for overlay only; let gitsigns own gutter visuals.
        signs = { add = " ", change = " ", delete = " " },
        priority = 1,
      },
    },
    keys = {
      {
        "<leader>go",
        function()
          require("mini.diff").toggle_overlay(0)
        end,
        desc = "Toggle mini.diff overlay",
      },
    },
  },

  {
    "christoomey/vim-tmux-navigator",
    cmd = {
      "TmuxNavigateLeft",
      "TmuxNavigateDown",
      "TmuxNavigateUp",
      "TmuxNavigateRight",
      "TmuxNavigatePrevious",
      "TmuxNavigatorProcessList",
    },
    keys = {
      { "<c-h>", "<cmd><C-U>TmuxNavigateLeft<cr>", desc = "Navigate left (tmux)" },
      { "<c-j>", "<cmd><C-U>TmuxNavigateDown<cr>", desc = "Navigate down (tmux)" },
      { "<c-k>", "<cmd><C-U>TmuxNavigateUp<cr>", desc = "Navigate up (tmux)" },
      { "<c-l>", "<cmd><C-U>TmuxNavigateRight<cr>", desc = "Navigate right (tmux)" },
      { "<c-\\>", "<cmd><C-U>TmuxNavigatePrevious<cr>", desc = "Navigate previous (tmux)" },
    },
  },
}
