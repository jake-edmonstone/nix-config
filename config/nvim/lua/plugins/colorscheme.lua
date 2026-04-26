local bg = "NONE"
local yellow = "#F1FA8C"
local green = "#50fa7b"
local purple = "#BD93F9"
local cyan = "#8BE9FD"
local pink = "#FF79C6"
local visual = "#3E4452"
local white = "#ABB2BF"
local black = "#191A21"
return {
  { "LazyVim/LazyVim", opts = { colorscheme = "dracula" } },
  { "catppuccin/nvim", enabled = false },
  { "folke/tokyonight.nvim", enabled = false },

  {
    "Mofiqul/dracula.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      transparent_bg = true,
      overrides = {
        CursorLine = { bg = "#2E303E" },
        NormalFloat = { bg = "NONE", ctermbg = "NONE" },
        BufferLineBufferSelected = { fg = "NONE" },
        TabLineFill = { fg = "NONE" },
        BufferLineFill = { fg = "NONE" },
        StatusLine = { bg = "NONE" },
        StatusLineTerm = { bg = "NONE" },
        StatusLineTermNC = { bg = "NONE" },
        MiniFilesNormal = { bg = "NONE" },
        MiniFilesBorder = { bg = "NONE" },
        TreesitterContextBottom = { underline = true, sp = "#6272a4" },
        LualineModified = { fg = yellow, bold = true },
        -- mini.diff overlay colors (delta-like dark red/green background blocks)
        MiniDiffOverDelete = { bg = "#3f0001" },
        MiniDiffOverChange = { bg = "#901011" },
        MiniDiffOverContext = { bg = "#3f0001" },
        MiniDiffOverAdd = { bg = "#002800" },
        MiniDiffOverChangeBuf = { bg = "#006000" },
        MiniDiffOverContextBuf = { bg = "#002800" },
      },
    },
  },

  {
    "nvim-lualine/lualine.nvim",
    opts = {
      options = {
        theme = {
          normal = {
            a = { fg = black, bg = purple, gui = "bold" },
            b = { fg = purple, bg = bg },
            c = { fg = white, bg = bg },
          },
          command = {
            a = { fg = black, bg = cyan, gui = "bold" },
            b = { fg = cyan, bg = bg },
          },
          visual = {
            a = { fg = black, bg = pink, gui = "bold" },
            b = { fg = pink, bg = bg },
          },
          inactive = {
            a = { fg = white, bg = visual, gui = "bold" },
            b = { fg = black, bg = white },
          },
          replace = {
            a = { fg = black, bg = yellow, gui = "bold" },
            b = { fg = yellow, bg = bg },
            c = { fg = white, bg = bg },
          },
          insert = {
            a = { fg = black, bg = green, gui = "bold" },
            b = { fg = green, bg = bg },
            c = { fg = white, bg = bg },
          },
        },
      },
    },
  },
}
