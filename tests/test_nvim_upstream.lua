local fixture = vim.fn.tempname()
local ok, err = xpcall(function()
  local ssh_tty = vim.env.SSH_TTY
  vim.env.SSH_TTY = nil
  vim.g.clipboard = nil
  dofile("config/nvim/lua/config/options.lua")
  assert(vim.g.clipboard == nil)
  vim.env.SSH_TTY = "/dev/pts/test"
  dofile("config/nvim/lua/config/options.lua")
  assert(vim.g.clipboard == "osc52")
  assert(vim.fn["provider#clipboard#Executable"]() == "OSC 52")
  vim.env.SSH_TTY = ssh_tty

  require("config.keymaps")
  assert(vim.fn.maparg("Z", "n", false, true).rhs == "1z=")
  vim.cmd.enew()
  vim.bo.spelllang = "en"
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "Some speling here." })
  local suggestion = assert(vim.fn.spellsuggest("speling", 1)[1])
  vim.api.nvim_win_set_cursor(0, { 1, 5 })
  vim.cmd.normal("Z")
  assert(vim.api.nvim_get_current_line() == "Some " .. suggestion .. " here.")

  require("lazy").load({ plugins = { "blink.cmp", "nvim-dap" } })
  local keymap = LazyVim.opts("blink.cmp").keymap
  assert(vim.deep_equal(keymap["<C-l>"], { "snippet_forward", "fallback" }))
  assert(vim.deep_equal(keymap["<C-h>"], { "snippet_backward", "fallback" }))
  local blink = require("blink.cmp")
  assert(not blink.snippet_forward())
  assert(not blink.snippet_backward())
  local luasnip = require("luasnip")
  luasnip.lsp_expand("${1:first} ${2:second}$0")
  local buf = vim.api.nvim_get_current_buf()
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

  local plugin = require("lazy.core.config").plugins["nvim-dap"]
  assert(debug.getinfo(plugin.config, "S").source:find("extras/dap/core.lua", 1, true))
  local dap = require("dap")
  assert(dap.adapters.codelldb == nil)
  for _, ft in ipairs({ "c", "cpp" }) do
    assert(#dap.configurations[ft] == 1)
    local launch = dap.configurations[ft][1]
    assert(launch.name == "Launch executable (GDB)" and launch.type == "gdb")
    assert(type(launch.program) == "function" and type(launch.cwd) == "function")
  end
  dap.adapters.gdb(function(adapter)
    assert(adapter.command == "gdb" and adapter.type == "executable")
    assert(vim.tbl_contains(adapter.args, "--interpreter=dap"))
    assert(vim.tbl_contains(adapter.args, 'set substitute-path "/virtual/root" "/actual/root"'))
  end, { gdb_source_substitutions = { { from = "/virtual/root", to = "/actual/root" } } })
  assert(vim.fn.hlexists("DapStoppedLine") == 1)
  assert(#vim.fn.sign_getdefined("DapBreakpoint") == 1)
  local decoded = require("dap.ext.vscode").json_decode('{"version": "0.2.0", // comment\n "configurations": []}')
  assert(decoded.version == "0.2.0")
  assert(require("lazy.core.config").plugins["mason-nvim-dap.nvim"] == nil)

  vim.fn.mkdir(fixture .. "/SupportModels/TMTraining", "p")
  vim.fn.writefile({}, fixture .. "/MODULE.bazel")
  vim.api.nvim_buf_set_name(0, fixture .. "/test.cpp")
  require("local.engine_dap").configure(dap)
  for _, ft in ipairs({ "c", "cpp" }) do
    assert(#dap.configurations[ft] == 2)
    local engine = dap.configurations[ft][2]
    assert(engine.name == "TMTraining: simulation debug" and engine.type == "gdb")
    assert(engine.cwd() == fixture .. "/.cache/nvim-dap/tmtraining/bin/release")
    assert(type(engine.program) == "function")
  end
end, debug.traceback)
vim.fn.delete(fixture, "rf")
assert(ok, err)
print("PASS: native clipboard and spelling, Blink snippet navigation, upstream DAP setup, GDB and engine profiles")
