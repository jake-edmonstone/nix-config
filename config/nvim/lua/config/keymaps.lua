-- move cursor back after yank in visual mode
vim.keymap.set("v", "y", "ygv<Esc>", { silent = true, desc = "Yank without moving cursor" })

-- make changing in any mode not replace register
vim.keymap.set("n", "c", '"_c', { silent = true, desc = "Change (black hole)" })
vim.keymap.set("v", "c", '"_c', { silent = true, desc = "Change (black hole)" })
vim.keymap.set("n", "C", '"_C', { silent = true, desc = "Change to EOL (black hole)" })
vim.keymap.set("v", "C", '"_C', { silent = true, desc = "Change to EOL (black hole)" })
vim.keymap.set("n", "x", '"_x', { silent = true, desc = "Delete char (black hole)" })
vim.keymap.set("n", "X", '"_X', { silent = true, desc = "Backspace (black hole)" })

-- indent entire file preserving cursor position
vim.keymap.set("n", "==", function()
  local cur = vim.api.nvim_win_get_cursor(0)
  vim.cmd.normal({ "gg=G", bang = true })
  vim.api.nvim_win_set_cursor(0, cur)
end, { desc = "Indent whole file", silent = true })

-- Spell fix: single key, replaces ZZ/ZQ which are redundant with :w/:q
vim.keymap.set("n", "Z", function()
  local word = vim.fn.expand("<cword>")
  local suggestions = vim.fn.spellsuggest(word, 1)
  if #suggestions > 0 then
    vim.cmd.normal({ "ciw" .. suggestions[1], bang = true })
  end
end, { silent = true, desc = "Replace with first spelling suggestion" })

-- center cursor after half-page scroll
vim.keymap.set("n", "<C-u>", "<C-u>zz", { silent = true, desc = "Half-page up (centered)" })
vim.keymap.set("n", "<C-d>", "<C-d>zz", { silent = true, desc = "Half-page down (centered)" })

-- async git conflict markers to quickfix
vim.keymap.set("n", "<leader>gq", function()
  vim.system(
    { "git", "diff", "--check", "--relative" },
    { text = true },
    vim.schedule_wrap(function(result)
      vim.fn.setqflist({}, " ", {
        title = "Git Conflicts",
        lines = vim.split(result.stdout or "", "\n"),
        efm = "%f:%l: %m",
      })
      vim.cmd("copen")
    end)
  )
end, { desc = "Git conflicts to quickfix" })

vim.keymap.set("n", "U", function()
  vim.cmd.packadd("nvim.undotree") -- built-in optional plugin; load on first press
  require("undotree").open({ command = "50vnew" })
end, { desc = "Undo tree", silent = true })

vim.keymap.set("n", "<leader>sF", function()
  Snacks.picker.grep({ cwd = vim.fs.dirname(vim.api.nvim_buf_get_name(0)) })
end, { desc = "Search current file directory" })

vim.keymap.set("v", "<leader><space>", function()
  Snacks.picker.files({ pattern = Snacks.picker.util.visual().text })
end, { desc = "Find files (selection)" })

vim.keymap.set("v", "<leader>ff", function()
  Snacks.picker.files({ pattern = Snacks.picker.util.visual().text })
end, { desc = "Find files (selection)" })

vim.keymap.set("v", "<leader>sg", function()
  Snacks.picker.grep({ search = Snacks.picker.util.visual().text })
end, { desc = "Grep (selection)" })

vim.keymap.set("v", "<leader>sF", function()
  Snacks.picker.grep({ search = Snacks.picker.util.visual().text, cwd = vim.fs.dirname(vim.api.nvim_buf_get_name(0)) })
end, { desc = "Search current file directory (selection)" })
