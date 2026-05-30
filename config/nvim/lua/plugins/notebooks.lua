local notebook_fts = { "markdown", "quarto", "python" }

local function notebook_ft_opts()
  return { ft = notebook_fts }
end

local function install_ipynb_diagnostic_filter()
  if vim.g.notebooks_ipynb_diagnostic_filter_installed then
    return
  end
  vim.g.notebooks_ipynb_diagnostic_filter_installed = true

  local function is_ipynb_buffer(bufnr)
    return vim.api.nvim_buf_get_name(bufnr):match("%.ipynb$") ~= nil
  end

  local function is_unused_expression(diagnostic)
    return diagnostic.code == "reportUnusedExpression" or diagnostic.message == "Expression value is unused"
  end

  for name, handler in pairs(vim.diagnostic.handlers) do
    if type(handler) == "table" and handler.show and handler.hide then
      vim.diagnostic.handlers[name] = {
        show = function(namespace, bufnr, diagnostics, opts)
          if is_ipynb_buffer(bufnr) then
            diagnostics = vim.tbl_filter(function(diagnostic)
              return not is_unused_expression(diagnostic)
            end, diagnostics)
          end
          handler.show(namespace, bufnr, diagnostics, opts)
        end,
        hide = handler.hide,
      }
    end
  end
end

