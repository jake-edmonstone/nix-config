-- Enable the Neovim Lua bytecode cache before lazy.nvim boots. lazy.nvim also
-- calls this inside its own setup (lazy/init.lua — Cache.enable()), but by then
-- config/lazy.lua and a few of lazy.nvim's own top-level files have already
-- parsed through the default loader. Doing it here caches those too.
-- Measured delta on this config: ~0.4 ms on warm startup (2% of ~19 ms total).
vim.loader.enable()
if vim.env.TERM_PROGRAM == "rex" and vim.env.OSC7577_TOKEN then
  require("config.rex_resume")
end
require("config.lazy")
