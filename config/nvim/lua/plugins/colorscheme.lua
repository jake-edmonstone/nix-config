local is_dark = vim.g.theme_mode ~= "light"
local colorscheme = is_dark and "dracula" or "dracula-alucard"
local palette = vim.g.theme

local bg = "NONE"
local yellow = palette.yellow
local green = palette.green
local purple = palette.purple
local cyan = palette.cyan
local pink = palette.pink
local visual = is_dark and "#3E4452" or palette.selection
local white = is_dark and "#ABB2BF" or palette.foreground
local black = is_dark and "#191A21" or palette.background

local overrides = {
  CursorLine = { bg = is_dark and "#2E303E" or palette.currentLineSolid },
  NormalFloat = { bg = "NONE", ctermbg = "NONE" },
  BufferLineBufferSelected = { fg = "NONE" },
  TabLineFill = { fg = "NONE" },
  BufferLineFill = { fg = "NONE" },
  StatusLine = { bg = "NONE" },
  StatusLineTerm = { bg = "NONE" },
  StatusLineTermNC = { bg = "NONE" },
  MiniFilesNormal = { bg = "NONE" },
  MiniFilesBorder = { bg = "NONE" },
  TreesitterContextBottom = { underline = true, sp = palette.comment },
  LualineModified = { fg = yellow, bold = true },
}

if is_dark then
  -- Delta-like dark red/green background blocks for mini.diff overlays.
  overrides.MiniDiffOverDelete = { bg = "#3f0001" }
  overrides.MiniDiffOverChange = { bg = "#901011" }
  overrides.MiniDiffOverContext = { bg = "#3f0001" }
  overrides.MiniDiffOverAdd = { bg = "#002800" }
  overrides.MiniDiffOverChangeBuf = { bg = "#006000" }
  overrides.MiniDiffOverContextBuf = { bg = "#002800" }
end

local theme_opts = {
  transparent_bg = true,
  overrides = overrides,
}

return {
  { "LazyVim/LazyVim", opts = { colorscheme = colorscheme } },
  { "catppuccin/nvim", enabled = false },
  { "folke/tokyonight.nvim", enabled = false },

  {
    "Mofiqul/dracula.nvim",
    lazy = not is_dark,
    priority = 1000,
    opts = theme_opts,
  },
  {
    "jaljoue/dracula-alucard.nvim",
    lazy = is_dark,
    priority = 1000,
    opts = theme_opts,
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
