vim.g.snacks_animate = false

-- reload files changed outside nvim
vim.o.autoread = true
vim.o.winborder = "rounded"
vim.o.pumborder = "rounded"
-- hide whitespace indicators (LazyVim enables list by default)
vim.o.list = false
vim.o.number = true
vim.o.relativenumber = false
vim.o.swapfile = false
vim.o.clipboard = "unnamedplus"

-- Over SSH, route the + register through OSC 52 directly so yanks work inside
-- AND outside tmux. Nvim's auto-fallback is skipped when 'clipboard' is set,
-- so we wire it explicitly here. The terminal (Ghostty, etc.) receives the
-- OSC 52 escape and writes to the Mac clipboard.
if vim.env.SSH_TTY then
  local osc52 = require("vim.ui.clipboard.osc52")
  vim.g.clipboard = {
    name = "OSC 52",
    copy = { ["+"] = osc52.copy("+"), ["*"] = osc52.copy("*") },
    paste = { ["+"] = osc52.paste("+"), ["*"] = osc52.paste("*") },
  }
end

-- blinking block in normal, blinking bar in insert, horizontal in replace
vim.o.guicursor =
  "n-v-c-sm:block-blinkwait700-blinkon400-blinkoff250,i-ci-ve:ver25-blinkwait700-blinkon400-blinkoff250,r-cr-o:hor20"

vim.g.root_spec = { "cwd" } -- use cwd as root, not git repo

-- (nvim.undotree is a built-in optional plugin; loaded on-demand from the `U`
-- keymap in config/keymaps.lua via packadd, so we don't pay for it at startup.)
