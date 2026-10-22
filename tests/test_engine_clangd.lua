local root = assert(arg[1])
local spec = dofile(root .. "/config/nvim/lua/plugins/lang.lua")
local plugin
for _, candidate in ipairs(spec) do
  if candidate[1] == "neovim/nvim-lspconfig" then
    plugin = candidate
    break
  end
end
assert(plugin)

local function options()
  return {
    servers = {
      clangd = {
        cmd = { "clangd", "--background-index", "--function-arg-placeholders" },
        cmd_env = { EXISTING = "preserved" },
      },
    },
  }
end

vim.g.engine_clangd_query_driver = nil
local default = options()
plugin.opts(nil, default)
assert(type(default.servers.clangd.cmd) == "table")
assert(vim.tbl_contains(default.servers.clangd.cmd, "--function-arg-placeholders=true"))

vim.g.engine_clangd_query_driver = "/scratch/dev/engine*/external/trusted/gcc.sh"
local opts = options()
plugin.opts(nil, opts)
local server = opts.servers.clangd
assert(type(server.cmd) == "function")
assert(server.cmd_env.EXISTING == "preserved")
assert(server.cmd_env.XDG_CACHE_HOME == "/scratch/dev/.cache")

local launches = {}
rawset(vim.lsp.rpc, "start", function(command, dispatchers, process_options)
  local launch = { command = command, dispatchers = dispatchers, options = process_options }
  table.insert(launches, launch)
  return launch
end)

for _, path in ipairs({ "/scratch/dev/engine", "/scratch/dev/engine-ticket", "/scratch/dev/engine-ticket/" }) do
  local dispatchers = {}
  local launch = server.cmd(dispatchers, { root_dir = path, cmd_env = server.cmd_env, detached = false })
  assert(launch.dispatchers == dispatchers)
  assert(launch.options.cwd == path)
  assert(launch.options.env == server.cmd_env)
  assert(launch.options.detached == false)
  assert(vim.tbl_contains(launch.command, "--query-driver=" .. vim.g.engine_clangd_query_driver))
  assert(vim.tbl_contains(launch.command, "--background-index"))
  assert(vim.tbl_contains(launch.command, "-j=3"))
end

for _, path in ipairs({ "/scratch/dev/engine-other/nested", "/scratch/dev/engineish", "/tmp/project" }) do
  local launch = server.cmd({}, { root_dir = path, cmd_cwd = "/tmp/launch" })
  assert(launch.options.cwd == "/tmp/launch")
  for _, argument in ipairs(launch.command) do
    assert(not argument:match("^%-%-query%-driver="))
  end
end

local first = launches[1].command
first[1] = "modified"
assert(launches[2].command[1] == "clangd")
print("engine clangd launch tests passed")
