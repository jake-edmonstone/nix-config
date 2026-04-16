return {
  {
    "nvim-mini/mini.files",
    dependencies = { "nvim-mini/mini.icons" },
    init = function()
      -- Load eagerly when neovim opens a directory (nvim .)
      if vim.fn.argc(-1) > 0 then
        local stat = vim.uv.fs_stat(vim.fn.argv(0))
        if stat and stat.type == "directory" then
          require("mini.files")
        end
      end
      -- Close mini.files when a Snacks picker opens to avoid floating window conflicts
      local group = vim.api.nvim_create_augroup("MiniFilesSnacksFix", { clear = true })
      vim.api.nvim_create_autocmd("FileType", {
        group = group,
        pattern = "snacks_picker_input",
        callback = function()
          local ok, MiniFiles = pcall(require, "mini.files")
          if ok then
            MiniFiles.close()
          end
        end,
      })
    end,
    config = function(_, opts)
      require("mini.files").setup(opts)
      require("util.mini-files.git").setup()
      require("util.mini-files.symlinks").setup()
    end,
    opts = {
      options = { use_as_default_explorer = true },
      mappings = {
        close = "q",
        go_in = "<Tab>",
        go_in_plus = "<Enter>",
        go_out = "-",
        go_out_plus = "",
        mark_goto = "'",
        mark_set = "m",
        reset = "<BS>",
        reveal_cwd = "@",
        show_help = "g?",
        synchronize = "=",
        trim_left = "<",
        trim_right = ">",
      },
    },
    keys = {
      {
        "<leader>o",
        function()
          local MiniFiles = require("mini.files")
          if not MiniFiles.close() then
            local buf_name = vim.api.nvim_buf_get_name(0)
            if buf_name == "" or not vim.uv.fs_stat(buf_name) then
              buf_name = vim.uv.cwd() --[[@as string]]
            end
            MiniFiles.open(buf_name, true)
          end
        end,
        desc = "Toggle mini.files (Directory of Current File)",
      },
      {
        "<leader>O",
        function()
          local MiniFiles = require("mini.files")
          if not MiniFiles.close() then
            MiniFiles.open(vim.uv.cwd(), true)
          end
        end,
        desc = "Toggle mini.files (cwd)",
      },
    },
  },
}
