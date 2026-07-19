# Technical Debt

Temporary workarounds and blocked updates in this configuration. Keep the
corresponding `TODO` comments in the code until each item is resolved.

## Nixpkgs Darwin linker regression

**Status:** Waiting for the fix to reach `nixpkgs-unstable`.

The July 2026 nixpkgs staging cycle enabled libc++ hardening in `ld64`. On
`aarch64-darwin`, the linker can crash with `Trace/BPT trap: 5`. This currently
prevents packages such as Sioyek and Qt Speech from building. The upstream fix
disables that hardening again and has been merged into `staging-next`, but the
maintainer estimated one to two weeks before it reaches the channels.

- Fix: [NixOS/nixpkgs#536365](https://github.com/NixOS/nixpkgs/pull/536365)
- Current action: keep the last working `flake.lock`; do not update nixpkgs yet.
- Before updating, test the channel without changing the lock:

  ```sh
  nix build github:NixOS/nixpkgs/nixpkgs-unstable#sioyek --no-link
  ```

- Once that succeeds, run `nix flake update nixpkgs` and `rebuild`.
- The update should also move `nh` from 4.3.2 to 4.4.1, whose subprocess-output
  fix should restore the garbage-collection space summary from `nh clean`.

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
