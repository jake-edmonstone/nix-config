vim.bo.shiftwidth = 4
vim.bo.tabstop = 4
vim.bo.softtabstop = 4
vim.bo.expandtab = true

-- Tree-sitter's indent expression can misindent an incomplete `else` block
-- while it is being typed. C++'s built-in indentation handles this grammar.
vim.bo.cindent = true
