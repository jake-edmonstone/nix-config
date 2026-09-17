local M = {}

local engine_root = "/scratch/dev/engine"
local tmtraining_dir = engine_root .. "/SupportModels/TMTraining"
local binary = engine_root .. "/bazel-bin/SupportModels/TMTraining/vulcan_training"
local stage_root = engine_root .. "/.cache/nvim-dap/tmtraining"
local stage_cwd = stage_root .. "/bin/release"

local function is_engine_context()
  local function is_under_engine(path)
    path = vim.fs.normalize(path or "")
    return path == engine_root or vim.startswith(path, engine_root .. "/")
  end

  return is_under_engine(vim.uv.cwd()) or is_under_engine(vim.api.nvim_buf_get_name(0))
end

local function require_file(path, remedy)
  if vim.fn.filereadable(path) ~= 1 then
    error(("Missing %s. %s"):format(path, remedy))
  end
end

local function copy(source, destination)
  local result = vim.system({ "cp", "-a", source, destination }):wait()
  if result.code ~= 0 then
    error(("Could not stage %s: %s"):format(source, result.stderr))
  end
end

local function prepare_tmtraining()
  require_file(
    binary,
    "Build it with: bazel build --config=simulation --config=debug //SupportModels/TMTraining:TMTraining_engine"
  )
  require_file(tmtraining_dir .. "/config/autorun.cfg", "The TMTraining runtime config is missing.")
  require_file(engine_root .. "/risk/riskLimits.cfg", "The engine risk configuration is missing.")

  -- The runner resolves config via ../../config. Mirror only that layout in
  -- the project's ignored cache, never in the source tree's build directory.
  vim.fn.delete(stage_root, "rf")
  vim.fn.mkdir(stage_cwd, "p")
  copy(tmtraining_dir .. "/config", stage_root .. "/config")
  copy(engine_root .. "/risk/riskLimits.cfg", stage_root .. "/config/riskLimits.cfg")

  return binary
end

local function debug_environment()
  local environment = vim.fn.environ()
  local gcc_lib = "/opt/packages/gcc/15.2.0/lib64"
  local library_paths = vim.split(environment.LD_LIBRARY_PATH or "", ":", { plain = true, trimempty = true })
  if not vim.tbl_contains(library_paths, gcc_lib) then
    table.insert(library_paths, 1, gcc_lib)
  end
  environment.LD_LIBRARY_PATH = table.concat(library_paths, ":")
  return environment
end

function M.configure(dap)
  if not is_engine_context() then
    return
  end

  local tmtraining = {
    name = "TMTraining: simulation debug",
    type = "gdb",
    request = "launch",
    program = prepare_tmtraining,
    cwd = stage_cwd,
    args = { "-simulatedDate=2023_05_02", "-simulatedStartTime=00:00:00" },
    -- Bazel recorded this synthetic compilation directory in the DWARF data.
    -- GDB itself runs from stage_cwd, so map it back to the actual checkout.
    gdb_source_substitutions = {
      { from = "/proc/self/cwd", to = engine_root },
    },
    -- GDB DAP replaces the inferior environment when env is supplied, so pass
    -- through Neovim's environment as well as the engine's GCC runtime path.
    env = debug_environment(),
    stopAtBeginningOfMainSubprogram = true,
  }

  for _, filetype in ipairs({ "c", "cpp" }) do
    table.insert(dap.configurations[filetype], tmtraining)
  end
end

return M
