local M = {}

local function find_engine_root(path)
  if not path or path == "" then
    return nil
  end

  local root = vim.fs.root(path, { "MODULE.bazel", "WORKSPACE", "WORKSPACE.bazel" })
  if root and vim.fn.isdirectory(root .. "/SupportModels/TMTraining") == 1 then
    return root
  end
end

local function engine_paths()
  local root = find_engine_root(vim.api.nvim_buf_get_name(0)) or find_engine_root(vim.uv.cwd())
  if not root then
    error("Open a source file inside an engine worktree before starting this debug profile.")
  end

  local tmtraining_dir = root .. "/SupportModels/TMTraining"
  local stage_root = root .. "/.cache/nvim-dap/tmtraining"
  return {
    root = root,
    tmtraining_dir = tmtraining_dir,
    binary = root .. "/bazel-bin/SupportModels/TMTraining/vulcan_training",
    stage_root = stage_root,
    stage_cwd = stage_root .. "/bin/release",
  }
end

local function is_engine_context()
  return find_engine_root(vim.api.nvim_buf_get_name(0)) ~= nil or find_engine_root(vim.uv.cwd()) ~= nil
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
  local paths = engine_paths()
  require_file(
    paths.binary,
    "Build it with: bazel build --config=simulation --config=debug //SupportModels/TMTraining:TMTraining_engine"
  )
  require_file(paths.tmtraining_dir .. "/config/autorun.cfg", "The TMTraining runtime config is missing.")
  require_file(paths.root .. "/risk/riskLimits.cfg", "The engine risk configuration is missing.")

  -- The runner resolves config via ../../config. Mirror only that layout in
  -- the project's ignored cache, never in the source tree's build directory.
  vim.fn.delete(paths.stage_root, "rf")
  vim.fn.mkdir(paths.stage_cwd, "p")
  copy(paths.tmtraining_dir .. "/config", paths.stage_root .. "/config")
  copy(paths.root .. "/risk/riskLimits.cfg", paths.stage_root .. "/config/riskLimits.cfg")

  return paths.binary
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
    cwd = function()
      return engine_paths().stage_cwd
    end,
    args = { "-simulatedDate=2023_05_02", "-simulatedStartTime=00:00:00" },
    -- Bazel recorded this synthetic compilation directory in the DWARF data.
    -- GDB itself runs from stage_cwd, so map it back to the actual checkout.
    gdb_source_substitutions = {
      {
        from = "/proc/self/cwd",
        to = function()
          return engine_paths().root
        end,
      },
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
