# Technical Debt

Temporary workarounds and blocked updates in this configuration. Keep the
corresponding `TODO` comments in the code until each item is resolved.

## mcp-nixos flaky Darwin test

**Status:** Waiting for nixpkgs to apply the correct upstream fix.

`mcp-nixos` 2.4.3 has a test that rejects successful file reads whenever the
file contents happen to contain the word `Error`. Nixpkgs attempted to fix this,
but its patch points to an unrelated upstream `.envrc` commit and re-enables the
flaky test on Darwin.

- Upstream fix:
  [utensils/mcp-nixos@d7ebc7b](https://github.com/utensils/mcp-nixos/commit/d7ebc7bfae70eaf20d54e87cf42764a1d57c35ef)
- Incorrect nixpkgs fix:
  [NixOS/nixpkgs#539664](https://github.com/NixOS/nixpkgs/pull/539664)
- Temporary code: `mcpNixosOverlay` in `flake.nix` applies the actual upstream
  patch.
- Once nixpkgs packages the correct patch, remove `mcpNixosOverlay` from
  `flake.nix` and build `mcp-nixos` directly before rebuilding:

  ```sh
  nix build .#darwinConfigurations.Jakes-MacBook.pkgs.mcp-nixos --no-link
  ```

## Neovim nightly for watcher-backed autoread

**Status:** Waiting for the required Neovim commit to reach the nixpkgs Neovim
package.

Neovim nightly is used so `autoread` notices external edits through file-system
watchers without custom polling autocommands.

- Upstream: [neovim/neovim#37971](https://github.com/neovim/neovim/pull/37971)
- Temporary code:
  - `flake.nix`: the `neovim-nightly-overlay` input and Darwin package override.
  - `config/nvim/lua/config/autocmds.lua`: the commented pre-watcher fallback.
  - `config/nvim/lua/config/options.lua`: the `autoread` dependency note.
- Once nixpkgs Neovim contains the change, remove the nightly input, output
  argument, and package override; delete the commented fallback and its `TODO`.
  Keep `vim.o.autoread = true`, but remove its nightly-specific comment.

## tmux 3.7 popup redraw regression

**Status:** Waiting for a tmux release newer than 3.7b that renders correctly.

tmux 3.7 through 3.7b corrupts or repeatedly redraws the title border of tmux
popups while Codex is streaming output. The configuration therefore pins tmux
3.6a.

- Temporary code: `tmuxOverlay` in `flake.nix`.
- There is no confirmed upstream issue linked for this setup yet.
- When nixpkgs ships a newer tmux, remove the overlay, rebuild, restart the tmux
  server, and test the session picker while Codex is actively generating text.
  Keep the pin if the popup title still flickers or is cut off.
