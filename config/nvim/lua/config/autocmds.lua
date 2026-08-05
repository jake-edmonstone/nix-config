local augroup = vim.api.nvim_create_augroup("UserConfig", { clear = true })

-- Don't auto-insert comment leaders on Enter or o/O
vim.api.nvim_create_autocmd("FileType", {
  group = augroup,
  callback = function()
    vim.opt_local.formatoptions:remove({ "r", "o" })
  end,
})

-- TODO: delete this fallback once we are off nightly and nixpkgs Neovim
-- includes neovim/neovim#37971. It documents the pre-watchers workaround but
-- should remain disabled while official watcher-backed 'autoread' is in use.
-- local function checktime_file_buffer()
--   if vim.bo.buftype == "" and vim.api.nvim_get_mode().mode ~= "c" then
--     vim.cmd("checktime " .. vim.api.nvim_get_current_buf())
--   end
-- end
--
-- vim.api.nvim_create_autocmd({ "BufEnter", "CursorMoved", "CursorMovedI" }, {
--   group = augroup,
--   callback = checktime_file_buffer,
-- })

-- Clean up [No Name] buffer after a file is opened via --remote (e.g. lazygit)
local initial_buffer = vim.api.nvim_get_current_buf()
vim.api.nvim_create_autocmd("BufReadPost", {
  group = augroup,
  once = true,
  callback = function()
    vim.schedule(function()
      if
        vim.api.nvim_buf_is_valid(initial_buffer)
        and vim.api.nvim_buf_is_loaded(initial_buffer)
        and vim.api.nvim_buf_get_name(initial_buffer) == ""
        and vim.bo[initial_buffer].buftype == ""
        and not vim.bo[initial_buffer].modified
        and initial_buffer ~= vim.api.nvim_get_current_buf()
      then
        vim.api.nvim_buf_delete(initial_buffer, {})
      end
    end)
  end,
})

-- q to close undo tree window
vim.api.nvim_create_autocmd("FileType", {
  group = augroup,
  pattern = "nvim-undotree",
  callback = function(args)
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buf = args.buf, silent = true })
  end,
})

-- Disable LSP logging (deferred to avoid loading vim.lsp at startup)
vim.api.nvim_create_autocmd("LspAttach", {
  group = augroup,
  once = true,
  callback = function()
    vim.lsp.log.set_level("off")
  end,
})
