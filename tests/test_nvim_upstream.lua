local root = assert(arg[1])
local api = vim.api
local lazy = vim.fn.stdpath("data") .. "/lazy/"
vim.opt.runtimepath:append(root .. "/config/nvim")
for _, plugin in ipairs({ "blink.cmp", "LuaSnip", "vim-tmux-navigator" }) do
  vim.opt.runtimepath:append(lazy .. plugin)
end

local ssh = vim.env.SSH_TTY
vim.env.SSH_TTY = nil
dofile(root .. "/config/nvim/lua/config/options.lua")
assert(vim.g.clipboard == nil)
vim.env.SSH_TTY = "/dev/pts/test"
dofile(root .. "/config/nvim/lua/config/options.lua")
assert(vim.g.clipboard == "osc52")
assert(vim.fn["provider#clipboard#Executable"]() == "OSC 52")
vim.env.SSH_TTY = ssh

require("config.keymaps")
assert(vim.fn.maparg("Z", "n", false, true).rhs == "1z=")
vim.bo.spelllang = "en"
api.nvim_buf_set_lines(0, 0, -1, false, { "Some speling here." })
local suggestion = assert(vim.fn.spellsuggest("speling", 1)[1])
api.nvim_win_set_cursor(0, { 1, 5 })
vim.cmd.normal("Z")
assert(api.nvim_get_current_line() == "Some " .. suggestion .. " here.")

local completion = dofile(root .. "/config/nvim/lua/plugins/completion.lua")
local keymap = completion[2].opts.keymap
assert(vim.deep_equal(keymap["<C-l>"], { "snippet_forward", "fallback" }))
assert(vim.deep_equal(keymap["<C-h>"], { "snippet_backward", "fallback" }))
-- Configure only the snippet backend: no UI, downloads or completion sources.
require("blink.cmp.config").merge_with({ snippets = { preset = "luasnip" } })
local blink = require("blink.cmp")
local luasnip = require("luasnip")
luasnip.setup()
assert(not blink.snippet_forward())
assert(not blink.snippet_backward())
vim.cmd.enew()
luasnip.lsp_expand("${1:first} ${2:second}$0")
local buf = api.nvim_get_current_buf()
assert(luasnip.session.current_nodes[buf].pos == 1)
assert(blink.snippet_forward())
assert(vim.wait(1000, function()
  return luasnip.session.current_nodes[buf].pos == 2
end))
assert(blink.snippet_backward())
assert(vim.wait(1000, function()
  return luasnip.session.current_nodes[buf].pos == 1
end))
luasnip.unlink_current()

local specs = dofile(root .. "/config/nvim/lua/plugins/editor.lua")
local navigator
for _, spec in ipairs(specs) do
  if spec[1] == "christoomey/vim-tmux-navigator" then
    navigator = spec
  elseif spec[1] == "nvim-treesitter/nvim-treesitter-context" then
    assert(spec.opts.max_lines == 0)
  end
end
assert(navigator)
assert(navigator.init == nil)
local tmux = vim.env.TMUX
vim.env.TMUX = "test,1,0"
vim.cmd.runtime("plugin/tmux_navigator.vim")
vim.env.TMUX = tmux
navigator.config()
local ctrlL = vim.fn.maparg("<C-l>", "n", false, true).callback
assert(ctrlL)
local navigations = 0
api.nvim_create_user_command("TmuxNavigateRight", function()
  navigations = navigations + 1
end, { force = true })
local ns = api.nvim_create_namespace("nvim.multicursor")
local other = api.nvim_create_buf(false, true)
api.nvim_buf_set_extmark(other, ns, 0, 0, {})
api.nvim_buf_set_extmark(buf, ns, 0, 0, {})
ctrlL()
assert(#api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}) == 0 and navigations == 0)
assert(#api.nvim_buf_get_extmarks(other, ns, 0, -1, {}) == 1)
ctrlL()
assert(navigations == 1)
for _, key in ipairs({ "<C-h>", "<C-j>", "<C-k>", "<C-l>" }) do
  local mapping = vim.fn.maparg(key, "t", false, true)
  assert(mapping.expr == 1 and mapping.rhs:find("IsFZF()", 1, true))
end
print("PASS: native clipboard/spelling, Blink snippet navigation, multicursor and terminal navigation, context height")
