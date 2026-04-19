local augroup = vim.api.nvim_create_augroup("UserConfig", { clear = true })

-- Don't auto-insert comment leaders on Enter or o/O
vim.api.nvim_create_autocmd("FileType", {
  group = augroup,
  callback = function()
    vim.opt_local.formatoptions:remove({ "r", "o" })
  end,
})

-- Extend LazyVim's built-in checktime autocmd (which listens on
-- FocusGained/TermClose/TermLeave) with BufEnter, so switching BACK to a buffer
-- whose underlying file was modified outside nvim also triggers a reload.
-- LazyVim intentionally omits BufEnter from its default set — this is the delta.
-- Guard: skip in command-line mode (don't redraw while you're typing :), and
-- skip non-file buffers (terminals, quickfix, help, oil/mini-files, etc.).
vim.api.nvim_create_autocmd("BufEnter", {
  group = augroup,
  callback = function()
    if vim.o.buftype ~= "nofile" and vim.api.nvim_get_mode().mode ~= "c" then
      vim.cmd.checktime()
    end
  end,
})

-- Clean up [No Name] buffer after a file is opened via --remote (e.g. lazygit)
vim.api.nvim_create_autocmd("BufReadPost", {
  group = augroup,
  once = true,
  callback = function()
    vim.schedule(function()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if
          vim.api.nvim_buf_is_loaded(buf)
          and vim.api.nvim_buf_get_name(buf) == ""
          and vim.bo[buf].buftype == ""
          and not vim.bo[buf].modified
          and buf ~= vim.api.nvim_get_current_buf()
        then
          vim.api.nvim_buf_delete(buf, {})
        end
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

-- Restore blinking block cursor on exit
vim.api.nvim_create_autocmd("VimLeave", {
  group = augroup,
  callback = function()
    io.write("\027[1 q")
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

-- Disable autoformat for C++ on Cerebras machines (manual format with <leader>cf still works)
if vim.fn.isdirectory("/cb") == 1 then
  vim.api.nvim_create_autocmd("FileType", {
    group = augroup,
    pattern = "cpp",
    callback = function()
      vim.b.autoformat = false
    end,
  })
end

-- XML uses 4-space indentation
vim.api.nvim_create_autocmd("FileType", {
  group = augroup,
  pattern = "xml",
  callback = function()
    vim.bo.shiftwidth = 4
    vim.bo.tabstop = 4
    vim.bo.softtabstop = 4
    vim.bo.expandtab = true
  end,
})
