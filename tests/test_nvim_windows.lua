-- Headless Neovim has no UIEnter to trigger LazyVim's normal late keymaps.
require("lazyvim.config").load("keymaps")
local function run()
  local ok, err = xpcall(function()
    local api = vim.api
    assert(not require("lazy.core.config").plugins["vim-tmux-navigator"])
    local function press(key)
      api.nvim_feedkeys(api.nvim_replace_termcodes(key, true, false, true), "xt", false)
    end
    vim.cmd.enew()
    api.nvim_buf_set_lines(0, 0, -1, false, { "alpha", "beta", "gamma" })
    vim.cmd.vsplit()
    vim.cmd.wincmd("l")
    local right = api.nvim_get_current_win()
    press("<C-h>")
    local left = api.nvim_get_current_win()
    assert(left ~= right)
    press("ggQjQj")
    local ns = assert(api.nvim_get_namespaces()["nvim.multicursor"])
    assert(#api.nvim_buf_get_extmarks(0, ns, 0, -1, {}) == 2)
    press("<C-l>")
    assert(api.nvim_get_current_win() == left)
    assert(#api.nvim_buf_get_extmarks(0, ns, 0, -1, {}) == 0)
    press("<C-l>")
    assert(api.nvim_get_current_win() == right)
    print("PASS: real LazyVim window navigation and native multicursor clearing")
  end, debug.traceback)
  if not ok then
    vim.api.nvim_err_writeln(err)
    vim.cmd.cquit(1)
  else
    vim.cmd("qa!")
  end
end
run()
