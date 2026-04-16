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
    opts = {
      options = {
        component_separators = { left = "", right = "" }, -- pipe separator character: │
        section_separators = "",
      },
      sections = {
        lualine_c = {
          { "diagnostics" },
          { "filetype", icon_only = true, separator = "", padding = { left = 1, right = 0 } },
          { LazyVim.lualine.pretty_path({ modified_sign = " ●", modified_hl = "LualineModified" }) },
        },
        lualine_x = { { "lsp_status" } },
        lualine_z = {},
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