return {
  {
    -- This implementation has a built-in template for new notebooks and does
    -- not require patching plugin internals for sparse notebook metadata.
    "goerz/jupytext.nvim",
    version = "0.2.0",
    lazy = false,
    opts = {
      format = "markdown",
      update = true,
      autosync = true,
      async_write = false,
    },
  },

  {
    "folke/which-key.nvim",
    opts = {
      spec = {
        { "<leader>j", group = "jupyter", mode = { "n", "v" } },
      },
    },
  },

  {
    "3rd/image.nvim",
    lazy = true,
    build = false,
    opts = {
      backend = "kitty",
      processor = "magick_cli",
      integrations = {
        markdown = { enabled = false },
        neorg = { enabled = false },
        typst = { enabled = false },
      },
    },
  },

  {
    "benlubas/molten-nvim",
    ft = notebook_fts,
    build = ":UpdateRemotePlugins",
    dependencies = { "3rd/image.nvim" },
    init = function()
      vim.g.molten_auto_open_output = false
      vim.g.molten_image_provider = "image.nvim"
      vim.g.molten_output_win_border = "rounded"
      vim.g.molten_wrap_output = true
      vim.g.molten_virt_text_output = true
      vim.g.molten_virt_lines_off_by_1 = true
    end,
    config = function()
      local function import_outputs(event)
        local bufnr = event.buf
        if vim.b[bufnr].notebooks_molten_outputs_imported then
          return
        end
        vim.b[bufnr].notebooks_molten_outputs_imported = true

        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(bufnr) then
            return
          end

          local kernels = vim.fn.MoltenAvailableKernels()
          local kernel_name
          local ok, notebook = pcall(function()
            local file = assert(io.open(event.file, "r"))
            local content = file:read("a")
            file:close()
            return vim.json.decode(content)
          end)

          if ok then
            kernel_name = vim.tbl_get(notebook, "metadata", "kernelspec", "name")
          end

          if not kernel_name or not vim.tbl_contains(kernels, kernel_name) then
            kernel_name = vim.tbl_contains(kernels, "python3") and "python3" or nil
          end

          if kernel_name then
            vim.cmd.MoltenInit(kernel_name)
          end
          vim.cmd.MoltenImportOutput()
        end)
      end

      vim.api.nvim_create_autocmd("BufEnter", {
        pattern = "*.ipynb",
        callback = import_outputs,
      })

      vim.api.nvim_create_autocmd("BufWritePost", {
        pattern = "*.ipynb",
        callback = function()
          local ok, status = pcall(require, "molten.status")
          if ok and status.initialized() == "Molten" then
            vim.cmd("MoltenExportOutput!")
          end
        end,
      })
    end,
    keys = {
      vim.tbl_extend("force", { "<leader>ji", "<cmd>MoltenInit<cr>", desc = "Jupyter init kernel" }, notebook_ft_opts()),
      vim.tbl_extend(
        "force",
        { "<leader>jo", "<cmd>MoltenShowOutput<cr>", desc = "Jupyter show output" },
        notebook_ft_opts()
      ),
      vim.tbl_extend(
        "force",
        { "<leader>jO", "<cmd>noautocmd MoltenEnterOutput<cr>", desc = "Jupyter enter output window" },
        notebook_ft_opts()
      ),
      vim.tbl_extend(
        "force",
        { "<leader>jh", "<cmd>MoltenHideOutput<cr>", desc = "Jupyter hide output" },
        notebook_ft_opts()
      ),
      vim.tbl_extend(
        "force",
        { "<leader>je", "<cmd>MoltenEvaluateOperator<cr>", desc = "Jupyter evaluate operator" },
        notebook_ft_opts()
      ),
      vim.tbl_extend(
        "force",
        { "<leader>je", ":<c-u>MoltenEvaluateVisual<cr>", mode = "v", desc = "Jupyter evaluate selection" },
        notebook_ft_opts()
      ),
      vim.tbl_extend(
        "force",
        { "<leader>jr", "<cmd>MoltenReevaluateCell<cr>", desc = "Jupyter re-evaluate Molten cell" },
        notebook_ft_opts()
      ),
      vim.tbl_extend("force", { "<leader>jx", "<cmd>MoltenDelete<cr>", desc = "Jupyter delete Molten cell" }, notebook_ft_opts()),
      vim.tbl_extend(
        "force",
        { "<leader>jI", "<cmd>MoltenImportOutput<cr>", desc = "Jupyter import notebook output" },
        notebook_ft_opts()
      ),
      vim.tbl_extend(
        "force",
        { "<leader>jE", "<cmd>MoltenExportOutput!<cr>", desc = "Jupyter save outputs to notebook" },
        notebook_ft_opts()
      ),
    },
  },

  {
    "quarto-dev/quarto-nvim",
    ft = { "markdown", "quarto" },
    dependencies = {
      "jmbuhr/otter.nvim",
      "nvim-treesitter/nvim-treesitter",
      "benlubas/molten-nvim",
    },
    opts = {
      lspFeatures = {
        enabled = true,
        languages = { "python" },
        chunks = "all",
        diagnostics = {
          enabled = true,
          triggers = { "BufWritePost" },
        },
        completion = {
          enabled = true,
        },
      },
      codeRunner = {
        enabled = true,
        default_method = "molten",
        ft_runners = {
          python = "molten",
        },
      },
    },
    config = function(_, opts)
      install_ipynb_diagnostic_filter()

      local quarto = require("quarto")
      quarto.setup(opts)

      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "markdown", "quarto" },
        callback = function()
          if vim.api.nvim_buf_get_name(0):match("%.ipynb$") then
            quarto.activate()
          end
        end,
      })

      local runner = require("quarto.runner")
      vim.keymap.set("n", "<leader>jc", runner.run_cell, { desc = "Jupyter run cell", silent = true })
      vim.keymap.set("n", "<leader>ja", runner.run_all, { desc = "Jupyter run all cells", silent = true })
      vim.keymap.set("n", "<leader>jA", runner.run_above, { desc = "Jupyter run cells above", silent = true })
      vim.keymap.set("n", "<leader>jB", runner.run_below, { desc = "Jupyter run cells below", silent = true })
      vim.keymap.set("n", "<leader>jl", runner.run_line, { desc = "Jupyter run line", silent = true })
      vim.keymap.set("v", "<leader>jv", runner.run_range, { desc = "Jupyter run selection", silent = true })
    end,
  },
}
