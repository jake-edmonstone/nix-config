# Technical Debt

Temporary workarounds and blocked updates in this configuration. Keep the
corresponding `TODO` comments in the code until each item is resolved.

## Neovim nightly for watcher-backed autoread

**Status:** Waiting for the required Neovim commit to reach the nixpkgs Neovim
package.

Neovim nightly is used so `autoread` notices external edits through file-system
watchers without custom polling autocommands.

As of 2026-09-07, nixpkgs unstable packages Neovim 0.12.5. Its release branch
does not contain the watcher commit, so the nightly override is still required.

- Upstream: [neovim/neovim#37971](https://github.com/neovim/neovim/pull/37971)
- Temporary code:
  - `flake.nix`: the `neovim-nightly-overlay` input and Darwin package override.
  - `config/nvim/lua/config/autocmds.lua`: the commented pre-watcher fallback.
  - `config/nvim/lua/config/options.lua`: the `autoread` dependency note.
- Once nixpkgs Neovim contains the change, remove the nightly input, output
  argument, and package override; delete the commented fallback and its `TODO`.
  Keep `vim.o.autoread = true`, but remove its nightly-specific comment.

## nix-homebrew auto-update breaks MAS activation

**Status:** Waiting for nix-homebrew to preserve `HOMEBREW_PATH` across
Homebrew's auto-update re-exec.

With activation auto-update enabled, the nix-homebrew wrapper re-executes Brew
with its filtered `PATH`. `brew bundle` then cannot find `mas`, even when it is
already installed, and every declarative Mac App Store entry fails. Cask and
MAS app upgrades still run because `homebrew.onActivation.upgrade` remains
enabled; the Homebrew executable is updated through the `nix-homebrew` flake
input.

- Upstream reports:
  [nix-homebrew#131](https://github.com/zhaofengli/nix-homebrew/issues/131) and
  [nix-homebrew#149](https://github.com/zhaofengli/nix-homebrew/issues/149).
- Temporary code: `homebrew.onActivation.autoUpdate = false` in
  `hosts/darwin/default.nix`.
- Once the wrapper preserves the original path across re-exec, set
  `autoUpdate` back to `true` and verify a rebuild recognizes the existing MAS
  apps.
