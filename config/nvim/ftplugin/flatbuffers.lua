-- Match the existing FlatBuffers schemas in /scratch/dev/engine.
vim.bo.shiftwidth = 4
vim.bo.tabstop = 4
vim.bo.softtabstop = 4
vim.bo.expandtab = true

-- Nix supplies this external parser. nvim-treesitter cannot auto-start it
-- because it is not in that plugin's registry.
local flatbuffers = vim.g.flatbuffers_treesitter_dir
if flatbuffers and not vim.g.flatbuffers_treesitter_initialized then
  vim.treesitter.language.add("flatbuffers", { path = flatbuffers .. "/parser" })

  -- The grammar's bundled query says `enumval_decl`, but the parser emits
  -- `enum_val_decl`. Correct it until upstream fixes the query.
  local highlights = table.concat(vim.fn.readfile(flatbuffers .. "/queries/highlights.scm"), "\n")
    :gsub("enumval_decl", "enum_val_decl")
  vim.treesitter.query.set("flatbuffers", "highlights", highlights)
  vim.g.flatbuffers_treesitter_initialized = true
end

if flatbuffers then
  vim.treesitter.start(0, "flatbuffers")
end

vim.lsp.start({
  name = "flatbuffers_ls",
  cmd = { "flatbuffers-language-server" },
  root_dir = vim.fs.root(0, { "MODULE.bazel", "WORKSPACE", ".git" }) or vim.uv.cwd(),
})
