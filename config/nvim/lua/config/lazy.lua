local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
  -- Also bootstrap LazyVim so its init (which loads options.lua) runs during the
  -- first Plugin.load() — before install_missing() opens a float and steals focus.
  -- If this fails, install_missing() will clone it, just with the cosmetic issue.
  vim.fn.system({ "git", "clone", "--filter=blob:none",
    "https://github.com/LazyVim/LazyVim.git", vim.fn.stdpath("data") .. "/lazy/LazyVim" })
end

vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = {
    -- add LazyVim and import its plugins
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    -- import/override with your plugins
    { import = "plugins" },
  },
  defaults = {
    -- By default, only LazyVim plugins will be lazy-loaded. Your custom plugins will load during startup.
    -- If you know what you're doing, you can set this to `true` to have all your custom plugins lazy-loaded by default.
    lazy = false,
    -- It's recommended to leave version=false for now, since a lot the plugin that support versioning,
    -- have outdated releases, which may break your Neovim install.
    version = false, -- always use the latest git commit
    -- version = "*", -- try installing the latest stable version for plugins that support semver
  },
  install = { colorscheme = { "dracula" } },
  -- Plugins are nix-pinned via lazy-lock.json; runtime update checks + mtime
  -- polling are noise here and pull in lazy.view.commands/lazy.manage at startup.
  checker = { enabled = false },
  change_detection = { enabled = false, notify = false },
  -- No plugins in this config require luarocks; disabling skips the hererocks
  -- install attempt and silences the ERROR in :checkhealth.
  rocks = { enabled = false },
  performance = {
    rtp = {
      -- disable some rtp plugins
      disabled_plugins = {
        "gzip",
        "matchit",
        "matchparen",
        "netrwPlugin",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
  ui = {
    border = "rounded",
  },
})
