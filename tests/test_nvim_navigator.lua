-- Run with the real config, after VeryLazy has installed LazyVim's keymaps.
vim.defer_fn(function()
  local ok, err = xpcall(function()
    local api = vim.api
    local plugin = require("lazy.core.config").plugins["vim-tmux-navigator"]
    assert(not plugin._.loaded, "Navigator must start unloaded for this test")
    local function press(key)
      api.nvim_feedkeys(api.nvim_replace_termcodes(key, true, false, true), "xt", false)
    end

    vim.cmd.enew()
    api.nvim_buf_set_lines(0, 0, -1, false, { "alpha", "beta", "gamma" })
    vim.cmd.vsplit()
    vim.cmd.wincmd("l")
    local right = api.nvim_get_current_win()
    local trigger = vim.env.NVIM_NAV_LOAD or "ctrl-l"
    if trigger == "ctrl-h" then
      press("<C-h>")
    elseif trigger == "command" then
      vim.cmd.TmuxNavigateLeft()
    else
      assert(trigger == "ctrl-l", "Unknown navigator load trigger")
      vim.cmd.wincmd("h")
    end
    local left = api.nvim_get_current_win()
    assert(left ~= right)

    -- Use actual native Q commands, not dummy marks or a direct mapping callback.
    press("ggQjQj")
    local ns = assert(api.nvim_get_namespaces()["nvim.multicursor"])
    assert(#api.nvim_buf_get_extmarks(0, ns, 0, -1, {}) == 2)
    press("<C-l>")
    assert(plugin._.loaded, "Keypress did not load the navigator")
    assert(api.nvim_get_current_win() == left, "Ctrl-L navigated instead of clearing cursors")
    assert(#api.nvim_buf_get_extmarks(0, ns, 0, -1, {}) == 0, "Ctrl-L did not clear native cursors")
    assert(vim.fn.maparg("<C-l>", "n", false, true).callback, "The override was replaced")

    press("<C-l>")
    assert(api.nvim_get_current_win() == right, "Ctrl-L did not navigate after clearing")
    press("<C-h>")
    assert(api.nvim_get_current_win() == left, "Plugin's default left mapping stopped working")
    press("ggQjQj<C-l>")
    assert(api.nvim_get_current_win() == left)
    assert(#api.nvim_buf_get_extmarks(0, ns, 0, -1, {}) == 0)
    print("PASS: real LazyVim keypresses, native cursors, navigation; first load via " .. trigger)
  end, debug.traceback)
  if not ok then
    vim.api.nvim_err_writeln(err)
    vim.cmd.cquit(1)
  else
    vim.cmd("qa!")
  end
end, 100)
