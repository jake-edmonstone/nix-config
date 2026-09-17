local function prompt_file()
  local program = vim.fn.input("Executable: ", vim.fn.getcwd() .. "/", "file")
  return program ~= "" and vim.fn.fnamemodify(program, ":p") or nil
end

local function prompt_directory()
  local directory = vim.fn.input("Working directory: ", vim.fn.getcwd(), "dir")
  return directory ~= "" and vim.fn.fnamemodify(directory, ":p") or nil
end

return {
  -- Debuggers are supplied declaratively by Nix, not downloaded by Mason.
  { "jay-babu/mason-nvim-dap.nvim", enabled = false },
  {
    "mfussenegger/nvim-dap",
    config = function()
      local dap = require("dap")

      -- GDB 14+ implements DAP directly; Nix supplies GDB 17.2 on Linux.
      dap.adapters.gdb = function(callback, config)
        local args = { "--interpreter=dap", "--eval-command", "set print pretty on" }
        for _, substitution in ipairs(config.gdb_source_substitutions or {}) do
          table.insert(args, "--eval-command")
          table.insert(args, ("set substitute-path %q %q"):format(substitution.from, substitution.to))
        end
        callback({ type = "executable", command = "gdb", args = args })
      end

      -- Keep the clangd extra for its LSP features, but it also supplies
      -- codelldb launch entries. codelldb is neither installed nor wanted:
      -- C/C++ debugging in this configuration is direct GDB DAP.
      dap.adapters.codelldb = nil
      dap.configurations.c = {}
      dap.configurations.cpp = {}

      local launch = {
        name = "Launch executable (GDB)",
        type = "gdb",
        request = "launch",
        program = prompt_file,
        cwd = prompt_directory,
        args = {},
        stopAtBeginningOfMainSubprogram = true,
      }

      for _, filetype in ipairs({ "c", "cpp" }) do
        dap.configurations[filetype] = dap.configurations[filetype] or {}
        table.insert(dap.configurations[filetype], launch)
      end

      -- User-specific project profiles live in this configuration repository,
      -- so they do not create untracked files in source checkouts.
      require("local.engine_dap").configure(dap)

      vim.api.nvim_set_hl(0, "DapStoppedLine", { default = true, link = "Visual" })
      for name, sign in pairs(LazyVim.config.icons.dap) do
        sign = type(sign) == "table" and sign or { sign }
        vim.fn.sign_define(
          "Dap" .. name,
          { text = sign[1], texthl = sign[2] or "DiagnosticInfo", linehl = sign[3], numhl = sign[3] }
        )
      end

      -- Keep LazyVim's launch.json support, including JSON-with-comments files.
      local vscode = require("dap.ext.vscode")
      local json = require("plenary.json")
      vscode.json_decode = function(str)
        return vim.json.decode(json.json_strip_comments(str))
      end
    end,
  },
}
